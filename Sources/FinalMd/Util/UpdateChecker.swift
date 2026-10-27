//
//  UpdateChecker.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  对应 Electron 版的 electron-updater：查 GitHub 上最新的 Release tag，
//  比当前版本新就引导用户去下载（原生版不内置二进制热更新，改用浏览器打开 Release 页）。
//

import Foundation
import AppKit

enum UpdateChecker {

    static let releasesURL = URL(string: "https://github.com/xiaoxicode/FinalMd/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/xiaoxicode/FinalMd/releases/latest")!

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }

    /// 返回形如 "v1.0.1" 的最新 tag，失败返回 nil
    static func latestRelease() async -> String? {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["tag_name"] as? String
    }
}
