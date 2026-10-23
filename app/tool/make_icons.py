#!/usr/bin/env python3
"""アプリアイコン「ファインダーの何」を描き、Android / iOS / ストア / Web / スプラッシュの画像を一式生成する。

意匠: 深いジェイドの卓（上から下へのグラデーションと左上の柔らかい光）の上に、アイボリーの牌
（下に側面と山吹色の背の層が見える立体）に太い「何」。牌の上に朱の▼（切る牌のカーソル）、
四隅にゴールドの L 字（カメラのファインダー）。

実行（リポジトリのルートまたは app/ から）:

    py -3.12 -m pip install pillow numpy     # 初回のみ
    py -3.12 app/tool/make_icons.py

生成するもの（既存は上書き。パスは app/ から）:
  assets/branding/icon_1024.png                 原画（全面を塗った正方形、アルファなし）
  assets/branding/play_store_icon_512.png       Google Play の「アプリアイコン」（512、32 ビット PNG）
  assets/branding/feature_graphic_1024x500.png  Google Play の「フィーチャーグラフィック」
  android/app/src/main/res/mipmap-*dpi/ic_launcher.png             旧形式（角丸）
  android/app/src/main/res/mipmap-*dpi/ic_launcher_foreground.png  アダプティブアイコンの前景（108dp）
  android/app/src/main/res/mipmap-*dpi/ic_launcher_monochrome.png  Android 13 のテーマアイコン
  android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml       アダプティブアイコン
  android/app/src/main/res/drawable/ic_launcher_gradient.xml       アダプティブアイコンの背景（グラデーション）
  android/app/src/main/res/values/ic_launcher_background.xml       ブランド色（通知の強調色・スプラッシュの背景を兼ねる）
  android/app/src/main/res/drawable-*dpi/ic_stat_notify.png        通知の小アイコン（白一色）
  android/app/src/main/res/drawable-*dpi/launch_logo.png           スプラッシュ中央のロゴ（Android 11 以下）
  android/app/src/main/res/drawable{,-v21}/launch_background.xml   スプラッシュ（Android 11 以下）
  android/app/src/main/res/values{,-night}-v31/styles.xml          スプラッシュ（Android 12 以降）
  ios/Runner/Assets.xcassets/AppIcon.appiconset/                   1024 の 1 枚 + Contents.json
  ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage*.png スプラッシュ中央のロゴ
  ios/Runner/Base.lproj/LaunchScreen.storyboard                    背景色とロゴの大きさだけ書き換える
  hosting/public/assets/{icon-192,icon-512,apple-touch-icon,favicon-48,og-default}.png  Web

日本語フォント（「何」と「なにきるカム」）が要る。見つからなければ環境変数 `ICON_FONT` に
.ttf / .ttc / .otf のパスを指定する（可変フォントなら太さ 900 / 700 を使う）。
"""
from __future__ import annotations

import json
import math
import os
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

APP_DIR = Path(__file__).resolve().parent.parent
RES = APP_DIR / "android" / "app" / "src" / "main" / "res"
BRANDING = APP_DIR / "assets" / "branding"
XCASSETS = APP_DIR / "ios" / "Runner" / "Assets.xcassets"
APPICONSET = XCASSETS / "AppIcon.appiconset"
LAUNCHIMAGE = XCASSETS / "LaunchImage.imageset"
STORYBOARD = APP_DIR / "ios" / "Runner" / "Base.lproj" / "LaunchScreen.storyboard"
WEB = APP_DIR / "hosting" / "public" / "assets"

SS = 4  # 描画は 4 倍で行い、縮小して滑らかにする
DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}

# ---- ブランド色（アプリの UI もこの配色に寄せる）----
JADE_TOP = (24, 134, 100)       # #188664 卓のグラデーション（上）
JADE = (13, 98, 74)             # #0D624A 主色。通知の強調色・スプラッシュの背景
JADE_BOTTOM = (6, 58, 45)       # #063A2D 卓のグラデーション（下）
JADE_GLOW = (60, 180, 135)      # #3CB487 左上の柔らかい光
IVORY = (252, 247, 234)         # #FCF7EA 牌の面（上）
IVORY_LOW = (240, 231, 210)     # #F0E7D2 牌の面（下）
IVORY_SIDE = (222, 208, 178)    # #DED0B2 牌の側面
TILE_BACK = (226, 160, 52)      # #E2A034 牌の背（山吹）
TILE_BACK_DARK = (176, 112, 28) # #B0701C
VERMILION = (230, 69, 44)       # #E6452C 朱（切る印）
VERMILION_LIGHT = (255, 112, 80)  # #FF7050 朱の明るい側（▼の上端）
GOLD = (230, 190, 98)           # #E6BE62 ファインダー
GOLD_LIGHT = (248, 222, 150)    # #F8DE96
INK = (28, 40, 36)              # #1C2824 「何」
SHADOW = (0, 18, 12)            # 影の色（半透明で重ねる）


