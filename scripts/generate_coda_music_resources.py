#!/usr/bin/env python3
"""Replace unlicensed upstream mode artwork with original vector-derived icons."""
from pathlib import Path
import hashlib, io
import cairosvg
from PIL import Image
root=Path(__file__).resolve().parents[1]
icons=root/'Packages/CodaMusic/Sources/Coda/Features/Home/QishuiModeIcons'
# Retain each upstream lookup key so no UI/API mode mapping is lost.
for png in sorted(icons.glob('*.png')):
    name=png.stem
    seed=hashlib.sha256(name.encode()).digest()
    # Original equalizer mark: per-resource rhythm varies deterministically;
    # no upstream artwork, fonts, logos, or copied icon paths are used.
    heights=[14 + (seed[i] % 47) for i in range(7)]
    gap=7
    x0=64-(6*gap)//2
    bars=''.join(f'<path d="M{x0+i*gap} {64-h/2:.1f}v{h:.1f}"/>' for i,h in enumerate(heights))
    # A broken circular orbit distinguishes scene modes while remaining
    # tintable by the existing SwiftUI template rendering mode.
    start=seed[7] % 75 + 15
    end=start+210
    svg=f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" fill="none" stroke="#111" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"><path d="M47 16a49 49 0 0 1 50 20M111 55a49 49 0 0 1-29 53M66 113a49 49 0 0 1-48-29M15 66a49 49 0 0 1 20-43"/>{bars}</svg>'''
    (icons/f'{name}.svg').write_text(svg+'\n')
    data=cairosvg.svg2png(bytestring=svg.encode(),output_width=256,output_height=256)
    img=Image.open(io.BytesIO(data)).convert('RGBA')
    img.save(png,format='PNG',optimize=True)
# Preserve official Coda iOS imagesets used as Image("…") in CodaCore;
# omit only the standalone app icon/accent so Readcc keeps its own brand.
up=root/'Packages/CodaMusic/ios/CodaIOS/Assets.xcassets'
out=root/'Resources/CodaMusicAssets.xcassets'
out.mkdir(parents=True,exist_ok=True)
import shutil
shutil.copy2(up/'Contents.json',out/'Contents.json')
for item in sorted(up.iterdir()):
    if item.name in {'AppIcon.appiconset','AccentColor.colorset','Contents.json'}:
        continue
    dest=out/item.name
    if item.is_dir(): shutil.copytree(item,dest,dirs_exist_ok=True)
    elif item.is_file(): shutil.copy2(item,dest)
# The official iOS app bundled this privacy manifest in the host app target.
shutil.copy2(root/'Packages/CodaMusic/Sources/Coda/Resources/PrivacyInfo.xcprivacy',root/'Resources/PrivacyInfo.xcprivacy')
print(f'Generated original tintable artwork for {len(list(icons.glob("*.png")))} preserved PNG resource names; copied Coda iOS imagesets, excluding app icon/accent; bundled privacy manifest.')
