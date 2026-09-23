"""Builds the app's icons from `Ump Smart Dine Logo.png`.

Run from the project root (needs Pillow):

    python tool/make_icons.py
    dart run flutter_launcher_icons

Outputs
  assets/branding/app_icon.png             1024² launcher icon (legacy / iOS)
  assets/branding/app_icon_foreground.png  1024² adaptive-icon foreground
  android/.../drawable-*/ic_stat_notify.png  status-bar notification icon
  android/.../drawable-nodpi/notification_large_icon.png  colour icon shown
                                            beside each notification

The launcher and notification icons use the burger-and-scroll mark only: the
"UMP SMART DINE APP" lettering is unreadable at icon sizes.

Android draws the status-bar icon from its alpha channel alone, and a
silhouette cut from the photographic mark reads as a blob at 24 px. So the
status-bar icon is a flat glyph drawn from the mark's composition — domed bun,
filling, patty, bottom bun, and the rolled scroll with its tie — in white on
transparency.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / 'Ump Smart Dine Logo.png'
RES = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
BRANDING = ROOT / 'assets' / 'branding'

# The burger-and-scroll mark within the logo (left, top, right, bottom).
MARK_BOX = (186, 98, 378, 237)

# AppColors.brandPale — the warm background behind the mark.
BRAND_PALE = (0xFF, 0xF3, 0xE0, 255)


def mark() -> Image.Image:
    logo = Image.open(LOGO).convert('RGBA')
    cropped = logo.crop(MARK_BOX)
    return cropped.crop(cropped.getchannel('A').getbbox())


def fit(image: Image.Image, box: int) -> Image.Image:
    """Scales [image] to fit inside a [box]×[box] square, keeping its shape."""
    scale = box / max(image.size)
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    return image.resize(size, Image.LANCZOS)


def centred(image: Image.Image, canvas: int, background) -> Image.Image:
    out = Image.new('RGBA', (canvas, canvas), background)
    out.alpha_composite(image, ((canvas - image.width) // 2, (canvas - image.height) // 2))
    return out


def glyph(size: int = 960) -> Image.Image:
    """The mark as a flat white glyph (alpha only), [size]×[size]."""
    img = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(img)

    def u(*v: float) -> list[int]:
        return [round(x * size) for x in v]

    d.chord(u(0.06, 0.16, 0.70, 0.70), 180, 360, fill=255)          # top bun
    d.rounded_rectangle(u(0.04, 0.47, 0.72, 0.53), radius=round(0.03 * size), fill=255)
    for i in range(6):                                                # lettuce
        x = 0.07 + i * 0.11
        d.ellipse(u(x, 0.49, x + 0.09, 0.575), fill=255)
    d.rounded_rectangle(u(0.07, 0.61, 0.69, 0.70), radius=round(0.045 * size), fill=255)  # patty
    d.rounded_rectangle(u(0.06, 0.74, 0.70, 0.84), radius=round(0.05 * size), fill=255)   # bottom bun

    scroll = Image.new('L', (size, size), 0)
    sd = ImageDraw.Draw(scroll)
    sd.rounded_rectangle(u(0.77, 0.10, 0.90, 0.80), radius=round(0.06 * size), fill=255)
    sd.rectangle(u(0.76, 0.43, 0.91, 0.47), fill=0)                  # the tie
    scroll = scroll.rotate(-14, center=(0.835 * size, 0.45 * size), resample=Image.BICUBIC)
    img.paste(255, (0, 0), scroll)

    white = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    white.putalpha(img)
    return white


def main() -> None:
    m = mark()
    BRANDING.mkdir(parents=True, exist_ok=True)

    # Launcher icon: the mark on the warm brand background, with margin.
    centred(fit(m, 760), 1024, BRAND_PALE).save(BRANDING / 'app_icon.png')

    # Adaptive foreground: the mark inside the 66% safe zone, on transparency
    # (the background colour comes from flutter_launcher_icons config).
    centred(fit(m, 600), 1024, (0, 0, 0, 0)).save(BRANDING / 'app_icon_foreground.png')

    # Status-bar icon per density; the glyph carries its own margin.
    shape = glyph()
    for folder, px in {
        'drawable-mdpi': 24,
        'drawable-hdpi': 36,
        'drawable-xhdpi': 48,
        'drawable-xxhdpi': 72,
        'drawable-xxxhdpi': 96,
    }.items():
        out_dir = RES / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        shape.resize((px, px), Image.LANCZOS).save(out_dir / 'ic_stat_notify.png')

    # Large icon beside each notification: full colour on the brand background.
    nodpi = RES / 'drawable-nodpi'
    nodpi.mkdir(parents=True, exist_ok=True)
    centred(fit(m, 200), 256, BRAND_PALE).save(nodpi / 'notification_large_icon.png')

    print('Icons written. Next: dart run flutter_launcher_icons')


if __name__ == '__main__':
    main()