def hex_of(c) -> str:
    return "#%02X%02X%02X" % c


# ---- 構図（構図座標: 構図の中心が (0,0)、一辺が 1）----
TILE_H = 0.515           # 牌の面の高さ
TILE_ASPECT = 0.76       # 面の幅 / 高さ
TILE_CY = 0.040          # 牌の面の中心
CURSOR_GAP = 0.181       # 牌の上端から▼の中心まで（牌の高さ比）
CURSOR_W, CURSOR_H = 0.298, 0.213  # ▼の幅・高さ（牌の高さ比）
GLYPH_H = 0.54           # 「何」の字面の高さ（牌の高さ比）
BRACKET_HX, BRACKET_HY = 0.335, 0.370  # L 字の角（中心線）の位置
BRACKET_ARM = 0.10
BRACKET_T = 0.042

FONT_CANDIDATES = [
    os.environ.get("ICON_FONT", ""),
    r"C:\Windows\Fonts\NotoSansJP-VF.ttf",
    r"C:\Windows\Fonts\YuGothB.ttc",
    r"C:\Windows\Fonts\meiryob.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Black.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
    "/System/Library/Fonts/ヒラギノ角ゴシック W8.ttc",
]


def find_font() -> str:
    for path in FONT_CANDIDATES:
        if path and Path(path).exists():
            return path
    sys.exit("日本語フォントが見つかりません。環境変数 ICON_FONT にフォントのパスを指定してください。")


FONT_PATH = find_font()


def load_font(size: float, weight: int) -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(FONT_PATH, max(1, int(round(size))))
    try:
        font.set_variation_by_axes([weight])  # 可変フォントのときだけ効く
    except (OSError, AttributeError, ValueError):
        pass
    return font


# ================================================================ 描画の土台
class Canvas:
    """[px] 四方（または [px]×[py]）の透明な画像を SS 倍で描く。構図の一辺を [unit]（px 幅に対する割合）、
    構図の中心を [center]（割合）に置く。"""

    def __init__(self, px: int, unit: float = 1.0, center=(0.5, 0.5), py: int | None = None):
        self.px, self.py = px, py or px
        self.w, self.h = self.px * SS, self.py * SS
        self.unit = unit * self.w
        self.cx, self.cy = center[0] * self.w, center[1] * self.h
        self.img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))

    def p(self, x, y):
        return (self.cx + x * self.unit, self.cy + y * self.unit)

    def s(self, v):
        return v * self.unit

    def box(self, x0, y0, x1, y1):
        return (*self.p(x0, y0), *self.p(x1, y1))

    def mask(self) -> Image.Image:
        return Image.new("L", (self.w, self.h), 0)

    def fill(self, mask: Image.Image, color, alpha: float = 1.0):
        layer = Image.new("RGBA", self.img.size, tuple(color) + (255,))
        if alpha < 1:
            mask = mask.point(lambda v: int(v * alpha))
        layer.putalpha(mask)
        self.img.alpha_composite(layer)

    def fill_gradient(self, mask: Image.Image, top, bottom, y0, y1):
        """[mask] の中を構図座標 y0→y1 の縦グラデーションで塗る。"""
        grad = vertical_gradient(self.w, self.h, [top, bottom], self.p(0, y0)[1], self.p(0, y1)[1])
        grad.putalpha(mask)
        self.img.alpha_composite(grad)

    def cut(self, mask: Image.Image):
        """描いたものから [mask] の部分を抜く。"""
        self.img.putalpha(ImageChops.subtract(self.img.getchannel("A"), mask))

    def result(self) -> Image.Image:
        return self.img.resize((self.px, self.py), Image.LANCZOS)


