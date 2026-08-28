#!/usr/bin/env python3
"""
Apple Watch Screenshot Generator for App Store Connect & Marketing.
Generates pixel-perfect Apple Watch screenshots matching Apple's official App Store Connect specifications:
  - Apple Watch Ultra (49mm): 410 x 502 px
  - Apple Watch Series 10/11 (46mm): 416 x 496 px
  - Apple Watch Series 7/8/9 (45mm): 396 x 484 px
  - Apple Watch Series 4/5/6/SE (44mm): 368 x 448 px
  - Framed Marketing Showcase: 1080 x 1920 px
"""

import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_BASE = REPO_ROOT / "AppStore"

# Watch Dimensions (Width, Height) strictly conforming to App Store Connect specs:
# 422 x 514 px, 410 x 502 px, 416 x 496 px, 396 x 484 px, 368 x 448 px, 312 x 390 px
RESOLUTIONS = {
    "AppleWatch_422x514_Primary": (422, 514),
    "AppleWatch_410x502_Ultra": (410, 502),
    "AppleWatch_416x496_Series10": (416, 496),
    "AppleWatch_396x484_Series9": (396, 484),
    "AppleWatch_368x448_SE": (368, 448),
    "AppleWatch_312x390_Series3": (312, 390),
}

# Color Palette (watchOS native dark theme)
OLED_BLACK = (0, 0, 0)
ROW_BG = (28, 28, 30)          # #1C1C1E
ROW_BG_ACTIVE = (44, 44, 46)   # #2C2C2E
CARD_BORDER = (48, 54, 61)     # #30363D
TEXT_WHITE = (255, 255, 255)
TEXT_MUTED = (142, 142, 147)   # #8E8E93
TEXT_SUBTLE = (99, 99, 102)    # #636366

APPLE_BLUE = (10, 132, 255)    # #0A84FF
APPLE_GREEN = (48, 209, 88)    # #30D158
APPLE_ORANGE = (255, 159, 10)  # #FF9F0A
APPLE_PURPLE = (191, 90, 242)  # #BF5AF2
APPLE_TEAL = (100, 210, 255)   # #64D2FF
APPLE_RED = (255, 69, 58)      # #FF453A
APPLE_YELLOW = (255, 214, 10)  # #FFD60A

BADGE_GREEN_BG = (25, 60, 35)
BADGE_BLUE_BG = (20, 45, 75)
BADGE_ORANGE_BG = (60, 40, 15)

def get_font(size, bold=False, rounded=False):
    font_paths = []
    if rounded:
        font_paths.extend([
            "/System/Library/Fonts/SFCompactRounded.ttf",
            "/System/Library/Fonts/SFNSRounded.ttf"
        ])
    if bold:
        font_paths.extend([
            "/System/Library/Fonts/SFCompact.ttf",
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/HelveticaNeue.ttc"
        ])
    else:
        font_paths.extend([
            "/System/Library/Fonts/SFCompact.ttf",
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/HelveticaNeue.ttc"
        ])

    for p in font_paths:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    return ImageFont.load_default()

# ----------------- VECTOR ICON DRAWING HELPERS -----------------

def draw_cart_icon(draw, cx, cy, size, color):
    s = size / 24.0
    # Cart basket
    p1 = (cx - 8 * s, cy - 6 * s)
    p2 = (cx - 5 * s, cy - 6 * s)
    p3 = (cx - 2 * s, cy + 4 * s)
    p4 = (cx + 7 * s, cy + 4 * s)
    p5 = (cx + 9 * s, cy - 3 * s)
    p6 = (cx - 4 * s, cy - 3 * s)
    draw.line([p1, p2, p3, p4, p5, p6], fill=color, width=max(2, int(2.2 * s)))
    # Wheels
    draw.ellipse([cx - 2 * s, cy + 6 * s, cx + 1 * s, cy + 9 * s], fill=color)
    draw.ellipse([cx + 5 * s, cy + 6 * s, cx + 8 * s, cy + 9 * s], fill=color)

