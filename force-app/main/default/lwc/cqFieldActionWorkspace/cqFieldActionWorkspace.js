import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqFieldActionReview.getView';
import saveDraft from '@salesforce/apex/CqFieldActionReview.saveDraft';
import submitReview from '@salesforce/apex/CqFieldActionReview.submit';
import reopenReview from '@salesforce/apex/CqFieldActionReview.reopen';

// Order on screen: glance, risk, signals, checklist, decision. RISK and SIGNALS are the step numbers of those two.
const STEPS = ['Review at a Glance', 'Risk', 'Signals and Evidence', 'Reviewer Checklist', 'Decision'];
const RISK = 1;
const SIGNALS = 2;
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
const KEEP = ['step', 'maxStep', 'picks', 'hazard', 'level', 'checks', 'outcome', 'rationale', 'faChoice', 'faTitle', 'actionType', 'recallClass'];

/** Field Action Review workspace: five steps in the page. CQ.AI gathers and suggests, the reviewer decides. */
export default class CqFieldActionWorkspace extends NavigationMixin(LightningElement) {
    @api recordId;
    v;
    error;
    step = 0;
    maxStep = 0;
    resumed = false;
    done = false;        // decision is saved
    showSummary = false; // the summary screen straight after submitting
    saving = false;
    picks = {};
    hazard = '';
    level = '';
    checks = {};
    outcome = '';
    rationale = '';
    faChoice = '';
    faTitle = '';
    actionType = '';
    recallClass = '';

    async connectedCallback() {
        try {
            this.apply(await getView({ recordId: this.recordId }), true);
        } catch (e) {
            this.error = this.msg(e, 'Could not read this review.');
        }
    }

    apply(v, first) {
        this.v = v;
        this.done = v.status === 'Decided' || v.status === 'Closed';
        if (!first) { return; }
        let d;
        try { d = v.draft ? JSON.parse(v.draft) : null; } catch (e) { d = null; }
        if (!this.done && d && d.v === 1) {
            KEEP.forEach((k) => { if (d[k] !== undefined) { this[k] = d[k]; } });
            this.resumed = this.maxStep > 0;
            return;
        }
        // first visit: pre-fill from the record and CQ.AI's suggestions; the reviewer can change any of it
        const picks = {};
        (v.records || []).forEach((r) => { if (r.suggested) { picks[r.id] = true; } });
        this.picks = picks;
        this.hazard = v.hazard || '';
        this.level = v.band;
        this.checks = {};   // the checklist is the reviewer's own answers: nothing is pre-filled
        this.faTitle = (v.title || '').replace(/^Review:\s*/i, '');
        const sug = (v.fieldActions || []).find((f) => f.suggested);
        this.faChoice = sug ? sug.id : (v.fieldActions || []).length ? '' : 'new';
    }

    msg(e, fallback) { return (e && e.body && e.body.message) || fallback; }
    get ready() { return !!this.v; }
    get heading() { return (this.v.name || '') + (this.v.title ? ' · ' + this.v.title : ''); }
    get live() { return this.ready && !this.done; }
    get is0() { return this.ready && ((!this.done && this.step === 0) || (this.done && !this.showSummary)); }
    get is1() { return this.live && this.step === SIGNALS; }   // the Signals and Evidence block in the template
    get is2() { return this.live && this.step === RISK; }      // the Risk block in the template
    get is3() { return this.live && this.step === 3; }
    get is4() { return this.live && this.step === 4; }
    get showResumed() { return this.resumed && this.live; }
    get canRestart() { return this.live && this.maxStep > 0 && !this.saving; }
    get canReopen() { return this.done && !this.saving; }

    // ---- step rail
    get valid() {
        return [this.maxStep > 0, this.maxStep > RISK && !!this.hazard.trim() && !!this.level, this.maxStep > SIGNALS, this.checksDone, this.done];
    }
    get steps() {
        const v = this.v || {};
        const n = this.pickedRecords.length;
        const answered = QUESTIONS.filter((q) => this.checks[q.id]).length;
        const subs = [
            this.maxStep > 0 || this.done ? 'Reviewed' : 'Start here',
            this.maxStep > RISK || this.done ? (this.level || v.riskLevel || v.band) + ' · score ' + v.score : 'CQ.AI suggests ' + v.band,
            this.maxStep > SIGNALS || this.done ? n + ' record' + (n === 1 ? '' : 's') + ' considered' : this.sameLot.length + ' on the same lot',
            this.done ? 'Answered' : answered + ' of ' + QUESTIONS.length + ' answered',
            this.done ? v.outcome : this.outcome || 'Not decided'
        ];
        const valid = this.valid;
        return STEPS.map((label, i) => {
            const ok = this.done || valid[i];
            return { i, n: i + 1, label, sub: subs[i], done: ok, notDone: !ok,
                cls: 'step' + ((!this.done && i === this.step) || (this.done && !this.showSummary && i === 0) ? ' active' : '') + (ok ? ' done' : ''),
                locked: this.done || i > this.maxStep };
        });
    }
    get progress() { return this.steps.filter((s) => s.done).length + ' of ' + STEPS.length + ' steps complete'; }

    // ---- step 1: review at a glance
    get problem() { const v = this.v; return v.problem || v.sourceTitle || v.title || 'No description on the source record.'; }
    get hasSource() { return !!this.v.sourceId; }
    get sourceLabel() { return this.v.sourceKind + ' ' + this.v.sourceName; }
    get tiles() {
        const v = this.v;
        const n = (x) => (x === undefined || x === null || x === '' ? '—' : String(x));
        return [
            ['Part', n(v.partName)], ['Lot', n(v.lot)], ['Affected', n(v.qtyAffected)], ['Shipped', n(v.qtyShipped)],
            ['Due', n(v.due)], ['Requested by', n(v.requestedBy)], ['Reviewer', n(v.reviewer)]
        ].map(([label, value]) => ({ key: label, label, value }));
    }
    get decidedLine() {
        const v = this.v;
        return 'Decided' + (v.decidedBy ? ' by ' + v.decidedBy : '') + ' · ' + v.outcome + (v.faName ? ' · ' + v.faName : '');
    }
    get hasFa() { return !!this.v.faId; }
    handleOpen(event) {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' } });
    }

