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

const consoleLog = [];

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
  const vp = page.viewportSize();
  console.log('OK', file, `${vp?.width}x${vp?.height}`);
}

async function clickSemantic(page, label, { exact = true, maxH = 90, maxW = 520 } = {}) {
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
  await page.waitForTimeout(900);
  return true;
}

async function openNav(page, label) {
  const box = await page.evaluate((lab) => {
    const nodes = Array.from(document.querySelectorAll('flt-semantics'));
    const c = [];
    for (const n of nodes) {
      const val = (n.getAttribute('aria-label') || n.innerText || '').trim();
      if (!(val === lab || val.endsWith(' ' + lab) || val.includes(lab))) continue;
      if (/Atende Ai|Automação no|Navegação principal|tooltip|Planos,|Empresas,/i.test(val) && val !== lab)
        continue;
      const r = n.getBoundingClientRect();
      if (r.x > 280 || r.height > 72 || r.width < 1 || r.y < 40) continue;
      c.push({
        x: r.x + Math.min(r.width / 2, 90),
        y: r.y + r.height / 2,
        score: (val === lab ? 20 : 0) + (280 - r.x),
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
  await page.waitForTimeout(1400);
  console.log('nav', label);
  return true;
}

async function openDrawerNav(page, label) {
  // hamburger then item
  await page.mouse.click(28, 28);
  await page.waitForTimeout(700);
  const ok = await clickSemantic(page, label, { exact: false, maxH: 80, maxW: 320 });
  if (!ok) console.warn('drawer nav failed', label);
  await page.waitForTimeout(1200);
  return ok;
}

async function goHome(page) {
  const home = await page.evaluate(() => {
    const nodes = Array.from(document.querySelectorAll('flt-semantics'));
    for (const n of nodes) {
      const val = (n.getAttribute('aria-label') || n.innerText || '').trim();
      if (val !== 'Início' && !/^Atende Ai$/i.test(val)) continue;
      const r = n.getBoundingClientRect();
      if (r.x > 280 || r.y > 120 || r.width < 1) continue;
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    }
    return { x: 90, y: 36 };
  });
  await page.mouse.click(home.x, home.y);
  await page.waitForTimeout(1400);
}

async function login(page, email, pass) {
  await page.goto(BASE, { waitUntil: 'domcontentloaded' });
  await waitFlutterReady(page);
  await page.keyboard.press('Escape');
  if (!(await clickSemantic(page, 'Entrar', { exact: true }))) {
    await page.mouse.click(1120, 40);
    await page.waitForTimeout(1800);
  }
  let n = 0;
  for (let i = 0; i < 40; i++) {
    n = await page.locator('input').count();
    if (n >= 2) break;
    await page.waitForTimeout(350);
  }
  if (n < 2) throw new Error('login inputs missing for ' + email);
  const inputs = page.locator('input');
  await inputs.nth(0).click({ force: true });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(email, { delay: 10 });
  await inputs.nth(1).click({ force: true });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(pass, { delay: 10 });
  if (!(await clickSemantic(page, 'Entrar na plataforma', { exact: false }))) {
    await page.mouse.click(720, 560);
  }
  await page.waitForTimeout(4500);
  console.log('login', email);
}

async function logout(page) {
  const ok = await clickSemantic(page, 'Sair', { exact: true });
  if (!ok) {
    // try bottom of sidebar
    await page.mouse.click(190, 860);
  }
  await page.waitForTimeout(1800);
}

async function attachConsole(page, tag) {
  page.on('console', (msg) => {
    if (msg.type() === 'error') {
      consoleLog.push({ tag, type: 'error', text: msg.text().slice(0, 240) });
    }
  });
  page.on('pageerror', (err) => {
    consoleLog.push({ tag, type: 'pageerror', text: String(err).slice(0, 240) });
  });
}

(async () => {
  const browser = await chromium.launch({ headless: true });

  // ========== PUBLIC ==========
  {
    const context = await browser.newContext({
      viewport: { width: 1440, height: 900 },
      deviceScaleFactor: 1,
    });
    const page = await context.newPage();
    await attachConsole(page, 'public');

    await page.goto(BASE, { waitUntil: 'domcontentloaded' });
    await waitFlutterReady(page);
    await shot(page, '24-1440-landing.png');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(600);
    await shot(page, '25-390-landing.png');

    await page.setViewportSize({ width: 1440, height: 900 });
    await page.waitForTimeout(400);
    if (!(await clickSemantic(page, 'Entrar', { exact: true }))) {
      await page.mouse.click(1120, 40);
      await page.waitForTimeout(1500);
    }
    await page.waitForTimeout(1000);
    await shot(page, '26-1440-login.png');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(500);
    await shot(page, '27-390-login.png');

    // Cadastro from login
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.waitForTimeout(400);
    const cad =
      (await clickSemantic(page, 'Cadastre-se', { exact: true })) ||
      (await clickSemantic(page, 'Cadastre-se', { exact: false }));
    console.log('cadastro open', cad);
    await page.waitForTimeout(1200);
    await shot(page, '28-1440-cadastro.png');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(500);
    await shot(page, '29-390-cadastro.png');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(600);

    // Login error
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto(BASE, { waitUntil: 'domcontentloaded' });
    await waitFlutterReady(page);
    if (!(await clickSemantic(page, 'Entrar', { exact: true }))) {
      await page.mouse.click(1120, 40);
      await page.waitForTimeout(1500);
    }
    let n = 0;
    for (let i = 0; i < 40; i++) {
      n = await page.locator('input').count();
      if (n >= 2) break;
      await page.waitForTimeout(300);
    }
    const inputs = page.locator('input');
    await inputs.nth(0).click({ force: true });
    await page.keyboard.press('Control+A');
    await page.keyboard.type('naoexiste@atenda.ai', { delay: 8 });
    await inputs.nth(1).click({ force: true });
    await page.keyboard.press('Control+A');
    await page.keyboard.type('senha-errada-123', { delay: 8 });
    await clickSemantic(page, 'Entrar na plataforma', { exact: false });
    await page.waitForTimeout(2500);
    await shot(page, '30-login-error.png');

    // Invalid invite / reset
    await page.goto(`${BASE}/#/accept-invite?token=invalid-fase12`, {
      waitUntil: 'domcontentloaded',
    });
    await waitFlutterReady(page);
    await page.waitForTimeout(1500);
    await shot(page, '31-convite-invalid.png');

    await page.goto(`${BASE}/#/reset-password?token=invalid-fase12`, {
      waitUntil: 'domcontentloaded',
    });
    await waitFlutterReady(page);
    await page.waitForTimeout(1500);
    await shot(page, '32-reset-invalid.png');

    await context.close();
  }

  // ========== TENANT ==========
  {
    const context = await browser.newContext({
      viewport: { width: 1440, height: 900 },
      deviceScaleFactor: 1,
    });
    const page = await context.newPage();
    await attachConsole(page, 'tenant');
    await login(page, TENANT_EMAIL, TENANT_PASS);

    await goHome(page);
    await shot(page, '01-1440-tenant-overview.png');

    const tenantModules = [
      ['Conversas', '02-1440-tenant-conversas.png'],
      ['Automações', '03-1440-tenant-automacoes.png'],
      ['Ações', '04-1440-tenant-acoes.png'],
      ['Templates', '05-1440-tenant-templates.png'],
      ['WhatsApp', '06-1440-tenant-whatsapp.png'],
      ['Equipe', '07-1440-tenant-equipe.png'],
    ];
    for (const [label, file] of tenantModules) {
      await openNav(page, label);
      await page.waitForTimeout(800);
      await shot(page, file);
    }

    // mobile 390
    const mobileModules = [
      ['Início', '08-390-tenant-overview.png', true],
      ['Conversas', '09-390-tenant-conversas.png', false],
      ['Automações', '10-390-tenant-automacoes.png', false],
      ['Ações', '11-390-tenant-acoes.png', false],
      ['Templates', '12-390-tenant-templates.png', false],
      ['WhatsApp', '13-390-tenant-whatsapp.png', false],
      ['Equipe', '14-390-tenant-equipe.png', false],
    ];
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(700);
    for (const [label, file, isHome] of mobileModules) {
      if (isHome) await goHome(page);
      else await openDrawerNav(page, label);
      await page.waitForTimeout(700);
      await shot(page, file);
    }

    // compact conversas
    await page.setViewportSize({ width: 800, height: 900 });
    await page.waitForTimeout(500);
    await openDrawerNav(page, 'Conversas');
    await page.waitForTimeout(1000);
    await shot(page, '33-800-conversas-lista.png');
    // try open first conversation
    const opened = await page.evaluate(() => {
      const nodes = Array.from(document.querySelectorAll('flt-semantics'));
      for (const n of nodes) {
        const val = (n.getAttribute('aria-label') || n.innerText || '').trim();
        const r = n.getBoundingClientRect();
        if (r.y < 120 || r.height < 40 || r.height > 140 || r.width < 120) continue;
        if (/Buscar|Filtro|Atualizar|Conversas|Voltar/i.test(val)) continue;
        if (val.length < 3) continue;
        return { x: r.x + r.width / 2, y: r.y + r.height / 2, val: val.slice(0, 40) };
      }
      return null;
    });
    if (opened) {
      await page.mouse.click(opened.x, opened.y);
      await page.waitForTimeout(1200);
      console.log('opened conversation', opened.val);
    }
    await shot(page, '34-800-conversas-detalhe.png');

    // automacoes lista/editor 390
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(400);
    await openDrawerNav(page, 'Automações');
    await page.waitForTimeout(1000);
    await shot(page, '37-390-automacoes-lista.png');
    const flow = await clickSemantic(page, 'Editar', { exact: false, maxH: 60 }) ||
      (await clickSemantic(page, 'Abrir', { exact: false, maxH: 60 }));
    if (!flow) {
      // click first flow card mid area
      await page.mouse.click(195, 280);
      await page.waitForTimeout(1200);
    }
    await shot(page, '38-390-automacoes-editor.png');
    // back if needed
    await clickSemantic(page, 'Voltar', { exact: true });

    // whatsapp wizard
    await openDrawerNav(page, 'WhatsApp');
    await page.waitForTimeout(1000);
    const wiz =
      (await clickSemantic(page, 'Assistente', { exact: true })) ||
      (await clickSemantic(page, 'Assistente', { exact: false }));
    console.log('wizard', wiz);
    await page.waitForTimeout(1000);
    await shot(page, '39-390-whatsapp-wizard.png');
    await page.keyboard.press('Escape');
    await clickSemantic(page, 'Fechar', { exact: true });
    await clickSemantic(page, 'Cancelar', { exact: true });

    // equipe convite
    await openDrawerNav(page, 'Equipe');
    await page.waitForTimeout(900);
    const inv =
      (await clickSemantic(page, 'Convidar', { exact: false })) ||
      (await clickSemantic(page, '+ Convidar', { exact: false }));
    console.log('invite', inv);
    await page.waitForTimeout(900);
    await shot(page, '40-390-equipe-convite.png');
    await page.keyboard.press('Escape');
    await clickSemantic(page, 'Cancelar', { exact: true });

    // logout + re-login smoke already covered in public/login; do logout
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.waitForTimeout(400);
    await logout(page);
    await context.close();
  }

  // ========== SUPERADMIN ==========
  {
    const context = await browser.newContext({
      viewport: { width: 1440, height: 900 },
      deviceScaleFactor: 1,
    });
    const page = await context.newPage();
    await attachConsole(page, 'superadmin');
    await login(page, SUPER_EMAIL, SUPER_PASS);

    await goHome(page);
    await shot(page, '15-1440-superadmin-overview.png');

    await openNav(page, 'Conversas');
    await shot(page, '16-1440-superadmin-conversas.png');

    await openNav(page, 'Clientes');
    await page.waitForTimeout(1200);
    await shot(page, '17-1440-superadmin-clientes.png');

    // Leads tab
    const leads =
      (await clickSemantic(page, 'Leads', { exact: true })) ||
      (await clickSemantic(page, 'Leads', { exact: false }));
    console.log('leads', leads);
    await page.waitForTimeout(1000);
    await shot(page, '18-1440-superadmin-leads.png');

    // WhatsApp admin tab
    const waAdmin =
      (await clickSemantic(page, 'WhatsApp', { exact: true, maxH: 70 })) ||
      (await clickSemantic(page, 'WhatsApp', { exact: false, maxH: 70 }));
    console.log('wa admin', waAdmin);
    await page.waitForTimeout(1000);
    await shot(page, '19-1440-superadmin-whatsapp-admin.png');

    // Cobrança empty then bella
    await openNav(page, 'Cobrança');
    await page.waitForTimeout(1000);
    await shot(page, '20-1440-superadmin-cobranca.png');

    // Select Bella for multi-tenant / billing context
    await openNav(page, 'Clientes');
    await page.waitForTimeout(1000);
    const bella =
      (await clickSemantic(page, 'Pizzaria Bella Massa', { exact: false, maxH: 120, maxW: 600 })) ||
      (await clickSemantic(page, 'Bella Massa', { exact: false, maxH: 120, maxW: 600 }));
    console.log('select bella', bella);
    await page.waitForTimeout(2000);

    // Mobile clientes
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(600);
    await openDrawerNav(page, 'Clientes');
    await page.waitForTimeout(1000);
    await shot(page, '35-390-clientes-lista.png');
    const bellaM =
      (await clickSemantic(page, 'Pizzaria Bella Massa', { exact: false, maxH: 120, maxW: 360 })) ||
      (await clickSemantic(page, 'Bella Massa', { exact: false, maxH: 120, maxW: 360 }));
    console.log('select bella mobile', bellaM);
    await page.waitForTimeout(1800);
    await shot(page, '36-390-clientes-detalhe.png');

    await page.setViewportSize({ width: 390, height: 844 });
    await goHome(page);
    await shot(page, '21-390-superadmin-overview.png');
    await openDrawerNav(page, 'Clientes');
    await shot(page, '22-390-superadmin-clientes.png');
    await openDrawerNav(page, 'Cobrança');
    await page.waitForTimeout(1200);
    await shot(page, '23-390-superadmin-cobranca.png');

    // Multi-tenant A→B→A at 1440
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.waitForTimeout(500);
    await openNav(page, 'Clientes');
    await page.waitForTimeout(1000);
    await clickSemantic(page, 'Pizzaria Bella Massa', { exact: false, maxH: 120, maxW: 600 });
    await page.waitForTimeout(1500);
    await openNav(page, 'Cobrança');
    await page.waitForTimeout(1200);
    await shot(page, 'mt-01-bella-cobranca.png');

    await openNav(page, 'Clientes');
    await page.waitForTimeout(1000);
    await clickSemantic(page, 'Loja Centro', { exact: false, maxH: 120, maxW: 600 });
    await page.waitForTimeout(1500);
    await openNav(page, 'Cobrança');
    await page.waitForTimeout(1200);
    await shot(page, 'mt-02-loja-cobranca.png');

    await openNav(page, 'Clientes');
    await page.waitForTimeout(1000);
    await clickSemantic(page, 'Pizzaria Bella Massa', { exact: false, maxH: 120, maxW: 600 });
    await page.waitForTimeout(1500);
    await openNav(page, 'Cobrança');
    await page.waitForTimeout(1200);
    await shot(page, 'mt-03-bella-cobranca-return.png');

    await goHome(page);
    await logout(page);
    await context.close();
  }

  fs.writeFileSync(
    path.join(OUT, 'console-errors.json'),
    JSON.stringify(consoleLog, null, 2),
    'utf8',
  );
  console.log('console errors', consoleLog.length);
  await browser.close();
  console.log('DONE');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
