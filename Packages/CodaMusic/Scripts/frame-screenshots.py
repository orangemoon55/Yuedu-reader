#!/usr/bin/env python3
"""统一的截图加框脚本：iPhone / iPad 嵌入真机外壳，Mac 窗口截图加 MacBook 外壳。

用法：
    python3 Scripts/frame-screenshots.py [选项] <截图.png> ...

按截图宽高比自动识别设备（可用 --device 指定）：
    iPhone  竖屏约 0.46 / 横屏约 2.17
    iPad    约 4:3（横屏）
    Mac     其余（窗口截图）
输出到 docs/assets/screenshots/<ios|ipad|mac>/<名称>.png，只保留加框后的版本。
名称默认取源文件名（Simulator 截图请用 --name 指定），已存在时覆盖。

选项：
    --device iphone|ipad|mac   跳过自动识别
    --name NAME                输出文件名（不含 .png），只能配合单张截图使用
    --rotate                   先逆时针旋转 90°（模拟器横屏截图存成竖屏时用）
    --delete-source            加框成功后把源截图移到废纸篓
    --frame-only               只生成屏幕透明的外壳（无需截图参数），供落地页把录屏垫在下面：
                               默认 MacBook（屏幕比例按 Mac 窗口截图 2940×1836），输出到
                               site/assets/screenshots/mac/frame.png；配合 --device iphone
                               输出竖屏 iPhone 外壳到 site/assets/screenshots/ios/frame.png

外壳之外为透明背景。需要 Pillow。
"""
import argparse
import shutil
import sys
import time
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
FRAMES = Path(__file__).resolve().parent / "device-frames"
OUT_ROOT = ROOT / "docs/assets/screenshots"
HOLLOW_FRAME_OUT = {
    "mac": ROOT / "site/assets/screenshots/mac/frame.png",
    "iphone": ROOT / "site/assets/screenshots/ios/frame.png",
}
PLATFORM_DIRS = {"iphone": "ios", "ipad": "ipad", "mac": "mac"}
MAC_WINDOW_SIZE = (2940, 1836)  # Mac 窗口截图尺寸，决定空心外壳的屏幕比例

# ---------------------------------------------------------------- iPhone / iPad

SS = 4  # 圆角遮罩按 4 倍绘制再缩小

# 屏幕区域 (左, 上, 右, 下) 与屏幕圆角，单位为外壳图像素
SPECS = {
    "iphone": dict(frame="iphone.png", rect=(45, 29, 706, 1463), radius=97),
    "ipad": dict(frame="ipad.png", rect=(41, 41, 1026, 779), radius=12),
}


def rounded_mask(size, radius):
    big = Image.new("L", (size[0] * SS, size[1] * SS), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, big.width - 1, big.height - 1), radius * SS, fill=255)
    return big.resize(size, Image.LANCZOS)


def transparent_background(img, rect, radius):
    """外壳图外侧的白色背景抠成透明，并让边缘平滑。

    1. 屏幕区域之外的纯白连通块：碰到图片边缘或面积很小（按钮缝隙）的算背景；
    2. 背景边界 2px 内按亮度换算半透明，并还原被白色污染的边缘颜色，避免锯齿和白边。
    """
    w, h = img.size
    px = img.load()
    l, t, r, b = rect
    white = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            if l <= x < r and t <= y < b:
                # 屏幕圆角之外的四角属于外壳/背景，不能排除
                cx = l + radius if x < l + radius else (r - 1 - radius if x > r - 1 - radius else x)
                cy = t + radius if y < t + radius else (b - 1 - radius if y > b - 1 - radius else y)
                if (x - cx) ** 2 + (y - cy) ** 2 <= (radius + 1) ** 2:
                    continue
            p = px[x, y]
            if p[0] >= 250 and p[1] >= 250 and p[2] >= 250:
                white[y * w + x] = 1
    bg = bytearray(w * h)
    seen = bytearray(w * h)
    for start in range(w * h):
        if not white[start] or seen[start]:
            continue
        comp, stack, touches = [], [start], False
        seen[start] = 1
        while stack:
            i = stack.pop()
            comp.append(i)
            x, y = i % w, i // w
            if x == 0 or y == 0 or x == w - 1 or y == h - 1:
                touches = True
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    j = ny * w + nx
                    if white[j] and not seen[j]:
                        seen[j] = 1
                        stack.append(j)
        if touches or len(comp) < 300:
            for i in comp:
                bg[i] = 1
    # 背景像素透明；背景外圈 2px 内的非背景像素按亮度算半透明
    out = img.copy()
    op = out.load()
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if bg[i]:
                op[x, y] = (0, 0, 0, 0)
                continue
            near = False
            for dy in range(-2, 3):
                for dx in range(-2, 3):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and bg[ny * w + nx]:
                        near = True
                        break
                if near:
                    break
            if not near:
                continue
            c = px[x, y]
            lum = (c[0] + c[1] + c[2]) / 3
            if lum >= 250:
                op[x, y] = (0, 0, 0, 0)
                continue
            a = min(1.0, (255 - lum) / (255 - 40))
            # 假设外轮廓本色为深灰，从“与白色混合”的像素里还原
            f = tuple(max(0, min(255, round((v - 255 * (1 - a)) / a))) for v in c[:3])
            op[x, y] = (*f, round(a * 255))
    return out


