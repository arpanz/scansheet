"""Builds a custom ScanSheet .frameflow project: one flowing background across
all slides, real app screenshots in studio device frames, zoomed UI call-outs,
icon tiles and a mini sheet. Usage: gen.py light|dark|night <out.json>, then
~/webdev/mockup/node_modules/.bin/tsx driver.mts <out.json> <out dir>"""
import base64, copy, io, json, os, random, sys
from PIL import Image

FF = os.path.dirname(os.path.abspath(__file__))
STORE = os.path.dirname(FF)
W, H = 1080, 1920
U = min(W, H * 9 / 19.5) / 1000  # px per unit
N = 7

INK, PAPER, EMERALD, DEEP, LIME, MINT = '#0B1210', '#F5F6F2', '#0B7D45', '#086336', '#D4F56A', '#D8F0E0'
ICONS = json.load(open(f'{FF}/icons.json'))
variant = sys.argv[1] if len(sys.argv) > 1 else 'light'
TILT = float(os.environ.get('TILT', '0'))  # 1 = phones and call-outs tilted
NIGHT = variant == 'night'
if NIGHT:  # ink page, the same emerald wave, white type throughout
    PAPER, MINT = '#0F1714', '#18271F'

base = json.load(open(f'{FF}/base.frameflow'))
DEVICE = next(e for e in base['slides'][0]['elements'] if e['type'] == 'device')
TITLE = next(e for e in base['slides'][0]['elements'] if e['type'] == 'text' and e['role'] == 'title')

assets = {}
_n = [0]


def uid(p='e'):
    _n[0] += 1
    return f'{p}{_n[0]:04d}'


def asset(src, w, h, name):
    i = uid('a')
    assets[i] = {'id': i, 'name': name, 'src': src, 'width': w, 'height': h}
    return i


def png_asset(im, name):
    buf = io.BytesIO()
    im.save(buf, 'PNG')
    return asset('data:image/png;base64,' + base64.b64encode(buf.getvalue()).decode(), im.width, im.height, name)


def svg_asset(svg, w, h, name):
    return asset('data:image/svg+xml;base64,' + base64.b64encode(svg.encode()).decode(), w, h, name)


def screen(name):
    return png_asset(Image.open(f'{STORE}/screens/{name}.png').convert('RGB'), name)


def no_shadow():
    return {'enabled': False, 'x': 0, 'y': 0, 'blur': 0, 'spread': 0, 'color': '#000000', 'opacity': 0}


def shadow(y=24, blur=60, op=.22, color='#0B1210'):
    return {'enabled': True, 'x': 0, 'y': y, 'blur': blur, 'spread': 0, 'color': color, 'opacity': op}


def device(asset_id, x=.5, y=.645, h=.79, rot=0, tilt=0):
    d = copy.deepcopy(DEVICE)
    d.update(id=uid(), x=x, y=y, h=h, rotation=rot * TILT, tiltY=tilt)
    d['screen'] = {**d['screen'], 'assetId': asset_id}
    return d


def title(text, y=.105, on_dark=False, size=112, align='center', x=.5, w=.86):
    on_dark = on_dark or NIGHT
    t = copy.deepcopy(TITLE)
    t.update(id=uid(), text=text, y=y, x=x, w=w, fontSize=size, align=align)
    t['fill'] = {'kind': 'solid', 'color': '#FFFFFF' if on_dark else INK}
    t['accent'] = {**t['accent'], 'style': 'color', 'color': LIME if on_dark else EMERALD}
    return t


def caption(text, x, y, size=30, color=INK, weight=600, w=.3):
    t = copy.deepcopy(TITLE)
    t.update(id=uid(), role='caption', text=text, x=x, y=y, w=w, fontSize=size, fontWeight=weight,
             lineHeight=1.2, letterSpacing=0, maxLines=1)
    t['fontFamily'] = 'Inter'
    t['fill'] = {'kind': 'solid', 'color': color}
    return t


def image(asset_id, x, y, w_px, h_px, rot=0, radius=0, sh=None, stroke=None):
    return {'id': uid(), 'type': 'image', 'name': 'Image', 'visible': True, 'locked': False,
            'x': x, 'y': y, 'rotation': rot * TILT, 'opacity': 1, 'shadow': sh or no_shadow(),
            'assetId': asset_id, 'w': w_px / U, 'h': h_px / U, 'fit': 'contain', 'radius': radius / U,
            'stroke': stroke or {'enabled': False, 'width': 0, 'color': '#FFFFFF', 'opacity': 1}}


def rect(x, y, w_px, h_px, color, radius=28, sh=None):
    return {'id': uid(), 'type': 'shape', 'name': 'Tile', 'visible': True, 'locked': False,
            'x': x, 'y': y, 'rotation': 0, 'opacity': 1, 'shadow': sh or no_shadow(), 'shape': 'rect',
            'w': w_px / U, 'h': h_px / U, 'radius': radius / U, 'fill': {'kind': 'solid', 'color': color},
            'stroke': {'enabled': False, 'width': 0, 'color': '#000000', 'opacity': 1}, 'blur': 0}


