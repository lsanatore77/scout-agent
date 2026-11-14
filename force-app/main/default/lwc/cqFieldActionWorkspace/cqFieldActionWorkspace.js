import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqFieldActionReview.getView';
import saveDraft from '@salesforce/apex/CqFieldActionReview.saveDraft';
import getScope from '@salesforce/apex/CqFieldActionLots.getScope';
import submitToCommittee from '@salesforce/apex/CqFieldActionLots.submitToCommittee';
import actOnStep from '@salesforce/apex/CqFarCommittee.act';
import reopenReview from '@salesforce/apex/CqFieldActionReview.reopen';
import getPhotoVersionId from '@salesforce/apex/CqTriagePhoto.getPhotoVersionId';

// Order on screen: glance, risk, signals, checklist, recommendation, committee approval.
const STEPS = ['Review at a Glance', 'Risk', 'Signals and Evidence', 'Reviewer Checklist', 'Recommendation', 'Committee Approval'];
const RISK = 1;
const SIGNALS = 2;
const CHECKS = 3;
const REC = 4;
const COMMITTEE = 5;
const READ_ONLY = [0, SIGNALS, COMMITTEE];   // steps the committee can open while the review is with them
const STEP_LABEL = { Open: 'Pending', Approved: 'Approved', Rejected: 'Sent Back', Void: 'Not Required', Skipped: 'Not Required' };
const PAGE = 5;      // records shown under a signal before "Show more"
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
const KEEP = ['step', 'maxStep', 'hazard', 'level', 'checks', 'outcome', 'rationale', 'faChoice', 'faTitle', 'actionType', 'recallClass', 'scope', 'lots',
    'team', 'emergency', 'emergencyReason', 'emergencyUser'];

/** Field Action Review workspace: six steps in the page. CQ.AI gathers and suggests, the coordinator recommends, a committee approves. */
export default class CqFieldActionWorkspace extends NavigationMixin(LightningElement) {
    @api recordId;
    v;
    sc;                  // the lots of the part, CQ.AI's suggested scope, and the scope as last recommended
    photoId;
    error;
    step = 0;
    maxStep = 0;
    resumed = false;
    done = false;        // decision is saved
    waiting = false;     // the recommendation is with the committee
    showSummary = false; // the summary screen straight after submitting
    saving = false;
    showAll = {};        // signal id -> true once the reviewer asks for every record
    hazard = '';
    level = '';
    checks = {};
    outcome = '';
    rationale = '';
    faChoice = '';
    faTitle = '';
    actionType = '';
    recallClass = '';
    scope = '';          // Full or Partial, for a new field action
    lots = [];           // lot numbers in scope when Partial
    moreLots = false;    // also list lot numbers that appear on records but have no CQ lot record
    team = {};           // committee seat (job function id) -> the person chosen for it
    emergency = false;
    emergencyReason = '';
    emergencyUser = '';
    comment = '';        // a committee member's comment when approving or sending back

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
        if (!first) { return; }
        let d;
        try { d = v.draft ? JSON.parse(v.draft) : null; } catch (e) { d = null; }
        if (!this.done && d && d.v === 1) {
            KEEP.forEach((k) => { if (d[k] !== undefined) { this[k] = d[k]; } });
            if (!Array.isArray(d.lots)) { this.lots = v.lot ? [v.lot] : []; }     // a draft from before scope was added
            this.resumed = this.maxStep > 0 && !this.waiting;
            if (this.waiting) { this.step = COMMITTEE; this.maxStep = COMMITTEE; }
            this.fillTeam();
            return;
        }
        if (this.waiting) { this.step = COMMITTEE; this.maxStep = COMMITTEE; }
        // first visit: pre-fill from the record and CQ.AI's suggestions; the reviewer can change any of it
        this.hazard = v.hazard || '';
        this.level = v.band;
        this.checks = {};   // the checklist is the reviewer's own answers: nothing is pre-filled
        this.faTitle = (v.title || '').replace(/^Review:\s*/i, '');
        const sug = (v.fieldActions || []).find((f) => f.suggested);
        this.faChoice = sug ? sug.id : (v.fieldActions || []).length ? '' : 'new';
        this.scope = ''; this.lots = v.lot ? [v.lot] : [];   // the review's own lot is ticked to start
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
    get is0() { return this.ready && ((this.open && this.step === 0) || (this.done && !this.showSummary)); }
    get is1() { return this.open && this.step === SIGNALS; }   // the Signals and Evidence block in the template
    get is2() { return this.live && this.step === RISK; }      // the Risk block in the template
    get is3() { return this.live && this.step === CHECKS; }
    get is4() { return this.live && this.step === REC; }
    get is5() { return this.open && this.step === COMMITTEE; }
    get showResumed() { return this.resumed && this.live; }
    get canRestart() { return this.live && this.maxStep > 0 && !this.saving; }
    get canReopen() { return this.done && !this.saving; }

