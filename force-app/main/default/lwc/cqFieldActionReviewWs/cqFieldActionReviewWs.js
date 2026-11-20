import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqFieldActionReview.getView';
import saveDraft from '@salesforce/apex/CqFieldActionReview.saveDraft';
import getScope from '@salesforce/apex/CqFieldActionLots.getScope';
import submitToCommittee from '@salesforce/apex/CqFieldActionLots.submitToCommittee';
import actOnStep from '@salesforce/apex/CqFarCommittee.act';
import getSign from '@salesforce/apex/CqFarCommittee.getSign';
import reopenReview from '@salesforce/apex/CqFieldActionReview.reopen';
import getPhotoVersionId from '@salesforce/apex/CqTriagePhoto.getPhotoVersionId';
import { readDraft, writeDraft, upTo } from 'c/cqWsDraft';

// shared pill tones (cqStyles .cq-pill.soft.*)
const STRENGTH_TONE = { watch: 'warn', assess: 'warn', escalate: 'crit' };
const SEAT_TONE = { approved: 'pos', rejected: 'crit' };

// Order on screen: glance, the reviewer's own assessment (checklist and risk, with the signals and evidence beside it),
// recommendation, committee approval.
const STEPS = ['Review at a Glance', 'Reviewer Assessment', 'Recommendation', 'Committee Approval'];
const ASK = [
    'Summarize this review,Why does CQ.AI suggest this outcome?,What is left on this review?',
    'How was the risk score worked out?,Which signals matter most?,LOT_QUESTION',
    'Why does CQ.AI suggest this outcome?,Which field actions are on this part?,What is left on this review?',
    'Who still needs to approve?,Summarize this review,What is left on this review?'
];
const ASSESS = 1;
const REC = 2;
const COMMITTEE = 3;
// drafts: version 3 = these four steps. Older drafts kept steps by number: version 1 had six (glance, risk, signals,
// checklist, recommendation, committee), version 2 five (glance, signals, assessment, recommendation, committee)
const READ_ONLY = [0, ASSESS, REC, COMMITTEE];   // steps that open while the review is with the committee (Assessment and Recommendation view only)
const STEP_LABEL = { Open: 'Pending', Approved: 'Approved', Rejected: 'Sent Back', Void: 'Not Required', Skipped: 'Not Required' };
const PAGE = 5;      // records shown under a signal before "Show more"

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
const LEVELS = ['Low', 'Medium', 'High'];
const ANSWERS = ['Yes', 'No', 'Not known'];
const QUESTIONS = [
    { id: 'left', text: 'Has affected product left our control (shipped or in use)?' },
    { id: 'injury', text: 'Has an injury or death been reported?' },
    { id: 'couldHarm', text: 'Could the problem cause injury if it happens again?' },
    { id: 'moreLots', text: 'Is more than one lot likely to be affected?' },
    { id: 'detect', text: 'Would the user detect the problem before use?' },
    { id: 'cause', text: 'Is the root cause understood?' }
];
const TYPES = ['Correction', 'Removal (Recall)', 'Advisory Notice'];
const CLASSES = ['Class I', 'Class II', 'Class III'];
const SCOPES = ['Full', 'Partial'];
const DRAFT = {
    version: 3,
    keep: ['hazard', 'level', 'checks', 'outcome', 'rationale', 'faChoice', 'faTitle', 'actionType', 'recallClass', 'scope',
        'team', 'emergency', 'emergencyReason', 'emergencyUser'],
    maps: { 1: [0, ASSESS, ASSESS, ASSESS, REC, COMMITTEE], 2: [0, ASSESS, ASSESS, REC, COMMITTEE] }
};

/**
 * Field Action Review workspace, on the shared workspace pieces (c-cq-ws-*): four steps in the page. CQ.AI gathers and
 * suggests, the coordinator recommends, a committee approves. Same data, steps and drafts as cqFieldActionWorkspace.
 */
export default class CqFieldActionReviewWs extends NavigationMixin(LightningElement) {
    @api recordId;
    v;
    sc;                  // the lots of the part, CQ.AI's suggested scope, and the scope as last recommended
    photoId;
    error;
    step = 0;
    maxStep = 0;
    seen = { 0: true };  // steps opened at least once: any step can be opened, but Submit to Committee waits until each has been
    resumed = false;
    done = false;        // decision is saved
    waiting = false;     // the recommendation is with the committee
    showSummary = false; // the summary screen straight after submitting
    saving = false;
    showAll = {};        // signal id -> true once the reviewer asks for every record
    hotSig = '';         // the signal under the pointer, lit in the list and the chart together
    openSig = {};        // signal id -> true while its records are shown under it in the table
    hazard = '';
    level = '';
    checks = {};
    outcome = '';
    rationale = '';
    faChoice = '';
    faTitle = '';
    actionType = '';
    recallClass = '';
    scope = '';          // Full or Partial, for a new field action; the lots of a Partial scope are chosen in the Field Action
    team = {};           // committee seat (job function id) -> the person chosen for it
    emergency = false;
    emergencyReason = '';
    emergencyUser = '';
    comment = '';        // a committee member's comment when approving or sending back
    pwWarn = '';         // why the signature password was cleared (it was filled in, not typed)
    seatError = '';      // why signing or acting on your seat did not go through, shown under its buttons
    _pw = '';            // the signature password: never rendered, never stored, cleared after every attempt
    signs = {};          // 'approve' / 'reject' -> what CQ's e-signature policy asks for (its own request: see loadSign)
    evTab = 'signals';   // the evidence tab open beside the checklist

    async connectedCallback() {
        try {
            const [v, sc] = await Promise.all([getView({ recordId: this.recordId }), getScope({ recordId: this.recordId })]);
            this.sc = sc;
            this.apply(v, true);
            this.loadPhoto();
        } catch (e) {
            this.error = this.msg(e, 'Could not read this review.');
        }
    }