def icon_svg(name, color, stroke=2):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 24 24" fill="none" '
            f'stroke="{color}" stroke-width="{stroke}" stroke-linecap="round" stroke-linejoin="round">{ICONS[name]}</svg>')


def callout(shot, box, x, y, width_px, rot=-2.5):
    """A piece of the real UI, cropped and floated larger than the phone shows it."""
    im = Image.open(f'{STORE}/screens/{shot}.png').convert('RGB').crop(box)
    h_px = width_px * im.height / im.width
    return image(png_asset(im, f'{shot}-callout'), x, y, width_px, h_px, rot=rot, radius=30,
                 sh=shadow(30, 70, .28), stroke={'enabled': True, 'width': 7 / U, 'color': '#FFFFFF', 'opacity': 1})


# ── Background: one wave across the whole set ────────────────────────────────

def wave(points):
    """Smooth path through points with flat tangents, closed under the curve."""
    d = f'M{points[0][0]},{points[0][1]}'
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        m = (x0 + x1) / 2
        d += f' C{m},{y0} {m},{y1} {x1},{y1}'
    return d


def background():
    TW = W * N
    s = W  # slide width
    top = [(-40, 1150), (s, 1150), (s * 1.5, 1250), (s * 2, 1080), (s * 2.5, 1320),
           (s * 3, 1120), (s * 3.5, 1270), (s * 4, 1060), (s * 4.5, 1290), (s * 5, 1110), (s * 5.5, 1320),
           (s * 6, 1140), (TW + 40, 1140)]
    mint = [(x, y - 150) for x, y in top]
    depth = [(-40, 1180), (s * .6, 1560), (s * 1.3, 1520), (s * 1.9, 1680), (s * 2.6, 1560), (s * 3.3, 1710),
             (s * 4, 1570), (s * 4.7, 1720), (s * 5.4, 1580), (s * 6.3, 1600), (TW + 40, 1200)]
    trail = [(x, y - 70) for x, y in depth]
    close = f' L{TW + 40},{H + 40} L-40,{H + 40} Z'
    # Hero and closing slides are solid emerald; the wave flows between them.
    bookends = f'M-40,-40 H{s} V{H + 40} H-40 Z M{s * 6},-40 H{TW + 40} V{H + 40} H{s * 6} Z'
    grid = ''.join(f'<path d="M{x},0 V{H}" />' for x in range(0, TW, 120)) + \
           ''.join(f'<path d="M0,{y} H{TW}" />' for y in range(0, H, 120))
    rnd = random.Random(4)
    brackets = ''
    for i in range(N):
        for _ in range(3):
            bx, by, bs = i * s + rnd.uniform(60, s - 160), rnd.uniform(1450, 1850), rnd.uniform(46, 80)
            brackets += (f'<g transform="translate({bx:.0f},{by:.0f})" fill="none" stroke="{LIME}" stroke-width="7" '
                         f'stroke-linecap="round" opacity=".35"><path d="M0,{bs*.35} V0 H{bs*.35}"/>'
                         f'<path d="M{bs*.65},0 H{bs} V{bs*.35}"/><path d="M{bs},{bs*.65} V{bs} H{bs*.65}"/>'
                         f'<path d="M{bs*.35},{bs} H0 V{bs*.65}"/></g>')
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{TW}" height="{H}" viewBox="0 0 {TW} {H}">
<defs><clipPath id="em"><path d="{wave(top)}{close}"/><path d="{bookends}"/></clipPath>
<linearGradient id="eg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{EMERALD}"/><stop offset="1" stop-color="{DEEP}"/></linearGradient></defs>
<g transform="translate({TW/2},{H/2}) scale({1/1.06:.6f}) translate({-TW/2},{-H/2})">
<rect x="-400" y="-200" width="{TW+800}" height="{H+400}" fill="{PAPER}"/>
<path d="{wave(mint)}{close}" fill="{MINT}"/>
<rect width="{TW}" height="{H}" fill="url(#eg)" clip-path="url(#em)"/>
<path d="{wave(depth)}{close}" fill="#064F2B" fill-opacity=".45"/>
<g clip-path="url(#em)" stroke="#FFFFFF" stroke-opacity=".055" stroke-width="2">{grid}</g>
<g clip-path="url(#em)">{brackets}</g>
<path d="{wave(trail)}" fill="none" stroke="{LIME}" stroke-width="8" stroke-dasharray="4 26" stroke-linecap="round"/>
</g></svg>'''
    return svg_asset(svg, TW, H, 'flow-background')


def mini_sheet():
    """A little spreadsheet with the new row lit up: where every scan lands."""
    rows = ''
    for r in range(5):
        y = 70 + r * 52
        fill = LIME if r == 4 else '#FFFFFF'
        rows += f'<rect x="16" y="{y}" width="388" height="44" rx="8" fill="{fill}"/>'
        for c, (cx, cw) in enumerate([(30, 120), (166, 150), (334, 52)]):
            op = '.85' if r == 4 else '.18'
            rows += f'<rect x="{cx}" y="{y + 16}" width="{cw - (r * 7 % 30)}" height="12" rx="6" fill="{INK}" fill-opacity="{op}"/>'
    head = ''.join(f'<rect x="{cx}" y="34" width="{cw}" height="14" rx="7" fill="#FFFFFF" fill-opacity=".9"/>'
                   for cx, cw in [(30, 70), (166, 90), (334, 40)])
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="420" height="350" viewBox="0 0 420 350">
<rect width="420" height="350" rx="28" fill="#EEF1EA"/>
<path d="M0,28 a28,28 0 0 1 28,-28 h364 a28,28 0 0 1 28,28 v40 h-420z" fill="{EMERALD}"/>{head}{rows}
<circle cx="378" cy="314" r="0" fill="{EMERALD}"/></svg>'''
    return svg_asset(svg, 420, 350, 'mini-sheet')


