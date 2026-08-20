import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const BASE = process.env.ADMIN_URL || 'http://127.0.0.1:7360';
const EMAIL = process.env.ADMIN_EMAIL || 'admin@bellamassa.com.br';
const PASS = process.env.ADMIN_PASSWORD || 'Bella@2026!';
const OUT = path.join(process.env.USERPROFILE || '', 'Desktop', 'fase10-evidencias');

const VIEWPORTS = [
  { name: '1440', width: 1440, height: 900 },
  { name: '1366', width: 1366, height: 768 },
  { name: '1200', width: 1200, height: 800 },
  { name: '800', width: 800, height: 900 },
  { name: '680', width: 680, height: 900 },
  { name: '390', width: 390, height: 844 },
];

function ensureDir(d) {
  fs.mkdirSync(d, { recursive: true });
}

async function waitFlutterReady(page) {
  await page.waitForFunction(
    () => {
      const loader = document.querySelector('.flutter-loader');
      const hasView = !!document.querySelector('flutter-view, flt-glass-pane, canvas');
      const loaderGone =
        !loader || getComputedStyle(loader).display === 'none' || loader.clientHeight === 0;
      return hasView && loaderGone;
    },
    { timeout: 120000 },
  );
  await page.waitForTimeout(1500);
}

async function shot(page, file) {
  const dest = path.join(OUT, file);
  await page.screenshot({ path: dest, fullPage: false });
  const vp = page.viewportSize();
  console.log('OK', file, `${vp.width}x${vp.height}`);
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
          if (r.width >= 1 && r.height >= 1) {
            best = { x: r.x + r.width / 2, y: r.y + r.height / 2 };
            bestScore = s;
          }
        }
      }
      return best;
    },
    { lab: label, exactMatch: exact },
  );
  if (box) {
    await page.mouse.click(box.x, box.y);
    await page.waitForTimeout(1000);
    return true;
  }
  return false;
}

async function openNav(page, label) {
  if (await clickSemantic(page, label, { exact: true })) {
    console.log('nav exact', label);
    return true;
  }
  const box = await page.evaluate((lab) => {
    const nodes = Array.from(document.querySelectorAll('flt-semantics'));
    const candidates = [];
    for (const n of nodes) {
      const val = (n.getAttribute('aria-label') || n.innerText || '').trim();
      if (!(val === lab || val.endsWith(' ' + lab))) continue;
      if (/Atenda Ai|Automação no|Início|Recolher/i.test(val)) continue;
      const r = n.getBoundingClientRect();
      if (r.width < 1 || r.height < 1 || r.x > 280) continue;
      candidates.push({
        x: r.x + Math.min(r.width / 2, 100),
        y: r.y + r.height / 2,
        len: val.length,
      });
    }
    candidates.sort((a, b) => b.len - a.len);
    return candidates[0] || null;
  }, label);
  if (box) {
    await page.mouse.click(box.x, box.y);
    await page.waitForTimeout(1200);
    console.log('nav endsWith', label);
    return true;
  }
  console.warn('nav failed', label);
  return false;
}

async function login(page) {
  await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 120000 });
  await waitFlutterReady(page);
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
  if (n < 2) throw new Error('login inputs missing');
  const inputs = page.locator('input');
  await inputs.nth(0).click({ force: true });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(EMAIL, { delay: 12 });
  await inputs.nth(1).click({ force: true });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(PASS, { delay: 12 });
  if (!(await clickSemantic(page, 'Entrar na plataforma', { exact: false }))) {
    await page.mouse.click(720, 560);
  }
  await page.waitForTimeout(5000);
  console.log('login ok');
}

