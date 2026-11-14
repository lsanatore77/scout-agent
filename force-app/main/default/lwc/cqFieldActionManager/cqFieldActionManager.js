import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqFieldActionScope.getView';
import getGenealogy from '@salesforce/apex/CqFieldActionScope.genealogy';
import setLot from '@salesforce/apex/CqFieldActionScope.setLot';
import confirmScope from '@salesforce/apex/CqFieldActionScope.confirmScope';
import discardChanges from '@salesforce/apex/CqFieldActionScope.discardChanges';
import saveLot from '@salesforce/apex/CqFieldActionScope.saveLot';
import railStatus from '@salesforce/apex/CqFieldActionRecovery.railStatus';

// The seven steps of a field action. Notifications and Regulatory Report are set aside for later and do not block.
const STEPS = [
    { label: 'Field Action at a Glance', ready: true },
    { label: 'Scope', ready: true },
    { label: 'Strategy', ready: true, needsScope: true },
    { label: 'Notifications', ready: false, later: true },
    { label: 'Regulatory Report', ready: false, later: true },
    { label: 'Recovery and Effectiveness', ready: true },
    { label: 'Closure', ready: true }
];
const SCOPE = 1;
const STRATEGY = 2;
const RECOVERY = 5;
const CLOSURE = 6;
const TRACE = {
    Verified: { mark: '✔ ', cls: 'tr ok' },
    NC: { mark: '✖ ', cls: 'tr bad' },
    'No lot recorded': { mark: '⚠ ', cls: 'tr warn' },
    'No approved supplier': { mark: '⚠ ', cls: 'tr warn' },
    'CoC missing': { mark: '⚠ ', cls: 'tr warn' },
    'CoC expired': { mark: '⚠ ', cls: 'tr warn' }
};

/** Field Action workspace: the coordinator's steps from what was decided through closure. */
export default class CqFieldActionManager extends NavigationMixin(LightningElement) {
    @api recordId;
    v;
    error;
    saving = false;
    step = 0;
    // scope step
    view = 'all';        // all | in
    open = {};           // row key -> expanded
    gens = {};           // lot -> genealogy from its batch record
    loading = {};        // lot -> genealogy being read
    ticking = {};        // lot -> tick being saved
    edits = {};          // lot row id -> { shipped, onHand, location } being typed
    editing = '';        // the lot row whose shipped, on hand and location are open for editing

    rail = {};           // strategy, recovery, verdict and status for the later steps

    async connectedCallback() {
        try { this.apply(await getView({ recordId: this.recordId })); this.openInScope(); }
        catch (e) { this.error = this.msg(e, 'Could not read this field action.'); }
        await this.loadRail();
    }
    async loadRail() {
        try { this.rail = await railStatus({ recordId: this.recordId }); } catch (e) { /* the rail falls back to what is known */ }
    }
    /** The lots in scope open straight away, so what they were built from shows without a click. */
    openInScope() {
        this.lots.filter((l) => l.inScope && l.known).forEach((l) => { if (!this.open[l.name]) { this.toggleLot(l.name, true); } });
    }
    get anyOpen() { return Object.values(this.open).some(Boolean); }
    get allChev() { return this.anyOpen ? '▾' : '▸'; }
    get allLabel() { return this.anyOpen ? 'Collapse all' : 'Expand the lots in scope'; }
    get allExpanded() { return this.anyOpen ? 'true' : 'false'; }
    handleAll() { if (this.anyOpen) { this.open = {}; } else { this.openInScope(); } }
    msg(e, fallback) { return (e && e.body && e.body.message) || fallback; }
    apply(v) { this.v = JSON.parse(JSON.stringify(v)); }
    get ready() { return !!this.v; }
    dash(x) { return x === undefined || x === null || x === '' ? '—' : String(x); }
    day(d) { return d ? new Date(d).toLocaleDateString() : ''; }
    when(d) { return d ? new Date(d).toLocaleString() : ''; }
    num(x) { return x === undefined || x === null ? '—' : String(Number(x)); }