_FRAME_CACHE = {}


def load_frame(device):
    if device not in _FRAME_CACHE:
        spec = SPECS[device]
        img = Image.open(FRAMES / spec["frame"]).convert("RGBA")
        _FRAME_CACHE[device] = transparent_background(img, spec["rect"], spec["radius"])
    return _FRAME_CACHE[device]


def frame_device(device, shot):
    spec = SPECS[device]
    base = load_frame(device)
    rect, radius = spec["rect"], spec["radius"]
    rotate = device == "iphone" and shot.width > shot.height
    if rotate:
        # 外壳逆时针转 90°，屏幕矩形同步换算
        w, h = base.size
        base = base.rotate(90, expand=True)
        l, t, r, b = rect
        rect = (t, w - r, b, w - l)
    size = (rect[2] - rect[0], rect[3] - rect[1])
    # 直接贴在外壳图的屏幕位置；圆角与外壳内角一致，四角保留外壳原有的黑边
    scaled = shot.resize(size, Image.LANCZOS)
    mask = rounded_mask(size, radius)
    alpha = Image.composite(scaled.getchannel("A"), Image.new("L", size, 0), mask)
    scaled.putalpha(alpha)
    out = base.copy()
    out.alpha_composite(scaled, (rect[0], rect[1]))
    return out



def hollow_device(device):
    """屏幕区域挖空（圆角与外壳内角一致）的外壳，录屏垫在下面即可。"""
    spec = SPECS[device]
    out = load_frame(device).copy()
    l, t, r, b = spec["rect"]
    size = (r - l, b - t)
    hole = rounded_mask(size, spec["radius"])
    alpha = out.getchannel("A")
    region = alpha.crop((l, t, r, b))
    region = Image.composite(Image.new("L", size, 0), region, hole)
    alpha.paste(region, (l, t))
    out.putalpha(alpha)
    print(f"screen rect: x={l} y={t} w={size[0]} h={size[1]} radius={spec['radius']}"
          f" canvas={out.width}x{out.height}")
    return out


# ---------------------------------------------------------------- Mac

MAC_SS = 2  # 先按 2 倍绘制再缩小，让圆角边缘更平滑

# 以下尺寸为最终输出像素
SCREEN_W = 1440
BEZEL_SIDE = 20
BEZEL_TOP = 28
BEZEL_BOTTOM = 30
LID_RADIUS = 34
SCREEN_RADIUS = 16
BASE_EXTRA = 0.075  # 底座左右各比屏幕外沿多出的比例
BASE_H = 22
BASE_TOP_R = 8  # 底座两端上沿圆角
BASE_BOTTOM_R = 14  # 底座两端下沿圆角
BASE_TAPER = 10  # 底边比顶边每侧内收的像素
LIP_W = 230
LIP_H = 8