    // ---- signals and evidence (third step)
    get recs() {
        return (this.v.records || []).map((r) => {
            const on = !!this.picks[r.id];
            return { ...r, on, pressed: on ? 'true' : 'false', tick: on ? '✓' : '',
                meta: [r.kind, r.status, r.lot ? 'lot ' + r.lot : 'no lot', r.why].filter(Boolean).join(' · '),
                line: r.name + (r.title ? ' · ' + r.title : ''),
                cls: 'act' + (on ? ' on' : r.suggested ? ' sug' : '') };
        });
    }
    get sameLot() { return this.recs.filter((r) => r.sameLot); }
    get otherRecs() { return this.recs.filter((r) => !r.sameLot); }
    get hasSameLot() { return this.sameLot.length > 0; }
    get hasOther() { return this.otherRecs.length > 0; }
    get noRecs() { return !this.recs.length; }
    get otherLabel() { return 'Other records on this part (' + this.otherRecs.length + ')'; }
    get pickedRecords() { return this.recs.filter((r) => r.on); }
    handleRec(event) { const id = event.currentTarget.dataset.id; this.picks = { ...this.picks, [id]: !this.picks[id] }; }

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

    // ---- step 5: decision
    get outcomes() {
        return [['No Field Action', 'Close this review. Nothing further is needed in the field.'],
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
    handleOutcome(event) { this.outcome = event.currentTarget.dataset.id; }
    handleFa(event) { this.faChoice = event.currentTarget.dataset.id; }
    handleInput(event) { this[event.target.dataset.f] = event.target.value; }

    // ---- navigation
    get blocker() {
        if (this.step === RISK) {
            if (!this.hazard.trim()) { return 'Write the health hazard summary'; }
            if (!this.level) { return 'Choose a risk level'; }
        }
        if (this.step === 3 && !this.checksDone) { return 'Answer every question'; }
        if (this.step === 4) {
            if (!this.outcome) { return 'Click an outcome to choose it'; }
            if (!this.rationale.trim()) { return 'Rationale needed'; }
            if (this.needed && !this.faChoice) { return 'Join a field action or start a new one'; }
            if (this.isNew && (!this.faTitle.trim() || !this.actionType)) { return 'Title and action type needed'; }
        }
        return '';
    }
    get cantNext() { return !!this.blocker || this.saving; }
    get cantBack() { return this.step === 0 || this.saving; }
    get nextLabel() { return this.saving ? 'Saving…' : this.step === 4 ? 'Submit decision' : 'Next'; }
    persist() {
        if (this.done) { return; }
        const s = { v: 1 };
        KEEP.forEach((k) => { s[k] = this[k]; });
        saveDraft({ recordId: this.recordId, draft: JSON.stringify(s) }).catch(() => {});
    }
    handleBack() { if (this.step > 0) { this.step -= 1; this.persist(); } }
    handleStep(event) {
        const i = Number(event.currentTarget.dataset.i);
        if (!this.done && i <= this.maxStep) { this.step = i; this.persist(); }
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
            'Evidence considered: ' + (this.pickedRecords.map((r) => r.name).join(', ') || 'none'),
            'Risk score: ' + v.score + ' of 100 (' + v.band + '). ' + (v.factors || []).map((f) => f.name + ' ' + f.pts + '/' + f.max).join('; '),
            'Risk level: ' + this.level + (this.level === v.band ? ' (as CQ.AI suggested)' : ' (CQ.AI suggested ' + v.band + ')'),
            'Checklist: ' + QUESTIONS.map((q) => q.text + ' ' + this.checks[q.id]).join(' | '),
            'Outcome: ' + this.outcome + (this.outcome === v.suggestedOutcome ? ' (as CQ.AI suggested)' : ' (CQ.AI suggested ' + v.suggestedOutcome + ')')
        ].join('\n');
    }
    get summaryRows() {
        const v = this.v;
        return [
            ['Outcome', v.outcome], ['Field Action', v.faName || 'None'], ['Risk', (v.riskLevel || '') + ' · score ' + v.score + ' of 100'],
            ['Rationale', v.rationale], ['Decided by', v.decidedBy]
        ].map(([k, val]) => ({ key: k, k, v: val }));
    }
    handleFinish() { this.showSummary = false; }

    async handleNext() {
        if (this.blocker || this.saving) { return; }
        this.resumed = false;
        if (this.step < 4) {
            this.step += 1;
            this.maxStep = Math.max(this.maxStep, this.step);
            this.persist();
            return;
        }
        this.saving = true;
        this.error = undefined;
        try {
            const join = this.needed && this.faChoice !== 'new';
            const v = await submitReview({
                recordId: this.recordId, hazard: this.hazard.trim(), summary: this.buildSummary(), score: this.v.score, riskLevel: this.level,
                outcome: this.outcome, rationale: this.rationale.trim(),
                fieldActionId: join ? this.faChoice : null, faTitle: this.faTitle.trim(), actionType: this.actionType, recallClass: this.recallClass
            });
            this.apply(v, false);
            this.showSummary = true;
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (e) {
            this.error = this.msg(e, 'Could not save the decision.');
        }
        this.saving = false;
    }
}
