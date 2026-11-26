#!/usr/bin/env node
// 验证 marked 对 \<foo+@bar.example.com> 与边界变体的语义
const { marked } = require('/tmp/mdref/node_modules/marked');
marked.setOptions({ gfm: true, breaks: true });
const tests = [
  '<foo\\+@bar.example.com>',
  '\\<foo+@bar.example.com>',
  '<foo+@bar.example.com>',
  'a <foo@bar.com> b',
  'a \\<foo@bar.com> b',
  '(foo+@bar.example.com)',
  '<foo+@bar.example.com>',
  'x<foo+@bar.example.com>',
];
for (const t of tests) {
  console.log(JSON.stringify(t), '=>', JSON.stringify(marked.parse(t)));
}
