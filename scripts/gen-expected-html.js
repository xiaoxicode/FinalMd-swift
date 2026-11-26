// gen-expected-html.js — 批量生成权威期望 HTML
// 读 stdin JSON: [{id, markdown, ref}]  输出 JSON: [{id, html}]
// ref=="cm"  → commonmark.js 0.31.2；ref=="gfm" → marked (GFM)
const fs = require('fs');
const commonmark = require('/tmp/mdref/node_modules/commonmark');
const { marked } = require('/tmp/mdref/node_modules/marked');

const input = JSON.parse(fs.readFileSync(0, 'utf8'));
// FinalMd 的 HTML 导出把软换行渲染为 <br>（GFM breaks:true 语义），
// 期望侧用同样的软换行渲染，才能做有意义的归一化对比。
const cmParser = new commonmark.Parser();
const cmWriter = new commonmark.HtmlRenderer({ softbreak: '<br />' });
marked.setOptions({ gfm: true, breaks: true });

const out = input.map(({ id, markdown, ref }) => {
  let html;
  try {
    if (ref === 'gfm') html = marked.parse(markdown, { async: false });
    else html = cmWriter.render(cmParser.parse(markdown));
  } catch (e) {
    html = '<!--ERROR: ' + e.message + '-->';
  }
  return { id, html };
});
process.stdout.write(JSON.stringify(out));
