#!/usr/bin/env python3
"""
Style audit for the CQ.AI workspaces.

Scans every LWC component's CSS (and inline style= attributes in its HTML) and reports each place a value is
typed directly instead of coming from a cqStyles token: font sizes, corner radii, colours, bold weights and
spacing. cqStyles itself is where the tokens live, so it is reported separately.

Usage:
    python3 scripts/style_audit.py                 # summary per component
    python3 scripts/style_audit.py --detail NAME   # every finding for one component
    python3 scripts/style_audit.py --md FILE       # write the full report as Markdown

Nothing is changed; the script only reads.
"""
import argparse
import collections
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'force-app', 'main', 'default', 'lwc')
TOKENS = 'cqStyles'

# what counts as drift, per kind
RADIUS_OK = {'999px', '50%', '0', 'inherit'}            # pills, circles, square edges
KINDS = ('font-size', 'radius', 'colour', 'weight', 'spacing')

DECL = re.compile(r'([a-z-]+)\s*:\s*([^;{}]+)')
COLOUR = re.compile(r'#[0-9a-fA-F]{3,8}\b|rgba?\([^)]*\)')
PX = re.compile(r'(?<![\w.-])(\d+(?:\.\d+)?)(px|rem)\b')


def strip_comments(text):
    return re.sub(r'/\*.*?\*/', '', text, flags=re.S)


def line_of(text, pos):
    return text.count('\n', 0, pos) + 1


def findings_in_css(text):
    """Yield (line, kind, property, value) for each typed value in a stylesheet or inline style."""
    clean = strip_comments(text)
    for m in DECL.finditer(clean):
        prop, value = m.group(1).strip(), m.group(2).strip()
        if prop.startswith('--'):
            continue                                        # a token definition, not a use
        line = line_of(clean, m.start())
        if 'var(--' in value and not PX.search(value.replace('var(', '')):
            continue
        if prop == 'font-size' and PX.search(value):
            yield line, 'font-size', prop, value
        elif prop in ('border-radius',) and value not in RADIUS_OK and PX.search(value):
            yield line, 'radius', prop, value
        elif prop == 'font-weight' and value in ('600', '700', 'bold', 'bolder'):
            yield line, 'weight', prop, value
        elif prop in ('padding', 'margin', 'gap', 'row-gap', 'column-gap') or prop.startswith(('padding-', 'margin-')):
            if PX.search(value):
                yield line, 'spacing', prop, value
        if COLOUR.search(value) and prop not in ('box-shadow',):
            for c in COLOUR.findall(value):
                yield line, 'colour', prop, c


def findings_in_html(text):
    for m in re.finditer(r'style="([^"]*)"', text):
        base = line_of(text, m.start())
        for _line, kind, prop, value in findings_in_css(m.group(1)):
            yield base, kind, prop, value
    # SVG presentation attributes with literal colours (charts)
    for m in re.finditer(r'(fill|stroke)="(#[0-9a-fA-F]{3,8})"', text):
        yield line_of(text, m.start()), 'colour', m.group(1), m.group(2)


def scan():
    report = {}
    for name in sorted(os.listdir(ROOT)):
        folder = os.path.join(ROOT, name)
        if not os.path.isdir(folder):
            continue
        items = []
        for fname in sorted(os.listdir(folder)):
            path = os.path.join(folder, fname)
            if fname.endswith('.css'):
                with open(path, encoding='utf-8') as f:
                    text = f.read()
                items += [(fname, *x) for x in findings_in_css(text)]
            elif fname.endswith('.html'):
                with open(path, encoding='utf-8') as f:
                    text = f.read()
                items += [(fname, *x) for x in findings_in_html(text)]
        if items:
            report[name] = items
    return report


def summary(report):
    rows = []
    for name, items in report.items():
        c = collections.Counter(k for _f, _l, k, _p, _v in items)
        rows.append((name, sum(c.values()), *[c[k] for k in KINDS]))
    rows.sort(key=lambda r: (r[0] == TOKENS, -r[1]))
    return rows


def print_summary(report):
    rows = summary(report)
    head = ('Component', 'Total') + tuple(k.title() for k in KINDS)
    widths = [max(len(str(r[i])) for r in rows + [head]) for i in range(len(head))]
    fmt = '  '.join('{:<%d}' % w if i == 0 else '{:>%d}' % w for i, w in enumerate(widths))
    print(fmt.format(*head))
    for r in rows:
        print(fmt.format(*r))
    total = collections.Counter()
    for name, items in report.items():
        if name != TOKENS:
            total.update(k for _f, _l, k, _p, _v in items)
    print('\nAcross components (cqStyles excluded): ' + ', '.join('%s %d' % (k, total[k]) for k in KINDS))
    print('Most common typed values:')
    common = collections.Counter((k, v) for n, items in report.items() if n != TOKENS for _f, _l, k, _p, v in items)
    for (k, v), n in common.most_common(15):
        print('  %-10s %-24s %d' % (k, v, n))


def print_detail(report, name):
    items = report.get(name)
    if not items:
        print('No findings for', name)
        return
    for fname, line, kind, prop, value in sorted(items):
        print('%s:%d  %-9s %s: %s' % (fname, line, kind, prop, value))


def write_md(report, path):
    rows = summary(report)
    out = ['# Style Audit', '', 'Typed values that bypass cqStyles tokens, per component. Read only; nothing was changed.', '',
           '| Component | Total | ' + ' | '.join(k.title() for k in KINDS) + ' |',
           '| --- | ---: | ' + ' | '.join('---:' for _ in KINDS) + ' |']
    out += ['| %s | %d | %s |' % (r[0], r[1], ' | '.join(str(x) for x in r[2:])) for r in rows]
    for name, items in sorted(report.items()):
        out += ['', '## ' + name, '', '| File | Line | Kind | Property | Value |', '| --- | ---: | --- | --- | --- |']
        out += ['| %s | %d | %s | %s | `%s` |' % (f, l, k, p, v.replace('|', '\\|')) for f, l, k, p, v in sorted(items)]
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out) + '\n')
    print('Wrote', path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--detail', metavar='COMPONENT')
    ap.add_argument('--md', metavar='FILE')
    args = ap.parse_args()
    report = scan()
    if args.detail:
        print_detail(report, args.detail)
    elif args.md:
        write_md(report, args.md)
    else:
        print_summary(report)


if __name__ == '__main__':
    sys.exit(main())
