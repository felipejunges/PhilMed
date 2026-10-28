"""Gera o ícone do PhilMed (cápsula + relógio) em todos os tamanhos.

Uso: python3 tool/make_icon.py . /tmp/preview   (requer Pillow)
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw

S = 2048  # resolução de trabalho (supersampling)
TEAL_TOP = (58, 160, 136)
TEAL_BOTTOM = (30, 100, 86)
TEAL_DARK = (24, 84, 72)
WHITE = (255, 255, 255)
MINT = (178, 235, 214)


def glyph(size=S):
    """Cápsula inclinada + relógio, fundo transparente, ocupando ~o quadro."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Cápsula desenhada na horizontal e depois rotacionada.
    cap = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(cap)
    L, W = int(size * 0.80), int(size * 0.34)
    x0, y0 = (size - L) // 2, (size - W) // 2
    x1, y1 = x0 + L, y0 + W
    r = W // 2
    mid = size // 2
    # metade esquerda branca, direita menta
    d.rounded_rectangle((x0, y0, x1, y1), radius=r, fill=MINT)
    left = Image.new("L", (size, size), 0)
    ImageDraw.Draw(left).rectangle((0, 0, mid, size), fill=255)
    white = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(white).rounded_rectangle((x0, y0, x1, y1), radius=r, fill=WHITE)
    cap.paste(white, (0, 0), ImageChops.multiply(white.split()[3], left))
    d = ImageDraw.Draw(cap)
    d.line((mid, y0 + 4, mid, y1 - 4), fill=TEAL_DARK + (90,), width=int(size * 0.012))
    cap = cap.rotate(45, resample=Image.BICUBIC, center=(mid, mid))
    # desloca a cápsula para cima/esquerda, abrindo espaço para o relógio
    off = int(size * -0.07)
    img.alpha_composite(cap, (off, off))

    # Relógio no canto inferior direito.
    d = ImageDraw.Draw(img)
    cr = int(size * 0.215)
    cx = cy = int(size * 0.715)
    ring = int(size * 0.035)
    d.ellipse((cx - cr - ring, cy - cr - ring, cx + cr + ring, cy + cr + ring), fill=TEAL_DARK)
    d.ellipse((cx - cr, cy - cr, cx + cr, cy + cr), fill=WHITE)
    hw = int(size * 0.03)
    d.line((cx, cy, cx, cy - cr * 0.62), fill=TEAL_DARK, width=hw)
    d.line((cx, cy, cx + cr * 0.48, cy), fill=TEAL_DARK, width=hw)
    d.ellipse((cx - hw, cy - hw, cx + hw, cy + hw), fill=TEAL_DARK)
    for i in range(12):
        import math
        a = math.radians(i * 30)
        rr0, rr1 = cr * 0.80, cr * 0.92
        d.line(
            (cx + rr0 * math.sin(a), cy - rr0 * math.cos(a), cx + rr1 * math.sin(a), cy - rr1 * math.cos(a)),
            fill=TEAL_DARK + (160,),
            width=int(size * 0.012),
        )
    return img


def background(size=S):
    bg = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(bg)
    for y in range(size):
        t = y / (size - 1)
        c = tuple(int(a + (b - a) * t) for a, b in zip(TEAL_TOP, TEAL_BOTTOM))
        d.line((0, y, size, y), fill=c + (255,))
    return bg


def place(layer, scale, size=S):
    g = layer.resize((int(size * scale),) * 2, Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(g, ((size - g.width) // 2, (size - g.height) // 2))
    return out


def legacy_icon():
    """Ícone quadrado arredondado (Android < 8, Linux)."""
    bg = background()
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * 0.22), fill=255)
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    icon.paste(bg, (0, 0), mask)
    icon.alpha_composite(place(glyph(), 0.78))
    return icon


def main(root, preview_dir):
    g = glyph()
    legacy = legacy_icon()
    # Adaptive: o conteúdo precisa caber no círculo seguro (66/108 dp).
    fg = place(g, 0.60)
    mono = fg.copy()
    # Monocromático (ícones temáticos): partes claras opacas, escuras vazadas.
    def mono_px(p):
        r, g_, b, a = p
        lum = 0.299 * r + 0.587 * g_ + 0.114 * b
        k = min(max((lum - 110) / 90, 0), 1)
        return (255, 255, 255, int(a * k))
    mono.putdata([mono_px(p) for p in fg.getdata()])

    res = os.path.join(root, "android/app/src/main/res")
    sizes = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, k in sizes.items():
        d = os.path.join(res, f"mipmap-{name}")
        os.makedirs(d, exist_ok=True)
        legacy.resize((int(48 * k),) * 2, Image.LANCZOS).save(os.path.join(d, "ic_launcher.png"))
        fg.resize((int(108 * k),) * 2, Image.LANCZOS).save(os.path.join(d, "ic_launcher_foreground.png"))
        mono.resize((int(108 * k),) * 2, Image.LANCZOS).save(os.path.join(d, "ic_launcher_monochrome.png"))

    anydpi = os.path.join(res, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, "ic_launcher.xml"), "w") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
            "</adaptive-icon>\n"
        )
    with open(os.path.join(res, "values/ic_launcher_background.xml"), "w") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            '    <color name="ic_launcher_background">#2C8572</color>\n</resources>\n'
        )

    os.makedirs(os.path.join(root, "assets"), exist_ok=True)
    legacy.resize((512, 512), Image.LANCZOS).save(os.path.join(root, "assets/icon.png"))

    # Prévia: ícone legado + adaptive com máscara circular, lado a lado.
    os.makedirs(preview_dir, exist_ok=True)
    P = 384
    prev = Image.new("RGBA", (P * 3 + 80, P + 40), (240, 240, 240, 255))
    prev.alpha_composite(legacy.resize((P, P), Image.LANCZOS), (20, 20))
    adaptive = background().copy()
    adaptive.alpha_composite(fg)
    circ = Image.new("L", (S, S), 0)
    ImageDraw.Draw(circ).ellipse((S * 0.09, S * 0.09, S * 0.91, S * 0.91), fill=255)
    a = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    a.paste(adaptive, (0, 0), circ)
    a = a.crop((int(S * 0.09), int(S * 0.09), int(S * 0.91), int(S * 0.91)))
    prev.alpha_composite(a.resize((P, P), Image.LANCZOS), (P + 40, 20))
    small = legacy.resize((48, 48), Image.LANCZOS)
    prev.alpha_composite(small.resize((P // 2, P // 2), Image.NEAREST), (2 * P + 60, 20))
    prev.alpha_composite(small, (2 * P + 60, P // 2 + 40))
    prev.save(os.path.join(preview_dir, "preview.png"))
    m = Image.new("RGBA", (S, S), (60, 60, 60, 255))
    m.alpha_composite(mono)
    m.resize((256, 256), Image.LANCZOS).save(os.path.join(preview_dir, "mono.png"))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
