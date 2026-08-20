import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const BASE = process.env.ADMIN_URL || 'http://127.0.0.1:7361';
const SUPER_EMAIL = process.env.SUPER_EMAIL || 'arthurlaranjo@hotmail.com';
const SUPER_PASS = process.env.SUPER_PASSWORD || 'adminpanel';
const TENANT_EMAIL = process.env.ADMIN_EMAIL || 'admin@bellamassa.com.br';
const TENANT_PASS = process.env.ADMIN_PASSWORD || 'Bella@2026!';
const OUT = path.join(process.env.USERPROFILE || '', 'Desktop', 'fase11-evidencias');

const VIEWPORTS = [
  { name: '1440', width: 1440, height: 900 },
  { name: '1366', width: 1366, height: 768 },
  { name: '1200', width: 1200, height: 800 },
  { name: '800', width: 800, height: 900 },
  { name: '680', width: 680, height: 900 },
  { name: '390', width: 390, height: 844 },
];

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
  const vp = page.viewportSize();
  console.log('OK', file, `${vp.width}x${vp.height}`);
}

async function clickSemantic(page, label, { exact = true, maxH = 80, maxW = 400 } = {}) {
  const box = await page.evaluate(
    ({ lab, exactMatch, maxH, maxW }) => {
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
          if (r.width >= 1 && r.height >= 1 && r.height <= maxH && r.width <= maxW) {
            best = { x: r.x + r.width / 2, y: r.y + r.height / 2 };
            bestScore = s;
          }
        }
      }
      return best;
    },
    { lab: label, exactMatch: exact, maxH, maxW },
  );
  if (!box) return false;
  await page.mouse.click(box.x, box.y);
  await page.waitForTimeout(1000);
  return true;
}

async function openNav(page, label) {
  if (await clickSemantic(page, label, { exact: true })) {
    console.log('nav', label);
    return true;
  }
  const box = await page.evaluate((lab) => {
    const nodes = Array.from(document.querySelectorAll('flt-semantics'));
    const c = [];
    for (const n of nodes) {
      const val = (n.getAttribute('aria-label') || n.innerText || '').trim();
      if (!(val === lab || val.endsWith(' ' + lab))) continue;
      if (/Atenda Ai|Automação no|Navegação principal/i.test(val)) continue;
      const r = n.getBoundingClientRect();
      if (r.x > 280 || r.height > 60 || r.width < 1) continue;
      c.push({ x: r.x + Math.min(r.width / 2, 90), y: r.y + r.height / 2, len: val.length });
    }
    c.sort((a, b) => b.len - a.len);
    return c[0] || null;
  }, label);
  if (!box) {
    console.warn('nav failed', label);
    return false;
  }
  await page.mouse.click(box.x, box.y);
  await page.waitForTimeout(1200);
  console.log('nav endsWith', label);
  return true;
}

async function login(page, email, pass) {
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
  if (n < 2) throw new Error('login inputs missing');
  const inputs = page.locator('input');
  await inputs.nth(0).click({ force: true });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(email, { delay: 12 });
  await inputs.nth(1).click({ force: true });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(pass, { delay: 12 });
  if (!(await clickSemantic(page, 'Entrar na plataforma', { exact: false }))) {
    await page.mouse.click(720, 560);
  }
  await page.waitForTimeout(5000);
  console.log('login', email);
}

async function selectBella(page) {
  await openNav(page, 'Clientes');
  await page.waitForTimeout(2000);
  // click Bella Massa text
  const ok =
    (await clickSemantic(page, 'Pizzaria Bella Massa', { exact: false, maxH: 120, maxW: 600 })) ||
    (await clickSemantic(page, 'Bella Massa', { exact: false, maxH: 120, maxW: 600 })) ||
    (await clickSemantic(page, 'pizzaria_bella_massa', { exact: false, maxH: 120, maxW: 600 }));
  if (!ok) {
    // try mid-list click
    await page.mouse.click(360, 280);
  }
  await page.waitForTimeout(2500);
  console.log('selected bella?', ok);
}