def draw_dining_icon(draw, cx, cy, size, color):
    s = size / 24.0
    # Fork
    fx = cx - 4 * s
    draw.line([(fx, cy - 8 * s), (fx, cy + 8 * s)], fill=color, width=max(2, int(2 * s)))
    draw.line([(fx - 3 * s, cy - 8 * s), (fx - 3 * s, cy - 3 * s), (fx + 3 * s, cy - 3 * s), (fx + 3 * s, cy - 8 * s)], fill=color, width=max(1, int(1.8 * s)))
    # Knife
    kx = cx + 4 * s
    draw.line([(kx, cy - 8 * s), (kx, cy + 8 * s)], fill=color, width=max(2, int(2 * s)))
    draw.arc([kx - 2 * s, cy - 8 * s, kx + 4 * s, cy + 1 * s], start=270, end=90, fill=color, width=max(1, int(1.8 * s)))

def draw_gas_icon(draw, cx, cy, size, color):
    s = size / 24.0
    # Pump body
    draw.rounded_rectangle([cx - 7 * s, cy - 7 * s, cx + 2 * s, cy + 8 * s], radius=int(2 * s), outline=color, width=max(2, int(2 * s)))
    # Window
    draw.rectangle([cx - 5 * s, cy - 4 * s, cx, cy - 1 * s], fill=color)
    # Hose / Nozzle
    draw.line([(cx + 2 * s, cy - 3 * s), (cx + 6 * s, cy - 3 * s), (cx + 6 * s, cy + 4 * s), (cx + 8 * s, cy + 6 * s)], fill=color, width=max(2, int(1.8 * s)))

def draw_transit_icon(draw, cx, cy, size, color):
    s = size / 24.0
    # Train body
    draw.rounded_rectangle([cx - 6 * s, cy - 8 * s, cx + 6 * s, cy + 5 * s], radius=int(3 * s), outline=color, width=max(2, int(2 * s)))
    # Windshield
    draw.rectangle([cx - 4 * s, cy - 5 * s, cx + 4 * s, cy - 1 * s], fill=color)
    # Headlights
    draw.ellipse([cx - 4 * s, cy + 1 * s, cx - 2 * s, cy + 3 * s], fill=color)
    draw.ellipse([cx + 2 * s, cy + 1 * s, cx + 4 * s, cy + 3 * s], fill=color)
    # Tracks / legs
    draw.line([(cx - 4 * s, cy + 5 * s), (cx - 6 * s, cy + 8 * s)], fill=color, width=max(2, int(2 * s)))
    draw.line([(cx + 4 * s, cy + 5 * s), (cx + 6 * s, cy + 8 * s)], fill=color, width=max(2, int(2 * s)))

def draw_store_icon(draw, cx, cy, size, color):
    s = size / 24.0
    # Roof
    draw.polygon([(cx - 8 * s, cy - 2 * s), (cx, cy - 8 * s), (cx + 8 * s, cy - 2 * s)], fill=color)
    # Pillars
    draw.rectangle([cx - 7 * s, cy - 1 * s, cx - 4 * s, cy + 6 * s], fill=color)
    draw.rectangle([cx - 2 * s, cy - 1 * s, cx + 1 * s, cy + 6 * s], fill=color)
    draw.rectangle([cx + 3 * s, cy - 1 * s, cx + 6 * s, cy + 6 * s], fill=color)
    # Base
    draw.rectangle([cx - 8 * s, cy + 6 * s, cx + 8 * s, cy + 8 * s], fill=color)

def draw_bag_icon(draw, cx, cy, size, color):
    s = size / 24.0
    # Bag body
    draw.rounded_rectangle([cx - 6 * s, cy - 3 * s, cx + 6 * s, cy + 8 * s], radius=int(2 * s), outline=color, width=max(2, int(2 * s)))
    # Handle
    draw.arc([cx - 3 * s, cy - 7 * s, cx + 3 * s, cy - 1 * s], start=180, end=0, fill=color, width=max(2, int(2 * s)))

