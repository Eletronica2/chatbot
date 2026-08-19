#!/usr/bin/env python3
import io
import time
from pathlib import Path
from PIL import Image
from playwright.sync_api import sync_playwright

OUT = Path("/tmp/atenda-audit2e")
OUT.mkdir(parents=True, exist_ok=True)
n = 0


def shot(page, name):
    global n
    n += 1
    path = OUT / f"{n:02d}-{name}.png"
    page.screenshot(path=str(path), timeout=20000, animations="disabled")
    print("SHOT", path.name, flush=True)


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


def tap(page, x, y, pause=1.2):
    page.mouse.click(x, y)
    time.sleep(pause)


def click_orange(page, x0, y0, x1, y1):
    png = page.screenshot(timeout=20000, animations="disabled")
    im = Image.open(io.BytesIO(png))
    pts = []
    for y in range(y0, min(y1, im.height)):
        for x in range(x0, min(x1, im.width)):
            r, g, b = im.getpixel((x, y))[:3]
            if r > 200 and 70 < g < 160 and b < 90:
                pts.append((x, y))
    print("orange", len(pts), (x0, y0, x1, y1), flush=True)
    if not pts:
        return False
    mx = max(p[0] for p in pts)
    cluster = [p for p in pts if p[0] > mx - 90]
    cx = sum(p[0] for p in cluster) // len(cluster)
    cy = sum(p[1] for p in cluster) // len(cluster)
    print("click", cx, cy, flush=True)
    page.mouse.click(cx, cy)
    time.sleep(1.4)
    return True


def close_dialog(page):
    page.keyboard.press("Escape")
    time.sleep(0.3)
    page.keyboard.press("Escape")
    time.sleep(0.8)


with sync_playwright() as p:
    browser = p.chromium.launch(
        headless=True,
        args=["--enable-webgl", "--ignore-gpu-blocklist", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
    )
    page = browser.new_page(viewport={"width": 1440, "height": 900})
    page.goto("http://127.0.0.1:4180", wait_until="domcontentloaded")
    wait_dark(page)
    tap(page, 1260, 42, 2.0)
    wait_dark(page)
    tap(page, 1180, 640, 4.0)
    wait_dark(page)

    tap(page, 100, 220, 1.5)
    click_orange(page, 1050, 90, 1420, 230)
    shot(page, "nova-acao")
    click_orange(page, 700, 520, 1100, 860)
    shot(page, "nova-acao-validation")
    close_dialog(page)

    tap(page, 100, 345, 1.6)
    shot(page, "equipe")
    click_orange(page, 1050, 90, 1420, 280)
    shot(page, "convidar")
    click_orange(page, 700, 420, 1100, 820)
    shot(page, "convidar-validation")
    close_dialog(page)

    tap(page, 100, 175, 1.6)
    shot(page, "automacoes")
    click_orange(page, 1050, 70, 1420, 240)
    shot(page, "nova-automacao")
    click_orange(page, 700, 480, 1100, 860)
    shot(page, "nova-automacao-validation")
    close_dialog(page)

    tap(page, 100, 305, 1.7)
    shot(page, "whatsapp")
    png = page.screenshot(timeout=20000, animations="disabled")
    im = Image.open(io.BytesIO(png))
    orange = []
    for y in range(125, 205):
        for x in range(230, 700):
            r, g, b = im.getpixel((x, y))[:3]
            if r > 200 and 70 < g < 160 and b < 90:
                orange.append((x, y))
    if orange:
        right = max(p[0] for p in orange)
        cy = sum(p[1] for p in orange) // len(orange)
        print("assistente", right + 100, cy, flush=True)
        page.mouse.click(right + 100, cy)
        time.sleep(1.8)
    shot(page, "wizard-s1")
    click_orange(page, 900, 700, 1400, 880)
    shot(page, "wizard-s2")
    click_orange(page, 900, 700, 1400, 880)
    shot(page, "wizard-s3")
    close_dialog(page)
    shot(page, "whatsapp-after")

    browser.close()
    print("DONE", n, flush=True)
