import { build, preview } from '/Users/arpan/webdev/mockup/node_modules/vite/dist/node/index.js';
import react from '/Users/arpan/webdev/mockup/node_modules/@vitejs/plugin-react/dist/index.js';
import { chromium } from '/Users/arpan/webdev/mockup/node_modules/playwright-core/index.mjs';
import sharp from '/Users/arpan/webdev/mockup/node_modules/sharp/dist/index.mjs';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';

// driver.ts project.json outDir
const [projectPath, outDir] = process.argv.slice(2);
const root = path.dirname(new URL(import.meta.url).pathname);
const config = { root, configFile: false as const, logLevel: 'error' as const, plugins: [react()],
  resolve: { alias: { '@ff': '/Users/arpan/webdev/mockup/src' } } };
await build({ ...config, build: { outDir: path.join(root, 'dist'), emptyOutDir: true } });
const server = await preview({ ...config, build: { outDir: path.join(root, 'dist') }, preview: { host: '127.0.0.1', port: 4391, strictPort: false } });
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  page.setDefaultTimeout(120_000);
  page.on('pageerror', (e) => console.error('[page]', e.message));
  await page.goto(server.resolvedUrls!.local[0]);
  await page.waitForFunction(() => (window as any).ffReady);
  const project = JSON.parse(await readFile(projectPath, 'utf8'));
  await mkdir(outDir, { recursive: true });
  const tiles: Buffer[] = [];
  for (let i = 0; i < project.slides.length; i++) {
    const b64 = await page.evaluate(([p, i]) => (window as any).ffRender(p, i), [project, i] as const);
    const buf = Buffer.from(b64, 'base64');
    await writeFile(path.join(outDir, `${project.slides[i].name}.png`), buf);
    tiles.push(await sharp(buf).resize({ height: 800 }).toBuffer());
  }
  const w = 450, gap = 24, pad = 40;
  await sharp({ create: { width: pad * 2 + tiles.length * w + (tiles.length - 1) * gap, height: 880, channels: 3, background: '#18181B' } })
    .composite(tiles.map((t, i) => ({ input: t, left: pad + i * (w + gap), top: pad })))
    .jpeg({ quality: 85 }).toFile(path.join(outDir, 'preview.jpg'));
  await writeFile(path.join(outDir, `${project.name}.frameflow`), JSON.stringify(project));
  console.log('rendered', tiles.length, '→', outDir);
} finally {
  await browser.close();
  server.httpServer.close();
}
