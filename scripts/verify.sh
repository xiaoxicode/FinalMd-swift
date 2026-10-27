#!/usr/bin/env bash
#
# 在无 Xcode 的机器上做类型校验：
# 本机只有 Command Line Tools，缺少 SwiftUI 的宏插件（SwiftUIMacros），
# @State / @Environment 等宏无法展开。这里把源码复制到临时目录，
# 用重命名的 property wrapper 顶替这些宏，再跑一次完整编译。
#
# 用法：scripts/verify.sh
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/finalmd-verify"
SHIM="$TMP/Sources/FinalMd/MacrosShim.swift"

rm -rf "$TMP"
mkdir -p "$TMP"
cp "$SRC/Package.swift" "$TMP/"
cp -R "$SRC/Sources" "$TMP/"

cat > "$SHIM" <<'SWIFT'
// 仅用于类型校验：顶替 SwiftUI 的 @State / @Environment 等宏（不能同名，Swift 会优先选宏）
import SwiftUI

@propertyWrapper struct StateShim<Value> {
    private let initial: Value
    init(wrappedValue: Value) { self.initial = wrappedValue }
    init(initialValue: Value) { self.initial = initialValue }
    var wrappedValue: Value { get { initial } nonmutating set { } }
    var projectedValue: Binding<Value> { Binding(get: { initial }, set: { _ in }) }
}

@propertyWrapper struct ObservedObjectShim<ObjectType: ObservableObject> {
    var wrappedValue: ObjectType
    init(wrappedValue: ObjectType) { self.wrappedValue = wrappedValue }
    var projectedValue: Wrapper { Wrapper(root: wrappedValue) }
    @dynamicMemberLookup struct Wrapper {
        let root: ObjectType
        subscript<Subject>(dynamicMember kp: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
            Binding(get: { root[keyPath: kp] }, set: { root[keyPath: kp] = $0 })
        }
    }
}

@propertyWrapper struct StateObjectShim<ObjectType: ObservableObject> {
    var wrappedValue: ObjectType
    init(wrappedValue: ObjectType) { self.wrappedValue = wrappedValue }
    var projectedValue: ObservedObjectShim<ObjectType>.Wrapper {
        ObservedObjectShim<ObjectType>.Wrapper(root: wrappedValue)
    }
}

@propertyWrapper struct EnvironmentObjectShim<ObjectType: ObservableObject> {
    var wrappedValue: ObjectType { fatalError("shim") }
    var projectedValue: ObservedObjectShim<ObjectType>.Wrapper { fatalError("shim") }
}

@propertyWrapper struct EnvironmentShim<Value> {
    init(_ keyPath: KeyPath<EnvironmentValues, Value>) { }
    var wrappedValue: Value { fatalError("shim") }
}

@propertyWrapper struct NSApplicationDelegateAdaptorShim<DelegateType: NSApplicationDelegate> {
    init(_ delegateType: DelegateType.Type) { }
    var wrappedValue: DelegateType { fatalError("shim") }
}
SWIFT

python3 - "$TMP/Sources/FinalMd" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
subs = [
    (r"@StateObject(?!Shim)", "@StateObjectShim"),
    (r"@State(?![A-Za-z])", "@StateShim"),
    (r"@ObservedObject(?!Shim)", "@ObservedObjectShim"),
    (r"@EnvironmentObject(?!Shim)", "@EnvironmentObjectShim"),
    (r"@Environment(?![A-Za-z])", "@EnvironmentShim"),
    (r"@NSApplicationDelegateAdaptor(?!Shim)", "@NSApplicationDelegateAdaptorShim"),
    (r"= State\(initialValue", "= StateShim(initialValue"),
    (r"= StateObject\(wrappedValue", "= StateObjectShim(wrappedValue"),
]
for p in root.rglob("*.swift"):
    if p.name == "MacrosShim.swift":
        continue
    s = p.read_text()
    for a, b in subs:
        s = re.sub(a, b, s)
    p.write_text(s)
PY

cd "$TMP"
echo "→ 校验编译（宏桩模式）…"
swift build --disable-sandbox 2>&1 | tail -40