def vertical_gradient(w: int, h: int, stops, y0: float, y1: float) -> Image.Image:
    """縦グラデーション（stops を y0→y1 に等間隔で並べ、外側は端の色）。"""
    ys = np.clip((np.arange(h) - y0) / max(1.0, y1 - y0), 0, 1)
    stops = np.array(stops, dtype=float)
    pos = ys * (len(stops) - 1)
    i = np.minimum(pos.astype(int), len(stops) - 2)
    t = (pos - i)[:, None]
    col = stops[i] * (1 - t) + stops[i + 1] * t
    arr = np.repeat(col[:, None, :], w, axis=1).round().astype(np.uint8)
    img = Image.fromarray(arr, "RGB").convert("RGBA")
    return img


def background(w: int, h: int | None = None, glow=(0.32, 0.18), glow_r=0.62) -> Image.Image:
    """卓: ジェイドの縦グラデーション + 左上の柔らかい光 + 周辺の落ち込み（RGB）。
    glow と glow_r は短辺を 1 とした割合。"""
    h = h or w
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    t = (yy / max(1, h - 1))[..., None]
    top, mid, bot = (np.array(c, dtype=float) for c in (JADE_TOP, JADE, JADE_BOTTOM))
    c = np.where(t < 0.5, top + (mid - top) * (t / 0.5), mid + (bot - mid) * ((t - 0.5) / 0.5))
    s = min(w, h)
    d = np.hypot((xx - glow[0] * w) / s, (yy - glow[1] * h) / s)
    g = (np.clip(1 - d / glow_r, 0, 1) ** 2 * 0.55)[..., None]
    c = c + (np.array(JADE_GLOW, dtype=float) - c) * g
    v = np.hypot((xx - w / 2) / s, (yy - h / 2) / s)
    c = c * (1 - (np.clip(v - 0.45, 0, None) * 0.5)[..., None])
    img = Image.fromarray(np.clip(c, 0, 255).round().astype(np.uint8), "RGB")
    return img.filter(ImageFilter.GaussianBlur(max(1, s / 400)))


def rounded_rect_mask(cv: Canvas, rect, radius) -> Image.Image:
    m = cv.mask()
    ImageDraw.Draw(m).rounded_rectangle(cv.box(*rect), cv.s(radius), fill=255)
    return m


def circle(cv: Canvas, x, y, r) -> Image.Image:
    m = cv.mask()
    ImageDraw.Draw(m).ellipse(cv.box(x - r, y - r, x + r, y + r), fill=255)
    return m


# ================================================================ 部品
def soft_shadow(cv: Canvas, mask: Image.Image, dy: float, blur: float, alpha: float):
    m = ImageChops.offset(mask, 0, int(round(cv.s(dy)))).filter(ImageFilter.GaussianBlur(cv.s(blur)))
    cv.fill(m, SHADOW, alpha)


def tile(cv: Canvas, cx, cy, h, solid=False):
    """牌（正面やや上から）。面の上に、アイボリーの側面と山吹の背の層が下に少し見える。
    solid=True は白一色のシルエット（背の層まで含む）。"""
    w = h * TILE_ASPECT
    r = h * 0.13
    x0, y0, x1, y1 = cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2
    side_d, back_d = h * 0.055, h * 0.125
    if solid:
        cv.fill(rounded_rect_mask(cv, (x0, y0, x1, y1 + back_d), r), (255, 255, 255))
        return
    full = rounded_rect_mask(cv, (x0, y0, x1, y1 + back_d), r)
    soft_shadow(cv, full, h * 0.05, h * 0.07, 0.55)
    soft_shadow(cv, full, h * 0.015, h * 0.015, 0.35)
    cv.fill_gradient(rounded_rect_mask(cv, (x0, y0 + back_d, x1, y1 + back_d), r),
                     TILE_BACK, TILE_BACK_DARK, y1 - h * 0.2, y1 + back_d)
    cv.fill(rounded_rect_mask(cv, (x0, y0 + side_d, x1, y1 + side_d), r), IVORY_SIDE)
    face = rounded_rect_mask(cv, (x0, y0, x1, y1), r)
    cv.fill_gradient(face, IVORY, IVORY_LOW, y0, y1)
    # 面の上縁の細い光
    inner = rounded_rect_mask(cv, (x0 + h * 0.012, y0 + h * 0.018, x1 - h * 0.012, y1), r * 0.9)
    cv.fill(ImageChops.subtract(face, inner), (255, 255, 255), 0.9)