    // ---- header
    get partText() { return this.dash(this.v.partNumber); }
    get scopeText() { return this.v.scope ? this.v.scope + ' · ' + this.stateText : 'Not set'; }
    get classText() { return this.dash(this.v.recallClass); }
    handleEdit() {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: this.recordId, objectApiName: 'Field_Action__c', actionName: 'edit' } });
    }
    async handleRefresh() {
        try { this.apply(await getView({ recordId: this.recordId })); this.error = undefined; this.gens = {}; this.edits = {}; this.open = {}; this.openInScope(); }
        catch (e) { this.error = this.msg(e, 'Could not refresh this field action.'); }
        await this.loadRail();
    }
    handleOpen(event) {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' } });
    }

    // ---- step rail
    get isFull() { return this.v.scope === 'Full'; }
    get isPartial() { return this.v.scope === 'Partial'; }
    get lots() { return this.v.lots || []; }
    get confirmedLots() { return this.lots.filter((l) => l.confirmed); }
    get draftLots() { return this.lots.filter((l) => l.inScope); }
    get pendingAdds() { return this.lots.filter((l) => l.inScope && !l.confirmed).length; }
    get pendingRemoves() { return this.lots.filter((l) => !l.inScope && l.confirmed).length; }
    get pending() { return this.pendingAdds + this.pendingRemoves; }
    get scopeConfirmed() { return this.isFull || (this.v.scopeStatus === 'Confirmed' && this.pending === 0); }
    get stateText() {
        if (this.isFull) { return 'Full Scope'; }
        return this.scopeConfirmed ? 'Confirmed' : this.v.scope ? 'Being Defined' : 'Not set';
    }
    get steps() {
        const n = this.isFull ? this.draftLots.length : this.confirmedLots.length;
        const lotsText = n + ' lot' + (n === 1 ? '' : 's');
        const subs = [
            this.v.actionType ? this.v.actionType + (this.v.recallClass ? ' · ' + this.v.recallClass : '') : 'Decided',
            this.v.scope ? this.stateText + ' · ' + lotsText : 'Scope not set'
        ];
        return STEPS.map((s, i) => {
            const done = !s.later && this.isDone(i);
            const sub = i < 2 ? subs[i] : s.later ? 'Later' : this.subOf(i);
            return { i, n: s.later ? '–' : i + 1, label: s.label, sub, done, notDone: !done, locked: this.isLocked(i),
                cls: 'step' + (i === this.step ? ' active' : '') + (done ? ' done' : '') + (s.later ? ' later' : '') };
        });
    }
    get strategyDone() { return this.scopeConfirmed && this.v.strategyStatus === 'Confirmed'; }
    get recoveryDone() { return this.strategyDone && this.rail.recovery === 'Confirmed'; }
    get isClosed() { return this.v.status === 'Closed'; }
    isDone(i) {
        if (i === 0) { return true; }
        if (i === SCOPE) { return this.scopeConfirmed; }
        if (i === STRATEGY) { return this.strategyDone; }
        if (i === RECOVERY) { return this.recoveryDone; }
        if (i === CLOSURE) { return this.isClosed; }
        return false;
    }
    subOf(i) {
        if (i === STRATEGY) { return !this.scopeConfirmed ? 'Needs confirmed scope' : this.v.strategyStatus || 'Not started'; }
        if (i === RECOVERY) {
            if (!this.strategyDone) { return 'Needs confirmed strategy'; }
            return this.rail.recovery === 'Confirmed' ? 'Effective' : this.rail.verdict === 'Not Effective' ? 'Not Effective' : 'In progress';
        }
        if (i === CLOSURE) { return this.isClosed ? 'Closed' : this.recoveryDone ? 'Ready to close' : 'Needs an effective verdict'; }
        return '';
    }
    isLocked(i) {
        const s = STEPS[i];
        if (!s.ready || s.later) { return true; }
        if (i === STRATEGY) { return !this.scopeConfirmed; }
        if (i === RECOVERY) { return !this.strategyDone; }
        if (i === CLOSURE) { return !this.recoveryDone && !this.isClosed; }
        return false;
    }
    /** The next or previous step that is not set aside for later. */
    near(dir) {
        for (let i = this.step + dir; i >= 0 && i < STEPS.length; i += dir) { if (!STEPS[i].later) { return i; } }
        return -1;
    }
    get progress() { return this.steps.filter((s) => s.done).length + ' of ' + STEPS.length + ' steps complete'; }
    handleStep(event) { const i = Number(event.currentTarget.dataset.i); if (!this.isLocked(i)) { this.go(i); } }
    go(i) { this.step = i; this.error = undefined; this.foot = { show: false, label: '', disabled: true, blocker: '' }; }
    get is0() { return this.ready && this.step === 0; }
    get is1() { return this.ready && this.step === SCOPE; }
    get is2() { return this.ready && this.step === STRATEGY; }
    get is5() { return this.ready && this.step === RECOVERY; }
    get is6() { return this.ready && this.step === CLOSURE; }
    get cantBack() { return this.near(-1) < 0; }
    get cantNext() { const i = this.near(1); return i < 0 || this.isLocked(i); }
    handleBack() { const i = this.near(-1); if (i >= 0) { this.go(i); } }
    handleNext() { if (!this.cantNext) { this.go(this.near(1)); } }
    // A step's own confirm button (Confirm Strategy, Confirm Verdict, Close Field Action) lives in the footer before Back and Next
    foot = { show: false, label: '', disabled: true, blocker: '' };
    handleFootChange(event) { this.foot = event.detail; }
    get showStepAction() { return (this.is2 || this.is5 || this.is6) && this.foot.show; }
    get nextCls() { return this.showStepAction ? 'btn' : 'btn primary'; }
    handleStepAction() {
        const s = this.template.querySelector('[data-step]');
        if (s) { s.confirm(); }
    }
    /** The Strategy step reports its status and the action, which also shows in the header. */
    handleStrategyChange(event) {
        const { status, action } = event.detail;
        if (this.v.strategyStatus !== status || (action && this.v.actionType !== action)) {
            this.v = { ...this.v, strategyStatus: status, actionType: action || this.v.actionType };
        }
    }
    /** Recovery and Closure report the verdict and the field action's status for the rail and the header. */
    handleRailChange(event) {
        const { recovery, verdict, status } = event.detail;
        this.rail = { ...this.rail, recovery, verdict, status };
        if (status && this.v.status !== status) { this.v = { ...this.v, status }; }
    }

    // ---- step 1: at a glance
    get tiles() {
        const rows = this.isFull ? this.draftLots : this.confirmedLots;
        const sum = (k) => rows.reduce((t, l) => t + (l[k] ? Number(l[k]) : 0), 0);
        const shipped = sum('shipped');
        return [
            ['Lots in scope', String(rows.length)],
            ['Units built', rows.some((l) => l.built) ? String(sum('built')) : '—'],
            ['Units shipped', shipped ? String(shipped) : this.dash(this.v.qtyShipped)],
            ['Risk', this.v.score !== undefined && this.v.score !== null ? (this.v.riskLevel || '') + ' · ' + this.v.score + ' of 100' : this.dash(this.v.riskLevel)]
        ].map(([label, value]) => ({ key: label, label, value }));
    }
    get decidedLine() {
        const v = this.v;
        return ['Decided' + (v.decidedBy ? ' by ' + v.decidedBy : ''), this.day(v.decidedOn)].filter(Boolean).join(' · ');
    }
    get reviews() {
        return (this.v.reviews || []).map((r) => ({
            ...r,
            meta: [r.source, r.lot ? 'lot ' + r.lot : '', r.risk ? r.risk + (r.score !== undefined && r.score !== null ? ' · ' + r.score : '') : '', this.day(r.decidedOn)].filter(Boolean).join(' · '),
            approval: r.approvalName ? r.approvalName + (r.emergency ? ' · emergency approval' : '') + (r.approvedBy ? ' · approved by ' + r.approvedBy : '') : 'Decided before committee approval was in place'
        }));
    }
    get hasReviews() { return this.reviews.length > 0; }
    get signals() {
        return (this.v.signals || []).map((s) => ({ ...s, pillCls: 'spill ' + (s.strength || '').toLowerCase(), where: s.lot ? 'lot ' + s.lot : 'whole part' }));
    }
    get hasSignals() { return this.signals.length > 0; }
    goScope() { this.step = SCOPE; }

    // ---- step 2: scope
    get scopePill() { return 'spill ' + (this.isFull ? 'full' : 'partial'); }
    get statePill() { return 'spill state' + (this.scopeConfirmed ? ' ok' : this.v.scope ? ' wait' : ''); }
    get scopeIntro() {
        if (this.isFull) { return 'Full scope covers every lot of ' + this.partText + '. Any lot found later is added automatically and logged below. Expand a lot to see what it was built from.'; }
        if (this.isPartial) { return 'Tick the lots this field action covers. Each tick is saved as a draft straight away; the scope counts once you confirm it. Expand a lot to see what it was built from and where those component lots were used.'; }
        return 'This field action has no scope set. It was decided before scope was part of the review.';
    }
    get canChange() { return this.isPartial && this.v.status !== 'Closed'; }
    get allTab() { return 'tog' + (this.view === 'all' ? ' on' : ''); }
    get inTab() { return 'tog' + (this.view === 'in' ? ' on' : ''); }
    get allPressed() { return this.view === 'all' ? 'true' : 'false'; }
    get inPressed() { return this.view === 'in' ? 'true' : 'false'; }
    handleView(event) { this.view = event.currentTarget.dataset.v; }
    get countLine() {
        const n = this.draftLots.length;
        return n + ' lot' + (n === 1 ? '' : 's') + ' in scope';
    }
    get pendingLine() {
        if (!this.isPartial) { return ''; }
        const parts = [];
        if (this.pendingAdds) { parts.push(this.pendingAdds + ' added'); }
        if (this.pendingRemoves) { parts.push(this.pendingRemoves + ' removed'); }
        if (parts.length) { return parts.join(', ') + ', not confirmed'; }
        if (this.v.scopeStatus === 'Confirmed') {
            return 'Confirmed' + (this.v.scopeConfirmedBy ? ' by ' + this.v.scopeConfirmedBy : '') + (this.v.scopeConfirmedOn ? ' · ' + this.when(this.v.scopeConfirmedOn) : '');
        }
        return 'Not confirmed yet';
    }
    get pendingCls() { return 'pendline' + (this.pending ? ' warn' : ''); }
    get busy() { return this.saving || Object.keys(this.ticking).length > 0; }
    get cantConfirm() { return this.busy || this.draftLots.length === 0 || this.scopeConfirmed; }
    get cantDiscard() { return this.busy || this.pending === 0; }
    get confirmLabel() { return this.saving ? 'Saving…' : this.scopeConfirmed ? 'Scope Confirmed' : 'Confirm Scope'; }
    get confirmHint() {
        if (this.scopeConfirmed) { return 'Strategy and the steps after it work from this lot list.'; }
        return this.draftLots.length ? 'Confirming the lot list opens Strategy.' : 'Tick at least one lot.';
    }

    /** The nested table: each lot, and when expanded what it was built from, level by level, with where-used rows. */
    get rows() {
        const out = [];
        const byName = new Map(this.lots.map((l) => [l.name, l]));
        // lots in scope, then CQ.AI suggestions, then lots with a lot record, then lot numbers found only on records
        const rank = (l) => (l.inScope || l.confirmed ? 0 : l.suggested ? 1 : l.known ? 2 : 3);
        const shown = (this.view === 'in' ? this.lots.filter((l) => l.inScope || l.confirmed) : this.lots)
            .map((l, i) => ({ l, i })).sort((a, b) => rank(a.l) - rank(b.l) || a.i - b.i).map((x) => x.l);
        shown.forEach((l) => {
            const key = l.name;
            const isOpen = !!this.open[key];
            out.push(this.lotRow(l, key, 0, isOpen, false));
            if (!isOpen) { return; }
            const g = this.gens[l.name];
            if (this.loading[l.name]) { out.push(this.noteRow(key + '|wait', 1, 'Reading the batch record…')); return; }
            if (!g) { return; }
            if (g.note) { out.push(this.noteRow(key + '|note', 1, g.note)); return; }
            const nodes = g.rows || [];
            const kids = new Map();
            nodes.forEach((n) => { const p = n.parentKey || '_'; if (!kids.has(p)) { kids.set(p, []); } kids.get(p).push(n); });
            const walk = (parent, depth) => {
                (kids.get(parent) || []).forEach((n) => {
                    const nk = key + '|' + n.key;
                    const used = (n.usedIn || []);
                    const hasKids = kids.has(n.key) || used.length > 0;
                    const nOpen = !!this.open[nk];
                    out.push(this.nodeRow(n, nk, depth, hasKids, nOpen, l, g));
                    if (!nOpen) { return; }
                    walk(n.key, depth + 1);
                    used.forEach((u, i) => {
                        const sister = u.samePart ? byName.get(u.lot) : null;
                        out.push(sister ? this.lotRow(sister, nk + '|u' + i, depth + 1, false, n.lot)
                            : this.noteRow(nk + '|u' + i, depth + 1, 'Also used in lot ' + u.lot + (u.part ? ' (' + u.part + ')' : '') + ', a different product'));
                    });
                });
            };
            walk('_', 1);
            if (!nodes.length) { out.push(this.noteRow(key + '|none', 1, 'No components recorded.')); }
        });
        return out;
    }
    indent(depth) { return 'width:' + (depth * 1.25) + 'rem'; }
    lotRow(l, key, depth, isOpen, sharedLot) {
        const removing = !l.inScope && l.confirmed;
        const pendingAdd = this.isPartial && l.inScope && !l.confirmed;
        const e = (l.id && this.edits[l.id]) || {};
        const where = sharedLot !== false;
        const traceText = l.records ? l.records + ' record' + (l.records === 1 ? '' : 's') + (l.signals ? ' · ' + l.signals + ' signal' + (l.signals === 1 ? '' : 's') : '') : 'No records';
        return {
            key, isLot: true, isNode: false, isNote: false,
            rowCls: 'r0' + (where ? ' wu' : l.inScope ? ' in' : l.suggested ? ' sug' : ''),
            indentStyle: this.indent(depth),
            hasKids: !where && !!l.known, noKids: where || !l.known, chev: isOpen ? '▾' : '▸', openText: isOpen ? 'true' : 'false',
            toggleLabel: (isOpen ? 'Collapse lot ' : 'Expand lot ') + l.name,
            item: where ? 'Where used · Lot ' + l.name : 'Lot ' + l.name, itemCls: where ? 'it wu' : 'it lot',
            partRev: this.partText + (this.gens[l.name] && this.gens[l.name].revision ? ' · Rev ' + this.gens[l.name].revision : ''),
            lot: l.name, qty: l.built !== undefined && l.built !== null ? this.num(l.built) + ' built' : '—', supplier: '—',
            trace: where ? 'Shares ' + sharedLot : (l.records ? '⚠ ' : '✔ ') + traceText,
            traceCls: where || l.records ? 'tr warn' : 'tr ok',
            name: l.name,
            showCheck: this.isPartial, checked: l.inScope, checkDisabled: !this.canChange || l.locked || !!this.ticking[l.name],
            checkLabel: (l.inScope ? 'Take lot ' : 'Put lot ') + l.name + (l.inScope ? ' out of scope' : ' in scope'),
            added: l.inScope, addedTitle: l.locked ? (l.reason || 'Came in with the review decision') : l.how === 'Coordinator' ? 'Ticked by the coordinator' : (l.reason || ''),
            pendingAdd, removing,
            suggested: !l.inScope && !removing && !!l.suggested, why: l.why,
            editable: !where && l.inScope && !!l.id, rowId: l.id,
            isEditing: !!l.id && this.editing === l.id, notEditing: !(l.id && this.editing === l.id),
            shippedVal: e.shipped !== undefined ? e.shipped : l.shipped, onHandVal: e.onHand !== undefined ? e.onHand : l.onHand,
            locVal: e.location !== undefined ? e.location : l.location || '',
            shippedText: this.num(l.shipped), onHandText: this.num(l.onHand), locText: l.location || '—',
            editLabel: 'Edit shipped, on hand and location for lot ' + l.name
        };
    }
    nodeRow(n, key, depth, hasKids, isOpen, lot, g) {
        const t = TRACE[n.trace] || { mark: '', cls: 'tr' };
        const sharedCount = (n.usedIn || []).length;
        const traceText = n.trace === 'NC' ? 'NC' + (n.ncNumber ? ' · ' + n.ncNumber : '') : n.trace || '—';
        return {
            key, isLot: false, isNode: true, isNote: false,
            rowCls: 'r' + Math.min(depth, 3),
            indentStyle: this.indent(depth),
            hasKids, noKids: !hasKids, chev: isOpen ? '▾' : '▸', openText: isOpen ? 'true' : 'false',
            toggleLabel: (isOpen ? 'Collapse ' : 'Expand ') + (n.name || n.partNumber),
            item: 'L' + n.level + ' · ' + (n.name || n.partNumber || ''),
            itemCls: 'it' + (n.itemType === 'Sub-assembly' ? ' sub' : ''),
            partRev: [n.partNumber, n.revision ? 'Rev ' + n.revision : ''].filter(Boolean).join(' · '),
            lot: this.dash(n.lot), qty: this.num(n.qtyUsed), supplier: this.dash(n.supplier),
            trace: t.mark + traceText + (sharedCount ? ' · used in ' + sharedCount + ' other lot' + (sharedCount === 1 ? '' : 's') : ''),
            traceCls: sharedCount && t.cls === 'tr ok' ? 'tr warn' : t.cls,
            covered: lot.inScope, coveredTitle: 'Comes with lot ' + lot.name + (g.batch ? ' (batch ' + g.batch + ')' : '')
        };
    }
    noteRow(key, depth, text) {
        return { key, isLot: false, isNode: false, isNote: true, rowCls: 'rnote', indentStyle: this.indent(depth), text };
    }

    handleToggle(event) {
        const key = event.currentTarget.dataset.key;
        this.toggleLot(key, !this.open[key]);
    }
    async toggleLot(key, isOpen) {
        this.open = { ...this.open, [key]: isOpen };
        if (!isOpen || key.includes('|')) { return; }
        const lot = key;
        if (this.gens[lot] || this.loading[lot]) { return; }
        this.loading = { ...this.loading, [lot]: true };
        try {
            const g = await getGenealogy({ recordId: this.recordId, lot });
            this.gens = { ...this.gens, [lot]: g };
        } catch (e) { this.error = this.msg(e, 'Could not read the genealogy.'); }
        const l = { ...this.loading }; delete l[lot]; this.loading = l;
    }

    /** A tick is saved straight away as a draft. The screen changes first; it goes back if the save fails. */
    async handleTick(event) {
        const name = event.target.dataset.name;
        const add = event.target.checked;
        const before = this.lots.find((l) => l.name === name);
        if (!before || this.ticking[name]) { return; }
        this.error = undefined;
        this.patchLot(name, { inScope: add });
        this.ticking = { ...this.ticking, [name]: true };
        try {
            const id = await setLot({ recordId: this.recordId, lot: name, add });
            this.patchLot(name, { id: id || undefined, how: before.how || (add ? 'Coordinator' : before.how) });
            if (this.v.scopeStatus !== 'Being Defined') { this.v = { ...this.v, scopeStatus: 'Being Defined' }; }
        } catch (e) {
            this.patchLot(name, { inScope: before.inScope });
            this.error = this.msg(e, 'Could not save that tick.');
        }
        const t = { ...this.ticking }; delete t[name]; this.ticking = t;
    }
    patchLot(name, change) {
        this.v = { ...this.v, lots: this.lots.map((l) => (l.name === name ? { ...l, ...change } : l)) };
    }

    async handleConfirm() {
        if (this.cantConfirm) { return; }
        await this.run(() => confirmScope({ recordId: this.recordId }));
    }
    async handleDiscard() {
        if (this.cantDiscard) { return; }
        await this.run(() => discardChanges({ recordId: this.recordId }));
    }

    handleQty(event) {
        const id = event.target.dataset.id; const f = event.target.dataset.f;
        const cur = { ...(this.edits[id] || {}) };
        cur[f] = f === 'location' ? event.target.value : event.target.value === '' ? null : Number(event.target.value);
        this.edits = { ...this.edits, [id]: cur };
    }
    handleStartEdit(event) {
        const id = event.currentTarget.dataset.id;
        if (this.editing && this.editing !== id) { const x = { ...this.edits }; delete x[this.editing]; this.edits = x; }
        this.editing = id;
    }
    handleCancelEdit() {
        const x = { ...this.edits }; delete x[this.editing]; this.edits = x;
        this.editing = '';
    }
    async handleSaveLot(event) {
        const id = event.currentTarget.dataset.id;
        const row = this.lots.find((l) => l.id === id);
        const e = this.edits[id] || {};
        await this.run(() => saveLot({ recordId: this.recordId, rowId: id,
            shipped: e.shipped !== undefined ? e.shipped : row.shipped, onHand: e.onHand !== undefined ? e.onHand : row.onHand,
            location: e.location !== undefined ? e.location : row.location }), () => { const x = { ...this.edits }; delete x[id]; this.edits = x; this.editing = ''; });
    }
    async run(call, after) {
        if (this.saving) { return; }
        this.saving = true; this.error = undefined;
        try {
            this.apply(await call());
            if (after) { after(); }
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (e) { this.error = this.msg(e, 'Could not save that.'); }
        this.saving = false;
    }

    // change log
    get changes() {
        return (this.v.changes || []).map((c, i) => ({ ...c, key: 'c' + i, at: this.when(c.doneAt),
            line: c.change + ' lot ' + c.lot + (c.reason ? ': ' + c.reason : ''), by: c.how === 'Automatic' ? 'Automatic' : c.doneBy }));
    }
    get hasChanges() { return this.changes.length > 0; }
    get hasLots() { return this.lots.length > 0; }
}
