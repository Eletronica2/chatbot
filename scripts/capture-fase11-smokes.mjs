import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const BASE = process.env.ADMIN_URL || 'http://127.0.0.1:7361';
const SUPER_EMAIL = process.env.SUPER_EMAIL || 'arthurlaranjo@hotmail.com';
const SUPER_PASS = process.env.SUPER_PASSWORD || 'adminpanel';
const OUT = path.join(process.env.USERPROFILE || '', 'Desktop', 'fase11-evidencias');
fs.mkdirSync(OUT, { recursive: true });

async function waitFlutterReady(page) {
  await page.waitForFunction(() => {
    const loader = document.querySelector('.flutter-loader');
    const hasView = !!document.querySelector('flutter-view, flt-glass-pane, canvas');
    const loaderGone =
      !loader || getComputedStyle(loader).display === 'none' || loader.clientHeight === 0;
    return hasView && loaderGone;
  }, { timeout: 120000 });
  await page.waitForTimeout(1500);
}

async function shot(page, file) {
  await page.screenshot({ path: path.join(OUT, file), fullPage: false });
  console.log('OK', file);
}

async function clickSemantic(page, label, { exact = true } = {}) {
  const box = await page.evaluate(
    ({ lab, exactMatch }) => {
      const nodes = Array.from(document.querySelectorAll('flt-semantics'));
      let best = null;
      let bestScore = 0;
      for (const n of nodes) {
        const aria = (n.getAttribute('aria-label') || '').trim();
        const txt = (n.innerText || '').trim();
        let s = 0;
        if (aria === lab || txt === lab) s = 2;
        else if (!exactMatch && (aria.includes(lab) || txt.includes(lab))) s = 1;
        if (s > bestScore) {
          const r = n.getBoundingClientRect();
          if (r.width >= 1 && r.height >= 1 && r.height <= 80) {
            best = { x: r.x + Math.min(r.width / 2, 100), y: r.y + r.height / 2 };
            bestScore = s;
          }
        }
      }
      return best;
    },
    { lab: label, exactMatch: exact },
  );
  if (!box) return false;
  await page.mouse.click(box.x, box.y);
  await page.waitForTimeout(1400);
  return true;
}

async function openNav(page, label) {
  // Prefer left rail: low x
  const box = await page.evaluate((lab) => {
    const nodes = Array.from(document.querySelectorAll('flt-semantics'));
    const c = [];
    for (const n of nodes) {
      const val = (n.getAttribute('aria-label') || n.innerText || '').trim();
      if (!(val === lab || val.endsWith(' ' + lab) || val.includes(lab))) continue;
      if (/Atende Ai|Automação no|Navegação principal|tooltip|Planos,/i.test(val)) continue;
      const r = n.getBoundingClientRect();
      if (r.x > 260 || r.height > 64 || r.width < 1 || r.y < 40) continue;
      c.push({
        x: r.x + Math.min(r.width / 2, 90),
        y: r.y + r.height / 2,
        score: (val === lab ? 10 : 0) + (260 - r.x),
        val,
      });
    }
    c.sort((a, b) => b.score - a.score);
    return c[0] || null;
  }, label);
  if (!box) {
    console.warn('nav failed', label);
    return false;
  }
  await page.mouse.click(box.x, box.y);
  await page.waitForTimeout(1600);
  console.log('nav', label, box.val);
  return true;
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  await page.goto(BASE, { waitUntil: 'domcontentloaded' });
  await waitFlutterReady(page);
  await page.keyboard.press('Escape');
  if (!(await clickSemantic(page, 'Entrar', { exact: true }))) {
    await page.mouse.click(1120, 40);
    await page.waitForTimeout(2000);
  }
  let n = 0;
  for (let i = 0; i < 40; i++) {
    n = await page.locator('input').count();
    if (n >= 2) break;
    await page.waitForTimeout(400);
  }
  const inputs = page.locator('input');
  await inputs.nth(0).click({ force: true });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(SUPER_EMAIL, { delay: 12 });
  await inputs.nth(1).click({ force: true });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(SUPER_PASS, { delay: 12 });
  if (!(await clickSemantic(page, 'Entrar na plataforma', { exact: false }))) {
    await page.mouse.click(720, 560);
  }
  await page.waitForTimeout(5000);

  await openNav(page, 'Clientes');
  await page.waitForTimeout(1500);
  await shot(page, '24-clientes-smoke.png');

  // Overview = brand / Início (não há item de sidebar "Início")
  const home = await page.evaluate(() => {
    const nodes = Array.from(document.querySelectorAll('flt-semantics'));
    for (const n of nodes) {
      const val = (n.getAttribute('aria-label') || n.innerText || '').trim();
      if (val !== 'Início' && !/^Atende Ai$/i.test(val)) continue;
      const r = n.getBoundingClientRect();
      if (r.x > 280 || r.y > 120 || r.width < 1) continue;
      return { x: r.x + r.width / 2, y: r.y + r.height / 2, val };
    }
    // fallback: click brand area
    return { x: 90, y: 36, val: 'fallback' };
  });
  await page.mouse.click(home.x, home.y);
  console.log('home', home);
  await page.waitForTimeout(1800);
  await shot(page, '25-overview-smoke.png');

  await browser.close();
  console.log('DONE');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
