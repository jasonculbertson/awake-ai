from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path
import math

OUT = Path(__file__).parent
W, H = 2560, 1600

FONT = "/System/Library/Fonts/SFNS.ttf"
MONO = "/System/Library/Fonts/SFNSMono.ttf"


def font(size):
    return ImageFont.truetype(FONT, size)


def mono(size):
    return ImageFont.truetype(MONO, size)


INK = (22, 28, 37)
MUTED = (93, 103, 118)
LIGHT = (248, 250, 252)
LINE = (222, 228, 236)
ORANGE = (255, 149, 0)
YELLOW = (255, 206, 72)
BLUE = (55, 132, 255)
SKY = (79, 188, 255)
GREEN = (52, 199, 89)
TEAL = (42, 207, 190)
PURPLE = (151, 91, 221)
RED = (255, 69, 58)
WHITE = (255, 255, 255)


def rounded(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def text_size(draw, text, f):
    box = draw.textbbox((0, 0), text, font=f)
    return box[2] - box[0], box[3] - box[1]


def wrap(draw, text, f, max_width):
    words = text.split()
    lines = []
    current = ""
    for word in words:
        test = (current + " " + word).strip()
        if text_size(draw, test, f)[0] <= max_width:
            current = test
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def draw_copy(draw, x, y, eyebrow, headline, body, accent):
    draw.text((x, y), eyebrow, font=font(34), fill=accent)
    y += 64
    for line in wrap(draw, headline, font(96), 820):
        draw.text((x, y), line, font=font(96), fill=INK)
        y += 108
    y += 20
    for line in wrap(draw, body, font(36), 760):
        draw.text((x, y), line, font=font(36), fill=MUTED)
        y += 50


def soft_shadow(base, box, radius=34, opacity=55, blur=30):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x1, y1, x2, y2 = box
    rounded(d, (x1 + 24, y1 + 28, x2 + 24, y2 + 28), radius, (0, 0, 0, opacity))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(layer)


def wallpaper(draw, box, c1=(44, 132, 255), c2=(113, 212, 255)):
    x1, y1, x2, y2 = box
    for i in range(y2 - y1):
        t = i / max(1, (y2 - y1))
        r = int(c1[0] * (1 - t) + c2[0] * t)
        g = int(c1[1] * (1 - t) + c2[1] * t)
        b = int(c1[2] * (1 - t) + c2[2] * t)
        draw.line((x1, y1 + i, x2, y1 + i), fill=(r, g, b))
    draw.rounded_rectangle((x1 + 90, y1 + 88, x2 - 90, y2 - 88), 34, outline=(255, 255, 255, 54), width=3)


def laptop(base, x, y, w, h, content_cb):
    d = ImageDraw.Draw(base)
    soft_shadow(base, (x, y, x + w, y + h), radius=42, opacity=70, blur=34)
    rounded(d, (x, y, x + w, y + h), 42, (16, 19, 26), (55, 64, 78), 3)
    sx, sy, sw, sh = x + 28, y + 28, w - 56, h - 56
    rounded(d, (sx, sy, sx + sw, sy + sh), 28, (235, 240, 247))
    wallpaper(d, (sx + 16, sy + 16, sx + sw - 16, sy + sh - 16))
    content_cb(d, sx + 16, sy + 16, sw - 32, sh - 32)


def mac_window(draw, x, y, w, h, title="Awake"):
    rounded(draw, (x, y, x + w, y + h), 24, (250, 252, 255), LINE, 2)
    rounded(draw, (x, y, x + w, y + 58), 24, (239, 243, 249), None)
    for i, color in enumerate([(255, 95, 87), (255, 189, 46), (39, 201, 63)]):
        draw.ellipse((x + 26 + i * 30, y + 22, x + 42 + i * 30, y + 38), fill=color)
    tw, _ = text_size(draw, title, font(19))
    draw.text((x + w / 2 - tw / 2, y + 18), title, font=font(19), fill=MUTED)


def toggle(draw, x, y, on=True):
    rounded(draw, (x, y, x + 58, y + 31), 16, GREEN if on else (198, 207, 218))
    draw.ellipse((x + (29 if on else 4), y + 4, x + (55 if on else 30), y + 30), fill=WHITE)


def tab_bar(draw, x, y, active):
    labels = ["Timer", "Apps", "Settings"]
    rounded(draw, (x, y, x + 640, y + 54), 16, (229, 234, 242))
    for i, label in enumerate(labels):
        lx = x + 8 + i * 212
        if label == active:
            rounded(draw, (lx, y + 7, lx + 196, y + 47), 13, WHITE)
        tw, _ = text_size(draw, label, font(20))
        draw.text((lx + 98 - tw / 2, y + 17), label, font=font(20), fill=INK if label == active else MUTED)


def awake_header(draw, x, y, status):
    draw.ellipse((x, y, x + 52, y + 52), fill=ORANGE)
    draw.text((x + 70, y - 2), "Awake", font=font(34), fill=INK)
    draw.text((x + 70, y + 34), status, font=font(22), fill=MUTED)
    rounded(draw, (x + 545, y + 6, x + 680, y + 42), 18, (255, 246, 230), (255, 213, 154))
    draw.text((x + 574, y + 15), "1:42:18", font=font(19), fill=ORANGE)


def popover_timer(draw, x, y, scale=1):
    mac_window(draw, x, y, 760, 590)
    awake_header(draw, x + 38, y + 84, "Agent run active")
    tab_bar(draw, x + 38, y + 166, "Timer")
    rounded(draw, (x + 48, y + 254, x + 712, y + 336), 18, (255, 248, 236), (255, 213, 154))
    draw.text((x + 80, y + 276), "AI agent is coding", font=font(30), fill=INK)
    draw.text((x + 80, y + 310), "Awake stops when the agent is idle", font=font(20), fill=MUTED)
    draw.text((x + 48, y + 372), "Quick Timer", font=font(23), fill=MUTED)
    for i, label in enumerate(["15m", "30m", "1h", "2h", "4h", "8h"]):
        bx = x + 48 + (i % 3) * 230
        by = y + 410 + (i // 3) * 60
        rounded(draw, (bx, by, bx + 204, by + 44), 12, (238, 242, 248), LINE)
        tw, _ = text_size(draw, label, font(20))
        draw.text((bx + 102 - tw / 2, by + 13), label, font=font(20), fill=INK)


def popover_apps(draw, x, y, expanded=False, list_only=False):
    mac_window(draw, x, y, 760, 610)
    awake_header(draw, x + 38, y + 84, "Sleep prevention active")
    tab_bar(draw, x + 38, y + 166, "Apps")
    if list_only:
        rows = [("Agent Session", True), ("Test Runner", True), ("Local Preview", True), ("Build Process", True), ("Terminal App", False)]
        yy = y + 250
        for name, on in rows:
            rounded(draw, (x + 48, yy, x + 712, yy + 62), 16, WHITE, LINE)
            toggle(draw, x + 74, yy + 17, on)
            draw.text((x + 148, yy + 18), name, font=font(25), fill=INK)
            rounded(draw, (x + 540, yy + 16, x + 688, yy + 46), 15, (237, 241, 247))
            draw.text((x + 574, yy + 24), "While open", font=font(16), fill=MUTED)
            yy += 72
        return
    yy = y + 250
    rounded(draw, (x + 48, yy, x + 712, yy + 64), 16, WHITE, LINE)
    toggle(draw, x + 74, yy + 18, True)
    draw.text((x + 148, yy + 19), "Agent Session", font=font(25), fill=INK)
    rounded(draw, (x + 540, yy + 17, x + 688, yy + 47), 15, (237, 241, 247))
    draw.text((x + 574, yy + 25), "While open", font=font(16), fill=MUTED)
    yy += 82
    rounded(draw, (x + 48, yy, x + 712, yy + 210), 18, (255, 249, 239), (255, 215, 160))
    draw.text((x + 82, yy + 28), "Auto-deactivate when idle", font=font(28), fill=INK)
    toggle(draw, x + 635, yy + 27, True)
    draw.text((x + 82, yy + 92), "CPU threshold", font=font(19), fill=MUTED)
    draw.line((x + 270, yy + 104, x + 560, yy + 104), fill=(214, 221, 230), width=7)
    draw.line((x + 270, yy + 104, x + 396, yy + 104), fill=ORANGE, width=7)
    draw.ellipse((x + 385, yy + 92, x + 409, yy + 116), fill=ORANGE)
    draw.text((x + 625, yy + 92), "8%", font=font(19), fill=INK)
    draw.text((x + 82, yy + 146), "Idle for", font=font(19), fill=MUTED)
    rounded(draw, (x + 270, yy + 136, x + 394, yy + 172), 11, (237, 241, 247))
    draw.text((x + 307, yy + 146), "3 min", font=font(17), fill=INK)
    draw.text((x + 82, yy + 186), "Turns off after 3 min below 8%", font=font(17), fill=MUTED)


def popover_terminal(draw, x, y):
    mac_window(draw, x, y, 760, 590)
    awake_header(draw, x + 38, y + 84, "Process detected")
    tab_bar(draw, x + 38, y + 166, "Apps")
    rounded(draw, (x + 48, y + 250, x + 712, y + 426), 20, (15, 18, 25), (49, 57, 73))
    for i, (txt, col) in enumerate([
        ("$ agent plan", GREEN),
        ("$ agent edit files", TEAL),
        ("$ run tests", YELLOW),
        ("agent processes detected", MUTED),
    ]):
        draw.text((x + 82, y + 280 + i * 38), txt, font=mono(22), fill=col)
    rounded(draw, (x + 48, y + 462, x + 712, y + 524), 16, WHITE, LINE)
    toggle(draw, x + 74, y + 479, True)
    draw.text((x + 148, y + 480), "Detect terminal processes", font=font(25), fill=INK)


def popover_settings(draw, x, y):
    mac_window(draw, x, y, 760, 620)
    awake_header(draw, x + 38, y + 84, "Smart triggers active")
    tab_bar(draw, x + 38, y + 166, "Settings")
    yy = y + 248
    for title, items in [
        ("SMART TRIGGERS", [("Stay awake when plugged in", ORANGE), ("Stay awake with lid closed", PURPLE), ("Stay awake with external display", TEAL)]),
        ("BATTERY", [("Stop when battery is low", GREEN)]),
    ]:
        draw.text((x + 48, yy), title, font=font(16), fill=MUTED)
        yy += 34
        rounded(draw, (x + 48, yy, x + 712, yy + len(items) * 60 + 20), 18, WHITE, LINE)
        for label, col in items:
            rounded(draw, (x + 78, yy + 18, x + 108, yy + 48), 8, col)
            draw.text((x + 130, yy + 21), label, font=font(20), fill=INK)
            toggle(draw, x + 632, yy + 18, True)
            yy += 60
        yy += 38


def popover_ai(draw, x, y):
    mac_window(draw, x, y, 760, 590)
    awake_header(draw, x + 38, y + 84, "AI command")
    tab_bar(draw, x + 38, y + 166, "Timer")
    rounded(draw, (x + 48, y + 250, x + 712, y + 326), 18, (255, 248, 236), (255, 213, 154))
    draw.text((x + 80, y + 274), "Stay awake while my agent codes", font=font(29), fill=ORANGE)
    rounded(draw, (x + 48, y + 364, x + 712, y + 496), 18, (245, 248, 252), LINE)
    draw.text((x + 80, y + 392), "Awake understood:", font=font(19), fill=MUTED)
    draw.text((x + 80, y + 430), "Watching agent task", font=font(32), fill=INK)
    draw.text((x + 80, y + 468), "Will stop when the agent goes idle", font=font(19), fill=MUTED)


def menu_mock(draw, x, y):
    rounded(draw, (x, y, x + 780, y + 520), 30, (250, 252, 255), LINE, 2)
    rounded(draw, (x + 74, y + 94, x + 706, y + 156), 22, (244, 247, 251))
    draw.text((x + 116, y + 112), "☀ 1:42:18", font=font(27), fill=ORANGE)
    draw.text((x + 586, y + 114), "9:41 AM", font=font(24), fill=MUTED)
    rounded(draw, (x + 174, y + 206, x + 530, y + 438), 20, WHITE, LINE)
    for i, item in enumerate(["Toggle Awake", "30 Minutes", "1 Hour", "2 Hours", "Stop Session"]):
        draw.text((x + 210, y + 238 + i * 42), item, font=font(23), fill=ORANGE if i == 0 else RED if i == 4 else INK)


def paste_ui(base, x, y, ui_kind, scale=1.22):
    ui = Image.new("RGBA", (900, 760), (0, 0, 0, 0))
    d = ImageDraw.Draw(ui)
    if ui_kind == "timer":
        popover_timer(d, 56, 70)
    elif ui_kind == "activity":
        popover_apps(d, 56, 70)
    elif ui_kind == "apps":
        popover_apps(d, 56, 70, list_only=True)
    elif ui_kind == "terminal":
        popover_terminal(d, 56, 70)
    elif ui_kind == "settings":
        popover_settings(d, 56, 56)
    elif ui_kind == "ai":
        popover_ai(d, 56, 70)
    elif ui_kind == "menu":
        menu_mock(d, 56, 110)
    w, h = int(ui.width * scale), int(ui.height * scale)
    ui = ui.resize((w, h), Image.LANCZOS)
    soft_shadow(base, (x + 40, y + 60, x + w - 40, y + h - 70), radius=42, opacity=46, blur=34)
    base.alpha_composite(ui, (x, y))


def render(filename, bg, layout, eyebrow, headline, body, accent, ui_kind):
    img = Image.new("RGBA", (W, H), (*bg, 255))
    d = ImageDraw.Draw(img)
    # Subtle depth without decorative blobs.
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    for yy in range(H):
        a = int(18 * yy / H)
        od.line((0, yy, W, yy), fill=(0, 0, 0, a))
    img.alpha_composite(overlay)
    d.rounded_rectangle((100, 100, 2460, 1500), 52, outline=(255, 255, 255, 92), width=3)
    if layout == "left-ui":
        paste_ui(img, 132, 300, ui_kind, 1.18)
        draw_copy(d, 1220, 350, eyebrow, headline, body, accent)
    elif layout == "right-ui":
        draw_copy(d, 170, 360, eyebrow, headline, body, accent)
        paste_ui(img, 1330, 290, ui_kind, 1.22)
    elif layout == "split":
        paste_ui(img, 120, 300, ui_kind, 1.18)
        draw_copy(d, 1240, 360, eyebrow, headline, body, accent)
    img.convert("RGB").save(OUT / filename, quality=96)


shots = [
    ("01-hero-store.png", (255, 255, 255), "left-ui", "AI agent coding", "Keep your Mac awake while your agent works.", "Built for long autonomous coding runs, with automatic shutoff when the agent goes idle.", ORANGE, "timer"),
    ("02-activity-store.png", (255, 247, 232), "right-ui", "Agent-aware", "Turns off when the run is done.", "Watches agent activity, tests, and builds, then deactivates when work goes idle.", ORANGE, "activity"),
    ("03-apps-store.png", (238, 247, 255), "split", "Workflow watchlist", "Made for long coding sessions.", "Keep awake while your agent edits files, runs tests, previews, and builds.", BLUE, "apps"),
    ("04-terminal-store.png", (244, 251, 247), "right-ui", "Shell-aware", "Knows what your agent started.", "Tracks agent runs, test suites, builds, scripts, and other long-running processes.", GREEN, "terminal"),
    ("05-triggers-store.png", (246, 242, 255), "right-ui", "Smart triggers", "Set it once. Let the run finish.", "Auto-activate when plugged in, on an external display, or in clamshell mode.", PURPLE, "settings"),
    ("06-ai-store.png", (255, 248, 235), "right-ui", "Plain-English control", "Tell Awake about the agent run.", "Stay awake while my agent codes. Awake understands the task and watches it.", ORANGE, "ai"),
    ("07-menu-store.png", (238, 247, 255), "right-ui", "Menu bar controls", "Fast controls without opening a window.", "Timer presets, countdowns, and quick toggles from the menu bar.", BLUE, "menu"),
]

for shot in shots:
    render(*shot)

print(f"Generated {len(shots)} store-style screenshots in {OUT}")