def brackets(cv: Canvas, hx, hy, arm, thick, solid=False):
    """四隅の L 字（ファインダー）。(±hx, ±hy) が角の中心線、arm が腕の長さ。端は丸める。"""
    m = cv.mask()
    d = ImageDraw.Draw(m)
    t = cv.s(thick)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * hx, sy * hy
            pts = [cv.p(cx - sx * arm, cy), cv.p(cx, cy), cv.p(cx, cy - sy * arm)]
            d.line(pts, fill=255, width=max(1, int(round(t))), joint="curve")
            for q in pts:
                d.ellipse((q[0] - t / 2, q[1] - t / 2, q[0] + t / 2, q[1] + t / 2), fill=255)
    if solid:
        cv.fill(m, (255, 255, 255))
        return
    soft_shadow(cv, m, thick * 0.35, thick * 0.5, 0.35)
    cv.fill_gradient(m, GOLD_LIGHT, GOLD, -hy, hy)


def glyph_mask(cv: Canvas, text, cx, cy, target_h, weight) -> Image.Image:
    """字面（インクの外接矩形）の高さが [target_h]、中心が (cx, cy) になる文字のマスク。"""
    tmp = ImageDraw.Draw(Image.new("L", (1, 1)))
    left, top, right, bottom = tmp.textbbox((0, 0), text, font=load_font(1000, weight), anchor="ls")
    font = load_font(1000 * cv.s(target_h) / (bottom - top), weight)
    left, top, right, bottom = tmp.textbbox((0, 0), text, font=font, anchor="ls")
    px, py = cv.p(cx, cy)
    m = cv.mask()
    ImageDraw.Draw(m).text((px - (left + right) / 2, py - (top + bottom) / 2), text, font=font, fill=255, anchor="ls")
    return m


def cursor(cv: Canvas, cx, cy, w, h, solid=False):
    """朱の▼（切る牌のカーソル）。角だけ少し丸める。"""
    m = cv.mask()
    ImageDraw.Draw(m).polygon([cv.p(cx - w / 2, cy - h / 2), cv.p(cx + w / 2, cy - h / 2), cv.p(cx, cy + h / 2)], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(cv.s(w * 0.05))).point(lambda v: 255 if v > 90 else 0)
    if solid:
        cv.fill(m, (255, 255, 255))
        return
    soft_shadow(cv, m, 0.008, 0.01, 0.35)
    cv.fill_gradient(m, VERMILION_LIGHT, VERMILION, cy - h / 2, cy + h / 2)


def mark(cv: Canvas, mode: str = "color", with_brackets: bool = True):
    """意匠の本体（背景なし）。

    mode:
      "color"  本来の色
      "mono"   白一色、「何」を抜く（テーマアイコン）
      "notify" 白一色、「何」は抜かない。小さく表示しても潰れないよう L 字を太く（通知の小アイコン）
    """
    h = TILE_H
    top = TILE_CY - h / 2
    cy_cur = top - CURSOR_GAP * h
    cw, ch = CURSOR_W * h, CURSOR_H * h
    if mode == "notify":
        brackets(cv, 0.375, 0.375, 0.20, 0.085, solid=True)
        # 24dp（mdpi で 24px）でも▼と牌がくっつかないよう、間を 1.5px ほど空ける
        nh, ncy = 0.40, 0.10
        tile(cv, 0, ncy, nh, solid=True)
        cursor(cv, 0, ncy - nh / 2 - 0.135, 0.26, 0.15, solid=True)
        return
    solid = mode == "mono"
    if with_brackets:
        brackets(cv, BRACKET_HX, BRACKET_HY, BRACKET_ARM, BRACKET_T, solid=solid)
    tile(cv, 0, TILE_CY, h, solid=solid)
    g = glyph_mask(cv, "何", 0, TILE_CY - 0.005, GLYPH_H * h, 900)
    if solid:
        cv.cut(g)
    else:
        cv.fill(g, INK)
    cursor(cv, 0, cy_cur, cw, ch, solid=solid)


# ================================================================ 書き出す画像
def master(px: int = 1024) -> Image.Image:
    """全面を塗った正方形（アルファなし）。丸め・影は OS 側が付ける。"""
    img = background(px).convert("RGBA")
    cv = Canvas(px)
    mark(cv)
    img.alpha_composite(cv.result())
    return img.convert("RGB")


