#!/usr/bin/env python3
import time
from pathlib import Path
from playwright.sync_api import sync_playwright

OUT = Path("/tmp/atenda-audit2c")
OUT.mkdir(parents=True, exist_ok=True)
BASE = "http://127.0.0.1:4180"
n = 0


def shot(page, name):
    global n
    n += 1
    path = OUT / f"{n:02d}-{name}.png"
    page.screenshot(path=str(path), timeout=20000, animations="disabled")
    print("SHOT", path.name, flush=True)


from PIL import Image
import io

def wait_dark(page):
    time.sleep(4)
    for i in range(10):
        png = page.screenshot(timeout=20000, animations="disabled")
        im = Image.open(io.BytesIO(png))
        px = im.getpixel((im.width // 2, im.height // 2))
        print(f"paint {i} {px}", flush=True)
        if px[0] < 80 and px[1] < 80 and px[2] < 90:
            return
        time.sleep(1)


def click_orange_blob(page, x0, y0, x1, y1, pick="rightmost"):
    png = page.screenshot(timeout=20000, animations="disabled")
    im = Image.open(io.BytesIO(png))
    pts = []
    for y in range(y0, min(y1, im.height)):
        for x in range(x0, min(x1, im.width)):
            r, g, b = im.getpixel((x, y))[:3]
            if r > 200 and 70 < g < 160 and b < 90:
                pts.append((x, y))
    print(f"orange pixels {len(pts)} in {x0,y0,x1,y1}", flush=True)
    if not pts:
        return False
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    if pick == "rightmost":
        mx = max(xs)
        cluster = [p for p in pts if p[0] > mx - 80]
        cx = sum(p[0] for p in cluster) // len(cluster)
        cy = sum(p[1] for p in cluster) // len(cluster)
    else:
        cx = sum(xs) // len(xs)
        cy = sum(ys) // len(ys)
    print("click orange", cx, cy, flush=True)
    page.mouse.click(cx, cy)
    time.sleep(1.3)
    return True


def tap(page, x, y, pause=1.2):
    page.mouse.click(x, y)
    time.sleep(pause)
    page.mouse.click(x, y)
    time.sleep(pause)


with sync_playwright() as p:
    browser = p.chromium.launch(
        headless=True,
        args=["--enable-webgl", "--ignore-gpu-blocklist", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
    )
    page = browser.new_page(viewport={"width": 1440, "height": 900})
    page.goto(BASE, wait_until="domcontentloaded")
    wait_dark(page)
    tap(page, 1260, 42, 2.0)
    wait_dark(page)
    # LoginScreen already defaults to the local tenant test user.
    tap(page, 1180, 640, 4.0)
    wait_dark(page)
    shot(page, "home")

    tap(page, 100, 220, 1.5)
    shot(page, "acoes")
    click_orange_blob(page, 1050, 90, 1420, 230, pick="rightmost")
    shot(page, "dialog-nova-acao")
    tap(page, 1020, 760, 0.9)
    shot(page, "dialog-nova-acao-validation")
    page.keyboard.press("Escape")
    time.sleep(0.5)

    tap(page, 100, 345, 1.5)
    shot(page, "equipe")
    click_orange_blob(page, 1050, 90, 1420, 250, pick="rightmost")
    shot(page, "dialog-convidar")
    tap(page, 1000, 540, 0.9)
    shot(page, "dialog-convidar-validation")
    page.keyboard.press("Escape")
    time.sleep(0.5)

    tap(page, 100, 175, 1.5)
    shot(page, "automacoes")
    click_orange_blob(page, 1050, 70, 1420, 220, pick="rightmost")
    shot(page, "dialog-nova-automacao")
    tap(page, 1000, 640, 0.8)
    shot(page, "dialog-nova-automacao-validation")
    page.keyboard.press("Escape")
    time.sleep(0.5)

    tap(page, 100, 305, 1.6)
    shot(page, "whatsapp")
    # click just to the right of the filled WhatsApp tab (Assistente)
    png = page.screenshot(timeout=20000, animations="disabled")
    im = Image.open(io.BytesIO(png))
    orange = []
    for y in range(130, 200):
        for x in range(230, 900):
            r, g, b = im.getpixel((x, y))[:3]
            if r > 200 and 70 < g < 160 and b < 90:
                orange.append((x, y))
    if orange:
        max_x = max(p[0] for p in orange if p[0] < 520)
        cy = sum(p[1] for p in orange) // len(orange)
        print("assistente guess", max_x + 90, cy, "orange", len(orange), flush=True)
        page.mouse.click(max_x + 90, cy)
        time.sleep(1.6)
    shot(page, "wizard-s1")
    tap(page, 1100, 795, 1.1)
    shot(page, "wizard-s2")
    tap(page, 1100, 795, 1.1)
    shot(page, "wizard-s3")
    page.keyboard.press("Escape")
    time.sleep(0.5)
    tap(page, 280, 575, 1.3)
    shot(page, "dialog-editar-conta-wa")
    page.keyboard.press("Escape")
    time.sleep(0.4)

    browser.close()
    print("DONE", n, flush=True)
