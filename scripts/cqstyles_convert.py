"""Audit every LWC against the CQ guide and apply the mechanical cqStyles conversion.

Usage: python3 convert.py <lwc dir> <out json> [--apply]
Mechanical conversion = @import cqStyles, hard-coded colours -> tokens, standard workspace header -> shared classes.
Everything that needs a design decision is only reported.
"""
import os, re, sys, json, collections

LWC, OUT = sys.argv[1], sys.argv[2]
APPLY = '--apply' in sys.argv
SKIP = {'cqStyles', 'cqEventReviewPanel', 'cqLotPicker', 'cqPartPicker'}   # already on cqStyles

def group(token, *hexes): return {h: token for h in hexes}
PLAIN = {}
PLAIN.update(group('--cq-link', '#1d5fd1', '#0b5cab', '#0176d3', '#2f6fb5'))
PLAIN.update(group('--cq-muted', '#5b6470', '#5c6572', '#706e6b', '#3d4550'))
PLAIN.update(group('--cq-faint', '#8a94a3'))
PLAIN.update(group('--cq-ink', '#1a1d21', '#181818', '#2b2f36'))
PLAIN.update(group('--cq-line', '#dde1e6', '#eceff2', '#e3e6ea', '#dddbda', '#dfe3e9', '#eee'))
PLAIN.update(group('--cq-hl-line', '#e5e5e5'))
PLAIN.update(group('--cq-hl-bg', '#f3f3f3'))
PLAIN.update(group('--cq-line-field', '#c4cad2', '#c9d2dc', '#c9c9c9', '#c9c7c5'))
PLAIN.update(group('--cq-surface', '#fafbfc', '#f5f6f8', '#eef2f7', '#f5f8fd', '#fafaf9', '#f0f0f0'))
PLAIN.update(group('--cq-neu-bg', '#eef0f3'))
PLAIN.update(group('--cq-accent', '#4a2fc0'))
PLAIN.update(group('--cq-accent-line', '#dcd3ff', '#e3d9fb', '#c7bdeb'))
PLAIN.update(group('--cq-accent-soft', '#f8f6ff', '#f3eefe', '#ece7ff', '#f1ecfa'))
PLAIN.update(group('--cq-crit-bg', '#fff8f7', '#fdecea', '#fbe9e7'))
PLAIN.update(group('--cq-crit-line', '#f3c7c2', '#f4c7c3'))
PLAIN.update(group('--cq-pos-bg', '#ebf7e6', '#e6f4ec', '#e6f4ea'))
PLAIN.update(group('--cq-pos-line', '#b7e1c1'))
PLAIN.update(group('--cq-warn-bg', '#fff6cc', '#fef1e6', '#fffbf5', '#ffe6cf'))
PLAIN.update(group('--cq-warn-line', '#f2d3a8'))
PLAIN.update(group('--cq-link-soft', '#e8f0fd', '#f5f9ff'))
# the guide's own values typed out by hand
PLAIN.update({'#0b5cad': '--cq-link', '#1b1f27': '--cq-ink', '#e5e8ec': '--cq-line', '#f6f7f9': '--cq-surface', '#8a93a0': '--cq-faint'})
# status colours: solid when used as a fill, fg when used as text or a border
STATUS = {}
STATUS.update(group('crit', '#b42318', '#ba0517', '#9b2c2c'))
STATUS.update(group('pos', '#2e844a', '#12784a', '#2f5d3a'))
STATUS.update(group('warn', '#7a4100', '#6b5300', '#8c4b02', '#8a3c00'))
STATUS.update({'#1a7f45': 'pos', '#8a4b00': 'warn', '#b3261e': 'crit'})
WHITE = {'#fff', '#ffffff'}
HEX = re.compile(r'#[0-9a-fA-F]{3,8}\b')

def prop_of(css, pos):
    """The property name of the declaration that contains css[pos]."""
    start = max(css.rfind(';', 0, pos), css.rfind('{', 0, pos)) + 1
    decl = css[start:pos]
    return decl.split(':')[0].strip().lower() if ':' in decl else ''