    apply(v, first) {
        this.v = v;
        this.done = v.status === 'Decided' || v.status === 'Closed';
        this.waiting = v.status === 'With Committee';
        this.loadSign();
        if (!first) { return; }
        const d = this.done ? null : readDraft(v.draft, DRAFT);
        if (d) {
            Object.assign(this, d.values);
            this.step = d.step; this.maxStep = d.maxStep; this.seen = d.seen;
            this.resumed = this.maxStep > 0 && !this.waiting;
            if (this.waiting) { this.step = COMMITTEE; this.maxStep = COMMITTEE; this.seen = upTo(COMMITTEE); }
            this.fillTeam();
            return;
        }
        this.seen = { 0: true };
        if (this.waiting) { this.step = COMMITTEE; this.maxStep = COMMITTEE; this.seen = upTo(COMMITTEE); }
        // first visit: pre-fill from the record and CQ.AI's suggestions; the reviewer can change any of it
        this.hazard = v.hazard || '';
        this.level = v.band;
        this.checks = {};   // the checklist is the reviewer's own answers: nothing is pre-filled
        this.faTitle = (v.title || '').replace(/^Review:\s*/i, '');
        const sug = (v.fieldActions || []).find((f) => f.suggested);
        this.faChoice = sug ? sug.id : (v.fieldActions || []).length ? '' : 'new';
        this.scope = '';
        this.team = {}; this.emergency = false; this.emergencyReason = ''; this.emergencyUser = '';
        this.fillTeam();
    }
    /** A seat with one person who holds the function is filled for the coordinator; they can change any of it. */
    fillTeam() {
        const taken = new Set(Object.values(this.team).filter(Boolean));
        const team = { ...this.team };
        this.allSeats.forEach((s) => {
            if (s.emergency) { if (!this.emergencyUser && s.people.length) { this.emergencyUser = s.people[0].id; } return; }
            if (team[s.functionId]) { return; }
            const free = s.people.find((p) => !taken.has(p.id));
            if (free) { team[s.functionId] = free.id; taken.add(free.id); }
        });
        this.team = team;
    }

