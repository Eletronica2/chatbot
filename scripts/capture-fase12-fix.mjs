import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const BASE = process.env.ADMIN_URL || 'http://127.0.0.1:7362';
const SUPER_EMAIL = process.env.SUPER_EMAIL || 'arthurlaranjo@hotmail.com';
const SUPER_PASS = process.env.SUPER_PASSWORD || 'adminpanel';
const TENANT_EMAIL = process.env.ADMIN_EMAIL || 'admin@bellamassa.com.br';
const TENANT_PASS = process.env.ADMIN_PASSWORD || 'Bella@2026!';
const OUT = path.join(process.env.USERPROFILE || '', 'Desktop', 'fase12-evidencias');
fs.mkdirSync(OUT, { recursive: true });

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

async function clickSemantic(page, label, { exact = true, maxH = 90, maxW = 600 } = {}) {
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
  // Prefer exact left-rail match by label alone
  const box = await page.evaluate((lab) => {
    const nodes = Array.from(document.querySelectorAll('flt-semantics'));
    const c = [];
    for (const n of nodes) {
      const aria = (n.getAttribute('aria-label') || '').trim();
      const txt = (n.innerText || '').trim();
      const val = aria || txt;
      if (val !== lab && txt !== lab && aria !== lab) continue;
      const r = n.getBoundingClientRect();
      if (r.x > 240 || r.height > 56 || r.width < 8 || r.y < 50) continue;
      c.push({ x: Math.min(r.x + 40, r.x + r.width / 2), y: r.y + r.height / 2, val, x0: r.x });
    }
    c.sort((a, b) => a.x0 - b.x0);
    return c[0] || null;
  }, label);
  if (!box) {
    console.warn('nav fail', label);
    return false;
  }
  await page.mouse.click(box.x, box.y);
  await page.waitForTimeout(1600);
  console.log('nav', label, box.val);
  return true;
}

async function goHome(page) {
  await page.mouse.click(90, 36);
  await page.waitForTimeout(1400);
}

async function login(page, email, pass) {
  await page.goto(BASE, { waitUntil: 'domcontentloaded' });
  await waitFlutterReady(page);
  await page.keyboard.press('Escape');
  if (!(await clickSemantic(page, 'Entrar', { exact: true }))) {
    await page.mouse.click(1120, 40);
    await page.waitForTimeout(1500);
  }
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
  await clickSemantic(page, 'Entrar na plataforma', { exact: false });
  await page.waitForTimeout(4500);
}

async function openDrawer(page) {
  await page.mouse.click(28, 28);
  await page.waitForTimeout(800);
}

