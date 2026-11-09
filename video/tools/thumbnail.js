// Render thumbnail.html to a 1280x720 PNG. Usage: node thumbnail.js <repoRoot> <out.png>
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const [repo, outFile] = process.argv.slice(2);
const server = http.createServer((req, res) => {
  const file = path.join(repo, decodeURIComponent(req.url.split('?')[0]).replace(/^\/repo\//, ''));
  if (!file.startsWith(path.resolve(repo)) || !fs.existsSync(file)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'content-type': 'text/html' });
  fs.createReadStream(file).pipe(res);
});

(async () => {
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  await page.goto(`http://127.0.0.1:${server.address().port}/repo/video/tools/thumbnail.html`);
  await page.evaluate(() => window.ready);
  await page.screenshot({ path: outFile });
  await browser.close();
  server.close();
})();
