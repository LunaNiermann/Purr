"""Generates the extension action icons: green rounded square, white '2'.
A designed brand mark is explicitly out of scope in the handoff; this is the
same drawn placeholder the app uses."""
from PIL import Image, ImageDraw, ImageFont
import os

GREEN = (47, 111, 91, 255)
PAPER = (247, 245, 241, 255)

os.makedirs("public/icons", exist_ok=True)

for size in (16, 32, 48, 128):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    radius = round(size * 0.31)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=GREEN)
    try:
        font = ImageFont.truetype(
            "../app/assets/fonts/InstrumentSans-Bold.ttf", round(size * 0.62)
        )
    except OSError:
        font = ImageFont.load_default()
    bbox = d.textbbox((0, 0), "2", font=font)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(
        ((size - w) / 2 - bbox[0], (size - h) / 2 - bbox[1]),
        "2",
        font=font,
        fill=PAPER,
    )
    img.save(f"public/icons/icon{size}.png")
    print(f"icon{size}.png")