    /** With the committee, ask CQ (in its own request) whether approving or sending back needs a signature. */
    async loadSign() {
        if (!this.waiting) { this.signs = {}; return; }
        try { this.signs = (await getSign({ recordId: this.recordId })) || {}; }
        catch (e) { this.signs = { approve: { unknown: true }, reject: { unknown: true } }; }
    }
    msg(e, fallback) { return (e && e.body && e.body.message) || fallback; }
    get ready() { return !!this.v; }
    // ---- header (same layout as the PHR workspace header)
    dash(x) { return x === undefined || x === null || x === '' ? '—' : String(x); }
    get dueText() {
        const p = String(this.v.due || '').split('-');
        return p.length === 3 ? new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2])).toLocaleDateString() : '—';
    }
    get partText() { return this.dash(this.v.partName); }
    get lotText() { return this.dash(this.v.lot); }
    get reviewerText() { return this.dash(this.v.reviewer); }
    get statusText() { return this.dash(this.v.status); }
    handleEdit() {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: this.recordId, objectApiName: 'Field_Action_Review__c', actionName: 'edit' } });
    }
    async handleRefresh() {
        try {
            const [v, sc] = await Promise.all([getView({ recordId: this.recordId }), getScope({ recordId: this.recordId })]);
            this.sc = sc; this.apply(v, false); this.error = undefined;
        }
        catch (e) { this.error = this.msg(e, 'Could not refresh this review.'); }
    }
    get open() { return this.ready && !this.done; }                  // not decided yet: being worked on, or with the committee
    get live() { return this.open && !this.waiting; }                // the coordinator is still working on it
    // ---- Ask CQ.AI: the Field Action agent, told which step is open, with ready questions for that step
    get askStep() { return STEPS[this.step] || ''; }
    get askSuggestions() {
        // Signals: ask about the lot only when the review has one
        const lotQ = this.v && this.v.lot ? 'Which relevant records share the lot?' : 'Which relevant records matter most?';
        return (ASK[this.step] || ASK[0]).replace('LOT_QUESTION', lotQ);
    }
    get is0() { return this.ready && ((this.open && this.step === 0) || (this.done && !this.showSummary)); }
    get is3() { return this.open && this.step === ASSESS; }    // the Reviewer Assessment block: checklist and risk, evidence beside it (view only with the committee)
    get is4() { return this.open && this.step === REC; }
    /** With the committee, Reviewer Assessment and Recommendation open view only: the main panel gets the viewonly class. */
    renderedCallback() {
        const m = this.template.querySelector('.view');
        if (m) { m.classList.toggle('viewonly', !!this.waiting && (this.step === ASSESS || this.step === REC)); }
        // a value binding can leave a text box empty on first draw: fill each box from its field unless someone is typing in it
        this.template.querySelectorAll('textarea[data-f], input[type="text"][data-f]').forEach((el) => {
            const want = this[el.dataset.f] || '';
            if (el !== this.template.activeElement && el.value !== want) { el.value = want; }
        });
    }
    get is5() { return this.open && this.step === COMMITTEE; }
    get showResumed() { return this.resumed && this.live; }
    get canRestart() { return this.live && this.maxStep > 0 && !this.saving; }
    get canReopen() { return this.done && !this.saving; }

    // ---- step rail
    get valid() {
        return [this.maxStep > 0, !!this.seen[ASSESS] && this.assessDone,
            !!this.seen[REC] && !!this.outcome && !!this.rationale.trim(), this.done];
    }
    get steps() {
        const v = this.v || {};
        const n = (v.signals || []).length;
        const answered = QUESTIONS.filter((q) => this.checks[q.id]).length;
        const subs = [
            this.maxStep > 0 || this.done ? 'Reviewed' : 'Start here',
            this.done || this.waiting ? (this.level || v.riskLevel || v.band) + ' · score ' + v.score
                : answered + ' of ' + QUESTIONS.length + ' answered · ' + n + ' signal' + (n === 1 ? '' : 's'),
            this.done ? v.outcome : this.outcome || v.outcome || 'Not decided',
            this.done ? 'Approved' : this.waiting ? this.approvedCount + ' of ' + this.csteps.length + ' approved' : this.emergency ? 'Emergency' : 'Not submitted'
        ];
        const valid = this.valid;
        return STEPS.map((label, i) => {
            const ok = this.done || (this.waiting ? i < COMMITTEE : valid[i]);
            const unseen = this.live && !this.seen[i];
            return { i, n: i + 1, label, sub: unseen ? 'Not Reviewed' : subs[i], done: ok, notDone: !ok,
                cls: 'step' + ((!this.done && i === this.step) || (this.done && !this.showSummary && i === 0) ? ' active' : '') + (ok ? ' done' : ''),
                locked: !this.canOpen(i) };
        });
    }
    /** While the review is with the committee only the display-only steps open; nothing can be changed. */
    canOpen(i) { return !this.done && (this.waiting ? READ_ONLY.includes(i) : true); }
    get progress() { return this.steps.filter((s) => s.done).length + ' of ' + STEPS.length + ' steps complete'; }

    // ---- inputs for the shared pieces
    get headerFields() {
        const v = this.v;
        return [{ key: 'src', label: 'Source', value: v.sourceName, id: v.sourceId }, { key: 'part', label: 'Part', value: v.partName },
            { key: 'lot', label: 'Lot', value: v.lot }, { key: 'rev', label: 'Reviewer', value: v.reviewer },
            { key: 'st', label: 'Status', value: v.status }, { key: 'due', label: 'Due', value: this.dueText }];
    }
    get railSteps() { return this.steps.map((s) => ({ label: s.label, sub: s.sub, done: s.done, active: s.cls.includes(' active'), locked: s.locked })); }
    get verdictTone() { return this.v.suggestedOutcome === 'Field Action Needed' ? 'crit' : ''; }
    get sourceLines() { return [this.v.sourceTitle, this.v.causeLine]; }
    get quoteBy() { return this.v.requestedBy ? 'Sent for review by ' + this.v.requestedBy : ''; }
    get outcomeOptions() { return this.outcomes.map((o) => ({ id: o.id, title: o.id, desc: o.why, cq: o.cq })); }
    get faOptions() { return this.faOpts.map((f) => ({ id: f.id, title: f.label, desc: f.why, cq: f.cq })); }

    // ---- step 1: review at a glance
    get problem() { const v = this.v; return v.problem || v.sourceTitle || v.title || 'No description on the source record.'; }
    get hasSource() { return !!this.v.sourceId; }
    get sourceLabel() { return this.v.sourceKind + ' ' + this.v.sourceName; }
    /** The newest photo on the source record (the NC or complaint). Shown only; photos are added on the source. */
    async loadPhoto() {
        if (!this.v || !this.v.sourceId) { return; }
        try { this.photoId = await getPhotoVersionId({ recordId: this.v.sourceId }); } catch (e) { this.photoId = null; }
    }
    get photoUrl() { return this.photoId ? '/sfc/servlet.shepherd/version/download/' + this.photoId : null; }
    get photoCls() { return 'photo' + (this.photoId ? ' has' : ''); }
    get tiles() {
        const v = this.v;
        const n = (x) => (x === undefined || x === null || x === '' ? '—' : String(x));
        return [
            ['Affected', n(v.qtyAffected)], ['Shipped', n(v.qtyShipped)], ['Requested By', n(v.requestedBy)]
        ].map(([label, value]) => ({ key: label, label, value }));
    }
    /** When CQ.AI suggests no field action, show why a person still sent it for review. */
    get showReason() { return this.v.suggestedOutcome === 'No Field Action' && !!this.v.reason; }
    get reasonLabel() { return 'Sent for Review' + (this.v.requestedBy ? ' by ' + this.v.requestedBy : ''); }
    get decidedLine() {
        const v = this.v;
        return 'Decided' + (v.decidedBy ? ' by ' + v.decidedBy : '') + ' · ' + v.outcome + (v.faName ? ' · ' + v.faName : '');
    }
    get hasFa() { return !!this.v.faId; }
    handleOpen(event) {
        const id = typeof event.detail === 'string' ? event.detail : event.currentTarget.dataset.id;   // shared pieces send the id; buttons here carry it
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, actionName: 'view' } });
    }

    // ---- signals and evidence (third step)
    // Display only: every signal is shown, with the records behind it. The reviewer does not pick, so the committee sees the same set.
    rec(r) {
        return { ...r, meta: [r.kind, r.status, r.lot ? 'Lot ' + r.lot : 'No Lot', r.why].filter(Boolean).join(' · '),
            line: r.title ? ' · ' + r.title : '' };
    }
    sig(s) {
        const seen = s.firstSeen ? new Date(s.firstSeen).toLocaleDateString() : '';
        const all = (s.records || []).map((r) => this.rec(r));
        const n = all.length;
        const rest = this.showAll[s.id] ? 0 : Math.max(0, n - PAGE);
        return { ...s, pillCls: 'cq-pill soft ' + (STRENGTH_TONE[(s.strength || '').toLowerCase()] || 'neu'),
            meta: titleCase([s.name, s.trend, seen ? 'first seen ' + seen : '', !s.lot ? 'whole part' : s.lot === this.v.lot ? 'this lot' : 'lot ' + s.lot,
                s.raisedBy ? 'raised by ' + s.raisedBy : '', s.status === 'Dismissed' ? 'dismissed earlier' : ''].filter(Boolean).join(' · ')),
            label: titleCase(s.label),
            why: titleCase(s.why),
            count: n + ' record' + (n === 1 ? '' : 's'),
            total: n,
            sigCls: 'sig' + (this.hotSig === s.id ? ' hot' : ''),
            records: rest ? all.slice(0, PAGE) : all, hasRest: rest > 0, restLabel: 'Show ' + rest + ' More' };
    }
    /** The signals as table rows: each signal, then (when opened) its records and the Show More row under it. */
    sigRows(list) {
        const rows = [];
        list.forEach((s) => {
            const open = !!this.openSig[s.id];
            rows.push({ key: 's' + s.id, isSig: true, id: s.id, rule: s.rule, pillCls: s.pillCls, strength: s.strength, sub: (s.meta || '').replace(/-/g, '‑'),   // lots and dates never break at the hyphen
                label: s.label, why: this.notRepeated(s.label, s.why), n: s.total,
                expanded: open ? 'true' : 'false', chevCls: 'chev' + (open ? ' open' : ''),
                rowCls: 'srow' + (this.hotSig === s.id ? ' hot' : '') + (open ? ' isopen' : '') });
            if (open) {
                s.records.forEach((r) => rows.push({ key: 'r' + s.id + r.id, isRec: true, id: r.id, name: r.name, line: r.line, meta: r.meta, sameLot: r.sameLot }));
                if (s.hasRest) { rows.push({ key: 'm' + s.id, isRest: true, id: s.id, restLabel: s.restLabel }); }
            }
        });
        return rows;
    }
    /** The grey line without its first sentence when the headline already starts with it ("6 Reviews." under "6 Reviews on This Part"). */
    notRepeated(label, why) {
        const m = /^([^.]+)\.\s+(.*)$/.exec(why || '');
        return m && (label || '').toLowerCase().startsWith(m[1].trim().toLowerCase()) ? m[2] : why;
    }
    get signalRows() { return this.sigRows(this.signals); }
    get moreSignalRows() { return this.sigRows(this.moreSignals); }
    handleSigToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.openSig = { ...this.openSig, [id]: !this.openSig[id] };
    }
    handleSigOver(event) { this.hotSig = event.currentTarget.dataset.id; }
    handleSigOut() { this.hotSig = ''; }

    /** Against Normal: one bar per signal, how many times its normal level it is now, on a log scale from 1x to 100x. */
    get normalBars() {
        const ink = { Escalate: '#b42318', Assess: '#c2570c', Watch: '#a37200' };
        return (this.v.signals || []).map((s) => {
            const t = s.times;
            const has = t !== undefined && t !== null;
            const w = has ? Math.max(1.5, Math.min(100, Math.log10(Math.max(Number(t), 1)) / 2 * 100)) : 0;
            const c = ink[s.strength] || ink.Watch;
            return { id: s.id, rule: s.rule, where: !s.lot ? 'Whole Part' : s.lot === this.v.lot ? 'Lot ' + s.lot + ' · This Lot' : 'Lot ' + s.lot,
                has, none: !has, rowCls: 'nrow' + (this.hotSig === s.id ? ' hot' : ''),
                barStyle: 'width:' + w + '%;background:' + c, times: has ? Number(t).toFixed(1).replace(/\.0$/, '') + '×' : 'No baseline',
                timesStyle: has ? 'color:' + c : 'color:#5b6470;font-weight:400' };
        });
    }
    get hasBars() { return this.normalBars.some((b) => b.has); }

    /** The last 12 months of records on the part, as three lines. */
    get trendChart() {
        const months = this.v.trendMonths || [];
        const series = this.v.trend || [];
        if (!months.length || !series.length) { return null; }
        const colors = { Complaints: '#1d5fd1', Nonconformances: '#c2570c', Reviews: '#4a2fc0' };
        const top = Math.max(1, ...series.map((x) => Math.max(...x.counts)));
        const maxY = top <= 5 ? 5 : Math.ceil(top / 5) * 5;
        const left = 44, right = 548, y0 = 14, y1 = 186;
        const px = (i) => left + i * (right - left) / Math.max(1, months.length - 1);
        const py = (n) => y1 - n / maxY * (y1 - y0);
        const last = months.length - 1;
        const ends = series.map((x) => py(x.counts[last]));
        const lines = series.map((x, k) => {
            const color = colors[x.name] || '#5b6470';
            // keep the end labels apart when lines finish at the same height
            let ey = ends[k] + 4;
            for (let j = 0; j < k; j++) { if (Math.abs(ends[j] - ends[k]) < 10) { ey += 11 * (k - j); } }
            return { key: x.name, name: x.name, color,
                points: x.counts.map((n, i) => px(i) + ',' + py(n)).join(' '),
                dots: x.counts.map((n, i) => ({ key: x.name + i, x: px(i), y: py(n), title: months[i] + ': ' + n + ' ' + x.name.toLowerCase() })),
                endX: px(last) + 8, endY: ey, endLabel: String(x.counts[last]),
                swatch: 'background:' + color };
        });
        const ticks = [0, maxY / 2, maxY].map((t) => ({ key: 't' + t, v: String(t), y: py(t), ty: py(t) + 4 }));
        const labels = months.map((m, i) => ({ key: 'm' + i, x: px(i), label: m.split(' ')[0] }));
        const total = (name) => { const x = series.find((y) => y.name === name); return x ? x.counts.reduce((a, b) => a + b, 0) : 0; };
        return { lines, ticks, labels, range: months[0] + ' to ' + months[last],
            label: 'Records on this part by month, ' + months[0] + ' to ' + months[last] + ': ' + series.map((x) => total(x.name) + ' ' + x.name.toLowerCase()).join(', ') };
    }
    get hasTrend() { return !!this.trendChart; }
    handleShowAll(event) { this.showAll = { ...this.showAll, [event.currentTarget.dataset.id]: true }; }
    get signals() { return (this.v.signals || []).map((s) => this.sig(s)); }
    get moreSignals() { return (this.v.moreSignals || []).map((s) => this.sig(s)); }
    get hasSignals() { return this.signals.length > 0; }
    get hasMore() { return this.moreSignals.length > 0; }
    get moreLabel() { const n = this.moreSignals.length; return 'Show ' + n + ' Weaker or Dismissed Signal' + (n === 1 ? '' : 's'); }
    get recs() { return (this.v.records || []).map((r) => this.rec(r)); }
    get hasRecs() { return this.recs.length > 0; }

    // ---- reviewer assessment (second step): the checklist, risk level and hazard summary, with the evidence in tabs beside them
    get evTabs() {
        const t = [['signals', 'Signals (' + this.signals.length + ')']];
        if (this.hasBars) { t.push(['normal', 'Against Normal']); }
        if (this.hasTrend) { t.push(['month', 'By Month']); }
        t.push(['score', 'Risk Score']);
        return t.map(([id, label]) => ({ id, label, sel: this.evTab === id ? 'true' : 'false', cls: 'evtab' + (this.evTab === id ? ' on' : '') }));
    }
    get tabSignals() { return this.evTab === 'signals'; }
    get tabNormal() { return this.evTab === 'normal'; }
    get tabMonth() { return this.evTab === 'month'; }
    get tabScore() { return this.evTab === 'score'; }
    handleTab(event) { this.evTab = event.detail; }
    get bandHint() { return 'CQ.AI suggests ' + this.v.band + ' (score ' + this.v.score + ')'; }
    get factors() { return (this.v.factors || []).map((f, i) => ({ ...f, key: 'f' + i, of: f.pts + ' / ' + f.max })); }
    get bandCls() { return 'lvl ' + (this.v.band || '').toLowerCase(); }
    get levels() {
        return LEVELS.map((l) => ({ id: l, cq: l === this.v.band, pressed: this.level === l ? 'true' : 'false', cls: l === this.v.band ? 'cq-chip ai' : 'cq-chip' }));
    }
    handleLevel(event) { if (this.waiting) { return; } this.level = event.currentTarget.dataset.id; }
    get assessDone() { return !!this.hazard.trim() && !!this.level && this.checksDone; }

    get questions() {
        return QUESTIONS.map((q) => ({
            ...q,
            opts: ANSWERS.map((a) => ({ key: q.id + a, q: q.id, a, cls: 'cq-chip', pressed: this.checks[q.id] === a ? 'true' : 'false' }))
        }));
    }
    get checksDone() { return QUESTIONS.every((q) => !!this.checks[q.id]); }
    handleCheck(event) { if (this.waiting) { return; } const d = event.currentTarget.dataset; this.checks = { ...this.checks, [d.q]: d.a }; }

    // ---- step 5: recommendation
    get outcomes() {
        return [['No Field Action', 'Nothing further is needed in the field.'],
                ['Field Action Needed', 'Start a field action, or join one that already covers this problem.']]
            .map(([id, why]) => ({ id, why, cq: id === this.v.suggestedOutcome, cls: id === this.v.suggestedOutcome ? 'cq-optcard ai' : 'cq-optcard', pressed: this.outcome === id ? 'true' : 'false' }));
    }
    get needed() { return this.outcome === 'Field Action Needed'; }
    get faOpts() {
        const list = (this.v.fieldActions || []).map((f) => ({
            id: f.id, label: 'Join ' + f.name, cq: f.suggested,
            why: [f.title, f.actionType, f.status, f.why].filter(Boolean).join(' · ')
        }));
        list.push({ id: 'new', label: 'Start a New Field Action', why: 'For a problem no open field action covers.', cq: !list.some((x) => x.cq) && !list.length });
        return list.map((o) => ({ ...o, cls: 'act' + (this.faChoice === o.id ? ' on' : o.cq ? ' sug' : ''), tick: this.faChoice === o.id ? '✓' : '' }));
    }
    get isNew() { return this.needed && this.faChoice === 'new'; }
    get typeOpts() { return TYPES.map((t) => ({ value: t, selected: this.actionType === t })); }
    get classOpts() { return CLASSES.map((t) => ({ value: t, selected: this.recallClass === t })); }
    // scope of a new field action: Full is every lot of the part; Partial starts with this review's lot and the
    // coordinator chooses the rest in the Field Action, where the lot list goes for its own approval
    get scopeData() { return this.sc || {}; }
    get scopeOpts() {
        const sug = this.scopeData.suggested;
        return SCOPES.map((id) => ({ id, cq: id === sug, cls: id === sug ? 'cq-chip ai' : 'cq-chip', pressed: this.scope === id ? 'true' : 'false' }));
    }
    get scopeSuggests() { return this.scopeData.suggested ? 'CQ.AI Suggests ' + this.scopeData.suggested + '. ' + (this.scopeData.why || '') : ''; }
    get isPartial() { return this.scope === 'Partial'; }
    get isFull() { return this.scope === 'Full'; }
    get allLots() { return (this.scopeData.lots || []).map((l) => l.name); }
    /** Lots CQ.AI would look at besides this review's own lot. */
    get alsoLots() { return (this.scopeData.lots || []).filter((l) => l.suggested && !l.thisLot).map((l) => l.name); }
    get fullLine() {
        const n = this.allLots.length;
        return 'Every lot of ' + this.partText + ', including lots found later (' + n + ' today).';
    }
    get startLine() {
        const also = this.alsoLots;
        return (this.v.lot ? 'The Field Action starts with lot ' + this.v.lot + '.' : 'No lot is recorded on this review, so the Field Action starts with none.')
            + (also.length ? ' CQ.AI would also look at ' + also.join(', ') + '.' : '')
            + ' The coordinator chooses the lots in the Field Action, and that list goes for its own approval.';
    }
    /** The scope as one line, for the committee's card and the summary. */
    get scopeLine() {
        if (this.outcomeNow !== 'Field Action Needed') { return ''; }
        const scope = this.done ? this.scopeData.scope : this.isNew ? this.scope : '';     // a review that joins a field action has no scope of its own
        if (!scope) { return this.v.lot ? 'Adds lot ' + this.v.lot + ' to the field action' : ''; }
        if (scope === 'Full') { return 'Full · ' + this.fullLine; }
        const also = this.alsoLots;
        return 'Partial · starts with ' + (this.v.lot ? 'lot ' + this.v.lot : 'no lot') + (also.length ? ' · CQ.AI would also look at ' + also.join(', ') : '')
            + ' · lots chosen and approved in the Field Action';
    }
    handleScope(event) { if (this.waiting) { return; } this.scope = event.currentTarget.dataset.id; }
    handleOutcome(event) { if (this.waiting) { return; } this.outcome = event.detail; }
    handleFa(event) { if (this.waiting) { return; } this.faChoice = event.detail; }
    handleInput(event) {
        const f = event.target.dataset.f;
        if (this.waiting && f !== 'comment') { return; }      // with the committee only a member's comment can be typed
        this[f] = event.target.value;
    }

    // ---- step 6: committee approval, on CQ Approvals
    get committee() { return (this.v && this.v.committee) || {}; }
    get allSeats() { return this.committee.seats || []; }
    get seats() {
        const taken = (id) => Object.entries(this.team).filter(([f, u]) => u && f !== id).map(([, u]) => u);
        return this.allSeats.filter((s) => !s.emergency).map((s) => {
            const others = taken(s.functionId);
            return { ...s, none: !s.people.length,
                opts: s.people.map((p) => ({ value: p.id, label: p.name + (others.includes(p.id) ? ' (already on the committee)' : ''), selected: this.team[s.functionId] === p.id })) };
        });
    }
    get emergencySeat() { return this.allSeats.find((s) => s.emergency); }
    get emergencyOpts() {
        const s = this.emergencySeat;
        return s ? s.people.map((p) => ({ value: p.id, label: p.name, selected: this.emergencyUser === p.id })) : [];
    }
    get normal() { return !this.emergency; }
    handleSeat(event) { this.team = { ...this.team, [event.target.dataset.id]: event.target.value }; }
    handleEmergency(event) { this.emergency = event.target.checked; }
    get members() {
        if (this.emergency) { const s = this.emergencySeat; return s ? [{ functionId: s.functionId, userId: this.emergencyUser }] : []; }
        return this.seats.map((s) => ({ functionId: s.functionId, userId: this.team[s.functionId] }));
    }
    /** One row per committee seat: your own open seat is highlighted with its buttons; other open seats say who they wait for. */
    get csteps() {
        return (this.committee.steps || []).map((s) => {
            const open = s.status === 'Open';
            const yours = open && s.mine && s.canAct;
            const when = s.doneOn ? new Date(s.doneOn).toLocaleString() : '';
            const line = open ? (s.mine ? 'Waiting for you' : 'Waiting for ' + s.person)
                : [STEP_LABEL[s.status] && s.status !== 'Void' && s.status !== 'Skipped' ? STEP_LABEL[s.status] + (when ? ' ' + when : '') : '',
                    s.doneBy && s.doneBy !== s.person ? 'recorded by ' + s.doneBy : ''].filter(Boolean).join(' · ');
            return {
                ...s, yours, adminAct: s.canAct && !yours && !this.needSign,     // a signature is the assigned person's own: no acting for others
                who: s.person + (s.mine ? ' (you)' : ''),
                label: open ? (yours ? 'Your Approval' : 'Waiting') : (STEP_LABEL[s.status] || s.status),
                cls: 'cq-pill soft ' + (yours ? 'you' : SEAT_TONE[(s.status || '').toLowerCase()] || 'neu'),
                rowCls: 'seat' + (yours ? ' yours' : ''),
                line, quote: s.comment ? '“' + s.comment + '”' : ''
            };
        });
    }
    get hasYours() { return this.csteps.some((s) => s.yours); }
    // ---- electronic signature: what CQ's policy asks for each action on this review
    signOf(action) { return (this.signs || {})[action] || {}; }
    get needSign() { return !!(this.signOf('approve').required || this.signOf('reject').required); }
    get signUnknown() { return !!(this.signOf('approve').unknown || this.signOf('reject').unknown); }
    get approveLabel() { return this.signOf('approve').required ? 'Sign and Approve' : 'Approve'; }
    get rejectLabel() { return this.signOf('reject').required ? 'Sign and Send Back' : 'Send Back'; }
    get commentRequired() { return !!this.signOf('approve').comment; }
    get commentHint() { return this.commentRequired ? 'Required with your signature.' : 'Required when you send it back.'; }
    get signMeaning() {
        const p = this.signOf('approve').purpose;
        return 'By signing, you ' + (p ? 'confirm: ' + p : 'approve this field action recommendation') + '. Type your password; it is not saved.';
    }
    /** Only typed characters count: autofill, paste and drop are refused, so the signer types the password themselves. */
    handlePwInput(event) {
        const t = event.inputType || '';
        if (t.startsWith('insertText') || t.startsWith('delete') || t === 'insertCompositionText') {
            this._pw = event.target.value; this.pwWarn = '';
            return;
        }
        this.refusePw(event.target);
    }
    handlePwBlock(event) { event.preventDefault(); this.refusePw(event.target); }
    /** The browser filled the field itself (its autofill animation starts): clear it. */
    handlePwAutofill(event) { if ((event.animationName || '').toLowerCase().includes('autofill')) { this.refusePw(event.target); } }
    refusePw(el) {
        if (el) { el.value = ''; }
        this._pw = '';
        this.pwWarn = 'Please type your password. Filled-in or pasted passwords are not accepted for a signature.';
    }
    /**
     * The signature box is a text box drawn with dots, so the browser does not treat it as a password box and offer
     * saved passwords. Where the browser cannot draw the dots it stays a password box, so the password is never shown.
     */
    get pwMasked() {
        try { return typeof CSS !== 'undefined' && !!CSS.supports && CSS.supports('-webkit-text-security', 'disc'); }
        catch (e) { return false; }
    }
    get pwType() { return this.pwMasked ? 'text' : 'password'; }
    get pwAuto() { return this.pwMasked ? 'off' : 'new-password'; }
    get pwStyle() { return this.pwMasked ? '-webkit-text-security: disc;' : ''; }
    clearPw() {
        this._pw = '';
        const el = this.template.querySelector('input.sigpw');
        if (el) { el.value = ''; }
    }
    get adminComment() { return this.canActAny && !this.hasYours; }
    /** The outcome matches what CQ.AI suggested. */
    get matchesSuggestion() { return !!this.v.suggestedOutcome && this.outcomeNow === this.v.suggestedOutcome; }
    get approvedCount() { return this.csteps.filter((s) => s.status === 'Approved').length; }
    get canActAny() { return this.csteps.some((s) => s.canAct); }
    get committeeTitle() { return 'Committee' + (this.committee.approvalName ? ' · ' + this.committee.approvalName : ''); }
    get approvedLine() { return this.approvedCount + ' of ' + this.csteps.length + ' approved'; }
    get approvalNote() { return 'Approvals run on CQ Approvals' + (this.committee.approvalName ? ' (' + this.committee.approvalName + ')' : '') + '. The Field Action starts when every member has approved.'; }
    get sentBack() { return this.live ? this.committee.sentBack : ''; }
    /** What the committee is approving: the coordinator's recommendation and what it rests on. */
    get recRows() {
        const v = this.v; const c = this.committee;
        const fa = this.outcomeNow !== 'Field Action Needed' ? '' : this.faChoice === 'new'
            ? 'Start a New Field Action: ' + [this.faTitle, this.actionType, this.recallClass].filter(Boolean).join(' · ')
            : 'Join ' + (((v.fieldActions || []).find((f) => f.id === this.faChoice) || {}).name || 'an open Field Action');
        return [
            ['Outcome', this.outcomeNow], ['Field Action', fa], ['Scope', this.scopeLine], ['Rationale', this.rationale || v.rationale],
            ['Risk', (this.level || v.riskLevel || v.band) + ' · score ' + v.score + ' of 100'],
            ['Health Hazard Summary', this.hazard || v.hazard],
            ['Checklist', QUESTIONS.filter((q) => this.checks[q.id]).map((q) => q.text + ' ' + this.checks[q.id]).join('\n')],
            ['Submitted', [c.recommendedBy, c.recommendedOn ? new Date(c.recommendedOn).toLocaleString() : ''].filter(Boolean).join(' · ')],
            ['Emergency', c.emergency ? c.emergencyReason : '']
        ].filter(([, val]) => !!val).map(([k, val]) => ({ key: k, k, v: val, isOutcome: k === 'Outcome' }));
    }
    get outcomeNow() { return this.outcome || this.v.outcome; }
    /** A message about acting on a seat: under your seat's buttons, or in the page banner when acting as admin. */
    fail(m) { if (this.hasYours) { this.seatError = m; } else { this.error = m; } }
    async handleAct(event) {
        const d = event.currentTarget.dataset;
        if (this.saving) { return; }
        this.seatError = '';
        if (d.a === 'reject' && !this.comment.trim()) { this.fail('Add a comment saying why you are sending it back.'); return; }
        const g = this.signOf(d.a);
        if (g.required && g.comment && !this.comment.trim()) { this.fail('A comment is required with your signature.'); return; }
        if (g.required && !this._pw) { this.fail('Type your password to sign.'); return; }
        const password = g.required ? this._pw : null;
        this.clearPw();                 // never kept, whatever happens next
        this.saving = true; this.error = undefined;
        try {
            const v = await actOnStep({ recordId: this.recordId, stepId: d.id, action: d.a, comment: this.comment.trim(), password });
            this.comment = '';
            this.apply(v, false);
            if (this.done) { this.showSummary = true; }
            else if (!this.waiting) { this.step = REC; }      // sent back: the coordinator picks it up at the recommendation
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (e) { this.fail(this.msg(e, 'Could not record that.')); }
        this.saving = false;
    }

    // ---- navigation: any step opens from the list, Back and Next always move; Submit to Committee waits for every step
    /** What is missing on one step, or ''. */
    stepBlocker(i) {
        if (i === ASSESS) {
            if (!this.checksDone) { return 'Answer every question'; }
            if (!this.level) { return 'Choose a risk level'; }
            if (!this.hazard.trim()) { return 'Write the health hazard summary'; }
        }
        if (i === REC) {
            if (!this.outcome) { return 'Click an outcome to choose it'; }
            if (!this.rationale.trim()) { return 'Rationale needed'; }
            if (this.needed && !this.faChoice) { return 'Join a field action or start a new one'; }
            if (this.isNew && (!this.faTitle.trim() || !this.actionType)) { return 'Title and action type needed'; }
            if (this.isNew && !this.scope) { return 'Choose Full or Partial'; }
        }
        if (i === COMMITTEE) {
            if (this.emergency) {
                if (!this.emergencyUser) { return 'Choose the emergency approver'; }
                if (!this.emergencyReason.trim()) { return 'Give the reason for the emergency'; }
            } else {
                const m = this.members;
                if (!m.length || m.some((x) => !x.userId)) { return 'Choose a person for every seat'; }
                if (new Set(m.map((x) => x.userId)).size !== m.length) { return 'One person can hold only one seat'; }
            }
        }
        return '';
    }
    /** Shown only beside Submit to Committee: steps not opened yet, then the first step with something missing. */
    get blocker() {
        if (this.step !== COMMITTEE || !this.live) { return ''; }
        const unseen = STEPS.filter((n, i) => !this.seen[i]);
        if (unseen.length) {
            const list = unseen.length === 1 ? unseen[0] : unseen.slice(0, -1).join(', ') + ' and ' + unseen[unseen.length - 1];
            return 'Open ' + list + ' first';
        }
        for (const i of [ASSESS, REC, COMMITTEE]) {
            const b = this.stepBlocker(i);
            if (b) { return i === COMMITTEE ? b : STEPS[i] + ': ' + b; }
        }
        return '';
    }
    get cantNext() { return !!this.blocker || this.saving; }
    get cantBack() { return this.step === 0 || this.saving; }
    get nextLabel() { return this.saving ? 'Saving…' : this.step === COMMITTEE ? 'Submit to Committee' : 'Next'; }
    persist() {
        if (this.done) { return; }
        saveDraft({ recordId: this.recordId, draft: writeDraft(this, DRAFT) }).catch(() => {});
    }
    go(i) {
        this.step = i;
        if (!this.live) { return; }
        this.seen = { ...this.seen, [i]: true };
        this.maxStep = Math.max(this.maxStep, i);
        this.resumed = false;
        this.persist();
    }
    handleBack() { if (this.step > 0) { this.go(this.step - 1); } }
    handleStep(event) {
        const i = Number(event.detail);
        if (this.canOpen(i)) { this.go(i); }
    }
    handleRestart() {
        this.step = 0; this.maxStep = 0; this.seen = { 0: true }; this.resumed = false; this.error = undefined;
        this.outcome = ''; this.rationale = ''; this.actionType = ''; this.recallClass = '';
        const v = { ...this.v, draft: null };
        this.apply(v, true);
        saveDraft({ recordId: this.recordId, draft: null }).catch(() => {});
    }
    async handleReopen() {
        this.saving = true;
        try {
            const v = await reopenReview({ recordId: this.recordId });
            this.showSummary = false; this.step = 0; this.maxStep = 0;
            this.apply({ ...v, draft: null }, true);
            this.outcome = v.outcome || ''; this.rationale = v.rationale || '';
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (e) { this.error = this.msg(e, 'Could not reopen the review.'); }
        this.saving = false;
    }

    buildSummary() {
        const v = this.v;
        return [
            'Signals shown: ' + ((v.signals || []).map((s) => s.name + ' ' + s.rule + ' (' + s.strength + ')').join(', ') || 'none'),
            'Risk score: ' + v.score + ' of 100 (' + v.band + '). ' + (v.factors || []).map((f) => f.name + ' ' + f.pts + '/' + f.max).join('; '),
            'Risk level: ' + this.level + (this.level === v.band ? ' (as CQ.AI suggested)' : ' (CQ.AI suggested ' + v.band + ')'),
            'Checklist: ' + QUESTIONS.map((q) => q.text + ' ' + this.checks[q.id]).join(' | '),
            'Outcome: ' + this.outcome + (this.outcome === v.suggestedOutcome ? ' (as CQ.AI suggested)' : ' (CQ.AI suggested ' + v.suggestedOutcome + ')'),
            this.isNew ? 'Scope: ' + this.scopeLine + (this.scope === this.scopeData.suggested ? ' (as CQ.AI suggested)' : ' (CQ.AI suggested ' + this.scopeData.suggested + ')') : ''
        ].filter(Boolean).join('\n');
    }
    get summaryRows() {
        const v = this.v;
        return [
            ['Outcome', v.outcome], ['Field Action', v.faName || 'None'], ['Scope', this.scopeLine], ['Risk', (v.riskLevel || '') + ' · score ' + v.score + ' of 100'],
            ['Rationale', v.rationale], ['Committee', this.committee.approvalName ? this.committee.approvalName + ' · ' + this.approvedCount + ' of ' + this.csteps.length + ' approved' : ''],
            ['Approved By', v.decidedBy]
        ].filter(([, val]) => !!val).map(([k, val]) => ({ key: k, k, v: val, isOutcome: k === 'Outcome' }));
    }
    handleFinish() { this.showSummary = false; }

    async handleNext() {
        if (this.blocker || this.saving) { return; }
        this.resumed = false;
        if (this.step < COMMITTEE) { this.go(this.step + 1); return; }
        this.saving = true;
        this.error = undefined;
        try {
            const v = await submitToCommittee({
                recordId: this.recordId, hazard: this.hazard.trim(), summary: this.buildSummary(), score: this.v.score, riskLevel: this.level,
                outcome: this.outcome, rationale: this.rationale.trim(), draft: writeDraft(this, DRAFT), team: JSON.stringify(this.members),
                emergency: this.emergency, emergencyReason: this.emergencyReason.trim(),
                scope: this.isNew ? this.scope : '', lots: []
            });
            this.apply(v, false);
            try { this.sc = await getScope({ recordId: this.recordId }); } catch (e) { /* the scope shown stays as recommended */ }
            this.step = COMMITTEE; this.maxStep = COMMITTEE; this.seen = upTo(COMMITTEE);
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (e) {
            this.error = this.msg(e, 'Could not submit to the committee.');
        }
        this.saving = false;
    }
}