def tokenise(css):
    mapped, unmapped = collections.Counter(), collections.Counter()
    def sub(m):
        h = m.group(0).lower()
        prop = prop_of(css, m.start())
        is_bg = 'background' in prop
        if h in WHITE:
            if is_bg: mapped['--cq-bg'] += 1; return 'var(--cq-bg)'
            return m.group(0)                       # white text / white borders stay literal
        if h in STATUS:
            t = '--cq-%s-%s' % (STATUS[h], 'solid' if is_bg else 'fg')
            mapped[t] += 1; return 'var(%s)' % t
        if h in PLAIN:
            mapped[PLAIN[h]] += 1; return 'var(%s)' % PLAIN[h]
        unmapped[h] += 1
        return m.group(0)
    return HEX.sub(sub, css), mapped, unmapped

HL_RULES = ['.hl', '.hl-top', '.hl-who', '.hl-icon', '.hl-name', '.hl-obj', '.hl-title', '.hl-actions', '.hl-fields']
HL_CLASSES = ['hl-top', 'hl-who', 'hl-icon', 'hl-name', 'hl-obj', 'hl-title', 'hl-actions', 'hl-fields', 'hl']

def header_block(html):
    m = re.search(r'<(header|div) class="hl">', html)
    if not m: return None
    tag, i, depth = m.group(1), m.start(), 0
    for mm in re.finditer(r'<(/?)' + tag + r'\b', html[i:]):
        depth += -1 if mm.group(1) else 1
        if depth == 0: return i, i + mm.end() + 1
    return None

def convert_header(name, html, css, js, notes):
    span = header_block(html)
    if not span or '.hl-top' not in css: return html, css, False
    i, j = span
    blk = html[i:j]
    for c in HL_CLASSES:
        blk = re.sub(r'class="%s"' % re.escape(c), 'class="cq-%s"' % c, blk)
    blk = blk.replace('class="f"', 'class="cq-hl-f"').replace('class="k"', 'class="cq-hl-k"')
    blk = blk.replace('class="v link"', 'class="cq-hl-v link"').replace('class="v"', 'class="cq-hl-v"')
    blk = blk.replace('class="btn primary"', 'class="cq-btn-primary"').replace('class="btn"', 'class="cq-btn-outline"')
    rest = html[:i] + html[j:]
    html = html[:i] + blk + html[j:]
    # drop the local header rules the shared classes replace
    kept = []
    for line in css.split('\n'):
        sel = line.split('{')[0].strip()
        if sel in HL_RULES: continue
        if sel in ('.f', '.k', '.v', '.v.link'):
            cls = sel.split('.')[1]
            used_elsewhere = re.search(r'class="[^"]*\b%s\b[^"]*"' % cls, rest) or re.search(r"'%s[ ']" % cls, js)
            if not used_elsewhere: continue
            notes.append('header sub-field class .%s is also used outside the header (or built in JS), so its local rule stays' % cls)
        kept.append(line.replace('.hl-icon lightning-icon', '.cq-hl-icon lightning-icon'))
    css = '\n'.join(kept)
    if 'border-radius: 12px 12px 0 0' not in ''.join(l for l in open(os.path.join(LWC, name, name + '.css')).read().split('\n') if l.startswith('.hl {')):
        css = css.rstrip('\n') + '\n/* this header sits flush inside its container, so no rounded top */\n.cq-hl { border-radius: 0; }\n'
    return html, css, True

