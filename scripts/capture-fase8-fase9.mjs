import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const BASE = process.env.ADMIN_URL || 'http://127.0.0.1:7357';
const EMAIL = process.env.ADMIN_EMAIL || 'admin@bellamassa.com.br';
const PASS = process.env.ADMIN_PASSWORD || 'Bella@2026!';
const OUT8 = path.join(process.env.USERPROFILE || '', 'Desktop', 'fase8-evidencias');
const OUT9 = path.join(process.env.USERPROFILE || '', 'Desktop', 'fase9-evidencias');

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

async function waitFlutterReady(page, timeoutMs = 120000) {
  await page.waitForFunction(
    () => {
      const loader = document.querySelector('.flutter-loader');
      const hasView = !!document.querySelector('flutter-view, flt-glass-pane, canvas');
      const loaderGone =
        !loader || getComputedStyle(loader).display === 'none' || loader.clientHeight === 0;
      return hasView && loaderGone;
    },
    { timeout: timeoutMs },
  );
  await page.waitForTimeout(1500);
}

async function shot(page, dir, file) {
  const dest = path.join(dir, file);
  await page.screenshot({ path: dest, fullPage: false });
  const vp = page.viewportSize();
  console.log('OK', file, `${vp.width}x${vp.height}`);
}

/** Click Flutter semantic node by label. Prefer exact aria/text match. */
async function clickSemantic(page, label, { exact = true } = {}) {
  const box = await page.evaluate(
    ({ lab, exactMatch }) => {
      const nodes = Array.from(document.querySelectorAll('flt-semantics'));
      const score = (n) => {
        const aria = (n.getAttribute('aria-label') || '').trim();
        const txt = (n.innerText || '').trim();
        if (aria === lab || txt === lab) return 2;
        if (!exactMatch && (aria.includes(lab) || txt.includes(lab))) return 1;
        return 0;
      };
      let best = null;
      let bestScore = 0;
      for (const n of nodes) {
        const s = score(n);
        if (s > bestScore) {
          const r = n.getBoundingClientRect();
          if (r.width >= 1 && r.height >= 1) {
            best = { x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width, h: r.height, s };
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
    await page.waitForTimeout(1100);
    return true;
  }
  const loc = exact
    ? page.getByText(label, { exact: true })
    : page.getByText(label, { exact: false });
  if (await loc.count()) {
    const b = await loc.first().boundingBox();
    if (b) {
      await page.mouse.click(b.x + b.width / 2, b.y + b.height / 2);
      await page.waitForTimeout(1100);
      return true;
    }
  }
  return false;
}

async function login(page) {
  await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 120000 });
  await waitFlutterReady(page);
  await shot(page, OUT9, '_debug-landing.png');

  // Landing → Entrar (NOT "Começar agora")
  if (!(await clickSemantic(page, 'Entrar', { exact: true }))) {
    // Approx: Entrar is left of gradient CTA in header
    await page.mouse.click(1120, 40);
    await page.waitForTimeout(2000);
  }
  // Close signup modal if opened by mistake
  const closed = await clickSemantic(page, 'Fechar', { exact: false });
  if (!closed) {
    // X on modal top-right area
    const hasWizard = await page.evaluate(() =>
      Array.from(document.querySelectorAll('flt-semantics')).some((n) =>
        (n.getAttribute('aria-label') || n.innerText || '').includes('Vamos conhecer'),
      ),
    );
    if (hasWizard) {
      await page.keyboard.press('Escape');
      await page.waitForTimeout(500);
      await clickSemantic(page, 'Entrar', { exact: true });
      await page.mouse.click(1120, 40);
      await page.waitForTimeout(1500);
    }
  }
  await shot(page, OUT9, '_debug-login-screen.png');

  let n = 0;
  for (let i = 0; i < 40; i++) {
    n = await page.locator('input').count();
    if (n >= 2) break;
    // password field may mount late
    await page.waitForTimeout(400);
  }
  console.log('input count', n);
  if (n < 2) {
    // last resort: navigate by clicking Entrar again
    await page.keyboard.press('Escape');
    await page.waitForTimeout(400);
    await clickSemantic(page, 'Entrar', { exact: true });
    await page.waitForTimeout(2000);
    n = await page.locator('input').count();
    console.log('input count retry', n);
  }
  if (n < 2) throw new Error('Login inputs not found');

  const inputs = page.locator('input');
  await inputs.nth(0).click({ force: true });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(EMAIL, { delay: 15 });
  await inputs.nth(1).click({ force: true });
  await page.keyboard.press('Control+A');
  await page.keyboard.type(PASS, { delay: 15 });
  await page.waitForTimeout(300);

  if (!(await clickSemantic(page, 'Entrar na plataforma'))) {
    await page.mouse.click(720, 560);
  }
  await page.waitForTimeout(5000);
  await shot(page, OUT9, '_debug-after-login.png');

  // Confirm dashboard: look for Conversas semantic
  for (let i = 0; i < 20; i++) {
    const ok = await page.evaluate(
      () =>
        Array.from(document.querySelectorAll('flt-semantics')).some((n) =>
          (n.getAttribute('aria-label') || n.innerText || '').includes('Conversas'),
        ),
    );
    if (ok) break;
    // retry submit
    if (i === 5) {
      await inputs.nth(1).click({ force: true });
      await page.keyboard.press('Control+A');
      await page.keyboard.type(PASS, { delay: 15 });
      await page.mouse.click(720, 560);
    }
    await page.waitForTimeout(500);
  }
  console.log('Login done');
}

async function openNav(page, label) {
  // Sidebar semantics often = helper + " " + label
  const aliases =
    label === 'Templates'
      ? ['Templates', 'Templates WhatsApp']
      : label === 'Início'
        ? ['Início']
        : [label];
  for (const a of aliases) {
    if (await clickSemantic(page, a, { exact: true })) {
      console.log('nav exact ->', a);
      return true;
    }
  }
  // Match sidebar nodes whose aria/text ends with " <label>" (helper prefix).
  // Do NOT use bare endsWith(label) — brand text ends with "WhatsApp".
  const box = await page.evaluate((lab) => {
    const nodes = Array.from(document.querySelectorAll('flt-semantics'));
    const candidates = [];
    for (const n of nodes) {
      const aria = (n.getAttribute('aria-label') || '').trim();
      const txt = (n.innerText || '').trim();
      const val = aria || txt;
      const ok = val === lab || val.endsWith(' ' + lab);
      if (!ok) continue;
      // Exclude brand / home chrome in sidebar
      if (/Atenda Ai|Automação no|Início|Recolher/i.test(val)) continue;
      const r = n.getBoundingClientRect();
      if (r.width < 1 || r.height < 1) continue;
      if (r.x > 280) continue; // sidebar only
      candidates.push({
        x: r.x + Math.min(r.width / 2, 100),
        y: r.y + r.height / 2,
        val,
        yTop: r.y,
        len: val.length,
      });
    }
    // Prefer longer labels (helper+name) over bare name collisions
    candidates.sort((a, b) => b.len - a.len || a.yTop - b.yTop);
    return candidates[0] || null;
  }, label);
  if (box) {
    await page.mouse.click(box.x, box.y);
    await page.waitForTimeout(1200);
    console.log('nav endsWith ->', label);
    return true;
  }
  console.warn('nav failed', label);
  return false;
}

async function listSemantics(page) {
  return page.evaluate(() =>
    Array.from(document.querySelectorAll('flt-semantics'))
      .map((n) => (n.getAttribute('aria-label') || n.innerText || '').trim())
      .filter((t) => t && t.length < 60)
      .slice(0, 60),
  );
}

async function tryClickFirstTemplate(page) {
  // Prefer status chip
  for (const st of ['APPROVED', 'PENDING', 'REJECTED']) {
    if (await clickSemantic(page, st)) return true;
  }
  const vp = page.viewportSize();
  if (vp.width >= 1100) {
    await page.mouse.click(320, 300);
  } else {
    await page.mouse.click(vp.width / 2, 280);
  }
  await page.waitForTimeout(900);
  return true;
}

(async () => {
  ensureDir(OUT8);
  ensureDir(OUT9);
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  page.setDefaultTimeout(30000);

  await login(page);
  console.log('semantics sample', await listSemantics(page));

  // ========== FASE 8 ==========
  await openNav(page, 'Templates');
  await page.waitForTimeout(2000);
  await shot(page, OUT8, '01-1440-templates-lista-detalhe.png');
  await tryClickFirstTemplate(page);
  await shot(page, OUT8, '02-1440-template-selecionado.png');
  await shot(page, OUT8, '03-1440-template-preview.png');

  for (const vp of VIEWPORTS.slice(1)) {
    await page.setViewportSize({ width: vp.width, height: vp.height });
    await page.waitForTimeout(800);
    if (vp.width >= 1100) {
      await shot(
        page,
        OUT8,
        vp.name === '1366' ? '04-1366-templates.png' : '05-1200-templates.png',
      );
    } else {
      const listMap = { '800': '06', '680': '08', '390': '10' };
      const detMap = { '800': '07', '680': '09', '390': '11' };
      await clickSemantic(page, 'Voltar');
      await page.waitForTimeout(500);
      await shot(page, OUT8, `${listMap[vp.name]}-${vp.name}-templates-lista.png`);
      await tryClickFirstTemplate(page);
      await shot(page, OUT8, `${detMap[vp.name]}-${vp.name}-template-detalhe.png`);
    }
  }

  await page.setViewportSize({ width: 1440, height: 900 });
  await openNav(page, 'Templates');
  await page.waitForTimeout(1000);
  const body = await listSemantics(page);
  if (body.some((t) => /\{\{\d+\}\}/.test(t))) {
    await shot(page, OUT8, '12-template-com-parametros.png');
  }
  if (body.some((t) => /APPROVED/i.test(t))) {
    await shot(page, OUT8, '15-template-status-APPROVED.png');
  }

  // ========== FASE 9 ==========
  await openNav(page, 'WhatsApp');
  await page.waitForTimeout(2000);
  console.log('whatsapp semantics', await listSemantics(page));

  const waMap = {
    1440: '01-1440-whatsapp.png',
    1366: '02-1366-whatsapp.png',
    1200: '03-1200-whatsapp.png',
    800: '04-800-whatsapp.png',
    680: '05-680-whatsapp.png',
    390: '06-390-whatsapp.png',
  };
  for (const vp of VIEWPORTS) {
    await page.setViewportSize({ width: vp.width, height: vp.height });
    await page.waitForTimeout(700);
    await shot(page, OUT9, waMap[vp.name]);
  }

  await page.setViewportSize({ width: 1440, height: 900 });
  await openNav(page, 'WhatsApp');
  await page.waitForTimeout(1200);

  const sem = await listSemantics(page);
  const connected = sem.some((t) => /pronta para atender|Conta ativa|Reconectar/i.test(t));
  const disconnected = sem.some((t) => /Conectar WhatsApp|ainda não|sem conta/i.test(t));
  if (connected) {
    await shot(page, OUT9, '07-1440-whatsapp-conectado.png');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(600);
    await shot(page, OUT9, '08-390-whatsapp-conectado.png');
  }
  if (disconnected) {
    await page.setViewportSize({ width: 1440, height: 900 });
    await shot(page, OUT9, '09-1440-whatsapp-desconectado.png');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(500);
    await shot(page, OUT9, '10-390-whatsapp-desconectado.png');
  }

  // Wizard
  await page.setViewportSize({ width: 1440, height: 900 });
  await openNav(page, 'WhatsApp');
  await page.waitForTimeout(1000);
  const opened =
    (await clickSemantic(page, 'Conectar WhatsApp')) ||
    (await clickSemantic(page, 'Assistente')) ||
    (await clickSemantic(page, 'Reconectar / atualizar')) ||
    (await clickSemantic(page, 'Abrir Meta agora'));
  if (opened) {
    await page.waitForTimeout(1000);
    await shot(page, OUT9, '11-1440-whatsapp-wizard.png');
    await page.setViewportSize({ width: 800, height: 900 });
    await page.waitForTimeout(500);
    await shot(page, OUT9, '12-800-whatsapp-wizard.png');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(500);
    await shot(page, OUT9, '13-390-whatsapp-wizard.png');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(400);
  } else {
    console.warn('Wizard CTA not found');
  }

  // Smokes
  await page.setViewportSize({ width: 1440, height: 900 });
  const smokes = [
    ['Templates', '17-templates-smoke.png'],
    ['Ações', '18-acoes-smoke.png'],
    ['Automações', '19-automacoes-smoke.png'],
    ['Clientes', '20-clientes-smoke.png'],
    ['Conversas', '22-conversas-smoke.png'],
  ];
  for (const [label, file] of smokes) {
    await openNav(page, label);
    await page.waitForTimeout(1200);
    await shot(page, OUT9, file);
  }

  // Overview via logo / home
  const homeOk =
    (await clickSemantic(page, 'Início')) ||
    (await clickSemantic(page, 'Atenda Ai')) ||
    (await clickSemantic(page, 'home'));
  if (!homeOk) {
    // Click brand area
    await page.mouse.click(80, 40);
    await page.waitForTimeout(1000);
  }
  await shot(page, OUT9, '21-overview-smoke.png');

  // Logout
  (await clickSemantic(page, 'Sair')) || (await clickSemantic(page, 'Logout'));
  await page.waitForTimeout(1500);
  // If still in app, click logout icon bottom
  await page.mouse.click(190, 860);
  await page.waitForTimeout(1000);
  await shot(page, OUT9, '23-login-smoke.png');

  await browser.close();
  console.log('DONE');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