def draw_gauge_icon(draw, cx, cy, size, color):
    s = size / 24.0
    draw.arc([cx - 8 * s, cy - 8 * s, cx + 8 * s, cy + 8 * s], start=135, end=405, fill=color, width=max(2, int(2.2 * s)))
    draw.line([(cx, cy), (cx + 4 * s, cy - 4 * s)], fill=color, width=max(2, int(2.2 * s)))
    draw.ellipse([cx - 2 * s, cy - 2 * s, cx + 2 * s, cy + 2 * s], fill=color)

def draw_chevron(draw, cx, cy, size, color):
    s = size / 20.0
    draw.line([(cx - 3 * s, cy - 5 * s), (cx + 2 * s, cy), (cx - 3 * s, cy + 5 * s)], fill=color, width=max(2, int(2.2 * s)))

def draw_back_arrow(draw, cx, cy, size, color):
    s = size / 20.0
    draw.line([(cx + 3 * s, cy - 6 * s), (cx - 3 * s, cy), (cx + 3 * s, cy + 6 * s)], fill=color, width=max(2, int(2.5 * s)))

def draw_check_icon(draw, cx, cy, size, color):
    s = size / 20.0
    draw.line([(cx - 5 * s, cy), (cx - 1 * s, cy + 4 * s), (cx + 6 * s, cy - 4 * s)], fill=color, width=max(2, int(2.5 * s)))

# ----------------- STATUS BAR HELPER -----------------

def draw_watch_status_bar(draw, w, time_str="9:41", title="PickMe", is_root=True):
    font_time = get_font(26, bold=True)
    font_title = get_font(28, bold=True)

    # Inset time to protect from Apple Watch corner curvature
    draw.text((w - 116, 20), time_str, font=font_time, fill=APPLE_TEAL)

    if is_root:
        draw.text((36, 20), title, font=font_title, fill=TEXT_WHITE)
    else:
        draw_back_arrow(draw, 44, 34, 20, APPLE_BLUE)
        font_back = get_font(24, bold=False)
        draw.text((62, 22), title, font=font_back, fill=APPLE_BLUE)

# ----------------- SCREEN RENDERERS (Internal Canvas 820 x 1004) -----------------

