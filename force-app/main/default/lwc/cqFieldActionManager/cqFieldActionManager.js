import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqFieldActionScope.getView';
import getGenealogy from '@salesforce/apex/CqFieldActionScope.genealogy';
import setLot from '@salesforce/apex/CqFieldActionScope.setLot';
import confirmScope from '@salesforce/apex/CqFieldActionScope.confirmScope';
import discardChanges from '@salesforce/apex/CqFieldActionScope.discardChanges';
import forScope from '@salesforce/apex/CqLotStock.forScope';
import railStatus from '@salesforce/apex/CqFieldActionRecovery.railStatus';
import notifyCounts from '@salesforce/apex/CqFieldActionNotify.counts';
import { sortRows, nextSort, heads } from 'c/cqSort';

// The seven steps of a field action. Regulatory Report is set aside for later and does not block.
const SMALL_WORDS = new Set(['a', 'an', 'the', 'and', 'or', 'of', 'on', 'in', 'to', 'at', 'for', 'is', 'by', 'per', 'with']);
/**
 * Title Case for short label lines that are not sentences (styling guide): every word capitalised except the small
 * words, unless one starts the line or follows ". " or "· ". Record numbers, dates and figures stay as written.
 * "11 complaints. Normal is 1.5 complaints per 90 days." -> "11 Complaints. Normal is 1.5 Complaints per 90 Days."
 */