def app_icon():
    return svg_asset(open(os.path.join(STORE, '../design/icon/full.svg')).read(), 1024, 1024, 'app-icon')


# ── Slides ───────────────────────────────────────────────────────────────────

D = 'dark-' if variant in ('dark', 'night') else ''
shots = {
    'scan': screen('01-scan'),
    'home': screen(f'{D}06-home'),
    'stock': screen(f'{D}02-stock-count'),
    'att': screen(f'{D}03-attendance'),
    'cols': screen('04-columns'),
    'export': screen('05-export'),
    'darkhome': screen('dark-06-home'),
}
callout_src = {k: (f'{D}{v}' if D and k in ('stock', 'att') else v)
               for k, v in {'stock': '02-stock-count', 'att': '03-attendance'}.items()}

slides = []


def slide(name, elements):
    slides.append({'id': uid('s'), 'name': name, 'elements': elements, 'overrides': {},
                   'background': {'kind': 'solid', 'color': PAPER, 'noise': 0}})


icon = app_icon()
sheet = mini_sheet()

# 1 · Hero on emerald: icon, the promise, a scan landing in a sheet
slide('01-scan', [
    image(icon, .5, .062, 128, 128, radius=30, sh=shadow(14, 30, .3, '#000000')),
    title('Scan to\n*Google Sheets*', y=.165, on_dark=True, size=118),
    device(shots['scan'], x=.47, y=.69, h=.74, rot=-3),
    image(sheet, .80, .81, 380, 316, rot=6, radius=26, sh=shadow(30, 60, .3, '#000000')),
])

# 2 · Anything with a code: four use-case tiles
tiles = []
for i, (ic, label) in enumerate([('package', 'Stock'), ('users', 'Attendance'), ('laptop', 'Assets'), ('ticket', 'Tickets')]):
    x = .155 + i * .23
    tiles += [rect(x, .262, 214, 196, '#1C2A23' if NIGHT else '#FFFFFF', 34, shadow(12, 30, .10)),
              image(svg_asset(icon_svg(ic, LIME if NIGHT else EMERALD), 96, 96, ic), x, .245, 74, 74),
              caption(label, x, .292, size=29, color='#FFFFFF' if NIGHT else INK)]
slide('02-anything', [title('Track anything\nwith a *code*'), *tiles, device(shots['home'], y=.715, h=.70)])

# 3 · Stock count, with its numbers pulled out
slide('03-stock', [title('Count stock\nin *minutes*'), device(shots['stock']),
                   callout(callout_src['stock'], (53, 413, 1027, 605), .5, .47, 940, rot=-2)])

# 4 · Attendance: who's missing, pulled out
slide('04-attendance', [title("See who's\n*not here yet*"), device(shots['att']),
                        callout(callout_src['att'], (53, 1010, 1027, 1365), .52, .62, 900, rot=2)])

# 5 · Columns: the type grid, pulled out
slide('05-columns', [title('Add the columns\n*you need*'), device(shots['cols']),
                     callout('04-columns', (53, 427, 1027, 787), .5, .46, 960, rot=-2)])

# 6 · Files: Excel and CSV cards, pulled out
slide('06-export', [title('Save as *Excel*\nor CSV'), device(shots['export']),
                    callout('05-export', (53, 1176, 1027, 1577), .5, .70, 920, rot=2)])

# 7 · Dark mode bookend on emerald
slide('07-dark', [title('Works in\n*dark mode*', on_dark=True, y=.11),
                  image(svg_asset(icon_svg('moon', LIME, 2.2), 96, 96, 'moon'), .5, .215, 84, 84),
                  device(shots['darkhome'], y=.69, h=.74, rot=3)])

project = copy.deepcopy(base)
project.update(name=f'ScanSheet flow {variant}', slides=slides, assets=assets)
project['span'] = {'enabled': True, 'background': {'kind': 'image', 'assetId': background(), 'fit': 'cover',
                                                   'blur': 0, 'overlay': '#00000000', 'noise': 0}}
json.dump(project, open(sys.argv[2], 'w'))
print('slides', len(slides), 'assets', len(assets))
