"""Generates demo garment cutouts by running the real remover.

The shapes are drawn, not photographed — there are no garments in a container.
But the *cutouts* are produced by the shipping BorderSampledRemover on those
drawings, so what the screenshots show is this service's actual output.
"""
import io, json, base64, pathlib
from PIL import Image, ImageDraw
from app.services.images.cutout import BorderSampledRemover

BG = (243, 242, 238)
W, H = 420, 520

def canvas():
    return Image.new('RGB', (W, H), BG), None

def sweater(d, c):
    d.rounded_rectangle([W*.28, H*.24, W*.72, H*.80], radius=14, fill=c)
    d.polygon([(W*.28,H*.26),(W*.09,H*.46),(W*.17,H*.56),(W*.28,H*.40)], fill=c)
    d.polygon([(W*.72,H*.26),(W*.91,H*.46),(W*.83,H*.56),(W*.72,H*.40)], fill=c)
    d.ellipse([W*.42,H*.20,W*.58,H*.29], fill=BG)

def tee(d, c):
    d.rounded_rectangle([W*.30, H*.26, W*.70, H*.72], radius=10, fill=c)
    d.polygon([(W*.30,H*.28),(W*.14,H*.40),(W*.21,H*.48),(W*.30,H*.38)], fill=c)
    d.polygon([(W*.70,H*.28),(W*.86,H*.40),(W*.79,H*.48),(W*.70,H*.38)], fill=c)
    d.ellipse([W*.43,H*.23,W*.57,H*.31], fill=BG)

def hoodie(d, c):
    d.rounded_rectangle([W*.26, H*.26, W*.74, H*.80], radius=16, fill=c)
    d.polygon([(W*.26,H*.28),(W*.08,H*.50),(W*.16,H*.60),(W*.26,H*.44)], fill=c)
    d.polygon([(W*.74,H*.28),(W*.92,H*.50),(W*.84,H*.60),(W*.74,H*.44)], fill=c)
    d.chord([W*.36,H*.16,W*.64,H*.34], 0, 180, fill=c)

def jeans(d, c):
    d.rectangle([W*.33, H*.18, W*.67, H*.38], fill=c)
    d.polygon([(W*.33,H*.38),(W*.48,H*.38),(W*.46,H*.86),(W*.35,H*.86)], fill=c)
    d.polygon([(W*.52,H*.38),(W*.67,H*.38),(W*.65,H*.86),(W*.54,H*.86)], fill=c)

def blouse(d, c):
    d.polygon([(W*.32,H*.26),(W*.68,H*.26),(W*.72,H*.74),(W*.28,H*.74)], fill=c)
    d.polygon([(W*.32,H*.27),(W*.16,H*.44),(W*.23,H*.52),(W*.32,H*.40)], fill=c)
    d.polygon([(W*.68,H*.27),(W*.84,H*.44),(W*.77,H*.52),(W*.68,H*.40)], fill=c)
    d.polygon([(W*.44,H*.26),(W*.56,H*.26),(W*.50,H*.40)], fill=BG)

def shirt(d, c):
    d.rectangle([W*.30, H*.26, W*.70, H*.76], fill=c)
    d.polygon([(W*.30,H*.28),(W*.13,H*.44),(W*.20,H*.52),(W*.30,H*.40)], fill=c)
    d.polygon([(W*.70,H*.28),(W*.87,H*.44),(W*.80,H*.52),(W*.70,H*.40)], fill=c)
    d.polygon([(W*.42,H*.24),(W*.50,H*.36),(W*.58,H*.24)], fill=BG)

def towel(d, c):
    d.rounded_rectangle([W*.30, H*.20, W*.70, H*.82], radius=6, fill=c)
    for i in range(4):
        y = H*.28 + i*H*.14
        d.rectangle([W*.30, y, W*.70, y+H*.02], fill=tuple(max(0,v-22) for v in c))

SHAPES = {
    'demo-jumper': (sweater, (60, 63, 68)),
    'demo-tee': (tee, (244, 244, 242)),
    'demo-hoodie': (hoodie, (31, 42, 68)),
    'demo-jeans': (jeans, (43, 58, 85)),
    'demo-silk': (blouse, (239, 227, 206)),
    'demo-red': (shirt, (179, 50, 44)),
    'demo-towel': (towel, (143, 179, 199)),
}

remover = BorderSampledRemover()
out = {}
for key, (draw_fn, colour) in SHAPES.items():
    img, _ = canvas()
    draw_fn(ImageDraw.Draw(img), colour)
    buf = io.BytesIO(); img.save(buf, format='PNG')

    result = remover.remove(buf.getvalue())
    assert result.is_plausible, f'{key}: coverage {result.coverage:.3f}'

    # Shrink for embedding: a wardrobe row draws these at ~44dp.
    cut = Image.open(io.BytesIO(result.png))
    cut.thumbnail((220, 220), Image.Resampling.LANCZOS)
    small = io.BytesIO(); cut.save(small, format='PNG', optimize=True)

    out[key] = base64.b64encode(small.getvalue()).decode()
    print(f'{key:14s} coverage={result.coverage:.3f} {len(small.getvalue())//1024}KB')

dest = pathlib.Path(__file__).resolve().parents[2] / 'app/assets/demo/cutouts.json'
dest.write_text(json.dumps(out, indent=0, sort_keys=True))
print('wrote', dest)
