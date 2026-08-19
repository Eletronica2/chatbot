#!/usr/bin/env python3
"""Visual audit round 2 — coordinate clicks (CanvasKit). Never prints secrets."""
import io
import re
import time
from pathlib import Path

from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = Path("/home/arthur/Área de trabalho/chatbot")
OUT = Path("/tmp/atenda-audit2")
OUT.mkdir(parents=True, exist_ok=True)
BASE = "http://127.0.0.1:4180"
CREDS = (ROOT / "CREDENCIAIS_TESTE.md").read_text(encoding="utf-8")


def cred(email: str) -> tuple[str, str]:
    m = re.search(rf"\|\s*{re.escape(email)}\s*\|\s*(\S+)\s*\|", CREDS)
    if not m:
        raise SystemExit(f"missing {email}")
    return email, m.group(1)


TENANT_EMAIL, TENANT_PASS = cred("admin@bellamassa.com.br")
ADMIN_EMAIL, ADMIN_PASS = cred("arthurlaranjo@hotmail.com")
n = 0


def shot(page, name, w=None, h=None):
    global n
    n += 1
    if w and h:
        page.set_viewport_size({"width": w, "height": h})
        time.sleep(0.6)
    path = OUT / f"{n:02d}-{name}.png"
    page.screenshot(path=str(path), full_page=False, timeout=20000, animations="disabled")
    print("SHOT", path.name, flush=True)
    return path