(async () => {
  ensureDir(OUT);
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  page.setDefaultTimeout(30000);

  await login(page);
  await openNav(page, 'Equipe');
  await page.waitForTimeout(2000);

  const equipeMap = {
    1440: '01-1440-equipe.png',
    1366: '02-1366-equipe.png',
    1200: '03-1200-equipe.png',
    800: '04-800-equipe.png',
    680: '05-680-equipe.png',
    390: '06-390-equipe.png',
  };
  for (const vp of VIEWPORTS) {
    await page.setViewportSize({ width: vp.width, height: vp.height });
    await page.waitForTimeout(700);
    await shot(page, equipeMap[vp.name]);
  }

  // Membro / menu
  await page.setViewportSize({ width: 1440, height: 900 });
  await openNav(page, 'Equipe');
  await page.waitForTimeout(1000);
  // open overflow near first row
  await page.mouse.click(1380, 320);
  await page.waitForTimeout(600);
  await shot(page, '07-1440-equipe-membro.png');
  await page.keyboard.press('Escape');

  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(500);
  await page.mouse.click(360, 300);
  await page.waitForTimeout(600);
  await shot(page, '08-390-equipe-membro.png');
  await page.keyboard.press('Escape');

  // Convite dialog
  await page.setViewportSize({ width: 1440, height: 900 });
  await openNav(page, 'Equipe');
  await page.waitForTimeout(800);
  await clickSemantic(page, 'Convidar', { exact: true });
  await page.waitForTimeout(1000);
  await shot(page, '09-1440-equipe-convite.png');

  await page.setViewportSize({ width: 800, height: 900 });
  await page.waitForTimeout(500);
  await shot(page, '10-800-equipe-convite.png');

  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(500);
  await shot(page, '11-390-equipe-convite.png');

  // validation: submit empty
  await clickSemantic(page, 'Gerar convite', { exact: true });
  await page.waitForTimeout(700);
  await shot(page, '12-equipe-convite-validacao.png');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(400);

  // Edit dialog
  await page.setViewportSize({ width: 1440, height: 900 });
  await openNav(page, 'Equipe');
  await page.waitForTimeout(800);
  await page.mouse.click(1380, 320);
  await page.waitForTimeout(400);
  await clickSemantic(page, 'Editar', { exact: true });
  await page.waitForTimeout(900);
  await shot(page, '13-equipe-edicao.png');
  // role dropdown visible in same dialog
  await shot(page, '14-equipe-role.png');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(400);

  // Status confirmation
  await page.mouse.click(1380, 320);
  await page.waitForTimeout(400);
  const toggled =
    (await clickSemantic(page, 'Desativar acesso', { exact: true })) ||
    (await clickSemantic(page, 'Reativar acesso', { exact: true }));
  if (toggled) {
    await page.waitForTimeout(700);
    await shot(page, '15-equipe-status-confirmacao.png');
    await clickSemantic(page, 'Cancelar', { exact: true });
    await page.waitForTimeout(400);
  }

  // Reset confirmation
  await page.mouse.click(1380, 320);
  await page.waitForTimeout(400);
  if (await clickSemantic(page, 'Gerar redefinição de senha', { exact: true })) {
    await page.waitForTimeout(700);
    await shot(page, '16-equipe-reset-confirmacao.png');
    await clickSemantic(page, 'Cancelar', { exact: true });
    await page.waitForTimeout(400);
  }

  // Smokes
  const smokes = [
    ['WhatsApp', '20-whatsapp-smoke.png'],
    ['Templates', '21-templates-smoke.png'],
    ['Ações', '22-acoes-smoke.png'],
    ['Automações', '23-automacoes-smoke.png'],
    ['Conversas', '25-conversas-smoke.png'],
  ];
  for (const [label, file] of smokes) {
    await openNav(page, label);
    await page.waitForTimeout(1200);
    await shot(page, file);
  }
  await openNav(page, 'Início');
  await page.waitForTimeout(1000);
  await shot(page, '24-overview-smoke.png');

  // Login smoke
  await clickSemantic(page, 'Sair', { exact: true });
  await page.waitForTimeout(1500);
  if (await clickSemantic(page, 'Entrar', { exact: true })) {
    await page.waitForTimeout(1500);
  }
  await shot(page, '26-login-smoke.png');

  await browser.close();
  console.log('DONE');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
