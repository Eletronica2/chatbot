import { chromium } from 'playwright';
import path from 'path';

const BASE = process.env.ADMIN_URL || 'http://127.0.0.1:7362';
const TENANT_EMAIL = process.env.ADMIN_EMAIL || 'admin@bellamassa.com.br';
const TENANT_PASS = process.env.ADMIN_PASSWORD || 'Bella@2026!';
const OUT = path.join(process.env.USERPROFILE || '', 'Desktop', 'fase12-evidencias');

async function waitFlutterReady(page) {
  await page.waitForFunction(() => {
    const loader = document.querySelector('.flutter-loader');
    const hasView = !!document.querySelector('flutter-view, flt-glass-pane, canvas');
    const loaderGone =
      !loader || getComputedStyle(loader).display === 'none' || loader.clientHeight === 0;
    return hasView && loaderGone;
  }, { timeout: 120000 });
  await page.waitForTimeout(1200);
}

async function shot(page, file) {
  await page.screenshot({ path: path.join(OUT, file), fullPage: false });
  console.log('OK', file);
}

async function clickText(page, label, { maxH = 120, maxW = 700 } = {}) {
  const box = await page.evaluate(
    ({ lab, maxH, maxW }) => {
      const nodes = Array.from(document.querySelectorAll('flt-semantics'));
      let best = null;
      let score = 0;
      for (const n of nodes) {
        const aria = (n.getAttribute('aria-label') || '').trim();
        const txt = (n.innerText || '').trim();
        let s = 0;
        if (aria === lab || txt === lab) s = 3;
        else if (aria.includes(lab) || txt.includes(lab)) s = 1;
        if (s > score) {
          const r = n.getBoundingClientRect();
          if (r.width >= 1 && r.height >= 1 && r.height <= maxH && r.width <= maxW) {
            best = { x: r.x + r.width / 2, y: r.y + r.height / 2 };
            score = s;
          }
        }
      }
      return best;
    },
    { lab: label, maxH, maxW },
  );
  if (!box) return false;
  await page.mouse.click(box.x, box.y);
  await page.waitForTimeout(1200);
  return true;
}

async function clickNavLabel(page, label) {
  const box = await page.evaluate((lab) => {
    const nodes = Array.from(document.querySelectorAll('flt-semantics'));
    for (const n of nodes) {
      const txt = (n.innerText || '').trim();
      const aria = (n.getAttribute('aria-label') || '').trim();
      const val = aria || txt;
      if (!(val === lab || val.endsWith(lab) || val.includes(lab))) continue;
      const r = n.getBoundingClientRect();
      if (r.x > 240 || r.height > 56 || r.width < 8 || r.y < 50) continue;
      return { x: Math.min(r.x + 40, r.x + r.width / 2), y: r.y + r.height / 2, val };
    }
    return null;
  }, label);
  if (!box) {
    console.warn('no nav', label);
    return false;
  }
  await page.mouse.click(box.x, box.y);
  await page.waitForTimeout(1600);
  console.log('nav', box.val);
  return true;
}

async function login(page, email, pass) {
  await page.goto(BASE, { waitUntil: 'domcontentloaded' });
  await waitFlutterReady(page);
  await page.keyboard.press('Escape');
  await clickText(page, 'Entrar');
  for (let i = 0; i < 40; i++) {
    if ((await page.locator('input').count()) >= 2) break;
    await page.waitForTimeout(300);
  }
  const inputs = page.locator('input');
  await inputs.nth(0).click({ force: true });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(email, { delay: 8 });
  await inputs.nth(1).click({ force: true });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(pass, { delay: 8 });
  await clickText(page, 'Entrar na plataforma');
  await page.waitForTimeout(4500);
}

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await context.newPage();
await login(page, TENANT_EMAIL, TENANT_PASS);
await clickNavLabel(page, 'Conversas');
await page.waitForTimeout(1500);
await page.mouse.click(340, 250);
await page.waitForTimeout(2500);
await shot(page, 'fix-01-depois.png');
await shot(page, 'fix-conversas-detalhe-desktop.png');
await page.setViewportSize({ width: 800, height: 900 });
await page.waitForTimeout(700);
await clickText(page, 'Voltar');
await page.waitForTimeout(900);
await shot(page, '33-800-conversas-lista.png');
await page.mouse.click(400, 250);
await page.waitForTimeout(2500);
await shot(page, '34-800-conversas-detalhe.png');
await page.setViewportSize({ width: 390, height: 844 });
await page.mouse.click(28, 28);
await page.waitForTimeout(700);
await clickText(page, 'WhatsApp');
await page.waitForTimeout(1200);
console.log('wizard', await clickText(page, 'Assistente'));
await page.waitForTimeout(1400);
await shot(page, '39-390-whatsapp-wizard.png');
await browser.close();
console.log('DONE');
