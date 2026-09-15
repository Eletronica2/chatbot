import { chromium } from 'playwright';
import path from 'path';

const BASE = 'http://127.0.0.1:7360';
const EMAIL = 'admin@bellamassa.com.br';
const PASS = 'Bella@2026!';
const OUT = path.join(process.env.USERPROFILE, 'Desktop', 'fase10-evidencias');

async function waitFlutterReady(page) {
  await page.waitForFunction(() => {
    const loader = document.querySelector('.flutter-loader');
    const hasView = !!document.querySelector('flutter-view, flt-glass-pane, canvas');
    const loaderGone = !loader || getComputedStyle(loader).display === 'none' || loader.clientHeight === 0;
    return hasView && loaderGone;
  }, { timeout: 120000 });
  await page.waitForTimeout(1500);
}

async function shot(page, file) {
  await page.screenshot({ path: path.join(OUT, file), fullPage: false });
  console.log('OK', file);
}

async function clickExact(page, label) {
  const box = await page.evaluate((lab) => {
    const nodes = Array.from(document.querySelectorAll('flt-semantics'));
    let best = null;
    let bestArea = Infinity;
    for (const n of nodes) {
      const val = (n.getAttribute('aria-label') || n.innerText || '').trim();
      if (val !== lab) continue;
      const r = n.getBoundingClientRect();
      if (r.width < 1 || r.height < 1) continue;
      const area = r.width * r.height;
      if (area < bestArea) {
        bestArea = area;
        best = { x: r.x + r.width / 2, y: r.y + r.height / 2, val, area };
      }
    }
    return best;
  }, label);
  if (!box) return false;
  await page.mouse.click(box.x, box.y);
  await page.waitForTimeout(900);
  console.log('click', label, box.area);
  return true;
}

async function openNav(page, label) {
  if (await clickExact(page, label)) return true;
  const box = await page.evaluate((lab) => {
    const nodes = Array.from(document.querySelectorAll('flt-semantics'));
    const candidates = [];
    for (const n of nodes) {
      const val = (n.getAttribute('aria-label') || n.innerText || '').trim();
      if (!(val === lab || val.endsWith(' ' + lab))) continue;
      if (/Atende Ai|Automação no|Navegação principal/i.test(val)) continue;
      const r = n.getBoundingClientRect();
      if (r.x > 280 || r.height > 60 || r.width > 280) continue;
      candidates.push({
        x: r.x + Math.min(r.width / 2, 90),
        y: r.y + r.height / 2,
        len: val.length,
      });
    }
    candidates.sort((a, b) => b.len - a.len);
    return candidates[0] || null;
  }, label);
  if (!box) return false;
  await page.mouse.click(box.x, box.y);
  await page.waitForTimeout(1200);
  return true;
}

async function login(page) {
  await page.goto(BASE, { waitUntil: 'domcontentloaded' });
  await waitFlutterReady(page);
  await page.keyboard.press('Escape');
  if (!(await clickExact(page, 'Entrar'))) {
    await page.mouse.click(1120, 40);
    await page.waitForTimeout(2000);
  }
  let n = 0;
  for (let i = 0; i < 40; i++) {
    n = await page.locator('input').count();
    if (n >= 2) break;
    await page.waitForTimeout(400);
  }
  if (n < 2) throw new Error('no inputs ' + n);
  const inputs = page.locator('input');
  await inputs.nth(0).click({ force: true });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(EMAIL, { delay: 12 });
  await inputs.nth(1).click({ force: true });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(PASS, { delay: 12 });
  if (!(await clickExact(page, 'Entrar na plataforma'))) {
    await page.mouse.click(720, 560);
  }
  await page.waitForTimeout(5000);
}

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1440, height: 900 },
  deviceScaleFactor: 1,
  serviceWorkers: 'block',
});
const page = await context.newPage();
await login(page);
await openNav(page, 'Equipe');
await page.waitForTimeout(2000);

// Dump labels containing Opções / Admin / Convidar
const labels = await page.evaluate(() =>
  Array.from(document.querySelectorAll('flt-semantics'))
    .map((n) => (n.getAttribute('aria-label') || n.innerText || '').trim())
    .filter((t) => /Opções|Convidar|Admin|Editar|membro|Você/i.test(t))
    .slice(0, 40),
);
console.log('labels', labels);

const openedMenu =
  (await clickExact(page, 'Opções do membro')) ||
  (await (async () => {
    // scan for button-like at right of member row
    const box = await page.evaluate(() => {
      const nodes = Array.from(document.querySelectorAll('flt-semantics'));
      for (const n of nodes) {
        const val = (n.getAttribute('aria-label') || '').trim();
        const r = n.getBoundingClientRect();
        if (r.x > 1280 && r.y > 280 && r.y < 420 && r.width < 60 && r.height < 60) {
          return { x: r.x + r.width / 2, y: r.y + r.height / 2, val };
        }
      }
      return null;
    });
    if (box) {
      console.log('right btn', box);
      await page.mouse.click(box.x, box.y);
      await page.waitForTimeout(700);
      return true;
    }
    await page.mouse.click(1348, 338);
    await page.waitForTimeout(700);
    return true;
  })());

await shot(page, '07-1440-equipe-membro.png');
console.log(
  'after menu',
  await page.evaluate(() =>
    Array.from(document.querySelectorAll('flt-semantics'))
      .map((n) => (n.getAttribute('aria-label') || n.innerText || '').trim())
      .filter((t) => /Editar|Desativar|Reativar|redefinição|Opções/i.test(t)),
  ),
);

if (await clickExact(page, 'Editar')) {
  await page.waitForTimeout(800);
  await shot(page, '13-equipe-edicao.png');
  await shot(page, '14-equipe-role.png');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(500);
} else {
  console.warn('no Editar — skip 13/14 or keep previous');
}

await page.mouse.click(1348, 338);
await page.waitForTimeout(700);
if ((await clickExact(page, 'Desativar acesso')) || (await clickExact(page, 'Reativar acesso'))) {
  await page.waitForTimeout(700);
  await shot(page, '15-equipe-status-confirmacao.png');
  await clickExact(page, 'Cancelar');
  await page.waitForTimeout(400);
}

await page.mouse.click(1348, 338);
await page.waitForTimeout(700);
if (await clickExact(page, 'Gerar redefinição de senha')) {
  await page.waitForTimeout(700);
  await shot(page, '16-equipe-reset-confirmacao.png');
  await clickExact(page, 'Cancelar');
}

await openNav(page, 'Início');
await clickExact(page, 'Início');
await page.waitForTimeout(1000);
await shot(page, '24-overview-smoke.png');

await page.setViewportSize({ width: 390, height: 844 });
await page.waitForTimeout(500);
await openNav(page, 'Equipe');
await page.waitForTimeout(1200);
if (!(await clickExact(page, 'Opções do membro'))) {
  await page.mouse.click(355, 360);
  await page.waitForTimeout(700);
}
await shot(page, '08-390-equipe-membro.png');

await browser.close();
console.log('DONE');
