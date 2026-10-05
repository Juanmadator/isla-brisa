"""Junta las capturas de captures/items en hojas de contacto con su nombre."""
import glob, os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
files = sorted(glob.glob(os.path.join(ROOT, "captures", "items", "*.png")))
cols, w, h = 4, 480, 270
per = 16
for sheet in range(0, len(files), per):
    chunk = files[sheet:sheet + per]
    rows = (len(chunk) + cols - 1) // cols
    out = Image.new("RGB", (cols * w, rows * h), "black")
    d = ImageDraw.Draw(out)
    for i, f in enumerate(chunk):
        im = Image.open(f).convert("RGB")
        x, y = (i % cols) * w, (i // cols) * h
        out.paste(im, (x, y))
        name = os.path.splitext(os.path.basename(f))[0]
        d.rectangle([x, y, x + 8 * len(name) + 10, y + 18], fill="black")
        d.text((x + 5, y + 3), name, fill="white")
    path = os.path.join(ROOT, "captures", "sheet_%d.png" % (sheet // per))
    out.save(path)
    print(path)
