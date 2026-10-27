#!/usr/bin/env node
/**
 * 把 Electron 版 shared/i18n/*.js 的词典转换成 Swift 字典文件。
 *
 *   node scripts/gen-i18n.js <FinalMd 仓库路径> [输出文件路径]
 *
 * 例：node scripts/gen-i18n.js ../FinalMd Sources/FinalMd/I18n/Dictionaries.swift
 */
'use strict';

const fs = require('fs');
const path = require('path');

const LANGS = [
  { code: 'zh', label: '简体中文', locale: 'zh-Hans' },
  { code: 'en', label: 'English', locale: 'en' },
  { code: 'ja', label: '日本語', locale: 'ja' },
  { code: 'ko', label: '한국어', locale: 'ko' },
  { code: 'fr', label: 'Français', locale: 'fr' },
  { code: 'de', label: 'Deutsch', locale: 'de' },
  { code: 'es', label: 'Español', locale: 'es' },
];

/** 转成合法的 Swift 多行字符串字面量内容 */
function swiftLiteral(s) {
  return String(s)
    .replace(/\\/g, '\\\\')   // 反斜杠
    .replace(/"/g, '\\"')     // 双引号
    .replace(/\r\n?/g, '\\n')
    .replace(/\n/g, '\\n')    // 换行
    .replace(/\t/g, '\\t')    // 制表符
    .replace(/\u2028/g, '\\u{2028}')
    .replace(/\u2029/g, '\\u{2029}');
}

function swiftKey(k) {
  // key 形如 app.title / tb.bold，不含需要转义的字符，但仍走一次安全转义
  return swiftLiteral(k);
}

function main() {
  const repo = path.resolve(process.argv[2] || '../FinalMd');
  const out = path.resolve(process.argv[3] || 'Sources/FinalMd/I18n/Dictionaries.swift');
  const dir = path.join(repo, 'shared', 'i18n');

  const dicts = {};
  for (const l of LANGS) {
    const file = path.join(dir, `${l.code}.js`);
    // eslint-disable-next-line global-require, import/no-dynamic-require
    dicts[l.code] = require(file);
  }

  // 以 zh 为基准，保证 key 顺序稳定
  const baseKeys = Object.keys(dicts.zh);
  const missing = [];
  for (const l of LANGS) {
    for (const k of baseKeys) {
      if (dicts[l.code][k] === undefined) missing.push(`${l.code}:${k}`);
    }
  }
  if (missing.length) {
    console.error('以下语言缺少 key（仍会生成，缺失项回落到英文）：');
    missing.forEach((m) => console.error('  - ' + m));
  }

  const lines = [];
  lines.push('//');
  lines.push('//  Dictionaries.swift');
  lines.push('//  FinalMd（墨写）— SwiftUI 原生版');
  lines.push('//');
  lines.push('//  ⚠️ 本文件由 scripts/gen-i18n.js 从 Electron 版 shared/i18n/*.js 自动生成，请勿手动修改。');
  lines.push(`//  生成时间：${new Date().toISOString()}`);
  lines.push(`//  基准语言：zh（${baseKeys.length} 个 key × ${LANGS.length} 种语言）`);
  lines.push('//');
  lines.push('');
  lines.push('import Foundation');
  lines.push('');
  lines.push('/// 界面支持的语言（顺序即语言选择器的显示顺序）');
  lines.push('struct AppLanguage: Identifiable, Hashable {');
  lines.push('    let code: String');
  lines.push('    let label: String');
  lines.push('    let locale: String');
  lines.push('    var id: String { code }');
  lines.push('}');
  lines.push('');
  lines.push('enum I18nDictionary {');
  lines.push('');
  lines.push('    static let supportedLanguages: [AppLanguage] = [');
  for (const l of LANGS) {
    lines.push(`        AppLanguage(code: "${l.code}", label: "${swiftLiteral(l.label)}", locale: "${l.locale}"),`);
  }
  lines.push('    ]');
  lines.push('');
  lines.push('    /// [语言代码: [文案 key: 文案]]');
  lines.push('    static let table: [String: [String: String]] = [');
  for (const l of LANGS) {
    lines.push(`        "${l.code}": [`);
    for (const k of baseKeys) {
      const v = dicts[l.code][k];
      if (v === undefined) continue;
      lines.push(`            "${swiftKey(k)}": "${swiftLiteral(v)}",`);
    }
    lines.push('        ],');
  }
  lines.push('    ]');
  lines.push('}');
  lines.push('');

  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, lines.join('\n'), 'utf8');
  console.log(`✅ 已生成 ${out}`);
  console.log(`   ${LANGS.length} 种语言 × ${baseKeys.length} 个 key`);
}

main();