function titleCase(text) {
    if (!text) { return text; }
    return String(text).replace(/[A-Za-z][A-Za-z']*/g, (w, i, all) => {
        const before = all.slice(0, i);
        const start = /^\s*$/.test(before) || /[.·:(]\s*$/.test(before);   // first word, or first after . · : (
        if (!start && SMALL_WORDS.has(w.toLowerCase())) { return w.toLowerCase(); }
        return w.charAt(0).toUpperCase() + w.slice(1);
    });
}
const STEPS = [
    { label: 'Field Action at a Glance', ready: true },
    { label: 'Scope', ready: true },
    { label: 'Strategy', ready: true, needsScope: true },
    { label: 'Notifications', ready: true },
    { label: 'Regulatory Report', ready: false, later: true },
    { label: 'Recovery and Effectiveness', ready: true },
    { label: 'Closure', ready: true }
];
const ASK = {
    0: 'Summarize this field action,Where does this field action stand?,What is left on this field action?',
    1: 'Which lots are in scope?,Why does CQ.AI suggest these lots?,How much stock is on hand?',
    2: 'Why does CQ.AI suggest this action type?,Which lots are on hold?,What does the effectiveness level mean?',
    3: 'Which customers have not replied?,Who has not been sent the notice?,Which lots have units nobody can account for?',
    5: 'Which customers have not responded?,Are we on track for the effectiveness target?,How many units are still in the field?',
    6: 'What is blocking closure?,Summarize this field action,What is left on this field action?'
};
const SCOPE = 1;
const STRATEGY = 2;
const NOTIFY = 3;
const RECOVERY = 5;
const CLOSURE = 6;
/** A step's "Go to" link (Closure's checklist) names the step it opens. */
const STEP_KEYS = { scope: SCOPE, strategy: STRATEGY, notifications: NOTIFY, recovery: RECOVERY, closure: CLOSURE };
const PAGE = 10;   // lots per page in the scope table
const SIG_PAGE = 5; // signals per page on the glance, as on Field Action Review
/** Page links: all of them up to 7 pages, otherwise the first, the last and two either side of the current one, with … for gaps. */
function pageLinks(n, cur) {
    const keep = [];
    for (let i = 0; i < n; i++) { if (n <= 7 || i === 0 || i === n - 1 || Math.abs(i - cur) <= 2) { keep.push(i); } }
    const out = [];
    keep.forEach((i, k) => {
        if (k > 0 && i - keep[k - 1] > 1) { out.push({ key: 'g' + i, text: '…', cls: 'pg gap', off: true, label: 'More pages' }); }
        const on = i === cur;
        out.push({ key: 'p' + i, p: i, text: String(i + 1), cls: 'pg' + (on ? ' on' : ''), off: on, current: on ? 'page' : 'false',
            label: 'Page ' + (i + 1) });
    });
    return out;
}
/** Trace marks are plain text in the row's colour (green, amber, red): no emoji, which some browsers draw in their own colours. */
const TRACE = {
    Verified: { mark: '✓ ', cls: 'cq-marktext ok' },
    NC: { mark: '✕ ', cls: 'cq-marktext bad' },
    'No lot recorded': { mark: '! ', cls: 'cq-marktext warn' },
    'No approved supplier': { mark: '! ', cls: 'cq-marktext warn' },
    'CoC missing': { mark: '! ', cls: 'cq-marktext warn' },
    'CoC expired': { mark: '! ', cls: 'cq-marktext warn' }
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
    stock = {};          // lot -> shipped, on hand and where, from Lot Shipment and Lot Stock (read-only)
    stockOpen = '';      // the row whose on-hand split is showing

    rail = {};           // strategy, recovery, verdict and status for the later steps
    notify = {};         // customers, notified and responded, for the Notifications step's line in the rail

    async connectedCallback() {
        // the On Hand card closes on any click outside it, or on Escape
        this.closePop = () => { if (this.keepPop) { this.keepPop = false; } else if (this.stockOpen) { this.stockOpen = ''; } };
        this.escPop = (e) => { if (e.key === 'Escape' && this.stockOpen) { this.stockOpen = ''; } };
        document.addEventListener('click', this.closePop);
        document.addEventListener('keydown', this.escPop);
        this.template.addEventListener('gostep', (event) => {
            const i = STEP_KEYS[event.detail && event.detail.step];
            if (i !== undefined && !this.isLocked(i)) { this.go(i); }
        });
        try { this.apply(await getView({ recordId: this.recordId })); }
        catch (e) { this.error = this.msg(e, 'Could not read this field action.'); }
        await this.loadRail();
        await this.loadStock();
    }
    disconnectedCallback() {
        document.removeEventListener('click', this.closePop);
        document.removeEventListener('keydown', this.escPop);
    }
    async loadStock() {
        if (!this.v) { return; }
        try { this.stock = await forScope({ lots: this.lots.map((l) => l.name) }); } catch (e) { /* the columns show dashes */ }
    }
    async loadRail() {
        try { this.rail = await railStatus({ recordId: this.recordId }); } catch (e) { /* the rail falls back to what is known */ }
        try { this.notify = await notifyCounts({ recordId: this.recordId }); } catch (e) { /* the rail falls back to what is known */ }
    }
    /** Every lot starts closed; the header chevron opens the lots in scope. */
    openInScope() {
        this.lots.filter((l) => l.inScope && l.known).forEach((l) => { if (!this.open[l.name]) { this.toggleLot(l.name, true); } });
    }
    get anyOpen() { return Object.values(this.open).some(Boolean); }
    get allChev() { return this.anyOpen ? '▾' : '▸'; }
    get allLabel() { return this.anyOpen ? 'Collapse All' : 'Expand the Lots in Scope'; }
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
    handleOpen(event) { this.openRecord(event.currentTarget.dataset.id); }
    /** The shared frame (c-cq-ws-shell) reports a header link as open, with the record id. */
    handleShellOpen(event) { this.openRecord(event.detail); }
    openRecord(id) {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, actionName: 'view' } });
    }
    /** The header fields the shared frame draws. */
    get headerFields() {
        return [
            { key: 'part', label: 'Part', value: this.partText },
            { key: 'type', label: 'Action Type', value: this.v.actionType },
            { key: 'class', label: 'Recall Class', value: this.classText },
            { key: 'scope', label: 'Scope', value: this.scopeText },
            { key: 'status', label: 'Status', value: this.v.status }
        ];
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
            const alert = i === RECOVERY && this.strategyDone && !this.isClosed && this.overdueTasks > 0;
            return { i, n: s.later ? '–' : i + 1, label: s.label, sub, done, notDone: !done, locked: this.isLocked(i),
                subCls: 'ssub' + (alert ? ' alert' : ''),
                cls: 'step' + (i === this.step ? ' active' : '') + (done ? ' done' : '') + (s.later ? ' later' : '') };
        });
    }
    get strategyDone() { return this.scopeConfirmed && this.v.strategyStatus === 'Confirmed'; }
    get recoveryDone() { return this.strategyDone && this.rail.recovery === 'Confirmed'; }
    get isClosed() { return this.v.status === 'Closed'; }
    get overdueTasks() { return Number(this.rail.overdue || 0); }
    isDone(i) {
        if (i === 0) { return true; }
        if (i === SCOPE) { return this.scopeConfirmed; }
        if (i === STRATEGY) { return this.strategyDone; }
        if (i === NOTIFY) { return this.strategyDone && this.notify.total > 0 && this.notify.settled === this.notify.total; }   // everyone submitted to Recovery or closed without a response
        if (i === RECOVERY) { return this.recoveryDone; }
        if (i === CLOSURE) { return this.isClosed; }
        return false;
    }
    subOf(i) {
        if (i === STRATEGY) { return !this.scopeConfirmed ? 'Needs confirmed scope' : this.v.strategyStatus || 'Not started'; }
        if (i === NOTIFY) {
            if (!this.strategyDone) { return 'Needs confirmed strategy'; }
            const t = this.notify.total || 0;
            if (!t) { return 'No customers yet'; }
            return (this.notify.responded || 0) + ' of ' + t + ' acknowledged';
        }
        if (i === RECOVERY) {
            if (!this.strategyDone) { return 'Needs confirmed strategy'; }
            const over = this.overdueTasks;
            if (over > 0 && !this.isClosed) { return over + ' overdue task' + (over === 1 ? '' : 's'); }
            return this.rail.recovery === 'Confirmed' ? 'Effective' : this.rail.verdict === 'Not Effective' ? 'Not Effective' : 'In progress';
        }
        if (i === CLOSURE) { return this.isClosed ? 'Closed' : this.recoveryDone ? 'Ready to close' : 'Needs an effective verdict'; }
        return '';
    }
    /**
     * Any step that is built can be opened to look at. Each step's own confirm still waits for the one before it:
     * Strategy says to confirm the scope first, Recovery the strategy, and Closure lists the verdict as an open item.
     */
    isLocked(i) {
        const s = STEPS[i];
        return !s.ready || !!s.later;
    }
    /** The next or previous step that is not set aside for later. */
    near(dir) {
        for (let i = this.step + dir; i >= 0 && i < STEPS.length; i += dir) { if (!STEPS[i].later) { return i; } }
        return -1;
    }
    /** The rail as the shared frame draws it: a step set aside for later shows a dash and is greyed. */
    get railSteps() {
        return this.steps.map((s) => ({ label: s.label, sub: s.sub, done: s.done, active: s.i === this.step, locked: s.locked,
            mark: STEPS[s.i].later ? '\u2013' : undefined, later: !!STEPS[s.i].later, alert: s.subCls.includes('alert') }));
    }
    get progress() { return this.steps.filter((s) => s.done).length + ' of ' + STEPS.length + ' steps complete'; }
    handleStep(event) { const i = Number(event.detail); if (!this.isLocked(i)) { this.go(i); } }
    go(i) { this.step = i; this.error = undefined; this.foot = { show: false, label: '', disabled: true, blocker: '' }; }
    // ---- Ask CQ.AI: the Field Action agent, told which step is open, with ready questions for that step
    get askStep() { return STEPS[this.step] ? STEPS[this.step].label : ''; }
    get askSuggestions() { return ASK[this.step] || ASK[0]; }
    /** Ask CQ.AI's Create CAPA link: open Closure and create the CAPA there, so its progress and errors show on the step. */
    handleAskAction(event) {
        if (event.detail.name !== 'createCapa' || this.isLocked(CLOSURE)) { return; }
        this.go(CLOSURE);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { const s = this.template.querySelector('c-cq-field-action-closure'); if (s) { s.createCapa(); } }, 0);
    }
    get is0() { return this.ready && this.step === 0; }
    get is1() { return this.ready && this.step === SCOPE; }
    get is2() { return this.ready && this.step === STRATEGY; }
    get is3() { return this.ready && this.step === NOTIFY; }
    get is5() { return this.ready && this.step === RECOVERY; }
    get is6() { return this.ready && this.step === CLOSURE; }
    get cantBack() { return this.near(-1) < 0; }
    get cantNext() { const i = this.near(1); return i < 0 || this.isLocked(i); }
    // on Scope, Back and Next sit beside the scope buttons above the table (smaller buttons, a one-off for now)
    get showFoot() { return !this.is1 || !this.hasLots; }
    handleBack() { const i = this.near(-1); if (i >= 0) { this.go(i); } }
    handleNext() { if (!this.cantNext) { this.go(this.near(1)); } }
    // A step's own confirm button (Confirm Strategy, Submit Responses, Confirm Verdict, Close Field Action) lives in the footer before Back and Next
    foot = { show: false, label: '', disabled: true, blocker: '' };
    handleFootChange(event) { this.foot = event.detail; }
    get showStepAction() { return (this.is2 || this.is3 || this.is5 || this.is6) && this.foot.show; }
    get hasFootActs() { return this.showStepAction || (this.is1 && this.isPartial && this.hasLots); }
    get footBlocker() { return this.showStepAction ? this.foot.blocker : ''; }
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
    /** Notifications reports how many customers were notified and responded, for its line in the rail. */
    handleNotifyChange(event) { this.notify = { ...event.detail }; }
    /** Recovery and Closure report the verdict and the field action's status for the rail and the header. */
    handleRailChange(event) {
        const { recovery, verdict, status, overdue } = event.detail;
        this.rail = { ...this.rail, recovery, verdict, status, overdue: overdue === undefined ? this.rail.overdue : String(overdue) };
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
            meta: [r.source, r.lot ? 'Lot ' + r.lot : '', r.risk ? r.risk + (r.score !== undefined && r.score !== null ? ' · ' + r.score : '') : '', this.day(r.decidedOn)].filter(Boolean).join(' · '),
            approval: r.approvalName ? r.approvalName + (r.emergency ? ' · emergency approval' : '') + (r.approvedBy ? ' · approved by ' + r.approvedBy : '') : 'Decided before committee approval was in place'
        }));
    }
    get hasReviews() { return this.reviews.length > 0; }
    /** The reviews table: a row per review, and under it, once opened, the reason it gave. */
    openRev = {};
    // the glance tables sort on a heading click (c/cqSort); a review's reason travels with it
    revSort = {};
    sigSort = {};
    get revHeads() {
        return heads([{ key: 'open', label: 'Open', cls: 'chcol', sortable: false, hidden: true }, { key: 'name', label: 'Review' },
            { key: 'approval', label: 'Approval' }, { key: 'source', label: 'Source' }, { key: 'score', label: 'Risk' },
            { key: 'decidedOn', label: 'Decided' }], this.revSort).map((h) => ({ ...h, shown: h.plain && !h.hidden }));
    }
    get sigHeads() { return heads([{ key: 'rule', label: 'Signal' }, { key: 'label', label: 'What We See' }], this.sigSort); }
    handleRevSort(event) { this.revSort = nextSort(this.revSort, event.currentTarget.dataset.key); }
    handleSigSort(event) { this.sigSort = nextSort(this.sigSort, event.currentTarget.dataset.key); this.sigPage = 0; }
    get reviewRows() {
        const out = [];
        sortRows(this.reviews, this.revSort).forEach((r) => {
            const open = !!this.openRev[r.id];
            out.push({ ...r, key: r.id, isRev: true, expanded: open ? 'true' : 'false', chevCls: 'cq-rchev' + (open ? ' open' : ''),
                toggleLabel: (open ? 'Hide' : 'Show') + ' the reason for ' + r.name,
                lotText: r.lot || '', riskText: r.risk ? r.risk + (r.score !== undefined && r.score !== null ? ' · ' + r.score : '') : '', dayText: this.day(r.decidedOn) || '' });
            if (open && r.rationale) { out.push({ key: r.id + '-why', isWhy: true, text: r.rationale }); }
        });
        return out;
    }
    handleRevToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.openRev = { ...this.openRev, [id]: !this.openRev[id] };
    }
    get signals() {
        return sortRows((this.v.signals || []).map((s) => ({ ...s, pillCls: 'cq-pill soft ' + ({ watch: 'warn', assess: 'warn', escalate: 'crit' }[(s.strength || '').toLowerCase()] || 'neu'), where: s.lot ? 'Lot ' + s.lot : 'Whole Part', label: titleCase(s.label) })), this.sigSort);
    }
    get hasSignals() { return this.signals.length > 0; }
    // five signals a page, as on Field Action Review; the table keeps the height of its first page
    sigPage = 0;
    sigMin = 0;
    get sigPageCount() { return Math.max(1, Math.ceil(this.signals.length / SIG_PAGE)); }
    get sigPageNow() { return Math.min(this.sigPage, this.sigPageCount - 1); }
    get signalPage() { const from = this.sigPageNow * SIG_PAGE; return this.signals.slice(from, from + SIG_PAGE); }
    get hasSigPages() { return this.signals.length > SIG_PAGE; }
    get cantPrevSig() { return this.sigPageNow === 0; }
    get cantNextSig() { return this.sigPageNow >= this.sigPageCount - 1; }
    get sigTableStyle() { return this.hasSigPages && this.sigMin ? 'min-height:' + this.sigMin + 'px' : ''; }
    handleSigPrev() { this.sigPage = Math.max(0, this.sigPageNow - 1); }
    handleSigNext() { this.sigPage = Math.min(this.sigPageCount - 1, this.sigPageNow + 1); }
    handleSigPage(event) { this.sigPage = Number(event.currentTarget.dataset.p); }
    get sigPageItems() { return pageLinks(this.sigPageCount, this.sigPageNow); }
    goScope() { this.step = SCOPE; }

    // ---- step 2: scope
    get scopePill() { return 'cq-pill soft neu'; }
    get statePill() { return 'cq-pill soft ' + (this.scopeConfirmed ? 'pos' : this.v.scope ? 'warn' : 'neu'); }
    get noScope() { return !this.v.scope; }
    get canChange() { return this.isPartial && this.v.status !== 'Closed'; }
    get allTab() { return 'cq-chip'; }
    get inTab() { return 'cq-chip'; }
    get allPressed() { return this.view === 'all' ? 'true' : 'false'; }
    get inPressed() { return this.view === 'in' ? 'true' : 'false'; }
    handleView(event) { this.view = event.currentTarget.dataset.v; this.page = 0; this.tableMin = 0; }
    /** Only unconfirmed changes are called out: '2 added, 1 removed, not confirmed'. */
    get pendingLine() {
        if (!this.isPartial) { return ''; }
        const parts = [];
        if (this.pendingAdds) { parts.push(this.pendingAdds + ' added'); }
        if (this.pendingRemoves) { parts.push(this.pendingRemoves + ' removed'); }
        return parts.length ? parts.join(', ') + ', not confirmed' : '';
    }
    get busy() { return this.saving || Object.keys(this.ticking).length > 0; }
    get cantConfirm() { return this.busy || this.draftLots.length === 0 || this.scopeConfirmed; }
    get cantDiscard() { return this.busy || this.pending === 0; }
    get confirmLabel() { return this.saving ? 'Saving…' : this.scopeConfirmed ? 'Scope Confirmed' : 'Confirm Scope'; }

    /** The lots the table lists: in scope, then CQ.AI suggestions, then lots with a lot record, then lot numbers found only on records. */
    get shownLots() {
        const rank = (l) => (l.inScope || l.confirmed ? 0 : l.suggested ? 1 : l.known ? 2 : 3);
        const ranked = (this.view === 'in' ? this.lots.filter((l) => l.inScope || l.confirmed) : this.lots)
            .map((l, i) => ({ l, i })).sort((a, b) => rank(a.l) - rank(b.l) || a.i - b.i).map((x) => x.l);
        if (!this.scopeSort.key) { return ranked; }
        // a heading click sorts the lots; what each was built from travels with it, and ties keep the order above
        return sortRows(ranked.map((l) => {
            const s = this.stock[l.name];
            return { l, name: l.name, lot: l.name, built: l.built, records: l.records || 0,
                shipped: s && s.shipped !== undefined && s.shipped !== null ? s.shipped : l.shipped,
                onHand: s && s.hasRecord ? s.total : null, status: l.inScope ? 'Added' : l.confirmed ? 'Removing' : '' };
        }), this.scopeSort).map((x) => x.l);
    }
    scopeSort = {};
    get scopeHeads() {
        return heads([{ key: 'scope', label: 'Scope', cls: 'cscope', sortable: false }, { key: 'name', label: 'Level / Item' },
            { key: 'partRev', label: 'Part \u00b7 Rev', sortable: false }, { key: 'lot', label: 'Lot' }, { key: 'built', label: 'Qty', num: true },
            { key: 'supplier', label: 'Supplier', sortable: false }, { key: 'records', label: 'Trace' }, { key: 'shipped', label: 'Shipped', num: true },
            { key: 'onHand', label: 'On Hand', num: true }, { key: 'status', label: 'Status' }], this.scopeSort);
    }
    handleScopeSort(event) { this.scopeSort = nextSort(this.scopeSort, event.currentTarget.dataset.key); this.page = 0; this.tableMin = 0; }
    // ten lots a page; a lot's open rows stay with it
    page = 0;
    get pageCount() { return Math.max(1, Math.ceil(this.shownLots.length / PAGE)); }
    get pageNow() { return Math.min(this.page, this.pageCount - 1); }
    get hasPages() { return this.shownLots.length > PAGE; }
    get cantPrevPage() { return this.pageNow === 0; }
    get cantNextPage() { return this.pageNow >= this.pageCount - 1; }
    handlePrevPage() { this.page = Math.max(0, this.pageNow - 1); }
    handleNextPage() { this.page = Math.min(this.pageCount - 1, this.pageNow + 1); }
    handlePage(event) { this.page = Number(event.currentTarget.dataset.p); }
    // the table keeps the height of its first page, so the pager and what is below it do not jump
    tableMin = 0;
    get tableStyle() { return this.hasPages && this.tableMin ? 'min-height:' + this.tableMin + 'px' : ''; }
    renderedCallback() {
        if (this.is0 && this.hasSigPages && !this.sigMin && this.sigPageNow === 0) {
            const s = this.template.querySelector('.sigwrap');
            if (s && s.clientHeight) { this.sigMin = s.clientHeight; }
        }
        if (!this.is1 || !this.hasPages || this.tableMin || this.pageNow !== 0 || this.anyOpen) { return; }
        const w = this.template.querySelector('.tree');
        if (w && w.clientHeight) { this.tableMin = w.clientHeight; }
    }
    get pageItems() { return pageLinks(this.pageCount, this.pageNow); }

    /** The nested table: each lot, and when expanded what it was built from, level by level, with where-used rows. */
    get rows() {
        const out = [];
        const byName = new Map(this.lots.map((l) => [l.name, l]));
        const shown = this.shownLots.slice(this.pageNow * PAGE, this.pageNow * PAGE + PAGE);
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
        const where = sharedLot !== false;
        const s = this.stock[l.name];
        const has = !!(s && s.hasRecord);
        const places = has ? (s.places || []).map((k, i, all) => ({ key: key + '|s' + i, location: k.location, units: String(Number(k.units)),
            href: k.locationId ? '/lightning/r/compliancequest__SQX_Location__c/' + k.locationId + '/view' : null, sep: i < all.length - 1 })) : [];
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
            trace: where ? 'Shares ' + sharedLot : (l.records ? '! ' : '✓ ') + traceText,
            traceCls: where || l.records ? 'cq-marktext warn' : 'cq-marktext ok',
            name: l.name,
            showCheck: this.isPartial, checked: l.inScope, checkDisabled: !this.canChange || l.locked || !!this.ticking[l.name],
            checkLabel: (l.inScope ? 'Take lot ' : 'Put lot ') + l.name + (l.inScope ? ' out of scope' : ' in scope'),
            added: l.inScope, addedTitle: l.locked ? (l.reason || 'Came in with the review decision') : l.how === 'Coordinator' ? 'Ticked by the coordinator' : (l.reason || ''),
            pendingAdd, removing,
            suggested: !l.inScope && !removing && !!l.suggested, why: l.why,
            showStock: !where,
            shippedText: this.num(s && s.shipped !== undefined && s.shipped !== null ? s.shipped : l.shipped),
            onHandText: has ? this.num(s.total) : '—', canOpen: places.length > 0,
            stockOpen: this.stockOpen === key && places.length > 0, stockExpanded: this.stockOpen === key ? 'true' : 'false',
            places, noPlaces: places.length === 0, locText: has ? 'None in stock' : '—',
            asOfText: has ? [s.source, s.asOf ? 'as of ' + this.when(s.asOf) : ''].filter(Boolean).join(' · ') : '',
            popLabel: 'On hand for lot ' + l.name
        };
    }
    nodeRow(n, key, depth, hasKids, isOpen, lot, g) {
        const t = TRACE[n.trace] || { mark: '', cls: 'cq-marktext' };
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
            traceCls: sharedCount && t.cls === 'cq-marktext ok' ? 'cq-marktext warn' : t.cls,
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

    /** On hand opens a small card with the split by CQ Location and how fresh the figures are. */
    handleStock(event) {
        const key = event.currentTarget.dataset.key;
        this.stockOpen = this.stockOpen === key ? '' : key;
        this.keepPop = true;
    }
    /** A click inside the On Hand card (a location link, say) keeps it open. */
    handlePopClick() { this.keepPop = true; }
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

    get hasLots() { return this.lots.length > 0; }
}
