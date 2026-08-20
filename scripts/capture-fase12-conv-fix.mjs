import { chromium } from 'playwright';
import path from 'path';

const BASE = process.env.ADMIN_URL || 'http://127.0.0.1:7362';
const EMAIL = process.env.ADMIN_EMAIL || 'admin@bellamassa.com.br';
const PASS = process.env.ADMIN_PASSWORD || 'Bella@2026!';
const OUT = path.join(process.env.USERPROFILE || '', 'Desktop', 'fase12-evidencias');

async function ready(page) {
  await page.waitForFunction(() => {
    const l = document.querySelector('.flutter-loader');
    const v = !!document.querySelector('flutter-view, flt-glass-pane, canvas');
    const g = !l || getComputedStyle(l).display === 'none' || l.clientHeight === 0;
    return v && g;
  }, { timeout: 120000 });
  await page.waitForTimeout(1200);
}

async function shot(page, f) {
  await page.screenshot({ path: path.join(OUT, f), fullPage: false });
  console.log('OK', f);
}

async function clickIncludes(page, lab, { leftRail = false } = {}) {
  const box = await page.evaluate(
    ({ lab, leftRail }) => {
      const nodes = [...document.querySelectorAll('flt-semantics')];
      for (const n of nodes) {
        const t = ((n.getAttribute('aria-label') || '') + ' ' + (n.innerText || '')).trim();
        if (!t.includes(lab)) continue;
        const r = n.getBoundingClientRect();
        if (r.width < 1 || r.height < 1) continue;
        if (leftRail && r.x > 240) continue;
        return { x: r.x + Math.min(40, r.width / 2), y: r.y + r.height / 2 };
      }
      return null;
    },
    { lab, leftRail },
  );
  if (!box) return false;
  await page.mouse.click(box.x, box.y);
  await page.waitForTimeout(1400);
  return true;
}

async function login(page) {
  await page.goto(BASE, { waitUntil: 'domcontentloaded' });
  await ready(page);
  await page.keyboard.press('Escape');
  if (!(await clickIncludes(page, 'Entrar'))) {
    await page.mouse.click(1120, 40);
    await page.waitForTimeout(1500);
  }
  for (let i = 0; i < 50; i++) {
    if ((await page.locator('input').count()) >= 2) break;
    await page.waitForTimeout(300);
  }
  if ((await page.locator('input').count()) < 2) throw new Error('no login inputs');
  const inputs = page.locator('input');
  await inputs.nth(0).click({ force: true });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(EMAIL, { delay: 8 });
  await inputs.nth(1).click({ force: true });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(PASS, { delay: 8 });
  await clickIncludes(page, 'Entrar na plataforma');
  await page.waitForTimeout(4500);
}

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await ctx.newPage();
await login(page);
await clickIncludes(page, 'Conversas', { leftRail: true });
await page.waitForTimeout(1500);
await page.mouse.click(340, 250);
await page.waitForTimeout(2500);
await shot(page, 'fix-01-depois.png');
await shot(page, 'fix-conversas-detalhe-desktop.png');

await page.setViewportSize({ width: 800, height: 900 });
await page.waitForTimeout(700);
await clickIncludes(page, 'Voltar');
await page.waitForTimeout(900);
await shot(page, '33-800-conversas-lista.png');
await page.mouse.click(400, 250);
await page.waitForTimeout(2500);
await shot(page, '34-800-conversas-detalhe.png');

await page.setViewportSize({ width: 390, height: 844 });
await page.mouse.click(28, 28);
await page.waitForTimeout(700);
await clickIncludes(page, 'WhatsApp');
await page.waitForTimeout(1200);
console.log('wizard', await clickIncludes(page, 'Assistente'));
await page.waitForTimeout(1200);
await shot(page, '39-390-whatsapp-wizard.png');

await browser.close();
console.log('DONE');
