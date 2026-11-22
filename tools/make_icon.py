import os, math
from PIL import Image, ImageDraw, ImageFont

OUT = r"C:\Users\wawml\Documents\deepseek-harness\default-workspace\github\gdou-schedule-ios\Resources\Assets.xcassets\AppIcon.appiconset"
os.makedirs(OUT, exist_ok=True)

S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# 海蓝渐变底
top = (0, 126, 190)
bot = (0, 78, 140)
for y in range(S):
    t = y / (S - 1)
    c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
    d.line([(0, y), (S, y)], fill=c + (255,))

# 圆角遮罩（iOS 会自动切圆角，这里只做视觉圆角）
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=255)
img.putalpha(mask)

d = ImageDraw.Draw(img)

# 顶部/底部柔光
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([-S * 0.3, -S * 0.5, S * 1.1, S * 0.4], fill=(255, 255, 255, 26))
img = Image.alpha_composite(img, glow)
d = ImageDraw.Draw(img)

def font(size):
    for p in [r"C:\Windows\Fonts\msyhbd.ttc", r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    return ImageFont.load_default()

glyph = "课"
f = font(470)
box = d.textbbox((0, 0), glyph, font=f)
w, h = box[2] - box[0], box[3] - box[1]
d.text(((S - w) / 2 - box[0], (S - h) / 2 - box[1] - 92), glyph, font=f, fill=(255, 255, 255, 255))

# 底部三行小课表格，呼应课表 UI
cell_w, cell_h, gap = 88, 48, 13
total_w = cell_w * 3 + gap * 2
x0 = (S - total_w) / 2
y0 = S * 0.775
for row in range(2):
    for col in range(3):
        x = x0 + col * (cell_w + gap)
        y = y0 + row * (cell_h + gap)
        alpha = 235 if (row, col) != (0, 1) else 120
        d.rounded_rectangle([x, y, x + cell_w, y + cell_h], radius=16, fill=(255, 255, 255, alpha))

img.save(os.path.join(OUT, "icon-1024.png"))
print("icon written", os.path.join(OUT, "icon-1024.png"), img.size)
