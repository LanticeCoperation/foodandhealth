"""Body Lab app icon: cream lab flask, mint liquid whose surface is a falling trend line."""
import math
import os
import sys

from PIL import Image, ImageDraw

OUT = sys.argv[1]
SS = 4  # supersampling
N = 1024 * SS

BG_TOP = (36, 124, 104)
BG_BOTTOM = (19, 74, 62)
CREAM = (246, 241, 232)
MINT = (126, 211, 186)
DEEP = (14, 58, 49)


def S(v):
    return v * SS


def rounded(points, radii, steps=12):
    """Polygon with each vertex rounded by a quadratic curve of the given radius."""
    out = []
    n = len(points)
    for k in range(n):
        p0, p1, p2 = points[k - 1], points[k], points[(k + 1) % n]
        r = radii[k]
        if r == 0:
            out.append(p1)
            continue
        def toward(a, b, dist):
            dx, dy = b[0] - a[0], b[1] - a[1]
            L = math.hypot(dx, dy)
            return (a[0] + dx / L * dist, a[1] + dy / L * dist)
        a = toward(p1, p0, r)
        b = toward(p1, p2, r)
        for t in range(steps + 1):
            u = t / steps
            x = (1 - u) ** 2 * a[0] + 2 * (1 - u) * u * p1[0] + u ** 2 * b[0]
            y = (1 - u) ** 2 * a[1] + 2 * (1 - u) * u * p1[1] + u ** 2 * b[1]
            out.append((x, y))
    return out


def flask_path(scale=1.0, cx=512, cy=512):
    """Flask outline (closed), centered, in 1024 coords before scaling."""
    neck_w, neck_top, neck_bot = 150, 215, 420
    body_w, body_bot = 560, 820
    pts = [
        (cx - neck_w / 2, neck_top),
        (cx - neck_w / 2, neck_bot),
        (cx - body_w / 2, body_bot),
        (cx + body_w / 2, body_bot),
        (cx + neck_w / 2, neck_bot),
        (cx + neck_w / 2, neck_top),
    ]
    radii = [0, 40, 60, 60, 40, 0]
    path = rounded(pts, radii)
    return [((x - cx) * scale + cx, (y - cy) * scale + cy) for x, y in path]


def draw_icon(size_scale, background):
    img = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    if background:
        grad = Image.new('RGBA', (1, N))
        for y in range(N):
            t = y / (N - 1)
            grad.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)) + (255,))
        img = grad.resize((N, N))

    path = [(S(x), S(y)) for x, y in flask_path(size_scale)]
    stroke = S(46 * size_scale)

    # interior (glass) = slightly darker than background so the outline pops
    mask = Image.new('L', (N, N), 0)
    ImageDraw.Draw(mask).polygon(path, fill=255)
    interior = Image.new('RGBA', (N, N), DEEP + (255,))
    img.paste(interior, (0, 0), mask)

    # liquid: below a falling trend line, clipped to the flask interior
    cx = 512
    def P(x, y):
        return (S((x - cx) * size_scale + cx), S((y - 512) * size_scale + 512))
    # 清楚往下走的折線：小反彈但整體下降
    trend = [P(230, 545), P(360, 610), P(450, 585), P(590, 680), P(800, 735)]
    liquid_poly = trend + [P(820, 900), P(200, 900)]
    lmask = Image.new('L', (N, N), 0)
    ImageDraw.Draw(lmask).polygon(liquid_poly, fill=255)
    lmask = Image.composite(lmask, Image.new('L', (N, N), 0), mask)
    img.paste(Image.new('RGBA', (N, N), MINT + (255,)), (0, 0), lmask)

    d = ImageDraw.Draw(img)
    # trend line on the liquid surface (cream), clipped by drawing before the outline
    line_layer = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    ld = ImageDraw.Draw(line_layer)
    ld.line(trend, fill=CREAM + (255,), width=int(S(22 * size_scale)), joint='curve')
    end = P(590, 680)
    r_dot = S(26 * size_scale)
    ld.ellipse([end[0] - r_dot, end[1] - r_dot, end[0] + r_dot, end[1] + r_dot], fill=CREAM + (255,))
    img.paste(line_layer, (0, 0), Image.composite(line_layer.split()[3], Image.new('L', (N, N), 0), mask))

    # bubbles
    for bx, by, br in [(420, 740, 24), (520, 770, 16), (340, 700, 13)]:
        x, y = P(bx, by)
        rr = S(br * size_scale)
        d.ellipse([x - rr, y - rr, x + rr, y + rr], outline=CREAM + (255,), width=int(S(9 * size_scale)))

    # flask outline
    d.line(path + [path[0]], fill=CREAM + (255,), width=int(stroke), joint='curve')
    for x, y in path:
        d.ellipse([x - stroke / 2, y - stroke / 2, x + stroke / 2, y + stroke / 2], fill=CREAM + (255,))
    # rim
    lip_w, lip_y = 230, 205
    x0, y0 = P(cx - lip_w / 2, lip_y - 26)
    x1, y1 = P(cx + lip_w / 2, lip_y + 26)
    d.rounded_rectangle([x0, y0, x1, y1], radius=S(26 * size_scale), fill=CREAM + (255,))

    return img.resize((1024, 1024), Image.LANCZOS)


os.makedirs(OUT, exist_ok=True)
draw_icon(1.0, True).convert('RGB').save(os.path.join(OUT, 'icon.png'))
# Android adaptive icon foreground: content inside the 66% safe zone, transparent bg
draw_icon(0.72, False).save(os.path.join(OUT, 'foreground.png'))

# preview: full icon, rounded (iOS-like) and small sizes
full = Image.open(os.path.join(OUT, 'icon.png')).convert('RGBA')
prev = Image.new('RGBA', (1500, 560), (239, 235, 228, 255))
m = Image.new('L', (512, 512), 0)
ImageDraw.Draw(m).rounded_rectangle([0, 0, 511, 511], radius=115, fill=255)
prev.paste(full.resize((512, 512), Image.LANCZOS), (24, 24), m)
x = 580
for sz in (180, 120, 60):
    mm = Image.new('L', (sz, sz), 0)
    ImageDraw.Draw(mm).rounded_rectangle([0, 0, sz - 1, sz - 1], radius=int(sz * 0.225), fill=255)
    prev.paste(full.resize((sz, sz), Image.LANCZOS), (x, 280 - sz // 2), mm)
    x += sz + 60
# adaptive (circle crop) preview
fg = Image.open(os.path.join(OUT, 'foreground.png'))
bg = Image.new('RGBA', (1024, 1024), BG_BOTTOM + (255,))
bg.alpha_composite(fg)
cm = Image.new('L', (200, 200), 0)
ImageDraw.Draw(cm).ellipse([0, 0, 199, 199], fill=255)
prev.paste(bg.resize((200, 200), Image.LANCZOS), (x, 180), cm)
prev.save(os.path.join(OUT, 'preview.png'))
print('ok')