def wait_painted(page):
    time.sleep(5)
    for i in range(10):
        png = page.screenshot(timeout=20000, animations="disabled")
        im = Image.open(io.BytesIO(png))
        px = im.getpixel((im.width // 2, im.height // 2))
        print(f"paint {i} {px}", flush=True)
        if px[0] < 80 and px[1] < 80 and px[2] < 90:
            return
        time.sleep(1.2)


def tap(page, x, y, pause=1.0):
    page.mouse.click(x, y)
    time.sleep(pause)


def hash_goto(page, fragment):
    page.goto(f"{BASE}/", wait_until="domcontentloaded")
    page.evaluate(f"location.hash = {fragment!r}")
    page.reload(wait_until="domcontentloaded")
    wait_painted(page)


def login(page, email, password):
    page.set_viewport_size({"width": 1440, "height": 900})
    page.goto(BASE, wait_until="domcontentloaded")
    wait_painted(page)
    tap(page, 1260, 42, 1.4)
    wait_painted(page)
    # email / password fields on the right card
    tap(page, 1050, 430, 0.2)
    page.keyboard.press("Control+A")
    page.keyboard.type(email)
    tap(page, 1050, 510, 0.2)
    page.keyboard.press("Control+A")
    page.keyboard.type(password)
    tap(page, 1180, 640, 3.2)
    wait_painted(page)


def logout(page):
    tap(page, 108, 860, 1.8)
    wait_painted(page)


NAV = {
    "conversas": (108, 128),
    "automacoes": (108, 168),
    "acoes": (108, 208),
    "templates": (108, 248),
    "whatsapp": (108, 288),
    "equipe": (108, 328),
    "clientes": (108, 288),
    "cobranca": (108, 328),
}


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
    page.set_default_timeout(12000)

    hash_goto(page, "#/accept-invite?token=invalid-audit")
    shot(page, "invite-invalid-wide")
    shot(page, "invite-invalid-compact", 680, 900)
    page.set_viewport_size({"width": 1440, "height": 900})
    tap(page, 720, 430, 0.2)
    page.keyboard.type("123")
    tap(page, 720, 620, 1.0)
    shot(page, "invite-invalid-validation")
    tap(page, 720, 430, 0.2)
    page.keyboard.press("Control+A")
    page.keyboard.type("SenhaForte!123")
    tap(page, 720, 510, 0.2)
    page.keyboard.type("SenhaForte!123")
    tap(page, 720, 620, 2.0)
    shot(page, "invite-invalid-submit-error")

    hash_goto(page, "#/reset-password?token=invalid-audit")
    shot(page, "reset-invalid-wide")
    shot(page, "reset-invalid-compact", 680, 900)
    page.set_viewport_size({"width": 1440, "height": 900})
    tap(page, 720, 430, 0.2)
    page.keyboard.press("Control+A")
    page.keyboard.type("SenhaForte!123")
    tap(page, 720, 510, 0.2)
    page.keyboard.press("Control+A")
    page.keyboard.type("outra")
    tap(page, 720, 620, 1.2)
    shot(page, "reset-mismatch-or-error")
    tap(page, 720, 510, 0.2)
    page.keyboard.press("Control+A")
    page.keyboard.type("SenhaForte!123")
    tap(page, 720, 620, 2.0)
    shot(page, "reset-invalid-submit-error")

    login(page, TENANT_EMAIL, TENANT_PASS)
    shot(page, "tenant-home")

    tap(page, *NAV["acoes"], 1.4)
    shot(page, "acoes-page")
    tap(page, 1288, 78, 1.1)
    shot(page, "dialog-nova-acao-wide")
    shot(page, "dialog-nova-acao-compact", 800, 900)
    page.set_viewport_size({"width": 1440, "height": 900})
    tap(page, 980, 720, 0.8)
    shot(page, "dialog-nova-acao-validation")
    page.keyboard.press("Escape")
    time.sleep(0.4)

    tap(page, *NAV["equipe"], 1.4)
    shot(page, "equipe-page")
    tap(page, 1288, 78, 1.1)
    shot(page, "dialog-convidar-wide")
    tap(page, 980, 560, 0.8)
    shot(page, "dialog-convidar-validation")
    page.keyboard.press("Escape")
    time.sleep(0.4)

    tap(page, *NAV["automacoes"], 1.5)
    shot(page, "automacoes-page")
    tap(page, 1288, 78, 1.1)
    shot(page, "dialog-nova-automacao")
    tap(page, 980, 620, 0.7)
    shot(page, "dialog-nova-automacao-validation")
    page.keyboard.press("Escape")
    time.sleep(0.4)
    tap(page, 1288, 120, 1.0)
    shot(page, "dialog-testar-or-settings")
    page.keyboard.press("Escape")
    time.sleep(0.3)

    tap(page, *NAV["whatsapp"], 1.6)
    shot(page, "whatsapp-page")
    tap(page, 1288, 78, 1.5)
    shot(page, "wizard-step1-ambiente-wide")
    shot(page, "wizard-step1-compact", 800, 900)
    page.set_viewport_size({"width": 1440, "height": 900})
    tap(page, 1080, 780, 1.0)
    shot(page, "wizard-step2-meta")
    shot(page, "wizard-step2-compact", 680, 900)
    page.set_viewport_size({"width": 1440, "height": 900})
    tap(page, 1080, 780, 1.0)
    shot(page, "wizard-step3-conectar-wide")
    shot(page, "wizard-step3-compact", 800, 900)
    page.set_viewport_size({"width": 1440, "height": 900})
    page.keyboard.press("Escape")
    time.sleep(0.4)
    shot(page, "whatsapp-after-wizard")

    tap(page, *NAV["templates"], 1.4)
    shot(page, "templates-page")

    logout(page)
    tap(page, 1330, 42, 1.2)
    shot(page, "dialog-signup")
    page.keyboard.press("Escape")
    time.sleep(0.4)

    login(page, ADMIN_EMAIL, ADMIN_PASS)
    shot(page, "superadmin-home")
    tap(page, *NAV["clientes"], 1.6)
    shot(page, "clientes-page")
    tap(page, 360, 78, 1.6)
    shot(page, "leads-list-wide")
    shot(page, "leads-list-compact", 800, 900)
    page.set_viewport_size({"width": 1440, "height": 900})
    tap(page, 420, 620, 1.3)
    shot(page, "dialog-proposta-wide")
    shot(page, "dialog-proposta-compact", 680, 900)
    page.set_viewport_size({"width": 1440, "height": 900})
    tap(page, 980, 680, 1.4)
    shot(page, "dialog-proposta-pdf-or-same")
    page.keyboard.press("Escape")
    time.sleep(0.3)
    page.keyboard.press("Escape")
    time.sleep(0.5)
    tap(page, 620, 620, 1.3)
    shot(page, "dialog-converter-lead")
    page.keyboard.press("Escape")
    time.sleep(0.4)
    tap(page, 1288, 78, 1.1)
    shot(page, "dialog-nova-empresa")
    tap(page, 980, 720, 0.7)
    shot(page, "dialog-nova-empresa-validation")
    page.keyboard.press("Escape")
    time.sleep(0.4)
    tap(page, *NAV["cobranca"], 1.4)
    shot(page, "billing-hub")
    shot(page, "billing-hub-compact", 800, 900)

    browser.close()
    print("DONE", n, flush=True)
