#!/usr/bin/env python3
"""Follow-up visual audit: login via textboxes, then remaining dialogs."""
import io
import re
import time
from pathlib import Path

from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = Path("/home/arthur/Área de trabalho/chatbot")
OUT = Path("/tmp/atenda-audit2b")
OUT.mkdir(parents=True, exist_ok=True)
BASE = "http://127.0.0.1:4180"
CREDS = (ROOT / "CREDENCIAIS_TESTE.md").read_text(encoding="utf-8")
n = 0


def cred(email: str) -> str:
    m = re.search(rf"\|\s*{re.escape(email)}\s*\|\s*(\S+)\s*\|", CREDS)
    if not m:
        raise SystemExit(f"missing {email}")
    return m.group(1)


TENANT_EMAIL = "admin@bellamassa.com.br"
TENANT_PASS = cred(TENANT_EMAIL)
ADMIN_EMAIL = "arthurlaranjo@hotmail.com"
ADMIN_PASS = cred(ADMIN_EMAIL)


def shot(page, name, w=None, h=None):
    global n
    n += 1
    if w and h:
        page.set_viewport_size({"width": w, "height": h})
        time.sleep(0.5)
    path = OUT / f"{n:02d}-{name}.png"
    page.screenshot(path=str(path), full_page=False, timeout=20000, animations="disabled")
    print("SHOT", path.name, flush=True)


def wait_painted(page):
    time.sleep(4)
    for i in range(8):
        png = page.screenshot(timeout=20000, animations="disabled")
        im = Image.open(io.BytesIO(png))
        px = im.getpixel((im.width // 2, im.height // 2))
        print(f"paint {i} {px}", flush=True)
        if px[0] < 80 and px[1] < 80 and px[2] < 90:
            return
        time.sleep(1)


def tap(page, x, y, pause=1.1):
    page.mouse.click(x, y)
    time.sleep(pause)


def fill_login(page, email, password):
    page.set_viewport_size({"width": 1440, "height": 900})
    page.goto(BASE, wait_until="domcontentloaded")
    wait_painted(page)
    tap(page, 1260, 42, 1.5)
    wait_painted(page)
    boxes = page.get_by_role("textbox")
    print("textboxes", boxes.count(), flush=True)
    if boxes.count() >= 2:
        boxes.nth(0).fill(email)
        boxes.nth(1).fill(password)
    tap(page, 1180, 640, 3.5)
    wait_painted(page)


def hash_reload(page, fragment):
    page.goto(f"{BASE}/", wait_until="domcontentloaded")
    page.evaluate(f"location.hash = {fragment!r}")
    page.reload(wait_until="domcontentloaded")
    wait_painted(page)


with sync_playwright() as p:
    browser = p.chromium.launch(
        headless=True,
        args=[
            "--enable-webgl",
            "--ignore-gpu-blocklist",
            "--use-gl=angle",
            "--use-angle=swiftshader",
            "--enable-unsafe-swiftshader",
        ],
    )
    page = browser.new_page(viewport={"width": 1440, "height": 900})

    # invite error via textboxes
    hash_reload(page, "#/accept-invite?token=invalid-audit")
    boxes = page.get_by_role("textbox")
    if boxes.count() >= 2:
        boxes.nth(0).fill("SenhaForte!123")
        boxes.nth(1).fill("SenhaForte!123")
    tap(page, 720, 590, 2.2)
    shot(page, "invite-submit-api-error")

    hash_reload(page, "#/reset-password?token=invalid-audit")
    boxes = page.get_by_role("textbox")
    if boxes.count() >= 2:
        boxes.nth(0).fill("SenhaForte!123")
        boxes.nth(1).fill("SenhaForte!123")
    tap(page, 720, 590, 2.2)
    shot(page, "reset-submit-api-error")

    fill_login(page, TENANT_EMAIL, TENANT_PASS)
    shot(page, "tenant-home")

    # sidebar items ~40px, start ~140
    tap(page, 100, 220, 1.4)  # Ações
    shot(page, "acoes")
    tap(page, 1320, 72, 1.2)
    shot(page, "dialog-nova-acao")
    shot(page, "dialog-nova-acao-800", 800, 900)
    page.set_viewport_size({"width": 1440, "height": 900})
    tap(page, 980, 780, 0.8)
    shot(page, "dialog-nova-acao-validation")
    page.keyboard.press("Escape")
    time.sleep(0.4)

    tap(page, 100, 340, 1.4)  # Equipe
    shot(page, "equipe")
    tap(page, 1320, 72, 1.2)
    shot(page, "dialog-convidar")
    tap(page, 980, 560, 0.8)
    shot(page, "dialog-convidar-validation")
    page.keyboard.press("Escape")
    time.sleep(0.4)

    tap(page, 100, 180, 1.5)  # Automações
    shot(page, "automacoes")
    tap(page, 1320, 72, 1.2)
    shot(page, "dialog-nova-automacao")
    tap(page, 980, 640, 0.8)
    shot(page, "dialog-nova-automacao-validation")
    page.keyboard.press("Escape")
    time.sleep(0.3)

    tap(page, 100, 300, 1.6)  # WhatsApp
    shot(page, "whatsapp")
    # Assistente coexistência — likely top-right
    tap(page, 1280, 72, 1.6)
    shot(page, "wizard-s1")
    shot(page, "wizard-s1-800", 800, 900)
    page.set_viewport_size({"width": 1440, "height": 900})
    tap(page, 1100, 790, 1.0)
    shot(page, "wizard-s2")
    tap(page, 1100, 790, 1.0)
    shot(page, "wizard-s3")
    shot(page, "wizard-s3-800", 800, 900)
    page.set_viewport_size({"width": 1440, "height": 900})
    page.keyboard.press("Escape")
    time.sleep(0.4)

    tap(page, 100, 260, 1.3)
    shot(page, "templates")

    tap(page, 190, 860, 1.8)
    wait_painted(page)

    fill_login(page, ADMIN_EMAIL, ADMIN_PASS)
    shot(page, "superadmin")
    tap(page, 100, 300, 1.5)  # Clientes
    shot(page, "clientes")
    tap(page, 720, 148, 1.5)  # Leads tab
    shot(page, "leads")
    shot(page, "leads-800", 800, 900)
    page.set_viewport_size({"width": 1440, "height": 900})
    tap(page, 430, 700, 1.4)
    shot(page, "dialog-proposta")
    shot(page, "dialog-proposta-680", 680, 900)
    page.set_viewport_size({"width": 1440, "height": 900})
    tap(page, 980, 700, 1.5)
    shot(page, "proposta-pdf-or-actions")
    page.keyboard.press("Escape")
    time.sleep(0.3)
    page.keyboard.press("Escape")
    time.sleep(0.5)
    tap(page, 620, 700, 1.3)
    shot(page, "dialog-converter")
    page.keyboard.press("Escape")
    time.sleep(0.4)
    tap(page, 720, 148, 0.8)
    tap(page, 500, 210, 1.2)  # Nova empresa
    shot(page, "dialog-nova-empresa")
    tap(page, 980, 740, 0.8)
    shot(page, "dialog-nova-empresa-validation")
    page.keyboard.press("Escape")
    time.sleep(0.3)
    tap(page, 100, 340, 1.3)
    shot(page, "cobranca")

    browser.close()
    print("DONE", n, flush=True)