    // ---- step rail
    get valid() {
        return [this.maxStep > 0, this.maxStep > RISK && !!this.hazard.trim() && !!this.level, this.maxStep > SIGNALS, this.checksDone,
            this.maxStep > REC && !!this.outcome && !!this.rationale.trim(), this.done];
    }
    get steps() {
        const v = this.v || {};
        const n = (v.signals || []).length;
        const answered = QUESTIONS.filter((q) => this.checks[q.id]).length;
        const subs = [
            this.maxStep > 0 || this.done ? 'Reviewed' : 'Start here',
            this.maxStep > RISK || this.done ? (this.level || v.riskLevel || v.band) + ' · score ' + v.score : 'CQ.AI suggests ' + v.band,
            n + ' signal' + (n === 1 ? '' : 's'),
            this.done || this.waiting ? 'Answered' : answered + ' of ' + QUESTIONS.length + ' answered',
            this.done ? v.outcome : this.outcome || v.outcome || 'Not decided',
            this.done ? 'Approved' : this.waiting ? this.approvedCount + ' of ' + this.csteps.length + ' approved' : this.emergency ? 'Emergency' : 'Not submitted'
        ];
        const valid = this.valid;
        return STEPS.map((label, i) => {
            const ok = this.done || (this.waiting ? i < COMMITTEE : valid[i]);
            return { i, n: i + 1, label, sub: subs[i], done: ok, notDone: !ok,
                cls: 'step' + ((!this.done && i === this.step) || (this.done && !this.showSummary && i === 0) ? ' active' : '') + (ok ? ' done' : ''),
                locked: !this.canOpen(i) };
        });
    }
    /** While the review is with the committee only the display-only steps open; nothing can be changed. */
    canOpen(i) { return !this.done && (this.waiting ? READ_ONLY.includes(i) : i <= this.maxStep); }
    get progress() { return this.steps.filter((s) => s.done).length + ' of ' + STEPS.length + ' steps complete'; }

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
            ['Affected', n(v.qtyAffected)], ['Shipped', n(v.qtyShipped)], ['Requested by', n(v.requestedBy)]
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
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' } });
    }

    // ---- signals and evidence (third step)
    // Display only: every signal is shown, with the records behind it. The reviewer does not pick, so the committee sees the same set.
    rec(r) {
        return { ...r, meta: [r.kind, r.status, r.lot ? 'lot ' + r.lot : 'no lot', r.why].filter(Boolean).join(' · '),
            line: r.title ? ' · ' + r.title : '' };
    }
    sig(s) {
        const seen = s.firstSeen ? new Date(s.firstSeen).toLocaleDateString() : '';
        const all = (s.records || []).map((r) => this.rec(r));
        const n = all.length;
        const rest = this.showAll[s.id] ? 0 : Math.max(0, n - PAGE);
        return { ...s, pillCls: 'spill ' + (s.strength || '').toLowerCase(),
            meta: [s.name, s.trend, seen ? 'first seen ' + seen : '', !s.lot ? 'whole part' : s.lot === this.v.lot ? 'this lot' : 'lot ' + s.lot,
                s.raisedBy ? 'raised by ' + s.raisedBy : '', s.status === 'Dismissed' ? 'dismissed earlier' : ''].filter(Boolean).join(' \u00b7 '),
            count: n + ' record' + (n === 1 ? '' : 's'),
            records: rest ? all.slice(0, PAGE) : all, hasRest: rest > 0, restLabel: 'Show ' + rest + ' more' };
    }
    handleShowAll(event) { this.showAll = { ...this.showAll, [event.currentTarget.dataset.id]: true }; }
    get signals() { return (this.v.signals || []).map((s) => this.sig(s)); }
    get moreSignals() { return (this.v.moreSignals || []).map((s) => this.sig(s)); }
    get hasSignals() { return this.signals.length > 0; }
    get hasMore() { return this.moreSignals.length > 0; }
    get moreLabel() { const n = this.moreSignals.length; return 'Show ' + n + ' weaker or dismissed signal' + (n === 1 ? '' : 's'); }
    get recs() { return (this.v.records || []).map((r) => this.rec(r)); }
    get hasRecs() { return this.recs.length > 0; }

    // ---- risk (second step)
    get factors() { return (this.v.factors || []).map((f, i) => ({ ...f, key: 'f' + i, of: f.pts + ' / ' + f.max })); }
    get bandCls() { return 'lvl ' + (this.v.band || '').toLowerCase(); }
    get levels() {
        return LEVELS.map((l) => ({ id: l, cq: l === this.v.band, cls: 'opt' + (this.level === l ? ' on' : l === this.v.band ? ' sug' : '') }));
    }
    handleLevel(event) { this.level = event.currentTarget.dataset.id; }

    // ---- step 4: reviewer checklist (styled like the PHR checklist)
    get questions() {
        return QUESTIONS.map((q) => ({
            ...q,
            opts: ANSWERS.map((a) => ({ key: q.id + a, q: q.id, a, cls: 'yn' + (this.checks[q.id] === a ? ' sel' : ''), pressed: this.checks[q.id] === a ? 'true' : 'false' }))
        }));
    }
    get checksDone() { return QUESTIONS.every((q) => !!this.checks[q.id]); }
    handleCheck(event) { const d = event.currentTarget.dataset; this.checks = { ...this.checks, [d.q]: d.a }; }

    // ---- step 5: recommendation
    get outcomes() {
        return [['No Field Action', 'Nothing further is needed in the field.'],
                ['Field Action Needed', 'Start a field action, or join one that already covers this problem.']]
            .map(([id, why]) => ({ id, why, cq: id === this.v.suggestedOutcome, cls: 'pathopt' + (this.outcome === id ? ' on' : id === this.v.suggestedOutcome ? ' sug' : '') }));
    }
    get needed() { return this.outcome === 'Field Action Needed'; }
    get faOpts() {
        const list = (this.v.fieldActions || []).map((f) => ({
            id: f.id, label: 'Join ' + f.name, cq: f.suggested,
            why: [f.title, f.actionType, f.status, f.why].filter(Boolean).join(' · ')
        }));
        list.push({ id: 'new', label: 'Start a new Field Action', why: 'For a problem no open field action covers.', cq: !list.some((x) => x.cq) && !list.length });
        return list.map((o) => ({ ...o, cls: 'act' + (this.faChoice === o.id ? ' on' : o.cq ? ' sug' : ''), tick: this.faChoice === o.id ? '✓' : '' }));
    }
    get isNew() { return this.needed && this.faChoice === 'new'; }
    get typeOpts() { return TYPES.map((t) => ({ value: t, selected: this.actionType === t })); }
    get classOpts() { return CLASSES.map((t) => ({ value: t, selected: this.recallClass === t })); }
    // scope of a new field action: Full is every lot of the part, Partial the lots ticked
    get scopeData() { return this.sc || {}; }
    get scopeOpts() {
        const sug = this.scopeData.suggested;
        return SCOPES.map((id) => ({ id, cq: id === sug, cls: 'opt' + (this.scope === id ? ' on' : id === sug ? ' sug' : '') }));
    }
    get scopeSuggests() { return this.scopeData.suggested ? 'CQ.AI Suggests ' + this.scopeData.suggested + '. ' + (this.scopeData.why || '') : ''; }
    get isPartial() { return this.scope === 'Partial'; }
    get isFull() { return this.scope === 'Full'; }
    /** Full covers the lots on record in CQ, and the review's own lot. */
    get allLots() { return (this.scopeData.lots || []).filter((l) => l.known || l.thisLot).map((l) => l.name); }
    get lotOpts() {
        const day = (d) => { const p = String(d || '').split('-'); return p.length === 3 ? new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2])).toLocaleDateString() : ''; };
        const n = (x, word) => x + ' ' + word + (x === 1 ? '' : 's');
        return (this.scopeData.lots || []).filter((l) => this.moreLots || l.known || l.thisLot || l.suggested || this.lots.includes(l.name)).map((l) => {
            const on = this.lots.includes(l.name);
            return { ...l, cls: 'act' + (on ? ' on' : l.suggested ? ' sug' : ''), tick: on ? '✓' : '', pressed: on ? 'true' : 'false',
                meta: [l.built !== undefined && l.built !== null ? l.built + ' built' : '', l.made ? 'made ' + day(l.made) : '',
                    n(l.records, 'record'), n(l.signals, 'signal'), l.why].filter(Boolean).join(' · ') };
        });
    }
    get hiddenLots() { return this.moreLots ? 0 : (this.scopeData.lots || []).length - this.lotOpts.length; }
    get hasHiddenLots() { return this.hiddenLots > 0; }
    get moreLotsLabel() { const n = this.hiddenLots; return 'Show ' + n + ' more lot number' + (n === 1 ? '' : 's') + ' found on records'; }
    handleMoreLots() { this.moreLots = true; }
    get fullLine() {
        const all = this.allLots;
        return 'Every lot of ' + this.partText + ' on record in CQ (' + all.length + ')' + (all.length ? ': ' + all.join(', ') : '') + '.';
    }
    /** The scope as one line, for the committee's card and the summary. */
    get scopeLine() {
        const sc = this.scopeData;
        if (this.outcomeNow !== 'Field Action Needed') { return ''; }
        const scope = this.done ? sc.scope : this.isNew ? this.scope : '';     // a review that joins a field action has no scope of its own
        const saved = sc.chosen || [];
        if (!scope) { const lot = saved.length ? saved.join(', ') : this.v.lot; return lot ? 'Adds lot ' + lot + ' to the field action' : ''; }
        const lots = scope === 'Full' ? (saved.length ? saved : this.allLots) : (this.live || !saved.length ? this.lots : saved);
        return scope + ' · ' + (scope === 'Full' ? 'all ' + lots.length + ' lot' + (lots.length === 1 ? '' : 's') + ' of the part: ' : 'lot' + (lots.length === 1 ? ' ' : 's ')) + lots.join(', ');
    }
    handleScope(event) { this.scope = event.currentTarget.dataset.id; }
    handleLot(event) {
        const id = event.currentTarget.dataset.id;
        this.lots = this.lots.includes(id) ? this.lots.filter((x) => x !== id) : [...this.lots, id];
    }
    handleOutcome(event) { this.outcome = event.currentTarget.dataset.id; }
    handleFa(event) { this.faChoice = event.currentTarget.dataset.id; }
    handleInput(event) { this[event.target.dataset.f] = event.target.value; }

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
    get csteps() {
        return (this.committee.steps || []).map((s) => ({
            ...s, label: STEP_LABEL[s.status] || s.status, cls: 'cpill ' + (s.status || '').toLowerCase(),
            line: [s.person, s.doneOn ? new Date(s.doneOn).toLocaleString() : '', s.doneBy && s.doneBy !== s.person ? 'recorded by ' + s.doneBy : ''].filter(Boolean).join(' \u00b7 '),
            quote: s.comment ? '\u201c' + s.comment + '\u201d' : ''
        }));
    }
    get approvedCount() { return this.csteps.filter((s) => s.status === 'Approved').length; }
    get canActAny() { return this.csteps.some((s) => s.canAct); }
    get committeeTitle() { return 'Committee' + (this.committee.approvalName ? ' \u00b7 ' + this.committee.approvalName : ''); }
    get sentBack() { return this.live ? this.committee.sentBack : ''; }
    /** What the committee is approving: the coordinator's recommendation and what it rests on. */
    get recRows() {
        const v = this.v; const c = this.committee;
        const fa = this.outcomeNow !== 'Field Action Needed' ? '' : this.faChoice === 'new'
            ? 'Start a new Field Action: ' + [this.faTitle, this.actionType, this.recallClass].filter(Boolean).join(' \u00b7 ')
            : 'Join ' + (((v.fieldActions || []).find((f) => f.id === this.faChoice) || {}).name || 'an open Field Action');
        return [
            ['Outcome', this.outcomeNow], ['Field Action', fa], ['Scope', this.scopeLine], ['Rationale', this.rationale || v.rationale],
            ['Risk', (this.level || v.riskLevel || v.band) + ' \u00b7 score ' + v.score + ' of 100'],
            ['Health Hazard Summary', this.hazard || v.hazard],
            ['Checklist', QUESTIONS.filter((q) => this.checks[q.id]).map((q) => q.text + ' ' + this.checks[q.id]).join('\n')],
            ['Recommended By', [c.recommendedBy, c.recommendedOn ? new Date(c.recommendedOn).toLocaleString() : ''].filter(Boolean).join(' \u00b7 ')],
            ['Emergency', c.emergency ? c.emergencyReason : '']
        ].filter(([, val]) => !!val).map(([k, val]) => ({ key: k, k, v: val }));
    }
    get outcomeNow() { return this.outcome || this.v.outcome; }
    async handleAct(event) {
        const d = event.currentTarget.dataset;
        if (this.saving) { return; }
        if (d.a === 'reject' && !this.comment.trim()) { this.error = 'Add a comment saying why you are sending it back.'; return; }
        this.saving = true; this.error = undefined;
        try {
            const v = await actOnStep({ recordId: this.recordId, stepId: d.id, action: d.a, comment: this.comment.trim() });
            this.comment = '';
            this.apply(v, false);
            if (this.done) { this.showSummary = true; }
            else if (!this.waiting) { this.step = REC; }      // sent back: the coordinator picks it up at the recommendation
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (e) { this.error = this.msg(e, 'Could not record that.'); }
        this.saving = false;
    }

    // ---- navigation
    get blocker() {
        if (this.step === RISK) {
            if (!this.hazard.trim()) { return 'Write the health hazard summary'; }
            if (!this.level) { return 'Choose a risk level'; }
        }
        if (this.step === CHECKS && !this.checksDone) { return 'Answer every question'; }
        if (this.step === COMMITTEE) {
            if (this.emergency) {
                if (!this.emergencyUser) { return 'Choose the emergency approver'; }
                if (!this.emergencyReason.trim()) { return 'Give the reason for the emergency'; }
            } else {
                const m = this.members;
                if (!m.length || m.some((x) => !x.userId)) { return 'Choose a person for every seat'; }
                if (new Set(m.map((x) => x.userId)).size !== m.length) { return 'One person can hold only one seat'; }
            }
        }
        if (this.step === REC) {
            if (!this.outcome) { return 'Click an outcome to choose it'; }
            if (!this.rationale.trim()) { return 'Rationale needed'; }
            if (this.needed && !this.faChoice) { return 'Join a field action or start a new one'; }
            if (this.isNew && (!this.faTitle.trim() || !this.actionType)) { return 'Title and action type needed'; }
            if (this.isNew && !this.scope) { return 'Choose Full or Partial'; }
            if (this.isNew && this.isPartial && !this.lots.length) { return 'Choose at least one lot'; }
        }
        return '';
    }
    get cantNext() { return !!this.blocker || this.saving; }
    get cantBack() { return this.step === 0 || this.saving; }
    get nextLabel() { return this.saving ? 'Saving…' : this.step === COMMITTEE ? 'Submit to Committee' : 'Next'; }
    persist() {
        if (this.done) { return; }
        const s = { v: 1 };
        KEEP.forEach((k) => { s[k] = this[k]; });
        saveDraft({ recordId: this.recordId, draft: JSON.stringify(s) }).catch(() => {});
    }
    handleBack() { if (this.step > 0) { this.step -= 1; this.persist(); } }
    handleStep(event) {
        const i = Number(event.currentTarget.dataset.i);
        if (this.canOpen(i)) { this.step = i; if (this.live) { this.persist(); } }
    }
    handleRestart() {
        this.step = 0; this.maxStep = 0; this.resumed = false; this.error = undefined;
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
            ['Rationale', v.rationale], ['Committee', this.committee.approvalName ? this.committee.approvalName + ' \u00b7 ' + this.approvedCount + ' of ' + this.csteps.length + ' approved' : ''],
            ['Approved by', v.decidedBy]
        ].filter(([, val]) => !!val).map(([k, val]) => ({ key: k, k, v: val }));
    }
    handleFinish() { this.showSummary = false; }

    async handleNext() {
        if (this.blocker || this.saving) { return; }
        this.resumed = false;
        if (this.step < COMMITTEE) {
            this.step += 1;
            this.maxStep = Math.max(this.maxStep, this.step);
            this.persist();
            return;
        }
        this.saving = true;
        this.error = undefined;
        try {
            const d = { v: 1 };
            KEEP.forEach((k) => { d[k] = this[k]; });
            const v = await submitToCommittee({
                recordId: this.recordId, hazard: this.hazard.trim(), summary: this.buildSummary(), score: this.v.score, riskLevel: this.level,
                outcome: this.outcome, rationale: this.rationale.trim(), draft: JSON.stringify(d), team: JSON.stringify(this.members),
                emergency: this.emergency, emergencyReason: this.emergencyReason.trim(),
                scope: this.isNew ? this.scope : '', lots: this.isNew && this.isPartial ? this.lots : []
            });
            this.apply(v, false);
            try { this.sc = await getScope({ recordId: this.recordId }); } catch (e) { /* the scope shown stays as recommended */ }
            this.step = COMMITTEE; this.maxStep = COMMITTEE;
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (e) {
            this.error = this.msg(e, 'Could not submit to the committee.');
        }
        this.saving = false;
    }
}