def audit(name, html, css, js):
    a = {}
    a['inputs'] = len(re.findall(r'<(?:input|textarea|select)\b', html))
    a['lightning_inputs'] = len(re.findall(r'<lightning-(?:input|combobox|textarea|record-picker|dual-listbox|radio-group|checkbox-group)\b', html))
    a['uses_cq_field'] = 'cq-field' in html
    btn = sorted(set(re.findall(r'^\.btn(?:\.[a-z-]+)?(?=[ ,{:])', css, re.M)))
    a['local_buttons'] = btn
    a['button_uses'] = len(re.findall(r'class="btn\b', html)) + len(re.findall(r"'btn\b", js))
    a['lightning_buttons'] = len(re.findall(r'<lightning-button\b', html))
    # selectable controls and how their selected state is drawn
    sel = []
    for m in re.finditer(r'^(\.[a-z][a-z0-9-]*)\.(on|sel|selected|active|picked)\s*\{([^}]*)\}', css, re.M):
        body = m.group(3)
        bg = re.search(r'background(?:-color)?:\s*([^;]+)', body)
        col = re.search(r'(?:^|;)\s*color:\s*([^;]+)', body)
        solid = bool(col and col.group(1).strip().lower() in ('#fff', '#ffffff', 'white'))
        sel.append({'cls': m.group(1), 'solid': solid, 'bg': bg.group(1).strip() if bg else '', 'color': col.group(1).strip() if col else ''})
    a['selectable'] = sel
    pills = []
    for m in re.finditer(r'^(\.[a-z][a-z0-9.-]*)\s*\{([^}]*border-radius:\s*(?:999px|99px|1[0-9]px|2[0-9]px)[^}]*)\}', css, re.M):
        body = m.group(2)
        fs = re.search(r'font-size:\s*(\d+)px', body)
        if fs and int(fs.group(1)) <= 12: pills.append(m.group(1))
    a['pills'] = pills
    a['uses_cq_pill'] = 'cq-pill' in html or 'cq-pill' in js
    msgs = sorted(set(re.findall(r'^(\.(?:err|errbox|warnbox|okbox|infobox|banner|alert|warn|notice)[a-z-]*)\s*\{', css, re.M)))
    a['message_boxes'] = msgs
    drops = []
    for m in re.finditer(r'^(\.[a-z][a-z0-9.-]*)\s*\{([^}]*position:\s*absolute[^}]*)\}', css, re.M):
        if re.search(r'max-height|overflow|box-shadow|z-index', m.group(2)): drops.append(m.group(1))
    a['overlays'] = drops
    a['has_place_check'] = 'getBoundingClientRect' in js
    fs = collections.Counter(int(x) for x in re.findall(r'font-size:\s*(\d+)px', css))
    a['font_sizes'] = dict(sorted(fs.items()))
    a['off_scale_font_uses'] = sum(n for s, n in fs.items() if s not in (11, 13, 14, 15))
    rad = collections.Counter(re.findall(r'border-radius:\s*([^;}]+)', css))
    a['radii'] = dict(rad.most_common(8))
    a['inline_hex'] = len(HEX.findall(html)) + len(re.findall(r"'#[0-9a-fA-F]{3,8}'", js))
    a['title_case_check'] = []
    return a

result = {}
for name in sorted(os.listdir(LWC)):
    d = os.path.join(LWC, name)
    if not os.path.isdir(d): continue
    rd = lambda ext: open(os.path.join(d, name + ext)).read() if os.path.exists(os.path.join(d, name + ext)) else ''
    html, css, js = rd('.html'), rd('.css'), rd('.js')
    r = {'css_bytes': len(css), 'html_bytes': len(html), 'already': name in SKIP or "c/cqStyles" in css}
    r['hex_before'] = len(HEX.findall(css))
    r.update(audit(name, html, css, js))
    notes = []
    if name not in SKIP and css:
        new_css, mapped, unmapped = tokenise(css)
        new_html, new_css, hdr = convert_header(name, html, new_css, js, notes)
        if "c/cqStyles" not in new_css:
            new_css = "@import 'c/cqStyles';\n\n" + new_css
        r['mapped'] = dict(mapped); r['mapped_total'] = sum(mapped.values())
        r['unmapped'] = dict(unmapped.most_common()); r['unmapped_total'] = sum(unmapped.values())
        r['header_converted'] = hdr
        r['has_local_header'] = bool(re.search(r'^\.hl-top\b', css, re.M))
        if APPLY:
            open(os.path.join(d, name + '.css'), 'w').write(new_css)
            if new_html != html: open(os.path.join(d, name + '.html'), 'w').write(new_html)
    else:
        r['mapped'] = {}; r['mapped_total'] = 0; r['unmapped'] = {}; r['unmapped_total'] = 0
        r['header_converted'] = False; r['has_local_header'] = bool(re.search(r'^\.hl-top\b', css, re.M))
    r['notes'] = notes
    result[name] = r
json.dump(result, open(OUT, 'w'), indent=1)
print('%-28s %5s %5s %5s  hdr btn sel pill msg ovl inp' % ('component', 'hex', 'map', 'left'))
for n, r in result.items():
    print('%-28s %5d %5d %5d   %s  %2d  %2d  %2d  %2d  %2d  %2d' % (n, r['hex_before'], r['mapped_total'], r['unmapped_total'],
          'Y' if r['header_converted'] else ('L' if r['has_local_header'] else '-'), len(r['local_buttons']), len(r['selectable']), len(r['pills']),
          len(r['message_boxes']), len(r['overlays']), r['inputs']))
