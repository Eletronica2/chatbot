import { chromium } from 'playwright';
import path from 'path';

const BASE = 'http://127.0.0.1:7357';
const OUT9 = path.join(process.env.USERPROFILE, 'Desktop', 'fase9-evidencias');

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

// Entrar
const box = await page.evaluate(() => {
  const nodes = Array.from(document.querySelectorAll('flt-semantics'));
  for (const n of nodes) {
    const v = (n.getAttribute('aria-label') || n.innerText || '').trim();
    if (v === 'Entrar') {
      const r = n.getBoundingClientRect();
      if (r.width > 1) return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    }
  }
  return null;
});
if (box) await page.mouse.click(box.x, box.y);
else await page.mouse.click(1120, 40);
await page.waitForTimeout(2000);
await page.screenshot({ path: path.join(OUT9, '23-login-smoke.png') });
console.log('login smoke ok');
await browser.close();
