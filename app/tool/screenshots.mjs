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

/** Clicks by on-screen text, which Flutter exposes through the a11y tree.
 *
 * Two lookups, because Flutter is not consistent about which it uses: a plain
 * label lands in the node's text, while a chip or a button with its own
 * semantics lands in `aria-label` and is invisible to `getByText`.
 */
async function tapText(page, text) {
  const byText = page.getByText(text, { exact: false }).first();
  const target = (await byText.count()) > 0
    ? byText
    : page.getByLabel(text, { exact: false }).first();
  await target.click();
  await page.waitForTimeout(1200);
}

/** Fails unless the bottom bar's five places are on screen.
 *
 * The bar replaced a drawer, and every other step here navigates by address,
 * which would carry on happily with no bar at all. This is the one place the
 * script looks at the navigation itself, so a build that lost it fails the run
 * instead of producing a full set of screenshots of a screen with no way
 * between them. Same two lookups as `tapText`, for the same reason.
 */
async function expectBar(page) {
  for (const label of ['Wardrobe', 'Laundry', 'Outfits', 'Ask', 'More']) {
    const byText = page.getByText(label, { exact: true });
    const byLabel = page.getByLabel(label, { exact: false });
    const found =
      (await byText.count()) > 0 || (await byLabel.count()) > 0;
    if (!found) throw new Error(`The bottom bar has no "${label}"`);
  }
}

/** Taps the wardrobe's grid/list toggle and fails unless the view changed.
 *
 * `from` is the label of the button to press, which names what pressing it
 * does; `to` is the label it must show afterwards. Throws, rather than carrying
 * on, if either is missing: a screenshot taken after a tap that did nothing is
 * a wrong picture with a right-looking name.
 */