(async () => {
  const browser = await chromium.launch({ headless: true });

  // ---- Superadmin session ----
  {
    const context = await browser.newContext({
      viewport: { width: 1440, height: 900 },
      deviceScaleFactor: 1,
    });
    const page = await context.newPage();
    await login(page, SUPER_EMAIL, SUPER_PASS);

    // Empty / system billing
    await openNav(page, 'Cobrança');
    await page.waitForTimeout(1500);
    await shot(page, '14-1440-cobranca-superadmin.png');
    await shot(page, '18-cobranca-empty.png');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(600);
    await shot(page, '15-390-cobranca-superadmin.png');

    // Select Bella then billing
    await page.setViewportSize({ width: 1440, height: 900 });
    await selectBella(page);
    await openNav(page, 'Cobrança');
    await page.waitForTimeout(2000);

    const map = {
      1440: '01-1440-cobranca-tenant.png',
      1366: '02-1366-cobranca-tenant.png',
      1200: '03-1200-cobranca-tenant.png',
      800: '04-800-cobranca-tenant.png',
      680: '05-680-cobranca-tenant.png',
      390: '06-390-cobranca-tenant.png',
    };
    for (const vp of VIEWPORTS) {
      await page.setViewportSize({ width: vp.width, height: vp.height });
      await page.waitForTimeout(700);
      await shot(page, map[vp.name]);
    }

    await page.setViewportSize({ width: 1440, height: 900 });
    await openNav(page, 'Cobrança');
    await page.waitForTimeout(1000);
    await shot(page, '07-1440-plano-atual-consumo.png');
    await shot(page, '09-1440-catalogo-planos.png');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(500);
    await shot(page, '08-390-plano-atual-consumo.png');
    await shot(page, '10-390-catalogo-planos.png');

    // Troca plano confirm dialog
    await page.setViewportSize({ width: 1440, height: 900 });
    await openNav(page, 'Cobrança');
    await page.waitForTimeout(1000);
    const opened =
      (await clickSemantic(page, 'Contratar', { exact: true })) ||
      (await clickSemantic(page, 'Trocar / renovar', { exact: true }));
    if (opened) {
      await page.waitForTimeout(800);
      await shot(page, '11-1440-troca-plano.png');
      await page.setViewportSize({ width: 800, height: 900 });
      await page.waitForTimeout(500);
      await shot(page, '12-800-troca-plano.png');
      await page.setViewportSize({ width: 390, height: 844 });
      await page.waitForTimeout(500);
      await shot(page, '13-390-troca-plano.png');
      await clickSemantic(page, 'Cancelar', { exact: true });
    } else {
      console.warn('checkout CTA not available (provider?)');
    }

    await page.setViewportSize({ width: 1440, height: 900 });
    await openNav(page, 'Clientes');
    await page.waitForTimeout(1200);
    await shot(page, '24-clientes-smoke.png');
    await openNav(page, 'Início');
    await clickSemantic(page, 'Início', { exact: true });
    await page.waitForTimeout(1000);
    await shot(page, '25-overview-smoke.png');

    await context.close();
  }

  // ---- Tenant session smokes ----
  {
    const context = await browser.newContext({
      viewport: { width: 1440, height: 900 },
      deviceScaleFactor: 1,
    });
    const page = await context.newPage();
    await login(page, TENANT_EMAIL, TENANT_PASS);

    const smokes = [
      ['Equipe', '19-equipe-smoke.png'],
      ['WhatsApp', '20-whatsapp-smoke.png'],
      ['Templates', '21-templates-smoke.png'],
      ['Ações', '22-acoes-smoke.png'],
      ['Automações', '23-automacoes-smoke.png'],
      ['Conversas', '26-conversas-smoke.png'],
    ];
    for (const [label, file] of smokes) {
      await openNav(page, label);
      await page.waitForTimeout(1200);
      await shot(page, file);
    }

    await clickSemantic(page, 'Sair', { exact: true });
    await page.waitForTimeout(1500);
    await clickSemantic(page, 'Entrar', { exact: true });
    await page.waitForTimeout(1500);
    await shot(page, '27-login-smoke.png');
    await context.close();
  }

  await browser.close();
  console.log('DONE');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
