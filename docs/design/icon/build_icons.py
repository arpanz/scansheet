import os, sys
OUT = sys.argv[1]
INK, LIME = '#0B1210', '#D4F56A'

def svg(name, size, body, defs=''):
    open(os.path.join(OUT, name), 'w').write(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">'
        f'<style>html,body{{margin:0}}</style><defs>{defs}</defs>{body}</svg>')

def shadowf(id, dy, blur, op, col='#2A3A05'):
    return (f'<filter id="{id}" x="-40%" y="-40%" width="180%" height="180%">'
            f'<feGaussianBlur in="SourceAlpha" stdDeviation="{blur}" result="b"/><feOffset in="b" dy="{dy}" result="o"/>'
            f'<feFlood flood-color="{col}" flood-opacity="{op}"/><feComposite in2="o" operator="in" result="s"/>'
            f'<feMerge><feMergeNode in="s"/><feMergeNode in="SourceGraphic"/></feMerge></filter>')

BG_GRAD = '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#E0F98A"/><stop offset="1" stop-color="#BFE64A"/></linearGradient>'
PAPER = '<linearGradient id="pp" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#EEF1EA"/></linearGradient>'

# Art in icon-design coordinates (1024 = the visible icon).
CELL = dict(x=232, y=312, w=520, h=400, rx=40, sw=40)
HANDLE = dict(x=700, y=660, s=104, rx=26, sw=22)
BARS = [(26, 16), (12, 14), (40, 16), (12, 18), (26, 14), (12, 16), (40, 14), (12, 16), (26, 0)]
GRID_Y, GRID_X = (148, 300, 716, 868), (224, 756)

def bars(fill=INK):
    total = sum(w + g for w, g in BARS)
    x, out = 492 - total / 2, ''
    for bw, gap in BARS:
        out += f'<rect x="{x:.1f}" y="404" width="{bw}" height="216" rx="5" fill="{fill}"/>'; x += bw + gap
    return out

def cell(shadow=True):
    c, h = CELL, HANDLE
    f1 = ' filter="url(#cs)"' if shadow else ''
    f2 = ' filter="url(#hs)"' if shadow else ''
    return (f'<rect x="{c["x"]}" y="{c["y"]}" width="{c["w"]}" height="{c["h"]}" rx="{c["rx"]}" fill="url(#pp)" stroke="{INK}" stroke-width="{c["sw"]}"{f1}/>'
            + bars() +
            f'<rect x="{h["x"]}" y="{h["y"]}" width="{h["s"]}" height="{h["s"]}" rx="{h["rx"]}" fill="{INK}" stroke="{LIME}" stroke-width="{h["sw"]}"{f2}/>')

def grid(scale=1.0, size=1024):
    m = size / 2
    t = lambda v: m + (v - 512) * scale
    return (''.join(f'<rect x="0" y="{t(y) - 4 * scale:.1f}" width="{size}" height="{8 * scale:.1f}" fill="{INK}" fill-opacity=".08"/>' for y in GRID_Y)
            + ''.join(f'<rect x="{t(x) - 4 * scale:.1f}" y="0" width="{8 * scale:.1f}" height="{size}" fill="{INK}" fill-opacity=".08"/>' for x in GRID_X))

DEFS = BG_GRAD + PAPER + shadowf('cs', 26, 28, .38) + shadowf('hs', 8, 8, .35)
place = lambda s, size=1024: f'transform="translate({size/2} {size/2}) scale({s}) translate(-512 -512)"'

# Full square icon: legacy launcher, Play Store, web.
svg('full.svg', 1024, f'<rect width="1024" height="1024" fill="url(#bg)"/>{grid()}{cell()}', DEFS)
# Flat version for favicons, where the shadow turns to mud.
svg('flat.svg', 1024, f'<rect width="1024" height="1024" fill="{LIME}"/>{cell(False)}', PAPER)

# Adaptive layers: 1024 = 108dp canvas, visible 72dp is the middle 2/3.
A = 2 / 3
svg('adaptive_bg.svg', 1024, f'<rect width="1024" height="1024" fill="url(#bg)"/>{grid(A)}', BG_GRAD)
svg('adaptive_fg.svg', 1024, f'<g {place(A)}>{cell()}</g>', DEFS)

# Themed icon: alpha only. Hollow cell, bars, and a handle cut free of the frame.
c, h = CELL, HANDLE
mono = (f'<mask id="cut"><rect width="1024" height="1024" fill="#fff"/>'
        f'<rect x="{h["x"]}" y="{h["y"]}" width="{h["s"]}" height="{h["s"]}" rx="{h["rx"]}" fill="#000" stroke="#000" stroke-width="{h["sw"]}"/></mask>')
svg('adaptive_mono.svg', 1024,
    f'<g {place(A)}><g mask="url(#cut)"><rect x="{c["x"]}" y="{c["y"]}" width="{c["w"]}" height="{c["h"]}" rx="{c["rx"]}" fill="none" stroke="#fff" stroke-width="{c["sw"]}"/></g>'
    + bars('#fff') + f'<rect x="{h["x"] + 4}" y="{h["y"] + 4}" width="{h["s"] - 8}" height="{h["s"] - 8}" rx="{h["rx"] - 4}" fill="#fff"/></g>', mono)

# Android 12+ splash: 1152 canvas, art must fit the 768 circle.
svg('splash_12.svg', 1152, f'<g {place(0.9, 1152)}>{cell()}</g>', DEFS)
# Pre-12 splash: tighter canvas, read as xxxhdpi.
svg('splash.svg', 768, f'<g {place(1.0, 768)}>{cell()}</g>', DEFS)