async function toggleView(page, { from, to }) {
  // By role and name, not by label: Flutter puts a tooltip in the node's text
  // rather than its `aria-label`, so `getByLabel` never matched and the old
  // `.catch(() => {})` hid that the tap had never happened.
  await page.getByRole('button', { name: from }).first().click({ timeout: 10_000 });
  await page.getByRole('button', { name: to }).first().waitFor({ timeout: 10_000 });
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

  await expectBar(page);
  await shot(page, `wardrobe-${theme}`);

  // The list view, reached through the toggle. Both are worth showing: the
  // grid is for finding a garment, the list for comparing several.
  if (theme === 'light') {
    // Each tap is checked by the toggle's own tooltip flipping, which it only
    // does once the view has changed. A tap that landed nowhere used to be
    // swallowed here and the "list" screenshot was a second copy of the grid.
    await toggleView(page, { from: 'Show as a list', to: 'Show as a grid' });
    await shot(page, 'wardrobe-list');
    await toggleView(page, { from: 'Show as a grid', to: 'Show as a list' });
  }

  await page.goto(`${BASE}/#/item/demo-jumper`, { waitUntil: 'load' });
  await ready(page);
  await shot(page, `item-detail-${theme}`);

  if (theme === 'light') {
    // The cutout editor, with a stroke actually drawn on it. An empty editor
    // would show the chrome and none of the point, and the drag is also the
    // only check that CanvasKit composites the mask the way the pixel tests
    // say it does.
    await page.goto(`${BASE}/#/item/demo-jumper/mask`, { waitUntil: 'load' });
    await ready(page);
    const { width, height } = VIEWPORT;
    const mid = { x: width / 2, y: height * 0.42 };
    await page.mouse.move(mid.x - 70, mid.y);
    await page.mouse.down();
    for (let dx = -70; dx <= 70; dx += 10) {
      await page.mouse.move(mid.x + dx, mid.y + Math.sin(dx / 20) * 12);
      await page.waitForTimeout(16);
    }
    await page.mouse.up();
    await page.waitForTimeout(800);
    await shot(page, 'cutout-editor');

    await page.goto(`${BASE}/#/scan`, { waitUntil: 'load' });
    await ready(page);
    await shot(page, 'scan-capture');

    // Front, then back — the shirt with a print across it is the case this
    // exists for, and one frame of it says more than the prose does.
    await tapText(page, 'Take a photo');
    await page.waitForTimeout(1200);
    await tapText(page, 'Add another photo');
    await page.waitForTimeout(1200);
    await shot(page, 'scan-collected');

    await tapText(page, 'Identify');
    await page.waitForTimeout(2500);
    await shot(page, 'scan-review');

    // The care-label flow. A capture now collects rather than reading, so
    // there are two screens worth showing: the shots taken so far, and the
    // review with what the reading changed.
    await page.goto(`${BASE}/#/item/demo-jumper/care-label`, {
      waitUntil: 'load',
    });
    await ready(page);
    await tapText(page, 'Take a photo');
    await page.waitForTimeout(1200);
    // A second side, which is the whole reason this screen exists.
    await tapText(page, 'Add another side');
    await page.waitForTimeout(1200);
    await shot(page, 'care-label-collected');

    await tapText(page, 'Read these');
    await page.waitForTimeout(2500);
    await shot(page, 'care-label-review');

    await page.goto(`${BASE}/#/item/demo-jumper/edit`, { waitUntil: 'load' });
    await ready(page);
    await shot(page, 'edit-item');


    // The pile scan, driven to its plan — the screen everything else serves.
    await page.goto(`${BASE}/#/pile`, { waitUntil: 'load' });
    await ready(page);
    await tapText(page, 'Take a photo');
    await page.waitForTimeout(3000);
    await shot(page, 'laundry-plan');

    // The three stages (basket, washing, drying). `laundry-piles` predates the
    // way back out of one, so the stages are shot from the current build.
    await page.goto(`${BASE}/#/laundry`, { waitUntil: 'load' });
    await ready(page);
    await shot(page, 'laundry-piles');

    // Treating a spill, driven to the vetted plan. The wool jumper is the
    // right subject: the canned advice includes a chlorine soak, and what the
    // screen shows is that soak refused with its reason.
    await page.goto(`${BASE}/#/item/demo-jumper/stain`, { waitUntil: 'load' });
    await ready(page);
    // Typed rather than tapping a chip. Flutter puts a real <input> behind the
    // focused field, and a chip's tap does not always reach the framework
    // through the accessibility node — whereas keystrokes always do, and the
    // button stays disabled until the field has something in it.
    await page.keyboard.type('Red wine', { delay: 40 });
    await page.waitForTimeout(600);
    await tapText(page, 'How do I get it out?');
    await page.waitForTimeout(3500);
    await shot(page, 'stain-advice');

    await page.goto(`${BASE}/#/outfits`, { waitUntil: 'load' });
    await ready(page);
    await shot(page, 'outfits');

    // The Saved tab, reached by its own address rather than by tapping — a
    // Flutter TabBar label is not reliably in the accessibility tree, and the
    // route exists precisely so screens are drivable without one. Ideas, the
    // other tab, is `/outfits`, shot just above.
    await page.goto(`${BASE}/#/outfits/saved`, { waitUntil: 'load' });
    await ready(page);
    await shot(page, 'outfits-saved');

    await page.goto(`${BASE}/#/packing`, { waitUntil: 'load' });
    await ready(page);
    await shot(page, 'packing');

    // Settings the way a person gets there now: through More. Failing to find
    // either word means the list or the bar has lost its way in.
    await page.goto(`${BASE}/#/more`, { waitUntil: 'load' });
    await ready(page);
    await expectBar(page);
    await tapText(page, 'Settings');
    await page.waitForTimeout(1200);
    await shot(page, 'settings');
  }

  await page.goto(`${BASE}/#/insights`, { waitUntil: 'load' });
  await ready(page);
  await shot(page, `insights-${theme}`);

  await context.close();
}

await browser.close();
console.log('done');