_EXTENT: dict[str, float] = {}


def extent(mode: str = "mono") -> float:
    """構図の中心から描いた画素のいちばん遠い点までの距離（構図座標）。"""
    if mode not in _EXTENT:
        cv = Canvas(512)
        mark(cv, mode)
        a = np.array(cv.result().getchannel("A")) > 8
        ys, xs = np.nonzero(a)
        _EXTENT[mode] = float(np.max(np.hypot(xs + 0.5 - 256, ys + 0.5 - 256))) / 512
    return _EXTENT[mode]


def adaptive_unit() -> float:
    """108dp の前景で、構図全体が中央の直径 66dp の safe zone（半径 33dp）に収まる縮尺。"""
    return (32.5 / 108) / extent("mono")


def adaptive_layer(px: int, mode: str) -> Image.Image:
    cv = Canvas(px, unit=adaptive_unit())
    mark(cv, mode)
    return cv.result()


def notify_icon(px: int) -> Image.Image:
    """24dp の通知アイコン（白一色の透過）。"""
    cv = Canvas(px)
    mark(cv, "notify")
    return cv.result()


def logo(px_per_unit: float) -> Image.Image:
    """スプラッシュの中央に置く意匠（背景なし、余白を切り詰めた矩形）。構図の一辺を [px_per_unit] px で描く。"""
    side = int(math.ceil(px_per_unit))
    cv = Canvas(side)
    mark(cv)
    img = cv.result()
    # 中心を保ったまま、描いた範囲（影を含む）まで左右・上下を対称に切り詰める
    a = np.array(img.getchannel("A")) > 2
    ys, xs = np.nonzero(a)
    c = side / 2
    dx = int(math.ceil(max(c - xs.min(), xs.max() + 1 - c)))
    dy = int(math.ceil(max(c - ys.min(), ys.max() + 1 - c)))
    return img.crop((int(c - dx), int(c - dy), int(c + dx), int(c + dy)))


def rounded(img: Image.Image, radius_ratio: float = 0.2) -> Image.Image:
    """角を丸めて外を透明にする（旧形式の ic_launcher.png と Web のアイコン）。"""
    size = img.width
    big = size * SS
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, big - 1, big - 1), radius_ratio * big, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask.resize((size, size), Image.LANCZOS))
    return out


def banner(w: int, h: int, subtitle: str) -> Image.Image:
    """横長の画像（フィーチャーグラフィック・OGP）。左に意匠、右にアプリ名と 1 行の説明。
    文字は右の余白に収まる大きさに自動で合わせ、文字の塊を上下中央に置く。"""
    k = 2
    W, H = w * k, h * k
    img = background(W, H, glow=(0.2, 0.1), glow_r=0.9).convert("RGBA")
    margin = 0.09 * H
    mark_px = int(H * 0.98)                 # 構図の一辺（L 字の外形はその約 0.75）
    mark_cx = margin + mark_px * 0.39
    cv = Canvas(mark_px)
    mark(cv)
    m = cv.result()
    img.alpha_composite(m, (int(mark_cx - m.width / 2), int(H / 2 - m.height / 2)))
    d = ImageDraw.Draw(img)
    x = mark_cx + mark_px * 0.39 + 0.07 * H
    avail = W - margin - x

    def fit(text: str, size: float, weight: int) -> ImageFont.FreeTypeFont:
        font = load_font(size, weight)
        width = d.textlength(text, font=font)
        return font if width <= avail else load_font(size * avail / width, weight)

    title = fit("なにきるカム", 0.19 * H, 800)
    sub = fit(subtitle, 0.068 * H, 600)
    tl, tt, tr, tb = d.textbbox((0, 0), "なにきるカム", font=title, anchor="ls")
    sl, st, sr, sb = d.textbbox((0, 0), subtitle, font=sub, anchor="ls")
    rule_gap, rule_h, sub_gap = 0.20 * (tb - tt), 0.075 * title.size, 0.30 * (tb - tt)
    block = (tb - tt) + rule_gap + rule_h + sub_gap + (sb - st)
    y = (H - block) / 2
    title_base = y - tt
    d.text((x, title_base), "なにきるカム", font=title, fill=IVORY + (255,), anchor="ls")
    ry = y + (tb - tt) + rule_gap
    d.rounded_rectangle((x + 0.04 * title.size, ry, x + 1.1 * title.size, ry + rule_h), rule_h / 2, fill=GOLD + (255,))
    d.text((x, ry + rule_h + sub_gap - st), subtitle, font=sub, fill=IVORY + (235,), anchor="ls")
    return img.resize((w, h), Image.LANCZOS).convert("RGB")


