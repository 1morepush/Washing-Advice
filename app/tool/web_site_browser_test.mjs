// Tests the parts of "use an earlier version" that are plain JavaScript, in a
// real browser: the pin script in web/index.html, the way-back bar injected
// into earlier builds, and the not-found page.
//
// Nothing here needs a Flutter build. It writes two pretend builds (0.37.0 and
// 0.38.0) that use the real web/index.html, lays the site out with the real
// tool/web_site.dart, serves it the way GitHub Pages would at
// /Washing-Advice/, and drives Chromium over it.
//
//   cd app
//   node tool/web_site_browser_test.mjs
//
// Needs `dart` on PATH, Playwright resolvable from NODE_PATH (as
// tool/screenshots.mjs does) and a Chromium: CHROMIUM_PATH overrides the
// default below. `playwright install` is neither needed nor wanted. Exits
// non-zero on the first failed check, so it can gate a change.
//
// Screenshots of the bar at 320 px land in $SHOTS (default: none are kept).

import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import {
  existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync,
  writeFileSync,
} from 'node:fs';
import http from 'node:http';
import { tmpdir } from 'node:os';
import path from 'node:path';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const BASE = '/Washing-Advice/';
const work = mkdtempSync(path.join(tmpdir(), 'web-site-browser-'));
const store = path.join(work, 'store');
const site = path.join(work, 'site');

// --- Pretend builds and the real assembly -----------------------------------

const template = readFileSync('web/index.html', 'utf8');

function fakeBuild(version) {
  const dir = path.join(work, `build-${version}`);
  mkdirSync(dir, { recursive: true });
  writeFileSync(
    path.join(dir, 'index.html'),
    template.replace('$FLUTTER_BASE_HREF', BASE),
  );
  // What the real bootstrap does, reduced to proof that it ran and which
  // version it belongs to, and to what the page could see in storage.
  writeFileSync(
    path.join(dir, 'flutter_bootstrap.js'),
    `document.body.insertAdjacentHTML('beforeend',
       '<main id="app" style="font:16px sans-serif">App ${version}</main>');
     document.body.dataset.app = '${version}';`,
  );
  writeFileSync(path.join(dir, 'flutter_service_worker.js'), '// worker');
  writeFileSync(
    path.join(work, `info-${version}.json`),
    JSON.stringify({
      version, name: `Name ${version}`, date: '2026-11-13',
      dataFormat: { wardrobe: 5, images: 1 },
    }),
  );
  return dir;
}

function dart(...args) {
  const run = spawnSync(process.env.DART ?? 'dart', ['tool/web_site.dart', ...args], {
    encoding: 'utf8',
  });
  if (run.status !== 0) {
    throw new Error(`web_site.dart ${args[0]} failed:\n${run.stderr}${run.stdout}`);
  }
  return run.stdout;
}

for (const version of ['0.37.0', '0.38.0']) {
  dart('publish', '--build', fakeBuild(version), '--store', store, '--out', site,
    '--base', BASE, '--info', path.join(work, `info-${version}.json`));
}

// --- A server that behaves like Pages ---------------------------------------

