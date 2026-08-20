import { chromium } from 'playwright';
import path from 'path';

const BASE = 'http://127.0.0.1:7357';
const EMAIL = 'admin@bellamassa.com.br';
const PASS = 'Bella@2026!';
const OUT = path.join(process.env.USERPROFILE, 'Desktop', 'fase9-evidencias', '_calib');

import fs from 'fs';
fs.mkdirSync(OUT, { recursive: true });

async function waitFlutterReady(page) {
  await page.waitForFunction(() => {
    const loader = document.querySelector('.flutter-loader');
    const hasView = !!document.querySelector('flutter-view, flt-glass-pane, canvas');
    const loaderGone = !loader || getComputedStyle(loader).display === 'none' || loader.clientHeight === 0;
    return hasView && loaderGone;
  }, { timeout: 120000 });
  await page.waitForTimeout(1500);
}

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
await page.goto(BASE, { waitUntil: 'domcontentloaded' });
await waitFlutterReady(page);
await page.mouse.click(1280, 40);
await page.waitForTimeout(2000);
const inputs = page.locator('input');
await inputs.nth(0).click({ force: true });
await page.keyboard.type(EMAIL, { delay: 15 });
await inputs.nth(1).click({ force: true });
await page.keyboard.type(PASS, { delay: 15 });
await page.mouse.click(720, 560);
await page.waitForTimeout(5000);
await page.screenshot({ path: path.join(OUT, '00-home.png') });

// Probe sidebar Y from 120 to 520
for (let y = 120; y <= 520; y += 30) {
  await page.mouse.click(100, y);
  await page.waitForTimeout(900);
  await page.screenshot({ path: path.join(OUT, `y${String(y).padStart(3, '0')}.png`) });
  console.log('probed', y);
}
await browser.close();
console.log('calib done');