SUBTITLE = "カメラをかざすと、切る牌がわかる。"


# ================================================================ 書き出し
def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    print("wrote", path.relative_to(APP_DIR))


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")
    print("wrote", path.relative_to(APP_DIR))


SPLASH_LOGO_DP = 200  # スプラッシュのロゴの構図の一辺（dp / pt）。描かれる幅は約 150、高さは約 170


def splash_v31_styles(parent: str, comment: str) -> str:
    return f'''<?xml version="1.0" encoding="utf-8"?>
<!-- tool/make_icons.py が生成。Android 12 以降のスプラッシュ（システムが描く）。{comment}
     values-night より API レベルの修飾子は優先度が低いので、values-night-v31 にも同じものを置く。
     アイコンはアダプティブアイコンの前景（意匠は 108dp の中央 66dp に収めてある）。 -->
<resources>
    <style name="LaunchTheme" parent="{parent}">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:windowSplashScreenBackground">@color/splash_background</item>
        <item name="android:windowSplashScreenAnimatedIcon">@mipmap/ic_launcher_foreground</item>
    </style>
</resources>
'''


LAUNCH_BACKGROUND = '''<?xml version="1.0" encoding="utf-8"?>
<!-- tool/make_icons.py が生成。Android 11 以下のスプラッシュ: ブランド色の地の中央にロゴ。 -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/splash_background" />
    <item>
        <bitmap
            android:gravity="center"
            android:src="@drawable/launch_logo" />
    </item>
</layer-list>
'''


def update_storyboard(logo_w_pt: int, logo_h_pt: int) -> None:
    """LaunchScreen.storyboard の背景色とロゴの大きさだけ書き換える（他はそのまま）。"""
    text = STORYBOARD.read_text(encoding="utf-8")
    r, g, b = (v / 255 for v in JADE)
    color = (f'<color key="backgroundColor" red="{r:.4f}" green="{g:.4f}" blue="{b:.4f}" alpha="1" '
             f'colorSpace="custom" customColorSpace="sRGB"/>')
    text, n1 = re.subn(r'<color key="backgroundColor"[^>]*/>', color, text, count=1)
    text, n2 = re.subn(r'<image name="LaunchImage" width="[^"]*" height="[^"]*"/>',
                       f'<image name="LaunchImage" width="{logo_w_pt}" height="{logo_h_pt}"/>', text, count=1)
    if n1 != 1 or n2 != 1:
        sys.exit("LaunchScreen.storyboard の backgroundColor / LaunchImage が見つかりません。")
    STORYBOARD.write_text(text, encoding="utf-8", newline="\n")
    print("wrote", STORYBOARD.relative_to(APP_DIR))


