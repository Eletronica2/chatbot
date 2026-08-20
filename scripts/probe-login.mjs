import { chromium } from 'playwright';
import path from 'path';

const BASE = 'http://127.0.0.1:7357';
const OUT = path.join(process.env.USERPROFILE, 'Desktop', 'fase9-evidencias');

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 120000 });
await page.waitForTimeout(3500);

const texts = await page.evaluate(() => {
  const out = [];
  document.querySelectorAll('flt-semantics, span, button, a, [role]').forEach((el) => {
    const t = (el.innerText || el.getAttribute('aria-label') || '').trim();
    if (t && t.length < 80) out.push({ t, tag: el.tagName, aria: el.getAttribute('aria-label') });
  });
  return out.slice(0, 80);
});
console.log('TEXTS', JSON.stringify(texts, null, 2));

const inputInfo = await page.evaluate(() => {
  return {
    inputs: document.querySelectorAll('input').length,
    flutterView: !!document.querySelector('flutter-view'),
    semantics: document.querySelectorAll('flt-semantics').length,
    htmlSnippet: document.body.innerHTML.slice(0, 500),
  };
});
console.log('INFO', inputInfo);

// Try coordinate click near top-right "Entrar"
await page.mouse.click(1280, 42);
await page.waitForTimeout(2000);
await page.screenshot({ path: path.join(OUT, '_probe-after-coord-entrar.png') });
console.log('inputs after coord', await page.locator('input').count());

// Try force click Entrar text
const entrar = page.getByText('Entrar', { exact: true });
console.log('Entrar count', await entrar.count());
if (await entrar.count()) {
  const box = await entrar.first().boundingBox();
  console.log('Entrar box', box);
  await entrar.first().click({ force: true });
  await page.waitForTimeout(2000);
}
await page.screenshot({ path: path.join(OUT, '_probe-after-force-entrar.png') });
console.log('inputs after force', await page.locator('input').count());

// Try Começar agora
const start = page.getByText(/Começar agora/i).first();
if (await start.count()) {
  const box = await start.boundingBox();
  console.log('Comecar box', box);
  if (box) await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForTimeout(2000);
}
await page.screenshot({ path: path.join(OUT, '_probe-after-comecar.png') });
console.log('inputs after comecar', await page.locator('input').count());

await browser.close();