def render_screen_1_categories(canvas):
    w, h = 820, 1004
    draw = ImageDraw.Draw(canvas)
    draw_watch_status_bar(draw, w, "9:41", "PickMe", is_root=True)

    # Section Header
    font_sec = get_font(20, bold=True)
    draw.text((36, 72), "WHICH CARD?", font=font_sec, fill=TEXT_MUTED)

    # List items
    categories = [
        ("Groceries", APPLE_BLUE, draw_cart_icon, "$100 avg"),
        ("Dining", APPLE_ORANGE, draw_dining_icon, "$40 avg"),
        ("Gas & Fuel", APPLE_GREEN, draw_gas_icon, "$60 avg"),
        ("Transit", APPLE_PURPLE, draw_transit_icon, "$15 avg"),
        ("Costco", APPLE_TEAL, draw_store_icon, "$200 avg"),
        ("Other", TEXT_MUTED, draw_bag_icon, "$50 avg"),
    ]

    font_item = get_font(30, bold=True)
    font_sub = get_font(20, bold=False)

    y = 108
    row_height = 98
    row_gap = 14

    for name, icon_color, icon_fn, avg in categories:
        # Row card
        draw.rounded_rectangle([32, y, w - 32, y + row_height], radius=22, fill=ROW_BG, outline=(42, 46, 54), width=1)
        # Icon circle
        draw.ellipse([50, y + 19, 110, y + 79], fill=(icon_color[0]//5, icon_color[1]//5, icon_color[2]//5))
        icon_fn(draw, 80, y + 49, 32, icon_color)

        # Title & Avg
        draw.text((128, y + 20), name, font=font_item, fill=TEXT_WHITE)
        draw.text((128, y + 56), f"Quick Pick • {avg}", font=font_sub, fill=TEXT_MUTED)

        # Chevron
        draw_chevron(draw, w - 65, y + 49, 22, TEXT_MUTED)
        y += row_height + row_gap

    # Caps button
    y_caps = y + 8
    draw.rounded_rectangle([32, y_caps, w - 32, y_caps + 94], radius=22, fill=(35, 28, 18), outline=(90, 60, 20), width=1)
    draw.ellipse([50, y_caps + 17, 110, y_caps + 77], fill=(50, 35, 15))
    draw_gauge_icon(draw, 80, y_caps + 47, 32, APPLE_ORANGE)
    draw.text((128, y_caps + 28), "Monthly Caps", font=font_item, fill=TEXT_WHITE)
    draw.text((128, y_caps + 62), "3 Active Trackers", font=font_sub, fill=APPLE_ORANGE)
    draw_chevron(draw, w - 65, y_caps + 47, 22, APPLE_ORANGE)


def render_screen_2_groceries_rec(canvas):
    w, h = 820, 1004
    draw = ImageDraw.Draw(canvas)
    draw_watch_status_bar(draw, w, "9:41", "PickMe", is_root=False)

    # Category Badge Header
    cy = 76
    draw.ellipse([w//2 - 42, cy, w//2 + 42, cy + 84], fill=(15, 35, 75))
    draw_cart_icon(draw, w//2, cy + 42, 44, APPLE_BLUE)

    font_cat = get_font(24, bold=True)
    draw.text((w//2, cy + 110), "GROCERIES", font=font_cat, fill=TEXT_MUTED, anchor="mm")

    # Main Card Box (Amex Cobalt)
    card_y = cy + 135
    card_h = 510
    draw.rounded_rectangle([32, card_y, w - 32, card_y + card_h], radius=28, fill=(16, 28, 48), outline=(35, 75, 135), width=2)

    # Card Brand / Issuer Pill
    draw.rounded_rectangle([56, card_y + 28, 175, card_y + 66], radius=10, fill=(20, 50, 95))
    font_badge = get_font(18, bold=True)
    draw.text((115, card_y + 47), "AMEX", font=font_badge, fill=APPLE_TEAL, anchor="mm")

    draw.text((w - 56, card_y + 47), "$100 Spend", font=get_font(22, bold=False), fill=TEXT_MUTED, anchor="rm")

    # Card Name Hero
    font_hero = get_font(46, bold=True)
    draw.text((56, card_y + 95), "Cobalt Card", font=font_hero, fill=TEXT_WHITE)

    # Reward Multiplier & Return
    font_rate = get_font(34, bold=True)
    draw.text((56, card_y + 165), "5.0 MR pts / $1", font=font_rate, fill=APPLE_TEAL)

    draw.line([(56, card_y + 225), (w - 56, card_y + 225)], fill=(30, 55, 95), width=2)

    # Calculation
    draw.text((56, card_y + 250), "Estimated Return:", font=get_font(22, bold=False), fill=TEXT_MUTED)
    draw.text((56, card_y + 285), "+$5.00 CAD (500 pts)", font=get_font(34, bold=True), fill=TEXT_WHITE)

    # Advantage Pill
    adv_y = card_y + 375
    draw.rounded_rectangle([56, adv_y, w - 56, adv_y + 90], radius=18, fill=BADGE_GREEN_BG, outline=APPLE_GREEN, width=1)
    draw_check_icon(draw, 88, adv_y + 45, 26, APPLE_GREEN)
    font_adv = get_font(26, bold=True)
    draw.text((120, adv_y + 30), "+$3.00 vs Default Card", font=font_adv, fill=APPLE_GREEN)
    draw.text((120, adv_y + 58), "3x more rewards than 1% baseline", font=get_font(18, bold=False), fill=(180, 240, 195))

    # Action Confirmation Button
    btn_y = card_y + card_h + 35
    draw.rounded_rectangle([32, btn_y, w - 32, btn_y + 105], radius=26, fill=APPLE_BLUE)
    draw_check_icon(draw, w//2 - 135, btn_y + 53, 30, TEXT_WHITE)
    draw.text((w//2 + 15, btn_y + 53), "I Tapped Cobalt", font=get_font(34, bold=True), fill=TEXT_WHITE, anchor="mm")


def render_screen_3_costco_rec(canvas):
    w, h = 820, 1004
    draw = ImageDraw.Draw(canvas)
    draw_watch_status_bar(draw, w, "9:41", "PickMe", is_root=False)

    # Category Badge Header
    cy = 76
    draw.ellipse([w//2 - 42, cy, w//2 + 42, cy + 84], fill=(20, 45, 65))
    draw_store_icon(draw, w//2, cy + 42, 44, APPLE_TEAL)

    font_cat = get_font(24, bold=True)
    draw.text((w//2, cy + 110), "COSTCO WHOLESALE", font=font_cat, fill=TEXT_MUTED, anchor="mm")

    # Main Card Box (Rogers Red WE MC)
    card_y = cy + 135
    card_h = 510
    draw.rounded_rectangle([32, card_y, w - 32, card_y + card_h], radius=28, fill=(35, 18, 22), outline=(120, 40, 50), width=2)

    # Card Brand / Issuer Pill
    draw.rounded_rectangle([56, card_y + 28, 225, card_y + 66], radius=10, fill=(65, 25, 30))
    font_badge = get_font(18, bold=True)
    draw.text((140, card_y + 47), "MASTERCARD", font=font_badge, fill=(255, 160, 160), anchor="mm")

    draw.text((w - 56, card_y + 47), "$150 Spend", font=get_font(22, bold=False), fill=TEXT_MUTED, anchor="rm")

    # Card Name Hero
    font_hero = get_font(42, bold=True)
    draw.text((56, card_y + 95), "Rogers Red WE", font=font_hero, fill=TEXT_WHITE)

    # Reward Multiplier & Return
    font_rate = get_font(34, bold=True)
    draw.text((56, card_y + 165), "2.0% Cash Back", font=font_rate, fill=APPLE_RED)

    draw.line([(56, card_y + 225), (w - 56, card_y + 225)], fill=(65, 30, 35), width=2)

    # Calculation
    draw.text((56, card_y + 250), "Estimated Return:", font=get_font(22, bold=False), fill=TEXT_MUTED)
    draw.text((56, card_y + 285), "+$3.00 CAD Cash Back", font=get_font(34, bold=True), fill=TEXT_WHITE)

    # Advantage Pill with Costco Notice
    adv_y = card_y + 375
    draw.rounded_rectangle([56, adv_y, w - 56, adv_y + 90], radius=18, fill=BADGE_GREEN_BG, outline=APPLE_GREEN, width=1)
    draw_check_icon(draw, 88, adv_y + 45, 26, APPLE_GREEN)
    font_adv = get_font(26, bold=True)
    draw.text((120, adv_y + 30), "Costco Rule: MC Only", font=font_adv, fill=APPLE_GREEN)
    draw.text((120, adv_y + 58), "+$1.50 vs non-eligible cards", font=get_font(18, bold=False), fill=(180, 240, 195))

    # Action Confirmation Button
    btn_y = card_y + card_h + 35
    draw.rounded_rectangle([32, btn_y, w - 32, btn_y + 105], radius=26, fill=APPLE_RED)
    draw_check_icon(draw, w//2 - 135, btn_y + 53, 30, TEXT_WHITE)
    draw.text((w//2 + 15, btn_y + 53), "I Tapped Rogers", font=get_font(34, bold=True), fill=TEXT_WHITE, anchor="mm")


def render_screen_4_dining_rec(canvas):
    w, h = 820, 1004
    draw = ImageDraw.Draw(canvas)
    draw_watch_status_bar(draw, w, "9:41", "PickMe", is_root=False)

    # Category Badge Header
    cy = 76
    draw.ellipse([w//2 - 42, cy, w//2 + 42, cy + 84], fill=(50, 32, 10))
    draw_dining_icon(draw, w//2, cy + 42, 44, APPLE_ORANGE)

    font_cat = get_font(24, bold=True)
    draw.text((w//2, cy + 110), "DINING & RESTAURANTS", font=font_cat, fill=TEXT_MUTED, anchor="mm")

    # Main Card Box (Amex Cobalt)
    card_y = cy + 135
    card_h = 510
    draw.rounded_rectangle([32, card_y, w - 32, card_y + card_h], radius=28, fill=(16, 28, 48), outline=(35, 75, 135), width=2)

    # Card Brand / Issuer Pill
    draw.rounded_rectangle([56, card_y + 28, 175, card_y + 66], radius=10, fill=(20, 50, 95))
    font_badge = get_font(18, bold=True)
    draw.text((115, card_y + 47), "AMEX", font=font_badge, fill=APPLE_TEAL, anchor="mm")

    draw.text((w - 56, card_y + 47), "$40.00 Spend", font=get_font(22, bold=False), fill=TEXT_MUTED, anchor="rm")

    # Card Name Hero
    font_hero = get_font(46, bold=True)
    draw.text((56, card_y + 95), "Cobalt Card", font=font_hero, fill=TEXT_WHITE)

    # Reward Multiplier & Return
    font_rate = get_font(34, bold=True)
    draw.text((56, card_y + 165), "5x Points (5.0 MR / $1)", font=font_rate, fill=APPLE_TEAL)

    draw.line([(56, card_y + 225), (w - 56, card_y + 225)], fill=(30, 55, 95), width=2)

    # Calculation
    draw.text((56, card_y + 250), "Estimated Return:", font=get_font(22, bold=False), fill=TEXT_MUTED)
    draw.text((56, card_y + 285), "+$2.00 CAD (200 pts)", font=get_font(34, bold=True), fill=TEXT_WHITE)

    # Advantage Pill
    adv_y = card_y + 375
    draw.rounded_rectangle([56, adv_y, w - 56, adv_y + 90], radius=18, fill=BADGE_GREEN_BG, outline=APPLE_GREEN, width=1)
    draw_check_icon(draw, 88, adv_y + 45, 26, APPLE_GREEN)
    font_adv = get_font(26, bold=True)
    draw.text((120, adv_y + 30), "+$1.20 vs Default Card", font=font_adv, fill=APPLE_GREEN)
    draw.text((120, adv_y + 58), "Top card for Canadian dining", font=get_font(18, bold=False), fill=(180, 240, 195))

    # Action Confirmation Button
    btn_y = card_y + card_h + 35
    draw.rounded_rectangle([32, btn_y, w - 32, btn_y + 105], radius=26, fill=APPLE_ORANGE)
    draw_check_icon(draw, w//2 - 135, btn_y + 53, 30, TEXT_WHITE)
    draw.text((w//2 + 15, btn_y + 53), "I Tapped Cobalt", font=get_font(34, bold=True), fill=TEXT_WHITE, anchor="mm")


def render_screen_5_spending_caps(canvas):
    w, h = 820, 1004
    draw = ImageDraw.Draw(canvas)
    draw_watch_status_bar(draw, w, "9:41", "PickMe", is_root=False)

    # Title
    draw.text((36, 74), "SPENDING CAPS", font=get_font(22, bold=True), fill=TEXT_MUTED)

    caps = [
        {
            "card": "Amex Cobalt",
            "name": "5x Grocery Monthly Cap",
            "spent": 1850.0,
            "limit": 2500.0,
            "color": APPLE_BLUE,
            "badge": "Active"
        },
        {
            "card": "Scotia Momentum VI",
            "name": "4% Groceries & Gas Cap",
            "spent": 16600.0,
            "limit": 25000.0,
            "color": APPLE_RED,
            "badge": "Active"
        },
        {
            "card": "Triangle World Elite",
            "name": "4% CT Money Annual Cap",
            "spent": 1200.0,
            "limit": 10000.0,
            "color": APPLE_YELLOW,
            "badge": "Healthy"
        }
    ]

    y = 112
    row_h = 250
    gap = 22

    font_card = get_font(32, bold=True)
    font_capname = get_font(22, bold=False)
    font_stat = get_font(28, bold=True)

    for item in caps:
        remaining = item["limit"] - item["spent"]
        ratio = min(1.0, max(0.0, item["spent"] / item["limit"]))

        # Card container
        draw.rounded_rectangle([32, y, w - 32, y + row_h], radius=24, fill=ROW_BG, outline=(42, 46, 54), width=1)

        # Header: Card Name + Badge
        draw.text((54, y + 26), item["card"], font=font_card, fill=TEXT_WHITE)
        draw.rounded_rectangle([w - 165, y + 24, w - 54, y + 62], radius=10, fill=(35, 45, 60))
        draw.text((w - 110, y + 43), item["badge"], font=get_font(18, bold=True), fill=APPLE_TEAL, anchor="mm")

        # Cap description
        draw.text((54, y + 72), item["name"], font=font_capname, fill=TEXT_MUTED)

        # Progress bar
        bar_y = y + 120
        bar_w = w - 108
        draw.rounded_rectangle([54, bar_y, 54 + bar_w, bar_y + 26], radius=13, fill=(48, 52, 60))
        fill_w = max(18, int(bar_w * ratio))
        draw.rounded_rectangle([54, bar_y, 54 + fill_w, bar_y + 26], radius=13, fill=item["color"])

        # Numbers below progress
        draw.text((54, y + 172), f"${int(item['spent']):,} spent of ${int(item['limit']):,}", font=get_font(22, bold=False), fill=TEXT_MUTED)
        draw.text((w - 54, y + 172), f"${int(remaining):,} left", font=font_stat, fill=APPLE_GREEN, anchor="ra")

        y += row_h + gap


# ----------------- FRAMED SHOWCASE MARKETING GENERATOR -----------------

def create_framed_marketing_graphic(render_fn, title_text, subtitle_text, out_path):
    width, height = 1080, 1920
    img = Image.new("RGB", (width, height), (10, 12, 16))
    draw = ImageDraw.Draw(img)

    # Background gradient
    for y in range(height):
        ratio = y / height
        r = int(10 + ratio * 12)
        g = int(14 + ratio * 18)
        b = int(22 + ratio * 32)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

    # Glow aura behind watch
    draw.ellipse([width//2 - 380, 420, width//2 + 380, 1320], fill=(18, 42, 75))
    draw.ellipse([width//2 - 270, 500, width//2 + 270, 1220], fill=(24, 58, 100))

    # Top Pill Badge
    font_badge = get_font(24, bold=True)
    draw.rounded_rectangle([width//2 - 130, 95, width//2 + 130, 145], radius=25, fill=(24, 40, 65), outline=APPLE_BLUE, width=2)
    draw.text((width//2, 120), "APPLE WATCH", font=font_badge, fill=APPLE_TEAL, anchor="mm")

    font_title = get_font(58, bold=True)
    font_sub = get_font(32, bold=False)

    draw.text((width//2, 200), title_text, font=font_title, fill=TEXT_WHITE, anchor="mm")
    draw.text((width//2, 260), subtitle_text, font=font_sub, fill=APPLE_BLUE, anchor="mm")

    # Watch Frame Dimensions (Ultra Style)
    watch_w, watch_h = 580, 710
    watch_x = (width - watch_w) // 2
    watch_y = 350

    # Watch Titanium Outer Case
    draw.rounded_rectangle([watch_x - 24, watch_y - 24, watch_x + watch_w + 24, watch_y + watch_h + 24], radius=115, fill=(45, 48, 55), outline=(90, 96, 110), width=4)
    # Bezel
    draw.rounded_rectangle([watch_x - 10, watch_y - 10, watch_x + watch_w + 10, watch_y + watch_h + 10], radius=100, fill=(25, 27, 32), outline=(15, 16, 19), width=3)
    # Digital Crown (Right)
    draw.rounded_rectangle([watch_x + watch_w + 22, watch_y + 140, watch_x + watch_w + 44, watch_y + 320], radius=10, fill=(75, 78, 88), outline=(110, 115, 130), width=2)
    # Action Button (Left)
    draw.rounded_rectangle([watch_x - 42, watch_y + 180, watch_x - 22, watch_y + 320], radius=10, fill=(210, 95, 25), outline=(255, 140, 50), width=2)

    # Render screen at high resolution and resize
    hi_canvas = Image.new("RGB", (820, 1004), OLED_BLACK)
    render_fn(hi_canvas)
    screen_img = hi_canvas.resize((watch_w, watch_h), Image.Resampling.LANCZOS)

    # Screen mask with rounded corners
    mask = Image.new("L", (watch_w, watch_h), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, watch_w, watch_h], radius=88, fill=255)

    img.paste(screen_img, (watch_x, watch_y), mask)

    # Bottom feature pills
    bottom_y = 1190
    features = [
        ("01", "Instant Wrist Category Advisor", APPLE_BLUE, BADGE_BLUE_BG),
        ("02", "Canadian Merchant & Network Rules", APPLE_GREEN, BADGE_GREEN_BG),
        ("03", "Real-Time Category Spending Caps", APPLE_ORANGE, BADGE_ORANGE_BG)
    ]
    bx = 90
    for num, feat_text, col, badge_bg in features:
        draw.rounded_rectangle([bx, bottom_y, width - 90, bottom_y + 82], radius=22, fill=(20, 25, 34), outline=(40, 48, 62), width=2)
        
        # Number badge on left
        draw.rounded_rectangle([bx + 20, bottom_y + 18, bx + 76, bottom_y + 64], radius=12, fill=badge_bg, outline=col, width=1)
        draw.text((bx + 48, bottom_y + 41), num, font=get_font(20, bold=True), fill=col, anchor="mm")

        # Feature text
        draw.text((bx + 96, bottom_y + 41), feat_text, font=get_font(30, bold=True), fill=TEXT_WHITE, anchor="lm")
        draw.ellipse([width - 145, bottom_y + 31, width - 125, bottom_y + 51], fill=col)
        bottom_y += 105

    # Footer note
    draw.text((width//2, height - 70), "PickMe • Always tap the highest-earning card on Apple Pay", font=get_font(24, bold=False), fill=TEXT_MUTED, anchor="mm")

    img.save(out_path, "PNG", quality=95)
    print(f"Generated Marketing Showcase: {out_path}")


# ----------------- MAIN PIPELINE -----------------

def main():
    print("==================================================")
    print("Generating Apple Watch Screenshots for App Store Connect")
    print("==================================================")

    screens = [
        ("01_watch_category_picker", render_screen_1_categories, "Quick Category Picker", "Instant wrist advice before Apple Pay"),
        ("02_watch_groceries_recommendation", render_screen_2_groceries_rec, "Instant Grocery Solver", "Amex Cobalt 5x points & advantage badge"),
        ("03_watch_costco_recommendation", render_screen_3_costco_rec, "Costco Wholesale Optimizer", "Mastercard exclusivity & 2% cash back"),
        ("04_watch_dining_recommendation", render_screen_4_dining_rec, "Dining & Restaurants", "5.0 MR points / $1 on food & drinks"),
        ("05_watch_spending_caps", render_screen_5_spending_caps, "Real-Time Spending Caps", "Track category limits and remaining room")
    ]

    # 1. Generate Raw App Store Connect Screenshots across all Apple Watch resolutions
    for res_name, (target_w, target_h) in RESOLUTIONS.items():
        out_dir = OUTPUT_BASE / res_name
        out_dir.mkdir(parents=True, exist_ok=True)
        print(f"\nGenerating {res_name} ({target_w} x {target_h})...")

        for slug, render_fn, _, _ in screens:
            canvas = Image.new("RGB", (820, 1004), OLED_BLACK)
            render_fn(canvas)
            resized = canvas.resize((target_w, target_h), Image.Resampling.LANCZOS)
            file_path = out_dir / f"{slug}.png"
            resized.save(file_path, "PNG", quality=98)
            print(f"  ✓ {file_path.name} ({target_w}x{target_h})")

    # 2. Generate Framed Marketing Showcase Graphics
    showcase_dir = OUTPUT_BASE / "AppleWatch_Framed_Showcase"
    showcase_dir.mkdir(parents=True, exist_ok=True)
    print(f"\nGenerating Framed Marketing Showcases (1080 x 1920)...")

    for slug, render_fn, title, sub in screens:
        out_path = showcase_dir / f"showcase_{slug}.png"
        create_framed_marketing_graphic(render_fn, title, sub, str(out_path))

    print("\n==================================================")
    print("✅ All Apple Watch App Store assets generated successfully!")
    print(f"Asset directory: {OUTPUT_BASE}")
    print("==================================================")

if __name__ == "__main__":
    main()