def main() -> None:
    print("font:", FONT_PATH)

    # --- 原画とストア用 ---
    m = master(1024)
    save(m, BRANDING / "icon_1024.png")
    # Google Play は「32 ビット PNG（アルファあり）」を求める。全面不透明のアルファを付ける。
    save(m.resize((512, 512), Image.LANCZOS).convert("RGBA"), BRANDING / "play_store_icon_512.png")
    save(banner(1024, 500, SUBTITLE),
         BRANDING / "feature_graphic_1024x500.png")

    # --- Android: 旧形式（角丸）、アダプティブの前景・モノクロ、通知、スプラッシュのロゴ ---
    for name, scale in DENSITIES.items():
        legacy = int(round(48 * scale))
        save(rounded(m.resize((legacy * 2, legacy * 2), Image.LANCZOS)).resize((legacy, legacy), Image.LANCZOS),
             RES / f"mipmap-{name}" / "ic_launcher.png")
        canvas = int(round(108 * scale))
        save(adaptive_layer(canvas, "color"), RES / f"mipmap-{name}" / "ic_launcher_foreground.png")
        mono = adaptive_layer(canvas, "mono")
        black = Image.new("RGBA", mono.size, (0, 0, 0, 0))
        black.putalpha(mono.getchannel("A"))
        save(black, RES / f"mipmap-{name}" / "ic_launcher_monochrome.png")
        save(notify_icon(int(round(24 * scale))), RES / f"drawable-{name}" / "ic_stat_notify.png")
        save(logo(SPLASH_LOGO_DP * scale), RES / f"drawable-{name}" / "launch_logo.png")

    write_text(RES / "mipmap-anydpi-v26" / "ic_launcher.xml",
               '<?xml version="1.0" encoding="utf-8"?>\n'
               '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
               '    <background android:drawable="@drawable/ic_launcher_gradient"/>\n'
               '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
               '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
               '</adaptive-icon>\n')
    write_text(RES / "drawable" / "ic_launcher_gradient.xml",
               '<?xml version="1.0" encoding="utf-8"?>\n'
               "<!-- tool/make_icons.py が生成。アダプティブアイコンの背景（卓のジェイド、上から下へ）。 -->\n"
               '<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">\n'
               f'    <gradient android:type="linear" android:angle="270"\n'
               f'        android:startColor="{hex_of(JADE_TOP)}"\n'
               f'        android:centerColor="{hex_of(JADE)}"\n'
               f'        android:endColor="{hex_of(JADE_BOTTOM)}" />\n'
               "</shape>\n")
    write_text(RES / "values" / "ic_launcher_background.xml",
               '<?xml version="1.0" encoding="utf-8"?>\n'
               "<!-- tool/make_icons.py が生成。 -->\n"
               "<resources>\n"
               "    <!-- ブランドの主色（ジェイド）。FCM の通知の色（AndroidManifest の default_notification_color）に使う。\n"
               "         アダプティブアイコンの背景は drawable/ic_launcher_gradient.xml のグラデーション。 -->\n"
               f'    <color name="ic_launcher_background">{hex_of(JADE)}</color>\n'
               "    <!-- スプラッシュの背景（launch_background.xml と values-v31 の windowSplashScreenBackground）。 -->\n"
               f'    <color name="splash_background">{hex_of(JADE)}</color>\n'
               "</resources>\n")
    for d in ("drawable", "drawable-v21"):
        write_text(RES / d / "launch_background.xml", LAUNCH_BACKGROUND)
    write_text(RES / "values-v31" / "styles.xml",
               splash_v31_styles("@android:style/Theme.Light.NoTitleBar", "端末がライトモードのとき。"))
    write_text(RES / "values-night-v31" / "styles.xml",
               splash_v31_styles("@android:style/Theme.Black.NoTitleBar", "端末がダークモードのとき。"))

    # --- iOS: アイコン 1024 の 1 枚（Xcode 14 以降のシングルサイズ）とスプラッシュ ---
    APPICONSET.mkdir(parents=True, exist_ok=True)
    for old in APPICONSET.glob("Icon-App-*.png"):
        old.unlink()
    save(m, APPICONSET / "Icon-App-1024x1024@1x.png")
    contents = {
        "images": [{"filename": "Icon-App-1024x1024@1x.png", "idiom": "universal", "platform": "ios",
                    "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }
    write_text(APPICONSET / "Contents.json", json.dumps(contents, indent=2) + "\n")
    logo3 = logo(SPLASH_LOGO_DP * 3)
    w_pt, h_pt = int(round(logo3.width / 3)), int(round(logo3.height / 3))
    for suffix, scale in (("", 1), ("@2x", 2), ("@3x", 3)):
        img = logo3 if scale == 3 else logo(SPLASH_LOGO_DP * scale)
        save(img.resize((w_pt * scale, h_pt * scale), Image.LANCZOS), LAUNCHIMAGE / f"LaunchImage{suffix}.png")
    update_storyboard(w_pt, h_pt)

    # --- Web（Hosting）---
    for size, name in ((512, "icon-512.png"), (192, "icon-192.png"), (48, "favicon-48.png")):
        save(rounded(m.resize((size, size), Image.LANCZOS)), WEB / name)
    save(m.resize((180, 180), Image.LANCZOS), WEB / "apple-touch-icon.png")  # iOS が自分で角を丸める
    save(banner(1200, 630, SUBTITLE),
         WEB / "og-default.png")


if __name__ == "__main__":
    main()