const types = {
  '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json',
};
const server = http.createServer((request, response) => {
  const url = new URL(request.url, 'http://x');
  let file = decodeURIComponent(url.pathname);
  if (!file.startsWith(BASE)) { response.statusCode = 404; response.end(); return; }
  file = path.join(site, file.slice(BASE.length));
  if (existsSync(file) && statSync(file).isDirectory()) file = path.join(file, 'index.html');
  if (!file.startsWith(site) || !existsSync(file)) {
    response.statusCode = 404;
    response.setHeader('content-type', 'text/html');
    response.end(readFileSync(path.join(site, '404.html')));
    return;
  }
  response.setHeader('content-type', types[path.extname(file)] ?? 'text/plain');
  response.end(readFileSync(file));
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const ORIGIN = `http://127.0.0.1:${server.address().port}`;

// --- Checks -----------------------------------------------------------------

const PIN = 'washingAdvice.pinnedVersion';
let failures = 0;
function check(name, ok, detail = '') {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : `  ${detail}`}`);
  if (!ok) failures++;
}

const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  args: ['--no-sandbox'],
});

async function open({ width = 320, height = 640, scheme = 'light' } = {}) {
  const context = await browser.newContext({
    viewport: { width, height }, colorScheme: scheme,
  });
  const page = await context.newPage();
  return { context, page };
}

async function appVersion(page) {
  // Either the page itself, or the frame inside the bar's shell.
  await page.waitForLoadState('domcontentloaded');
  const target = (await page.locator('#wa-frame').count())
    ? page.frameLocator('#wa-frame')
    : page;
  await target.locator('#app').waitFor();
  return target.locator('body').getAttribute('data-app');
}
const pinOf = (page) => page.evaluate((k) => localStorage.getItem(k), PIN);

try {
  // 1. Nothing pinned: the root is the newest build.
  {
    const { context, page } = await open();
    await page.goto(`${ORIGIN}${BASE}`);
    check('no pin: the root opens the newest build', (await appVersion(page)) === '0.38.0');
    check('no pin: stays at the root', new URL(page.url()).pathname === BASE, page.url());
    check('no pin: no way-back bar at the root', (await page.locator('#wa-rollback').count()) === 0);
    await context.close();
  }

  // 2. A pin is honoured before the app starts, and the bar is shown.
  {
    const { context, page } = await open();
    await page.goto(`${ORIGIN}${BASE}?latest=1`); // storage needs an origin
    await page.evaluate((k) => localStorage.setItem(k, '0.37.0'), PIN);
    await page.goto(`${ORIGIN}${BASE}`);
    check('pinned: the root redirects to the chosen version',
      new URL(page.url()).pathname === `${BASE}v/0.37.0/`, page.url());
    const ran = await appVersion(page); check('pinned: the chosen build is what runs', ran === '0.37.0', String(ran));
    check('pinned: the bar says which version', (await page.locator('#wa-rollback').innerText()).includes('0.37.0'));
    check('pinned: the bar is the only injected copy',
      (await page.content()).split('washing-advice-rollback-bar').length - 1 <= 1);

    // 3. Layout at 320 px: bar on the page, frame below it, no sideways scroll.
    const bar = await page.locator('#wa-rollback').boundingBox();
    const frame = await page.locator('#wa-frame').boundingBox();
    check('bar fits 320 px', bar.x >= 0 && bar.x + bar.width <= 320, JSON.stringify(bar));
    check('app frame starts where the bar ends', Math.abs(frame.y - (bar.y + bar.height)) <= 1, `${frame.y} vs ${bar.y + bar.height}`);
    check('app frame reaches the bottom of the window, so its own bottom bar is uncovered',
      Math.abs(frame.y + frame.height - 640) <= 1, JSON.stringify(frame));
    check('no horizontal scroll', await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    if (process.env.SHOTS) {
      mkdirSync(process.env.SHOTS, { recursive: true });
      await page.screenshot({ path: path.join(process.env.SHOTS, 'bar-light-320.png') });
    }

    // 4. Back to latest clears the pin and lands on the root's build.
    await page.getByRole('button', { name: 'Back to latest' }).click();
    await page.waitForURL((u) => u.pathname === BASE);
    check('back to latest: the pin is cleared', (await pinOf(page)) === null);
    check('back to latest: lands on the newest build', (await appVersion(page)) === '0.38.0');
    check('back to latest: the address is clean', new URL(page.url()).search === '', page.url());
    await context.close();
  }

  // 5. The escape hatch needs no UI.
  {
    const { context, page } = await open();
    await page.goto(`${ORIGIN}${BASE}?latest=1`);
    await page.evaluate((k) => localStorage.setItem(k, '0.37.0'), PIN);
    await page.goto(`${ORIGIN}${BASE}?latest=1`);
    check('?latest=1: stays on the newest build', (await appVersion(page)) === '0.38.0');
    check('?latest=1: clears the pin', (await pinOf(page)) === null);
    check('?latest=1: is removed from the address', new URL(page.url()).search === '', page.url());
    await page.goto(`${ORIGIN}${BASE}`);
    check('?latest=1: the next plain open is not redirected', (await appVersion(page)) === '0.38.0');
    await context.close();
  }

  // 6. A pin to a version that was dropped lands on 404, which clears it.
  {
    const { context, page } = await open();
    await page.goto(`${ORIGIN}${BASE}?latest=1`);
    await page.evaluate((k) => localStorage.setItem(k, '0.1.0'), PIN);
    await page.goto(`${ORIGIN}${BASE}`);
    await page.waitForURL((u) => u.pathname === BASE && !u.search);
    check('dropped version: ends on the newest build', (await appVersion(page)) === '0.38.0');
    check('dropped version: the pin is cleared', (await pinOf(page)) === null);
    await context.close();
  }

  // 7. Garbage in the pin is ignored, not followed.
  {
    const { context, page } = await open();
    await page.goto(`${ORIGIN}${BASE}?latest=1`);
    await page.evaluate((k) => localStorage.setItem(k, '../../evil'), PIN);
    await page.goto(`${ORIGIN}${BASE}`);
    check('a pin that is not a version is ignored', (await appVersion(page)) === '0.38.0' && new URL(page.url()).pathname === BASE);
    await context.close();
  }

  // 8. A versioned page is never redirected by a pin (no loop).
  {
    const { context, page } = await open();
    await page.goto(`${ORIGIN}${BASE}?latest=1`);
    await page.evaluate((k) => localStorage.setItem(k, '0.37.0'), PIN);
    await page.goto(`${ORIGIN}${BASE}v/0.37.0/`);
    check('on a versioned path the pin does not redirect again',
      new URL(page.url()).pathname === `${BASE}v/0.37.0/`);
    await context.close();
  }

  // 9. Dark, and a narrow tall bar at a large text size.
  {
    const { context, page } = await open({ scheme: 'dark' });
    await page.goto(`${ORIGIN}${BASE}v/0.37.0/`);
    const colours = await page.evaluate(() => {
      const bar = document.getElementById('wa-rollback');
      const style = getComputedStyle(bar);
      return [style.backgroundColor, style.color];
    });
    check('dark: the bar follows the colour scheme', colours[0] !== 'rgb(255, 244, 214)', colours.join(' / '));
    if (process.env.SHOTS) {
      await page.screenshot({ path: path.join(process.env.SHOTS, 'bar-dark-320.png') });
    }
    await page.addStyleTag({ content: 'html { font-size: 160% } #wa-rollback { font-size: 22px }' });
    await page.setViewportSize({ width: 320, height: 640 });
    const bar = await page.locator('#wa-rollback').boundingBox();
    const frame = await page.locator('#wa-frame').boundingBox();
    check('large text: the bar wraps and the frame still starts below it',
      bar.x + bar.width <= 320 && frame.y >= bar.y + bar.height - 1, `${JSON.stringify(bar)} ${JSON.stringify(frame)}`);
    if (process.env.SHOTS) {
      await page.screenshot({ path: path.join(process.env.SHOTS, 'bar-large-320.png') });
    }
    await context.close();
  }

  // 10. versions.json is served and says what the picker needs.
  {
    const { context, page } = await open();
    const body = await (await page.request.get(`${ORIGIN}${BASE}versions.json`)).json();
    check('versions.json lists the earlier version with its data format',
      body.versions.length === 1 && body.versions[0].version === '0.37.0'
      && body.versions[0].dataFormat.wardrobe === 5 && body.root.version === '0.38.0');
    await context.close();
  }
} finally {
  await browser.close();
  server.close();
  rmSync(work, { recursive: true, force: true });
}

console.log(failures === 0 ? '\nAll checks passed.' : `\n${failures} check(s) failed.`);
process.exit(failures === 0 ? 0 : 1);
