import re,sys
ADD = r'''
/* ============================ PAGE LAYOUT PIECES =======================
   Columns, cards and rows that several workspaces lay their steps out with. */
/* two columns side by side. top = each column keeps its own height; wide = 1.4 to 1; wide32 = 3 to 2 */
.cq-cols { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
.cq-cols.top { align-items: start; }
.cq-cols.wide { grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr); }
.cq-cols.wide32 { grid-template-columns: minmax(0, 3fr) minmax(0, 2fr); }
@media (max-width: 760px) { .cq-cols, .cq-cols.wide, .cq-cols.wide32 { grid-template-columns: 1fr; } }
/* a column of blocks; lead = the main column, with more air between them */
.cq-col { display: flex; flex-direction: column; gap: 8px; min-width: 0; }
.cq-col.lead { gap: 14px; }
/* a name with its detail lines under it, taking the room in a row */
.cq-stack { display: flex; flex-direction: column; flex: 1 1 auto; min-width: 0; }
/* a ruled row in a card: what it is on the left, its value or pill on the right */
.cq-krow { display: flex; align-items: center; gap: 12px; padding: 8px 0; border-bottom: 1px solid var(--cq-line); }
.cq-krow:last-child { border-bottom: none; padding-bottom: 0; }
.cq-para { margin-top: 6px; font-size: 14px; line-height: 1.45; white-space: pre-line; }
.cq-big { font-size: 20px; font-weight: 700; }
.cq-mt14 { margin-top: 14px; }
/* The Problem: the grey card that opens a glance, and its text */
.cq-pcard { padding: 14px; border-radius: var(--cq-r-card); background: var(--cq-surface); border: 1px solid var(--cq-line); display: flex; flex-direction: column; gap: 8px; min-width: 0; }
.cq-prob { margin: 0; font-size: 14px; line-height: 1.45; }
/* a numbered card inside a step: .cq-stepcard > .cq-stepcard-head (.cq-stepcard-n + .cq-stepcard-title, then .cq-grow + .cq-stepcard-tot) */
.cq-stepcard { display: flex; flex-direction: column; gap: 10px; min-width: 0; padding: 14px; border-radius: 10px; border: 1px solid var(--cq-line); background: var(--cq-bg); }
.cq-stepcard-head { display: flex; align-items: baseline; gap: 8px; }
.cq-stepcard-n { font-size: 13px; font-weight: 700; color: var(--cq-muted); }
.cq-stepcard-title { font-size: 15px; font-weight: 700; }
.cq-stepcard-tot { font-size: 13px; font-weight: 600; }
/* a stock location link and the dot between two of them */
.cq-ploc { color: var(--cq-link); font-weight: 600; text-decoration: none; }
.cq-ploc:hover { text-decoration: underline; }
.cq-dotsep { color: var(--cq-faint); }
/* a decision card in Next Steps: its name, its state line, the suggestion, the choices */
.cq-dcard-name { font-size: 14px; font-weight: 700; }
.cq-dcard-state { margin-top: 2px; min-height: 19px; color: var(--cq-muted); }
.cq-dcard-sug { flex: 1 1 auto; min-width: 0; line-height: 1.45; }
.cq-dcard-chips { display: flex; flex-wrap: wrap; gap: 6px; }
/* "what we know" fold-out and the Start Over link */
.cq-know summary { color: var(--cq-link); font-size: 13px; font-weight: 600; cursor: pointer; }
.cq-restart { margin: 4px 8px 0; padding: 0; border: none; background: none; color: var(--cq-link); font: inherit; font-size: 13px; text-align: left; cursor: pointer; }
/* the small "From" / "For" card at the top of a popup, and the loading line */
.cq-fromcard { padding: 10px 12px; border-radius: 8px; border: 1px solid var(--cq-hl-line); background: var(--cq-surface); display: flex; flex-direction: column; gap: 2px; line-height: 1.45; }
.cq-spin { position: relative; display: inline-block; width: 24px; height: 24px; }
.cq-spinwrap { display: flex; align-items: center; gap: 10px; min-height: 40px; }
/* "Happened Before": the amber warning box, its heading, the red link, and a button that is a link */
.cq-recur { margin-top: 14px; padding: 14px; border-radius: 10px; border: 1px solid var(--cq-warn-line); background: var(--cq-warn-bg); display: flex; flex-direction: column; gap: 8px; }
.cq-recur-head { display: flex; align-items: center; gap: 8px; font-weight: 700; color: var(--cq-warn-fg); }
.cq-redlink { color: var(--cq-crit-fg); font-weight: 600; text-decoration: underline; }
.cq-linkbtn { display: inline-flex; align-items: center; text-decoration: none; color: var(--cq-ink); }
'''
def norm(l): return re.sub(r'\s+',' ',l.strip())
SHARED=set()
for src in (ADD, open('cqStyles/cqStyles.css').read()):
    for l in src.split('\n'):
        if re.match(r'^\.cq-[^{]*\{.*\}\s*$',l): SHARED.add(norm(l))
