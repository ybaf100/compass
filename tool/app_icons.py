"""Apply/verify committed passcom icons; regeneration alone requires Pillow."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct

ROOT = Path(__file__).resolve().parents[1]
ICONS = ROOT / 'platform_overrides/icons'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def png_size(path):
    data = path.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n' or data[25] != 2:
        raise ValueError(f'Expected opaque RGB PNG: {path}')
    return struct.unpack('>II', data[16:24])


def generate(source):
    from PIL import Image, ImageOps
    image = ImageOps.exif_transpose(Image.open(source)).convert('RGB')
    if image.width != image.height:
        raise ValueError('App icon source must be square; no automatic cropping')
    ICONS.mkdir(parents=True, exist_ok=True)
    image = image.resize((1024, 1024), Image.Resampling.LANCZOS)
    image.save(ICONS / 'passcom.png')
    ios = ICONS / 'ios/AppIcon.appiconset'
    ios.mkdir(parents=True, exist_ok=True)
    entries = []
    for idiom, size, scales in [
        *[(idiom, size, scales) for idiom, scales in
          [('iphone', [2, 3]), ('ipad', [1, 2])]
          for size in [20, 29, 40]],
        ('iphone', 60, [2, 3]), ('ipad', 76, [1, 2]),
        ('ipad', 83.5, [2]), ('ios-marketing', 1024, [1]),
    ]:
        for scale in scales:
            name = f'Icon-App-{size}x{size}@{scale}x.png'
            pixels = int(size * scale)
            image.resize((pixels, pixels), Image.Resampling.LANCZOS).save(ios / name)
            entries.append({'size': f'{size}x{size}', 'idiom': idiom,
                            'filename': name, 'scale': f'{scale}x'})
    (ios / 'Contents.json').write_text(json.dumps({
        'images': entries, 'info': {'version': 1, 'author': 'xcode'}}, indent=2) + '\n')
    for density, scale in DENSITIES.items():
        folder = ICONS / f'android/mipmap-{density}'
        folder.mkdir(parents=True, exist_ok=True)
        size = int(48 * scale)
        image.resize((size, size), Image.Resampling.LANCZOS).save(folder / 'ic_launcher.png')
        # 72dp artwork within the official 108dp adaptive foreground canvas.
        # Keep the supplied artwork intact; the launcher applies its own mask.
        size = int(108 * scale)
        foreground = Image.new('RGB', (size, size), '#071E4D')
        art_size = int(72 * scale)
        foreground.paste(image.resize((art_size, art_size), Image.Resampling.LANCZOS),
                         ((size - art_size) // 2, (size - art_size) // 2))
        foreground.save(folder / 'ic_launcher_foreground.png')


def apply():
    for source, target in [
        (ICONS / 'android', ROOT / 'android/app/src/main/res'),
        (ICONS / 'ios/AppIcon.appiconset', ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'),
    ]:
        if not target.parent.exists():
            raise ValueError('Run Flutter bootstrap before applying icons')
        shutil.copytree(source, target, dirs_exist_ok=True)


def verify(applied=False):
    if png_size(ICONS / 'passcom.png') != (1024, 1024):
        raise ValueError('Invalid master icon dimensions')
    catalog = ICONS / 'ios/AppIcon.appiconset'
    entries = json.loads((catalog / 'Contents.json').read_text())['images']
    if {e['idiom'] for e in entries} != {'iphone', 'ipad', 'ios-marketing'}:
        raise ValueError('Missing iPhone/iPad/marketing icons')
    for entry in entries:
        size = int(float(entry['size'].split('x')[0]) * int(entry['scale'][0]))
        if png_size(catalog / entry['filename']) != (size, size):
            raise ValueError('Invalid iOS icon dimensions')
    for density, scale in DENSITIES.items():
        for name, dp in [('ic_launcher.png', 48), ('ic_launcher_foreground.png', 108)]:
            if png_size(ICONS / f'android/mipmap-{density}' / name) != (int(dp * scale),) * 2:
                raise ValueError('Invalid Android icon dimensions')
    if applied:
        for source, target in [
            (ICONS / 'android', ROOT / 'android/app/src/main/res'),
            (catalog, ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'),
        ]:
            for original in source.rglob('*'):
                if original.is_file():
                    copied = target / original.relative_to(source)
                    if not copied.exists() or copied.read_bytes() != original.read_bytes():
                        raise ValueError(f'Generated icon differs: {copied}')
    digest = hashlib.sha256((ICONS / 'passcom.png').read_bytes()).hexdigest()
    print(f'passcom icons verified: iPhone/iPad, 5 Android densities + adaptive; master SHA256 {digest}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, help='Regenerate icons from user-supplied square image (Pillow)')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--verify-applied', action='store_true')
    args = parser.parse_args()
    if args.source:
        generate(args.source)
    if args.apply:
        apply()
    verify(applied=args.verify_applied or args.apply)
