import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const BASE = process.env.ADMIN_URL || 'http://127.0.0.1:7362';
const SUPER_EMAIL = process.env.SUPER_EMAIL || 'arthurlaranjo@hotmail.com';
const SUPER_PASS = process.env.SUPER_PASSWORD || 'adminpanel';
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

async function dumpNav(page) {
  return page.evaluate(() =>
    Array.from(document.querySelectorAll('flt-semantics'))
      .map((n) => {
        const r = n.getBoundingClientRect();
        return {
          aria: (n.getAttribute('aria-label') || '').trim(),
          txt: (n.innerText || '').trim().slice(0, 80),
          x: Math.round(r.x),
          y: Math.round(r.y),
          w: Math.round(r.width),
          h: Math.round(r.height),
        };
      })
      .filter((n) => n.x < 260 && n.y > 40 && n.y < 700 && n.h > 10 && n.h < 70 && n.w > 10),
  );
}

async function clickNavLabel(page, label) {
  const nodes = await dumpNav(page);
  const hit = nodes.find(
    (n) =>
      n.aria === label ||
      n.txt === label ||
      n.aria.endsWith(label) ||
      n.txt.endsWith(label) ||
      n.aria.includes(label) ||
      n.txt.includes(label),
  );
  if (!hit) {
    console.warn('no nav node', label, nodes.map((n) => n.aria || n.txt));
    return false;
  }
  await page.mouse.click(hit.x + Math.min(40, hit.w / 2), hit.y + hit.h / 2);
  await page.waitForTimeout(1600);
  console.log('clicked', label, hit.aria || hit.txt);
  return true;
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

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();
  await login(page, SUPER_EMAIL, SUPER_PASS);

  // Dump nav for diagnostics
  console.log('NAV', JSON.stringify(await dumpNav(page), null, 2));

  // Open Clientes via CTA
  const viaBtn = await clickText(page, 'Gerenciar empresas');
  console.log('gerenciar', viaBtn);
  await page.waitForTimeout(1500);
  if (!viaBtn) await clickNavLabel(page, 'Clientes');
  await shot(page, '17-1440-superadmin-clientes.png');

  // Leads tab
  await clickText(page, 'Leads');
  await page.waitForTimeout(1200);
  await shot(page, '18-1440-superadmin-leads.png');

  // WhatsApp admin tab
  await clickText(page, 'WhatsApp');
  await page.waitForTimeout(1200);
  await shot(page, '19-1440-superadmin-whatsapp-admin.png');

  // Empresas again then Bella
  await clickText(page, 'Empresas');
  await page.waitForTimeout(800);
  await clickText(page, 'Pizzaria Bella Massa', { maxH: 140 });
  await page.waitForTimeout(2000);

  await clickNavLabel(page, 'Cobrança');
  await page.waitForTimeout(1500);
  await shot(page, 'mt-01-bella-cobranca.png');

  await clickNavLabel(page, 'Clientes');
  await page.waitForTimeout(1000);
  await clickText(page, 'Loja Centro', { maxH: 140 });
  await page.waitForTimeout(2000);
  await clickNavLabel(page, 'Cobrança');
  await page.waitForTimeout(1500);
  await shot(page, 'mt-02-loja-cobranca.png');

  await clickNavLabel(page, 'Clientes');
  await page.waitForTimeout(1000);
  await clickText(page, 'Pizzaria Bella Massa', { maxH: 140 });
  await page.waitForTimeout(2000);
  await clickNavLabel(page, 'Cobrança');
  await page.waitForTimeout(1500);
  await shot(page, 'mt-03-bella-cobranca-return.png');

  // System empty cobranca
  await clickNavLabel(page, 'Clientes');
  await page.waitForTimeout(1000);
  await clickText(page, 'Operacao SaaS', { maxH: 140 }) ||
    (await clickText(page, 'default', { maxH: 80 }));
  await page.waitForTimeout(1500);
  await clickNavLabel(page, 'Cobrança');
  await page.waitForTimeout(1200);
  await shot(page, '20-1440-superadmin-cobranca.png');

  // Mobile clientes
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(600);
  await page.mouse.click(28, 28);
  await page.waitForTimeout(700);
  await clickText(page, 'Clientes');
  await page.waitForTimeout(1500);
  await shot(page, '35-390-clientes-lista.png');
  await shot(page, '22-390-superadmin-clientes.png');
  await clickText(page, 'Pizzaria Bella Massa', { maxH: 140, maxW: 380 });
  await page.waitForTimeout(2000);
  await shot(page, '36-390-clientes-detalhe.png');
  await page.mouse.click(28, 28);
  await page.waitForTimeout(700);
  await clickText(page, 'Cobrança');
  await page.waitForTimeout(1500);
  await shot(page, '23-390-superadmin-cobranca.png');

  await context.close();

  // Tenant conversas detail + wizard
  const tctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const tp = await tctx.newPage();
  await login(tp, TENANT_EMAIL, TENANT_PASS);
  console.log('TENANT NAV', JSON.stringify(await dumpNav(tp), null, 2));
  await clickNavLabel(tp, 'Conversas');
  await tp.waitForTimeout(1500);
  // click first row in list (center of list column)
  await tp.mouse.click(340, 250);
  await tp.waitForTimeout(2200);
  await shot(tp, 'fix-conversas-detalhe-desktop.png');

  await tp.setViewportSize({ width: 800, height: 900 });
  await tp.waitForTimeout(700);
  await clickText(tp, 'Voltar');
  await tp.waitForTimeout(900);
  await shot(tp, '33-800-conversas-lista.png');
  await tp.mouse.click(400, 250);
  await tp.waitForTimeout(2200);
  await shot(tp, '34-800-conversas-detalhe.png');

  await tp.setViewportSize({ width: 390, height: 844 });
  await tp.mouse.click(28, 28);
  await tp.waitForTimeout(700);
  await clickText(tp, 'WhatsApp');
  await tp.waitForTimeout(1200);
  const wiz = await clickText(tp, 'Assistente');
  console.log('wizard', wiz);
  await tp.waitForTimeout(1200);
  await shot(tp, '39-390-whatsapp-wizard.png');

  await tp.mouse.click(28, 28);
  await tp.waitForTimeout(700);
  await clickText(tp, 'Automações');
  await tp.waitForTimeout(1200);
  await shot(tp, '37-390-automacoes-lista.png');
  await tp.mouse.click(200, 320);
  await tp.waitForTimeout(1600);
  await shot(tp, '38-390-automacoes-editor.png');

  await tctx.close();
  await browser.close();
  console.log('DONE');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
