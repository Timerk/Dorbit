"""Compose actual Godot ship finishes; check transparency and review framing."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.tools/art-python'))
from PIL import Image, ImageDraw, ImageFont

catalog = json.loads((ROOT / 'assets/ships/catalog.json').read_text())
font_path = Path('C:/Windows/Fonts/segoeui.ttf')
font = ImageFont.truetype(str(font_path), 26) if font_path.exists() else ImageFont.load_default(size=26)
small = ImageFont.truetype(str(font_path), 20) if font_path.exists() else ImageFont.load_default(size=20)
background = (13, 23, 33)
overview = Image.new('RGB', (2400, 2344), background)
draw = ImageDraw.Draw(overview)
draw.text((35, 20), 'DORBIT / ACTUAL GODOT MATERIALS', font=font, fill=(225, 235, 242))
draw.text((35, 58), 'Coated armor, exposed metal and distinct cockpit glass | same assets as flight', font=small, fill=(130, 175, 197))
views = ['perspective', 'front', 'rear', 'side', 'top', 'underside']
for index, (slug, entry) in enumerate(catalog.items()):
    directory = ROOT / 'art/ship-review/materials' / slug
    thumbnail = Image.open(ROOT / 'assets/ui/ships' / (slug + '.png')).convert('RGBA')
    assert thumbnail.size == (400, 360) and thumbnail.getpixel((0, 0))[3] == 0, slug + ': thumbnail must be transparent'
    bounds = thumbnail.getchannel('A').point(lambda alpha: 255 if alpha > 40 else 0).getbbox()
    assert bounds and bounds[0] > 0 and bounds[1] > 0 and bounds[2] < 400 and bounds[3] < 360, slug + ': clipped thumbnail'
    sheet = Image.new('RGB', (1800, 1160), background)
    painter = ImageDraw.Draw(sheet)
    painter.text((25, 16), entry['name'].upper() + ' / GODOT SURFACE REVIEW', font=font, fill=(225, 235, 242))
    for number, view in enumerate(views):
        image = Image.open(directory / (view + '.png')).convert('RGBA')
        assert image.size == (600, 540), slug + ': wrong review size'
        bounds = image.getchannel('A').point(lambda alpha: 255 if alpha > 40 else 0).getbbox()
        assert bounds and bounds[0] > 0 and bounds[1] > 0 and bounds[2] < image.width and bounds[3] < image.height, slug + ': clipped ' + view
        x, y = (number % 3) * 600, 70 + (number // 3) * 540
        sheet.paste(image, (x, y), image)
        painter.text((x + 20, y + 8), view.upper(), font=small, fill=(130, 175, 197))
    sheet.save(directory / 'views.jpg', quality=93)
    image = Image.open(directory / 'hangar.png').convert('RGB')
    assert image.size == (900, 600), slug + ': wrong hangar size'
    image = image.resize((780, 520), Image.Resampling.LANCZOS)
    # Three columns preserve the render aspect ratio and common display scale.
    x, y = 10 + (index % 3) * 800, 104 + (index // 3) * 560
    overview.paste(image, (x, y))
    draw.text((x + 15, y + 7), entry['name'].upper(), font=font, fill=(225, 235, 242))
    print('REVIEW', slug, ': six unclipped views and transparent thumbnail')
overview.save(ROOT / 'docs/feedback/ship-materials-overview.jpg', quality=93)