def vertical_gradient(size, top, bottom):
    w, h = size
    grad = Image.new("RGBA", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        grad.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return grad.resize((w, h))


def base_outline(w, h, rt, rb, taper, steps=40):
    """底座正面轮廓：两端侧面是一条连续弧线，上沿小圆角，下沿大圆角并向内收。

    每端由两段二次贝塞尔组成，在最外侧点处切线都竖直，所以衔接平滑。
    """
    bulge_y = h * 0.35  # 最外侧点的高度

    def quad(p0, c, p1):
        out = []
        for i in range(steps + 1):
            t = i / steps
            u = 1 - t
            out.append((u * u * p0[0] + 2 * u * t * c[0] + t * t * p1[0],
                        u * u * p0[1] + 2 * u * t * c[1] + t * t * p1[1]))
        return out

    # 右端：顶 -> 最外侧 -> 底
    right = quad((w - rt, 0), (w, 0), (w, bulge_y)) + quad(
        (w, bulge_y), (w, h), (w - taper - rb, h)
    )
    # 左端由右端镜像得到，并按逆向顺序接上
    left = [(w - x, y) for x, y in reversed(right)]
    return right + left


def frame_mac(shot, hollow=False):
    """hollow=True 时屏幕区域留空（透明），供网页把视频垫在外壳下面。"""
    s = MAC_SS
    screen_w = SCREEN_W * s
    screen_h = round(shot.height * screen_w / shot.width)

    lid_w = screen_w + 2 * BEZEL_SIDE * s
    lid_h = screen_h + (BEZEL_TOP + BEZEL_BOTTOM) * s
    base_w = round(lid_w * (1 + 2 * BASE_EXTRA))
    base_h = BASE_H * s
    canvas_w = base_w
    canvas_h = lid_h + base_h
    lid_x = (canvas_w - lid_w) // 2

    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)

    # 屏幕外壳：外圈铝边 + 黑色边框
    d.rounded_rectangle(
        (lid_x, 0, lid_x + lid_w - 1, lid_h + LID_RADIUS * s),
        radius=LID_RADIUS * s,
        fill=(170, 172, 177, 255),
    )
    edge = 3 * s
    d.rounded_rectangle(
        (lid_x + edge, edge, lid_x + lid_w - 1 - edge, lid_h + LID_RADIUS * s),
        radius=(LID_RADIUS - 3) * s,
        fill=(12, 12, 14, 255),
    )

    # 摄像头
    cam_r = 4 * s
    cx, cy = canvas_w // 2, (BEZEL_TOP * s) // 2
    d.ellipse((cx - cam_r, cy - cam_r, cx + cam_r, cy + cam_r), fill=(32, 34, 40, 255))
    d.ellipse((cx - cam_r // 2, cy - cam_r // 2, cx + cam_r // 2, cy + cam_r // 2), fill=(52, 60, 80, 255))

    # 屏幕内容：截图本身带透明圆角，先铺黑底
    sx, sy = lid_x + BEZEL_SIDE * s, BEZEL_TOP * s
    screen_mask = Image.new("L", (screen_w, screen_h), 0)
    ImageDraw.Draw(screen_mask).rounded_rectangle(
        (0, 0, screen_w - 1, screen_h + SCREEN_RADIUS * s), radius=SCREEN_RADIUS * s, fill=255
    )
    screen = Image.new("RGBA", (screen_w, screen_h), (0, 0, 0, 255))
    screen.alpha_composite(shot.resize((screen_w, screen_h), Image.LANCZOS))
    canvas.paste(screen, (sx, sy), screen_mask)

    # 底座：正面看是一块两端圆润、底边略内收的铝合金薄板
    body_y = lid_h
    body_h = canvas_h - body_y
    body = vertical_gradient((base_w, body_h), (236, 237, 240, 255), (156, 158, 164, 255))
    # 顶面一道亮边，表现底座上表面
    ImageDraw.Draw(body).rectangle((0, 0, base_w, 2 * s), fill=(250, 250, 252, 255))
    # 下沿一道暗边，表现底部收进去的弧面
    edge_h = 5 * s
    body.alpha_composite(
        vertical_gradient((base_w, edge_h), (120, 122, 128, 0), (98, 100, 106, 255)),
        (0, body_h - edge_h),
    )
    body_mask = Image.new("L", (base_w, body_h), 0)
    ImageDraw.Draw(body_mask).polygon(
        base_outline(base_w, body_h, BASE_TOP_R * s, BASE_BOTTOM_R * s, BASE_TAPER * s), fill=255
    )
    canvas.paste(body, (0, body_y), body_mask)

    # 开盖凹槽
    lip_w, lip_h = LIP_W * s, LIP_H * s
    lx = (canvas_w - lip_w) // 2
    lip = vertical_gradient((lip_w, lip_h), (150, 152, 158, 255), (210, 211, 215, 255))
    lip_mask = Image.new("L", (lip_w, lip_h), 0)
    ImageDraw.Draw(lip_mask).rounded_rectangle(
        (0, -lip_h, lip_w - 1, lip_h - 1), radius=lip_h, fill=255
    )
    canvas.paste(lip, (lx, body_y), lip_mask)

    if hollow:
        canvas.paste((0, 0, 0, 0), (sx, sy, sx + screen_w, sy + screen_h), screen_mask)

    out = canvas.resize((canvas_w // s, canvas_h // s), Image.LANCZOS)
    if hollow:
        # 屏幕区域在输出图中的位置，网页按百分比定位视频
        print(f"screen rect: x={sx // s} y={sy // s} w={screen_w // s} h={screen_h // s}"
              f" canvas={out.width}x{out.height}")
    return out

# ---------------------------------------------------------------- 入口


def detect_device(shot):
    ratio = shot.width / shot.height
    if 0.42 <= ratio <= 0.5 or 2.0 <= ratio <= 2.35:
        return "iphone"
    if 1.25 <= ratio <= 1.45 or 0.69 <= ratio <= 0.8:
        return "ipad"
    return "mac"


def move_to_trash(path):
    trash = Path.home() / ".Trash"
    dest = trash / path.name
    if dest.exists():
        dest = trash / f"{path.stem} {time.strftime('%H%M%S')}{path.suffix}"
    shutil.move(str(path), dest)


def main(argv):
    ap = argparse.ArgumentParser(description="截图加框", usage=__doc__)
    ap.add_argument("files", nargs="*", type=Path)
    ap.add_argument("--device", choices=sorted(PLATFORM_DIRS))
    ap.add_argument("--name")
    ap.add_argument("--rotate", action="store_true")
    ap.add_argument("--delete-source", action="store_true")
    ap.add_argument("--frame-only", action="store_true")
    args = ap.parse_args(argv)
    if args.frame_only:
        device = args.device or "mac"
        if device not in HOLLOW_FRAME_OUT:
            ap.error(f"--frame-only 不支持 {device}")
        dest = HOLLOW_FRAME_OUT[device]
        dest.parent.mkdir(parents=True, exist_ok=True)
        if device == "mac":
            blank = Image.new("RGBA", MAC_WINDOW_SIZE, (0, 0, 0, 0))
            out = frame_mac(blank, hollow=True)
        else:
            out = hollow_device(device)
        out.save(dest, optimize=True)
        print(dest.relative_to(ROOT))
        return 0
    if not args.files:
        ap.error("请指定截图")
    if args.name and len(args.files) != 1:
        ap.error("--name 只能配合单张截图使用")

    for src in args.files:
        shot = Image.open(src).convert("RGBA")
        if args.rotate:
            shot = shot.rotate(90, expand=True)
        device = args.device or detect_device(shot)
        if device == "ipad" and shot.width < shot.height:
            sys.exit(f"{src}: iPad 外壳只有横屏，竖向存储的横屏截图请加 --rotate")
        out = frame_mac(shot) if device == "mac" else frame_device(device, shot)
        dest = OUT_ROOT / PLATFORM_DIRS[device] / f"{args.name or src.stem}.png"
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.resolve() == src.resolve():
            sys.exit(f"{src}: 输出会覆盖源文件，请用 --name 换个名字")
        out.save(dest, optimize=True)
        print(f"{device:6s} {dest.relative_to(ROOT)}")
        if args.delete_source:
            move_to_trash(src)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