(async () => {
  const browser = await chromium.launch({ headless: true });

  // Public token routes with hard reload
  {
    const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
    const page = await context.newPage();
    await page.goto(`${BASE}/#/accept-invite?token=invalid-fase12`, { waitUntil: 'domcontentloaded' });
    await waitFlutterReady(page);
    await page.waitForTimeout(2000);
    await shot(page, '31-convite-invalid.png');
    await page.goto(`${BASE}/#/reset-password?token=invalid-fase12`, { waitUntil: 'domcontentloaded' });
    await waitFlutterReady(page);
    await page.waitForTimeout(2000);
    await shot(page, '32-reset-invalid.png');
    await context.close();
  }

  // Superadmin critical screens + multi-tenant
  {
    const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
    const page = await context.newPage();
    await login(page, SUPER_EMAIL, SUPER_PASS);
    await goHome(page);

    await openNav(page, 'Clientes');
    await page.waitForTimeout(1500);
    await shot(page, '17-1440-superadmin-clientes.png');

    // Leads tab inside Clientes
    let leads = await clickSemantic(page, 'Leads', { exact: true, maxH: 50 });
    if (!leads) {
      // click near tabs area
      await page.mouse.click(520, 120);
      await page.waitForTimeout(800);
      leads = await clickSemantic(page, 'Leads', { exact: false, maxH: 50 });
    }
    console.log('leads', leads);
    await page.waitForTimeout(1200);
    await shot(page, '18-1440-superadmin-leads.png');

    // WhatsApp admin tab
    await clickSemantic(page, 'WhatsApp', { exact: true, maxH: 50 });
    await page.waitForTimeout(1200);
    await shot(page, '19-1440-superadmin-whatsapp-admin.png');

    // Cobrança empty (home context - reset tenant first via system tenant)
    await openNav(page, 'Clientes');
    await page.waitForTimeout(1000);
    await clickSemantic(page, 'Operacao SaaS', { exact: false, maxH: 120 }) ||
      (await clickSemantic(page, 'default', { exact: false, maxH: 80 }));
    await page.waitForTimeout(1500);
    await openNav(page, 'Cobrança');
    await page.waitForTimeout(1200);
    await shot(page, '20-1440-superadmin-cobranca.png');

    // Bella -> Cobrança
    await openNav(page, 'Clientes');
    await page.waitForTimeout(1000);
    await clickSemantic(page, 'Pizzaria Bella Massa', { exact: false, maxH: 140, maxW: 700 });
    await page.waitForTimeout(2000);
    await openNav(page, 'Cobrança');
    await page.waitForTimeout(1500);
    await shot(page, 'mt-01-bella-cobranca.png');

    // Loja Centro
    await openNav(page, 'Clientes');
    await page.waitForTimeout(1000);
    await clickSemantic(page, 'Loja Centro', { exact: false, maxH: 140, maxW: 700 });
    await page.waitForTimeout(2000);
    await openNav(page, 'Cobrança');
    await page.waitForTimeout(1500);
    await shot(page, 'mt-02-loja-cobranca.png');

    // Back Bella
    await openNav(page, 'Clientes');
    await page.waitForTimeout(1000);
    await clickSemantic(page, 'Pizzaria Bella Massa', { exact: false, maxH: 140, maxW: 700 });
    await page.waitForTimeout(2000);
    await openNav(page, 'Cobrança');
    await page.waitForTimeout(1500);
    await shot(page, 'mt-03-bella-cobranca-return.png');

    // Mobile clients
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(600);
    await openDrawer(page);
    await clickSemantic(page, 'Clientes', { exact: true });
    await page.waitForTimeout(1500);
    await shot(page, '35-390-clientes-lista.png');
    await shot(page, '22-390-superadmin-clientes.png');
    const bella = await clickSemantic(page, 'Pizzaria Bella Massa', { exact: false, maxH: 140, maxW: 380 });
    console.log('bella mobile', bella);
    await page.waitForTimeout(2000);
    await shot(page, '36-390-clientes-detalhe.png');

    await openDrawer(page);
    await clickSemantic(page, 'Cobrança', { exact: true });
    await page.waitForTimeout(1500);
    await shot(page, '23-390-superadmin-cobranca.png');

    await context.close();
  }

  // Tenant: conversas detalhe + wizard + automacoes
  {
    const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
    const page = await context.newPage();
    await login(page, TENANT_EMAIL, TENANT_PASS);
    await openNav(page, 'Conversas');
    await page.waitForTimeout(1500);

    // click first conversation row roughly in list
    await page.mouse.click(360, 260);
    await page.waitForTimeout(2000);
    await shot(page, 'fix-conversas-detalhe-desktop.png');

    await page.setViewportSize({ width: 800, height: 900 });
    await page.waitForTimeout(600);
    // back if needed then open again
    await clickSemantic(page, 'Voltar', { exact: true });
    await page.waitForTimeout(800);
    await shot(page, '33-800-conversas-lista.png');
    await page.mouse.click(400, 260);
    await page.waitForTimeout(2000);
    await shot(page, '34-800-conversas-detalhe.png');

    await page.setViewportSize({ width: 390, height: 844 });
    await openDrawer(page);
    await clickSemantic(page, 'WhatsApp', { exact: true });
    await page.waitForTimeout(1200);
    const wiz = await clickSemantic(page, 'Assistente', { exact: true }) ||
      (await clickSemantic(page, 'Assistente', { exact: false }));
    console.log('wizard', wiz);
    await page.waitForTimeout(1200);
    await shot(page, '39-390-whatsapp-wizard.png');
    await page.keyboard.press('Escape');
    await clickSemantic(page, 'Fechar', { exact: true });

    await openDrawer(page);
    await clickSemantic(page, 'Automações', { exact: true });
    await page.waitForTimeout(1200);
    await shot(page, '37-390-automacoes-lista.png');
    await page.mouse.click(195, 300);
    await page.waitForTimeout(1500);
    await shot(page, '38-390-automacoes-editor.png');

    await context.close();
  }

  await browser.close();
  console.log('DONE');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
