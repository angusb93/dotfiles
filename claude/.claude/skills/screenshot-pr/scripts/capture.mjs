#!/usr/bin/env node
// Playwright capture helper for the screenshot-pr skill.
//
// Usage:
//   node capture.mjs --url <url> --out <path> [--viewport 1280x800]
//                    [--selector "main"] [--fullpage] [--wait networkidle]
//                    [--click "button#open"] [--scroll-to "#section"]
//                    [--mask ".timestamp,.avatar"] [--dark]
//
// Exits 0 on success, prints the output path. On navigation failure writes a
// placeholder PNG with an error banner so the diff still produces a useful
// artifact.

import { chromium } from 'playwright';
import { parseArgs } from 'node:util';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const { values } = parseArgs({
  options: {
    url: { type: 'string' },
    out: { type: 'string' },
    viewport: { type: 'string', default: '1280x800' },
    wait: { type: 'string', default: 'networkidle' }, // load | domcontentloaded | networkidle | commit
    selector: { type: 'string' },                     // if set, screenshot just this element
    fullpage: { type: 'boolean', default: false },
    click: { type: 'string' },                        // click this selector before capture (opens modals etc)
    'scroll-to': { type: 'string' },                  // scroll element into view before capture
    mask: { type: 'string' },                         // comma-separated selectors to black-box
    dark: { type: 'boolean', default: false },
    timeout: { type: 'string', default: '30000' },
  },
});

if (!values.url || !values.out) {
  console.error('Usage: capture.mjs --url <url> --out <path> [options]');
  process.exit(2);
}

const [w, h] = values.viewport.split('x').map(Number);
if (!w || !h) {
  console.error(`Bad viewport: ${values.viewport}`);
  process.exit(2);
}

mkdirSync(dirname(values.out), { recursive: true });

const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: w, height: h },
  deviceScaleFactor: 2,
  reducedMotion: 'reduce',
  colorScheme: values.dark ? 'dark' : 'light',
});

// Stabilise: disable animations/transitions, hide caret, freeze scroll behavior.
await context.addInitScript(() => {
  const style = document.createElement('style');
  style.setAttribute('data-screenshot-pr', ''); // excluded from the styled-ness check below
  style.textContent = `
    *, *::before, *::after {
      animation-duration: 0s !important;
      animation-delay: 0s !important;
      transition-duration: 0s !important;
      transition-delay: 0s !important;
      caret-color: transparent !important;
    }
    html { scroll-behavior: auto !important; }
  `;
  (document.head || document.documentElement).appendChild(style);
});

const page = await context.newPage();

async function capture() {
  await page.goto(values.url, {
    waitUntil: values.wait,
    timeout: Number(values.timeout),
  });

  // Wait for web fonts to be ready — they cause the most spurious diffs.
  await page.evaluate(() => (document.fonts?.ready ?? Promise.resolve()));

  // Dev servers (Next, Vite) compile per-route on first hit — the HTML can land
  // before its stylesheet exists, yielding an unstyled capture even at
  // networkidle. If no real CSS made it in, give the compiler a moment and
  // reload once. (Cross-origin sheets throw on cssRules — treat as styled.)
  const hasStyles = () => page.evaluate(() =>
    Array.from(document.styleSheets)
      .filter(s => !(s.ownerNode instanceof Element && s.ownerNode.hasAttribute('data-screenshot-pr')))
      .some(s => { try { return s.cssRules.length > 0; } catch { return true; } })
  );
  if (!(await hasStyles())) {
    await page.waitForTimeout(1500);
    await page.reload({ waitUntil: values.wait, timeout: Number(values.timeout) });
    await page.evaluate(() => (document.fonts?.ready ?? Promise.resolve()));
    if (!(await hasStyles())) {
      console.error(`warning: ${values.url} appears unstyled after reload — dev server may be serving a stale build (check that its CSS endpoint returns 200)`);
    }
  }

  // Wait for images above the fold to load.
  await page.evaluate(async () => {
    const imgs = Array.from(document.images).filter(i => !i.complete);
    await Promise.all(
      imgs.map(i => new Promise(r => {
        i.addEventListener('load', r, { once: true });
        i.addEventListener('error', r, { once: true });
      }))
    );
  });

  if (values['scroll-to']) {
    await page.locator(values['scroll-to']).first().scrollIntoViewIfNeeded();
  }
  if (values.click) {
    await page.locator(values.click).first().click();
    await page.waitForTimeout(300);
  }

  // Small settle time for layout shift from late-loading content.
  await page.waitForTimeout(250);

  const masks = values.mask
    ? values.mask.split(',').map(s => page.locator(s.trim()))
    : [];

  const shotOpts = {
    path: values.out,
    fullPage: values.fullpage,
    animations: 'disabled',
    caret: 'hide',
    mask: masks,
    maskColor: '#000',
  };

  if (values.selector) {
    const el = page.locator(values.selector).first();
    await el.waitFor({ state: 'visible', timeout: 10_000 });
    await el.screenshot({ path: values.out, animations: 'disabled', caret: 'hide', mask: masks, maskColor: '#000' });
  } else {
    await page.screenshot(shotOpts);
  }
}

try {
  await capture();
  console.log(values.out);
} catch (err) {
  // Write a placeholder so the diff pipeline still has two PNGs to compare.
  const msg = String(err?.message ?? err).slice(0, 400);
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}">
    <rect width="100%" height="100%" fill="#2a1f1f"/>
    <text x="24" y="48" fill="#ffb4b4" font-family="monospace" font-size="20">capture failed</text>
    <text x="24" y="88" fill="#ddd" font-family="monospace" font-size="14">${values.url}</text>
    <foreignObject x="24" y="110" width="${w - 48}" height="${h - 140}">
      <div xmlns="http://www.w3.org/1999/xhtml" style="color:#ddd;font:12px/1.4 monospace;white-space:pre-wrap">${msg.replace(/[<>&]/g, c => ({'<':'&lt;','>':'&gt;','&':'&amp;'}[c]))}</div>
    </foreignObject>
  </svg>`;
  // Playwright can render an SVG to PNG for us.
  const errPage = await context.newPage();
  await errPage.setContent(`<html><body style="margin:0">${svg}</body></html>`);
  await errPage.screenshot({ path: values.out });
  console.log(values.out);
  console.error(`capture error: ${msg}`);
  process.exitCode = 1;
} finally {
  await browser.close();
}
