// Captures the app's screens from a real build.
//
// Not mock-ups: this drives the web build of `lib/main_demo.dart`, which is the
// shipping app with its outside-world dependencies overridden. The wardrobe
// list, the item detail and the scan flow rendered here are the real widgets
// reading real domain objects.
//
//   flutter build web -t lib/main_demo.dart --no-web-resources-cdn \
//     --output=build/demo
//   npx http-server build/demo -p 8910 --silent &
//   node tool/screenshots.mjs
//
// Chromium comes from the image; `playwright install` is neither needed nor
// wanted here.

import { mkdir } from 'node:fs/promises';
import { createRequire } from 'node:module';

// Resolved through `require` rather than a bare `import`, so a globally
// installed Playwright on NODE_PATH is found. ESM import specifiers ignore
// NODE_PATH, and this script is meant to run without adding a package.json to
// a Flutter project purely to hold one dev tool.
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const BASE = process.env.DEMO_URL ?? 'http://127.0.0.1:8910';
const OUT = 'docs/screenshots';

// A phone-shaped viewport. The app is built for a phone, and shooting it at
// desktop width would show a layout no user will ever see.
const VIEWPORT = { width: 420, height: 900 };

await mkdir(OUT, { recursive: true });

const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  args: ['--no-sandbox'],
});

/** Waits for Flutter to have painted something other than the loading screen. */
async function ready(page) {
  await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 60_000 });
  // Flutter renders to a canvas, so there is no DOM node to wait on for a
  // specific screen. A short settle is the honest way to do this.
  await page.waitForTimeout(2500);
}

async function shot(page, name) {
  await page.screenshot({ path: `${OUT}/${name}.png` });
  console.log(`captured ${name}.png`);
}

/** Clicks by on-screen text, which Flutter exposes through the a11y tree. */
async function tapText(page, text) {
  await page.getByText(text, { exact: false }).first().click();
  await page.waitForTimeout(1200);
}

for (const theme of ['light', 'dark']) {
  const context = await browser.newContext({
    viewport: VIEWPORT,
    deviceScaleFactor: 2,
    colorScheme: theme,
    // Flutter's semantics tree is off until something asks for it. Without it
    // there are no nodes to click and the flow cannot be driven at all.
    forcedColors: 'none',
  });
  const page = await context.newPage();

  page.on('console', (message) => {
    if (message.type() === 'error') console.error(`[browser] ${message.text()}`);
  });

  await page.goto(`${BASE}/`, { waitUntil: 'load' });
  await ready(page);

  // Turn on the accessibility tree so text is clickable.
  await page.evaluate(() => {
    const button = document.querySelector('flt-semantics-placeholder');
    if (button) button.click();
  });
  await page.waitForTimeout(800);

  await shot(page, `wardrobe-${theme}`);

  await page.goto(`${BASE}/#/item/demo-jumper`, { waitUntil: 'load' });
  await ready(page);
  await shot(page, `item-detail-${theme}`);

  if (theme === 'light') {
    await page.goto(`${BASE}/#/scan`, { waitUntil: 'load' });
    await ready(page);
    await shot(page, 'scan-capture');

    await tapText(page, 'Take a photo');
    await page.waitForTimeout(2000);
    await shot(page, 'scan-review');
  }

  await context.close();
}

await browser.close();
console.log('done');