H=[('opts','cq-opts'),('nowrap','cq-nowrap'),('whyv','cq-ai-says'),('rk','cq-sub')]
GL=[('pcard','cq-pcard'),('prob','cq-prob'),('top8','cq-mt16')]
IT=[('recur','cq-recur'),('recur-head','cq-recur-head'),('redlink','cq-redlink'),('linkbtn','cq-linkbtn')]
FC=[('fromcard','cq-fromcard'),('spin','cq-spin'),('spinwrap','cq-spinwrap')]
DC=[('dname','cq-dcard-name'),('dstate','cq-dcard-state'),('dsug','cq-dcard-sug'),('dchips','cq-dcard-chips')]
FA=[('col','cq-col'),('fn','cq-stack'),('krow','cq-krow'),('para','cq-para'),('big','cq-big'),('top14','cq-mt14')]
SC=[('card','cq-stepcard'),('ch','cq-stepcard-head'),('cn','cq-stepcard-n'),('ct','cq-stepcard-title'),('tot','cq-stepcard-tot')]
PL=[('mut','cq-muted'),('dotsep','cq-dotsep'),('ploc','cq-ploc')]
CFG={
 'cqDispositionWorkspace': dict(m=GL, cols='plain'),
 'cqInvestigationWorkspace': dict(m=GL+IT+FC, cols='plain'),
 'cqInvestigationCause': dict(m=FC),
 'cqTriageAssistant': dict(m=H+[('col','cq-col'),('know','cq-know'),('restart','cq-restart'),('top8','cq-mt16')]+DC+IT, drop=['.cq-msg.errbox { margin-top: 12px; }']),
 'cqFieldActionReview': dict(m=DC),
 'cqFieldActionWorkspace': dict(m=[('opts','cq-opts'),('rk','cq-sub')]+FA+[('know','cq-know'),('restart','cq-restart')], cols='top', drop=['.cq-msg.errbox { margin-top: 12px; }']),
 'cqFieldActionManager': dict(m=FA+PL, cols='top'),
 'cqFieldActionStrategy': dict(m=PL),
 'cqFieldActionClosure': dict(m=SC),
 'cqFieldActionRecovery': dict(m=SC),
}
def run(c):
    cfg=CFG[c]; m=dict(cfg['m']); cols=cfg.get('cols')
    h=open(f'{c}/{c}.html').read(); js=open(f'{c}/{c}.js').read(); css=open(f'{c}/{c}.css').read()
    for k in list(m):
        if re.search(r"['\" ]%s['\" ]"%re.escape(k),js): print('  JS uses',k,'-> skipped'); m.pop(k)
    if cols and re.search(r"['\" ]cols['\" ]",js): print('  JS uses cols'); cols=None
    def fix(mm):
        t=mm.group(1).split(); out=[]
        hascols='cols' in t and cols
        for x in t:
            if hascols and x=='cols': out+= ['cq-cols']+(['top'] if cols=='top' else [])
            elif hascols and x=='wide': out.append('wide32' if cols=='top' else 'wide')
            else: out.append(m.get(x,x))
        return 'class="%s"'%' '.join(out)
    h2=re.sub(r'class="([^"{}]*)"',fix,h)
    out=[]; dropped=0
    for l in css.split('\n'):
        s=norm(l)
        if s in cfg.get('drop',[]): dropped+=1; continue
        if cols and (s.startswith('.cols {') or s.startswith('.cols.wide {')): dropped+=1; continue
        if cols and s=='@media (max-width: 760px) { .cols, .cols.wide { grid-template-columns: 1fr; } }': continue
        if cols: l=l.replace('{ .cols, .cols.wide, ','{ ')
        mm=re.match(r'^(\s*)([^@/{}][^{}]*?)(\s*\{.*)$',l)
        if mm:
            sel=re.sub(r'\.([a-z][a-z0-9-]*)',lambda x:'.'+m.get(x.group(1),x.group(1)),mm.group(2))
            l=mm.group(1)+sel+mm.group(3)
            if norm(l) in SHARED: dropped+=1; continue
        out.append(l)
    if cols: assert '.cols' not in '\n'.join(out), [x for x in out if '.cols' in x]
    open(f'{c}/{c}.html','w').write(h2); open(f'{c}/{c}.css','w').write('\n'.join(out))
    print(c,'dropped',dropped,'rules now',sum(1 for l in out if '{' in l),'html lines changed',sum(1 for a,b in zip(h.split('\n'),h2.split('\n')) if a!=b))
if __name__=='__main__':
    if sys.argv[1]=='styles':
        p='cqStyles/cqStyles.css'; s=open(p).read().rstrip('\n')+'\n'+ADD; open(p,'w').write(s); print('cqStyles rules',s.count('{'))
    else:
        for c in sys.argv[1:]: run(c)
