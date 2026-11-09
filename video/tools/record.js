// Render scenes of stage.html to MP4, frame by frame (deterministic, in sync with the voiceover).
// Usage: node record.js <repoRoot> <outDir> <fps> <sceneId...>
// Expects <outDir>/timings.json (from tts.py). Writes <outDir>/scenes/<id>.mp4
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const [repo, out, fpsArg, ...ids] = process.argv.slice(2);
const FPS = +fpsArg || 30;
const TYPES = { '.html': 'text/html', '.json': 'application/json', '.js': 'text/javascript' };

const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  const base = url.startsWith('/repo/') ? repo : url.startsWith('/out/') ? out : null;
  const file = base && path.join(base, url.replace(/^\/(repo|out)\//, ''));
  if (!file || !file.startsWith(path.resolve(base)) || !fs.existsSync(file)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});

(async () => {
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;
  const timings = JSON.parse(fs.readFileSync(path.join(out, 'timings.json')));
  fs.mkdirSync(path.join(out, 'scenes'), { recursive: true });
  const browser = await chromium.launch();

  for (const id of ids) {
    const sc = timings.find(s => s.id === id);
    const frames = Math.round((sc.start + sc.duration) * FPS) - Math.round(sc.start * FPS);
    const ctx = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
    const page = await ctx.newPage();
    page.on('pageerror', e => console.error(`[${id}] page error:`, e.message));
    await page.goto(`http://127.0.0.1:${port}/repo/video/tools/stage.html?scene=${id}&timings=/out/timings.json&app=/repo/apps/hustle-tracker/index.html`);
    await page.evaluate(() => window.ready);

    if (process.env.STILLS) {
      // Preview mode: STILLS="0.3,0.6" saves PNGs at those fractions of the scene.
      const fracs = process.env.STILLS.split(',').map(Number);
      for (let i = 0; i < frames; i++) {
        const t = i / FPS;
        await page.evaluate(t => window.seek(t), t);
        const hit = fracs.findIndex(f => Math.round(f * (frames - 1)) === i);
        if (hit >= 0) await page.screenshot({ path: path.join(out, 'scenes', `${id}-${fracs[hit]}.png`) });
      }
      console.log(`${id}: stills saved`);
      await ctx.close();
      continue;
    }

    const file = path.join(out, 'scenes', `${id}.mp4`);
    const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-',
      '-c:v', 'libx264', '-preset', 'medium', '-crf', '16', '-pix_fmt', 'yuv420p', '-r', String(FPS), file],
      { stdio: ['pipe', 'inherit', 'inherit'] });
    const t0 = Date.now();
    for (let i = 0; i < frames; i++) {
      await page.evaluate(t => window.seek(t), i / FPS);
      const buf = await page.screenshot({ type: 'jpeg', quality: 95 });
      if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    }
    ff.stdin.end();
    await new Promise(r => ff.on('close', r));
    console.log(`${id}: ${frames} frames in ${((Date.now() - t0) / 1000).toFixed(0)}s`);
    await ctx.close();
  }
  await browser.close();
  server.close();
})();
