import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS_DIR = REPO_ROOT / "android" / "play_store_assets"
ASSETS_DIR.mkdir(parents=True, exist_ok=True)
ICON_PATH = REPO_ROOT / "App" / "CardCopilot" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"

# Color Palette
BG_DARK = (14, 17, 22)         # #0E1116
CARD_SURFACE = (22, 27, 34)    # #161B22
CARD_BORDER = (48, 54, 61)     # #30363D
ACCENT_GREEN = (46, 160, 67)   # #2EA043
ACCENT_BLUE = (88, 166, 255)   # #58A6FF
ACCENT_GOLD = (210, 153, 34)   # #D29922
TEXT_PRIMARY = (240, 246, 252) # #F0F6FC
TEXT_MUTED = (139, 148, 158)   # #8B949E

def get_font(size, bold=False):
    # Try system fonts on macOS
    font_paths = [
        "/System/Library/Fonts/SFProDisplay-Bold.otf" if bold else "/System/Library/Fonts/SFProDisplay-Regular.otf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf"
    ]
    for p in font_paths:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    return ImageFont.load_default()

def create_feature_graphic():
    width, height = 1024, 500
    img = Image.new("RGB", (width, height), BG_DARK)
    draw = ImageDraw.Draw(img)

    # Background gradient / accents
    for y in range(height):
        ratio = y / height
        r = int(14 + ratio * 8)
        g = int(17 + ratio * 15)
        b = int(22 + ratio * 30)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

    # Glow circles
    draw.ellipse([width - 300, -100, width + 200, 400], fill=(20, 50, 90))
    draw.ellipse([-100, height - 250, 350, height + 200], fill=(20, 70, 40))

    # Load and place App Icon
    if os.path.exists(ICON_PATH):
        icon = Image.open(ICON_PATH).convert("RGBA")
        icon = icon.resize((150, 150), Image.Resampling.LANCZOS)
        # Rounded corners for icon
        mask = Image.new("L", (150, 150), 0)
        mask_draw = ImageDraw.Draw(mask)
        mask_draw.rounded_rectangle([0, 0, 150, 150], radius=32, fill=255)
        img.paste(icon, (80, (height - 150) // 2), mask)

    # Title and subtitles
    font_title = get_font(52, bold=True)
    font_sub = get_font(24, bold=False)
    font_badge = get_font(18, bold=True)

    text_x = 265
    draw.text((text_x, 140), "Card Copilot", font=font_title, fill=TEXT_PRIMARY)
    draw.text((text_x, 210), "Canadian Credit Card Optimizer", font=font_sub, fill=ACCENT_BLUE)
    draw.text((text_x, 250), "Always tap the right card for maximum rewards.", font=font_sub, fill=TEXT_MUTED)

    # Badges
    badges = ["🇨🇦 Canadian Merchants", "⚡ Instant Recommendation", "🔒 100% Offline & Private"]
    bx = text_x
    by = 315
    for b in badges:
        bw = len(b) * 11 + 24
        draw.rounded_rectangle([bx, by, bx + bw, by + 38], radius=19, fill=(30, 40, 55), outline=CARD_BORDER)
        draw.text((bx + 12, by + 9), b, font=font_badge, fill=TEXT_PRIMARY)
        bx += bw + 14

    out_path = os.path.join(ASSETS_DIR, "feature_graphic_1024x500.png")
    img.save(out_path, "PNG", quality=95)
    print(f"Generated: {out_path}")

def create_phone_screenshot(title_text, subtitle_text, content_builder, filename):
    width, height = 1080, 2400
    img = Image.new("RGB", (width, height), BG_DARK)
    draw = ImageDraw.Draw(img)

    # Top gradient background
    for y in range(700):
        ratio = y / 700.0
        r = int(14 + (1.0 - ratio) * 15)
        g = int(17 + (1.0 - ratio) * 35)
        b = int(22 + (1.0 - ratio) * 60)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

    # Top Header Copy
    font_h1 = get_font(56, bold=True)
    font_h2 = get_font(32, bold=False)

    draw.text((60, 140), title_text, font=font_h1, fill=TEXT_PRIMARY)
    draw.text((60, 220), subtitle_text, font=font_h2, fill=ACCENT_BLUE)

    # Phone Mockup Frame Container
    frame_x1, frame_y1 = 60, 340
    frame_x2, frame_y2 = width - 60, height - 60
    
    # Outer device bezel
    draw.rounded_rectangle([frame_x1, frame_y1, frame_x2, frame_y2], radius=48, fill=(20, 24, 30), outline=(60, 70, 85), width=3)
    
    # Inner screen
    inner_x1, inner_y1 = frame_x1 + 16, frame_y1 + 16
    inner_x2, inner_y2 = frame_x2 - 16, frame_y2 - 16
    draw.rounded_rectangle([inner_x1, inner_y1, inner_x2, inner_y2], radius=40, fill=CARD_SURFACE)

    # Draw Status Bar
    font_time = get_font(24, bold=True)
    draw.text((inner_x1 + 40, inner_y1 + 25), "9:41", font=font_time, fill=TEXT_PRIMARY)
    draw.ellipse([inner_x2 - 100, inner_y1 + 30, inner_x2 - 85, inner_y1 + 45], fill=TEXT_PRIMARY) # battery/signal dummy

    # Call custom screen content renderer
    content_builder(draw, inner_x1, inner_y1 + 70, inner_x2 - inner_x1, inner_y2 - inner_y1 - 70)

    out_path = os.path.join(ASSETS_DIR, filename)
    img.save(out_path, "PNG", quality=95)
    print(f"Generated: {out_path}")

# 1. Home Screen Content
def render_home_content(draw, x, y, w, h):
    font_appbar = get_font(38, bold=True)
    font_sub = get_font(22, bold=False)
    font_card_title = get_font(30, bold=True)
    font_body = get_font(22, bold=False)
    font_tag = get_font(18, bold=True)

    draw.text((x + 40, y + 20), "Card Copilot", font=font_appbar, fill=TEXT_PRIMARY)
    draw.text((x + 40, y + 68), "Canadian Wallet Optimizer", font=font_sub, fill=TEXT_MUTED)

    # Search bar
    sy = y + 120
    draw.rounded_rectangle([x + 40, sy, x + w - 40, sy + 70], radius=16, fill=(33, 38, 45), outline=CARD_BORDER)
    draw.text((x + 70, sy + 22), "🔍  Search merchant or store...", font=font_body, fill=TEXT_MUTED)

    # Quick Repeats
    draw.text((x + 40, sy + 110), "QUICK REPEATS", font=font_tag, fill=TEXT_MUTED)
    rx = x + 40
    for chip in ["Loblaws", "Costco", "Shell Gas"]:
        cw = len(chip) * 16 + 50
        draw.rounded_rectangle([rx, sy + 145, rx + cw, sy + 195], radius=25, fill=(40, 50, 65))
        draw.text((rx + 20, sy + 160), f"✓ {chip}", font=font_body, fill=TEXT_PRIMARY)
        rx += cw + 16

    # Nearby Merchants
    draw.text((x + 40, sy + 230), "NEARBY MERCHANTS", font=font_tag, fill=TEXT_MUTED)

    merchants = [
        ("Loblaws (Queen & Portland)", "Grocery", "120m away", (46, 160, 67)),
        ("Costco Wholesale #541", "Wholesale Club", "450m away", (88, 166, 255)),
        ("Pai Northern Thai Kitchen", "Dining", "230m away", (210, 153, 34)),
        ("Shoppers Drug Mart", "Drug Store", "310m away", (218, 54, 51)),
        ("Shell Gas Station", "Gas Station", "580m away", (227, 98, 9)),
        ("Toronto Marriott Downtown", "Lodging", "800m away", (163, 113, 247))
    ]

    my = sy + 270
    for name, cat, dist, color in merchants:
        draw.rounded_rectangle([x + 40, my, x + w - 40, my + 120], radius=18, fill=(28, 33, 40), outline=CARD_BORDER)
        draw.text((x + 65, my + 25), name, font=font_card_title, fill=TEXT_PRIMARY)
        
        # Pill
        draw.rounded_rectangle([x + 65, my + 70, x + 200, my + 100], radius=8, fill=color)
        draw.text((x + 80, my + 74), cat, font=font_tag, fill=(255, 255, 255))
        draw.text((x + 220, my + 74), dist, font=font_body, fill=TEXT_MUTED)
        my += 140

# 2. Recommendation Screen Content
def render_recommendation_content(draw, x, y, w, h):
    font_appbar = get_font(36, bold=True)
    font_hero_name = get_font(42, bold=True)
    font_sub = get_font(24, bold=False)
    font_val = get_font(52, bold=True)
    font_tag = get_font(20, bold=True)

    draw.text((x + 40, y + 20), "Loblaws (Queen & Portland)", font=font_appbar, fill=TEXT_PRIMARY)
    draw.text((x + 40, y + 68), "$60.00 purchase", font=font_sub, fill=TEXT_MUTED)

    # Hero Card (Cobalt Blue Gradient)
    cy = y + 130
    draw.rounded_rectangle([x + 40, cy, x + w - 40, cy + 340], radius=24, fill=(20, 56, 115), outline=(100, 160, 255), width=2)
    draw.text((x + 75, cy + 35), "AMERICAN EXPRESS", font=font_tag, fill=(180, 210, 255))
    draw.text((x + w - 160, cy + 35), "AMEX", font=font_tag, fill=(115, 209, 255))
    draw.text((x + 75, cy + 200), "Cobalt Card", font=font_hero_name, fill=(255, 255, 255))
    draw.text((x + 75, cy + 260), "•••• •••• •••• 2026", font=font_sub, fill=(180, 210, 255))

    # Reward Calculation Box
    ry = cy + 370
    draw.text((x + 40, ry), "ESTIMATED REWARD", font=font_tag, fill=TEXT_MUTED)
    draw.text((x + 40, ry + 35), "+$3.00 CAD", font=font_val, fill=ACCENT_GREEN)

    # Advantage badge
    draw.rounded_rectangle([x + 420, ry + 40, x + w - 40, ry + 95], radius=12, fill=(25, 75, 40))
    draw.text((x + 440, ry + 55), "+$1.80 vs default", font=font_tag, fill=ACCENT_GREEN)

    # Explanation card
    ey = ry + 120
    draw.rounded_rectangle([x + 40, ey, x + w - 40, ey + 220], radius=18, fill=(28, 33, 40), outline=CARD_BORDER)
    draw.text((x + 65, ey + 25), "Use Cobalt — 5x points on groceries.", font=get_font(28, bold=True), fill=TEXT_PRIMARY)
    draw.text((x + 65, ey + 75), "Applied rule: 5.0 MR points per $1 CAD (300 pts = $3.00)", font=font_sub, fill=TEXT_MUTED)
    draw.text((x + 65, ey + 125), "Runner-up: Scotia Momentum VI ($2.40 back, 4%)", font=font_sub, fill=TEXT_MUTED)

    # Button
    by = ey + 260
    draw.rounded_rectangle([x + 40, by, x + w - 40, by + 90], radius=20, fill=ACCENT_GREEN)
    draw.text((x + w//2 - 130, by + 28), "I Tapped This Card", font=get_font(28, bold=True), fill=(255, 255, 255))

# 3. Amount Capture Screen Content
def render_amount_content(draw, x, y, w, h):
    font_appbar = get_font(36, bold=True)
    font_amount = get_font(84, bold=True)
    font_sub = get_font(26, bold=False)
    font_tag = get_font(20, bold=True)
    font_key = get_font(38, bold=True)

    draw.text((x + 40, y + 20), "Enter Purchase Amount", font=font_appbar, fill=TEXT_PRIMARY)
    draw.text((x + 40, y + 70), "Loblaws Supermarket", font=font_sub, fill=TEXT_MUTED)

    # Amount display
    draw.text((x + w//2 - 120, y + 160), "$60.00", font=font_amount, fill=TEXT_PRIMARY)
    draw.text((x + w//2 - 160, y + 270), "Category: Grocery (Typical: $60)", font=font_sub, fill=ACCENT_BLUE)

    # Preset pills
    py = y + 330
    draw.text((x + 40, py), "QUICK PRESETS", font=font_tag, fill=TEXT_MUTED)
    px = x + 40
    for preset in ["$15", "$25", "$35", "$50", "$60", "$100"]:
        draw.rounded_rectangle([px, py + 35, px + 120, py + 95], radius=14, fill=(35, 42, 54), outline=CARD_BORDER)
        draw.text((px + 30, py + 52), preset, font=get_font(24, bold=True), fill=TEXT_PRIMARY)
        px += 135

    # Keypad
    ky = py + 160
    keys = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]]
    for row in keys:
        kx = x + 40
        for key in row:
            draw.rounded_rectangle([kx, ky, kx + 260, ky + 100], radius=16, fill=(28, 33, 40), outline=CARD_BORDER)
            draw.text((kx + 115, ky + 25), key, font=font_key, fill=TEXT_PRIMARY)
            kx += 280
        ky += 120

    # Compare button
    by = ky + 30
    draw.rounded_rectangle([x + 40, by, x + w - 40, by + 90], radius=20, fill=ACCENT_BLUE)
    draw.text((x + w//2 - 110, by + 28), "Compare Cards", font=get_font(28, bold=True), fill=(255, 255, 255))

# 4. Dashboard Screen Content
def render_dashboard_content(draw, x, y, w, h):
    font_appbar = get_font(36, bold=True)
    font_title = get_font(28, bold=True)
    font_val = get_font(60, bold=True)
    font_sub = get_font(22, bold=False)
    font_tag = get_font(18, bold=True)

    draw.text((x + 40, y + 20), "Experiment Dashboard", font=font_appbar, fill=TEXT_PRIMARY)

    # 30-Checkout Progress Card
    py = y + 90
    draw.rounded_rectangle([x + 40, py, x + w - 40, py + 160], radius=20, fill=(28, 33, 40), outline=CARD_BORDER)
    draw.text((x + 65, py + 25), "30-CHECKOUT TARGET", font=font_tag, fill=TEXT_MUTED)
    draw.text((x + w - 160, py + 25), "24 / 30", font=get_font(24, bold=True), fill=TEXT_PRIMARY)
    # Progress bar
    draw.rounded_rectangle([x + 65, py + 80, x + w - 65, py + 105], radius=12, fill=(40, 50, 65))
    draw.rounded_rectangle([x + 65, py + 80, x + 65 + int((w - 130) * 0.8), py + 105], radius=12, fill=ACCENT_GREEN)

    # Gauges (Category Accuracy & Arithmetic)
    gy = py + 190
    # Left gauge
    draw.rounded_rectangle([x + 40, gy, x + w//2 - 15, gy + 200], radius=20, fill=(28, 33, 40), outline=CARD_BORDER)
    draw.text((x + 65, gy + 25), "CATEGORY ACCURACY", font=font_tag, fill=TEXT_MUTED)
    draw.text((x + 65, gy + 70), "95.8%", font=font_val, fill=ACCENT_GREEN)
    draw.text((x + 65, gy + 145), "Target: ≥ 85% ✓", font=font_sub, fill=TEXT_MUTED)

    # Right gauge
    draw.rounded_rectangle([x + w//2 + 15, gy, x + w - 40, gy + 200], radius=20, fill=(28, 33, 40), outline=CARD_BORDER)
    draw.text((x + w//2 + 40, gy + 25), "ARITHMETIC MATCH", font=font_tag, fill=TEXT_MUTED)
    draw.text((x + w//2 + 40, gy + 70), "100%", font=font_val, fill=ACCENT_GREEN)
    draw.text((x + w//2 + 40, gy + 145), "Target: 100% ✓", font=font_sub, fill=TEXT_MUTED)

    # Value Recovered Card
    vy = gy + 230
    draw.rounded_rectangle([x + 40, vy, x + w - 40, vy + 220], radius=20, fill=(28, 33, 40), outline=CARD_BORDER)
    draw.text((x + 65, vy + 25), "WALLET VALUE RECOVERED", font=font_tag, fill=TEXT_MUTED)
    draw.text((x + 65, vy + 70), "$184.50 CAD", font=font_val, fill=ACCENT_GREEN)
    draw.text((x + 65, vy + 150), "+$26.10 CAD pending statement reconciliation", font=font_sub, fill=TEXT_MUTED)

# 5. Wallet Health Screen Content
def render_wallet_health_content(draw, x, y, w, h):
    font_appbar = get_font(36, bold=True)
    font_title = get_font(28, bold=True)
    font_val = get_font(52, bold=True)
    font_sub = get_font(22, bold=False)
    font_tag = get_font(18, bold=True)

    draw.text((x + 40, y + 20), "Wallet Health & Audit", font=font_appbar, fill=TEXT_PRIMARY)

    # Annual Value
    vy = y + 90
    draw.rounded_rectangle([x + 40, vy, x + w - 40, vy + 190], radius=20, fill=(28, 33, 40), outline=CARD_BORDER)
    draw.text((x + 65, vy + 25), "ESTIMATED ANNUAL PORTFOLIO VALUE", font=font_tag, fill=TEXT_MUTED)
    draw.text((x + 65, vy + 65), "$1,280.45 CAD / yr", font=font_val, fill=ACCENT_GREEN)
    draw.text((x + 65, vy + 135), "Total Annual Fees: $279.00 CAD • Net: +$1,001.45", font=font_sub, fill=TEXT_MUTED)

    # Card list
    cards = [
        ("Amex Cobalt", "American Express", "+$450.00", "$155.00", "KEEP", ACCENT_GREEN),
        ("Scotia Momentum VI", "Scotiabank", "+$290.00", "$120.00", "KEEP", ACCENT_GREEN),
        ("Rogers Red WE", "Rogers Bank", "+$340.00", "$0.00", "FREE TO KEEP", ACCENT_GREEN),
        ("Tangerine Money-Back", "Tangerine", "+$180.00", "$0.00", "FREE TO KEEP", ACCENT_GREEN),
        ("Triangle World Elite", "Canadian Tire Bank", "+$120.00", "$0.00", "FREE TO KEEP", ACCENT_GREEN)
    ]

    cy = vy + 220
    for name, issuer, val, fee, verdict, vcolor in cards:
        draw.rounded_rectangle([x + 40, cy, x + w - 40, cy + 130], radius=18, fill=(28, 33, 40), outline=CARD_BORDER)
        draw.text((x + 65, cy + 20), name, font=font_title, fill=TEXT_PRIMARY)
        draw.text((x + 65, cy + 60), f"{issuer} • Fee: {fee}", font=font_sub, fill=TEXT_MUTED)
        draw.text((x + 65, cy + 90), f"Marginal Reward Value: {val}", font=font_sub, fill=ACCENT_BLUE)

        # Verdict Tag
        vw = len(verdict) * 12 + 24
        draw.rounded_rectangle([x + w - 65 - vw, cy + 25, x + w - 65, cy + 65], radius=10, fill=vcolor)
        draw.text((x + w - 55 - vw, cy + 32), verdict, font=font_tag, fill=(255, 255, 255))
        cy += 150

def main():
    print("Generating Google Play Store visual assets...")
    create_feature_graphic()
    create_phone_screenshot("Nearby Merchant Radar", "Instant category & network detection", render_home_content, "screenshot_1_home.png")
    create_phone_screenshot("Smart Recommendation", "Mathematical reward solver & advantage badge", render_recommendation_content, "screenshot_2_recommendation.png")
    create_phone_screenshot("Fast Amount Capture", "Typical Canadian purchase presets & keypad", render_amount_content, "screenshot_3_amount_capture.png")
    create_phone_screenshot("Experiment Dashboard", "Track accuracy & confirmed value recovered", render_dashboard_content, "screenshot_4_dashboard.png")
    create_phone_screenshot("Wallet Portfolio Audit", "Keep, downgrade & acquisition advice", render_wallet_health_content, "screenshot_5_wallet_health.png")
    print("All store assets generated successfully!")

if __name__ == "__main__":
    main()
