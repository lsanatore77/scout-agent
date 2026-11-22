import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqDispositionWorkspace.getView';
import completeDispositions from '@salesforce/apex/CqDispositionWorkspace.completeDispositions';

// Ask CQ.AI ready questions for each step (no commas: the popover splits on them)
const ASK = {
    'Disposition at a Glance': 'Why does CQ.AI suggest this disposition?,What was done with this part before?,What is still open on this NC?',
    'Dispose by Lot': 'Why does CQ.AI suggest this disposition?,When is Use As Is acceptable?,What happens when I complete the disposition?',
    'Disposition Complete': 'What is still open on this NC?,Summarize this nonconformance'
};
const STEPS = ['Disposition at a Glance', 'Dispose by Lot'];
const USE_AS_IS = 'Use As Is';

/**
 * CQ.AI Disposition workspace: the nonconformance's record header, then two steps in the page.
 * Disposition at a Glance shows the problem, CQ.AI's suggestion, the lots and what was done on this part before.
 * Dispose by Lot records what was done with each lot (a lot can be split across types) and Complete Disposition
 * saves and completes the dispositions in CQ in one step. Steps can be opened in any order.
 */
export default class CqDispositionWorkspace extends NavigationMixin(LightningElement) {
    @api recordId;
    v;
    loadError;
    error;
    step = 0;
    seen = { 0: true };
    forms = [];         // per open lot: { impactedId, rows: [{ key, draftId, type, qty, completedOn, comment, justification }] }
    result;             // what Complete Disposition did
    suggestedAtSave;
    saving = false;
    keySeq = 0;

    connectedCallback() { this.load(); }

    async load() {
        try {
            this.v = await getView({ recordId: this.recordId });
            this.loadError = undefined;
            this.initForms();
        } catch (e) {
            this.loadError = this.msg(e, 'Could not read this nonconformance.');
        }
    }

    initForms() {
        const today = this.todayIso();
        this.forms = (this.v.lots || []).filter((l) => l.left > 0).map((l) => ({
            impactedId: l.impactedId,
            rows: [{ key: 'r' + (this.keySeq++), draftId: l.draftId, type: this.v.suggestType, qty: this.num(l.left), completedOn: today, comment: '', justification: '' }]
        }));
    }

    get ready() { return !!this.v; }
    msg(e, fallback) { return (e && e.body && e.body.message) || (e && e.message) || fallback; }
    num(x) { return x === undefined || x === null ? 0 : Number(x); }
    fmt(x) { const n = this.num(x); return Number.isInteger(n) ? String(n) : String(+n.toFixed(2)); }
    todayIso() { const d = new Date(); const p = (n) => String(n).padStart(2, '0'); return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()); }
    dateText(iso) { return iso ? new Date(iso + 'T00:00:00').toLocaleDateString() : '—'; }
    dash(x) { return x === undefined || x === null || x === '' ? '—' : String(x); }
    href(id) { return '/lightning/r/' + id + '/view'; }
    units(n) { return this.fmt(n) + (this.num(n) === 1 ? ' Unit' : ' Units'); }

    // ---- header
    get titleText() { return this.dash(this.v.title); }
    get lotText() { return this.dash(this.v.lot); }
    get stageText() { return this.v.stage ? this.v.stage.replace(/\s*\/\s*/, ' / ') : '—'; }
    get riskText() { return this.dash(this.v.risk); }
    get dueText() { return this.dateText(this.v.dispDue); }
    get ownerText() { return this.dash(this.v.owner); }
    get partHref() { return '/lightning/r/compliancequest__SQX_Part__c/' + this.v.partId + '/view'; }
    get invHref() { return this.href(this.v.investigationId); }
    get userText() { return 'you'; }
    /** The header fields the shared frame (c-cq-ws-shell) draws; the risk level in its colour. */
    get headerFields() {
        const tone = { low: 'pos', medium: 'warn', high: 'crit' }[(this.v.risk || '').toLowerCase()];
        return [
            { key: 'title', label: 'Title', value: this.titleText },
            { key: 'part', label: 'Part', value: this.v.partNumber, id: this.v.partId },
            { key: 'lot', label: 'Lot', value: this.lotText },
            { key: 'stage', label: 'Stage', value: this.stageText },
            { key: 'risk', label: 'Risk', value: this.riskText, tone },
            { key: 'due', label: 'Disposition Due', value: this.dueText },
            { key: 'owner', label: 'Owner', value: this.ownerText }
        ];
    }
    /** A header link (the part) opens in a new tab, as it did before the shared frame. */
    handleShellOpen(event) { window.open(this.href(event.detail), '_blank'); }
    handleEdit() {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage',
            attributes: { recordId: this.recordId, objectApiName: 'compliancequest__SQX_Nonconformance__c', actionName: 'edit' } });
    }

    // ---- Ask CQ.AI, told which step is open
    get askStep() { return this.showDone ? 'Disposition Complete' : STEPS[this.step]; }
    get askSuggestions() { return ASK[this.askStep]; }

    // ---- what is shown
    get isDone() { return !!this.result || this.v.isComplete; }
    get showDone() { return this.isDone; }
    get showGlance() { return !this.isDone && this.step === 0; }
    get showDispose() { return !this.isDone && this.step === 1; }

    get steps() {
        const done = this.isDone;
        const subs = [
            done || this.step !== 0 ? 'Reviewed' : 'Start Here',
            done ? this.doneSummary : this.seen[1] ? this.planSummary : 'Not Reviewed'
        ];
        // the glance is done once you move on from it; Dispose by Lot is done when the dispositions are complete
        const stepDone = [done || this.step !== 0, done];
        return STEPS.map((label, i) => ({
            i, n: i + 1, label, sub: subs[i], done: stepDone[i], notDone: !stepDone[i],
            cls: 'step' + (!done && i === this.step ? ' active' : '') + (stepDone[i] ? ' done' : '')
        }));
    }
    /** The rail as the shared frame draws it. */
    get railSteps() { return this.steps.map((s) => ({ label: s.label, sub: s.sub, done: s.done, active: s.cls.includes('active') })); }
    get notDone() { return !this.showDone; }
    get progress() { return this.steps.filter((s) => s.done).length + ' of 2 steps complete'; }
    get planSummary() {
        const by = {};
        this.forms.forEach((f) => f.rows.forEach((r) => { if (r.type) { by[r.type] = (by[r.type] || 0) + this.num(r.qty); } }));
        const parts = Object.keys(by).map((t) => t + ' ' + this.fmt(by[t]));
        return parts.length ? parts.join(' · ') : 'Choose a Type';
    }
    get doneSummary() {
        const recs = this.result ? this.result.done : this.allRecords.filter((r) => r.status === 'Complete');
        const by = {};
        recs.forEach((r) => { if (r.type) { by[r.type] = (by[r.type] || 0) + this.num(r.qty); } });
        const parts = Object.keys(by).map((t) => t + ' ' + this.fmt(by[t]));
        return (parts.length ? parts.join(' · ') + ' · ' : '') + 'Complete';
    }
    get allRecords() { const out = []; (this.v.lots || []).forEach((l) => (l.records || []).forEach((r) => out.push(r))); return out; }

    // ---- step 1: Disposition at a Glance
    get problemText() { return this.v.description || this.v.title || 'No description on this NC.'; }
    get totalLeft() { return (this.v.lots || []).reduce((a, l) => a + this.num(l.left), 0); }
    get leftText() { return this.units(this.totalLeft); }
    get lotCount() { return (this.v.lots || []).length; }
    get noLots() { return this.lotCount === 0; }
    get approvalText() { return this.v.needsApproval ? 'Required' : 'Not Required'; }
    get suggestHeadline() {
        if (!this.v.suggestType || this.totalLeft === 0) { return 'Nothing to Dispose'; }
        const open = (this.v.lots || []).filter((l) => l.left > 0);
        if (open.length === 1) { return this.v.suggestType + ' ' + this.units(open[0].left) + ' of Lot ' + open[0].lot; }
        return this.v.suggestType + ' ' + this.units(this.totalLeft);
    }
    get lotRows() {
        return (this.v.lots || []).map((l) => ({
            impactedId: l.impactedId, partName: l.partName || '—', lot: l.lot,
            impactedText: this.fmt(l.impacted), disposedText: this.fmt(l.disposed), leftText: this.fmt(l.left),
            leftCls: 'num strong' + (l.left > 0 ? ' amber' : ' green'),
            recs: (l.records || []).map((r) => ({ id: r.id, name: r.name, href: this.href(r.id),
                meta: '· ' + (r.type ? r.type + ' ' : '') + this.fmt(r.qty) + ' · ' + r.status })),
            noRecs: !(l.records && l.records.length)
        }));
    }
    get triagedText() {
        const bits = ['Triaged'];
        if (this.v.risk) { bits.push('Risk ' + this.v.risk); }
        if (this.v.path) { bits.push(this.v.path); }
        return bits.join(' · ');
    }
    get decidedDisp() {
        return 'Disposition Required, due ' + this.dueText + (this.v.needsApproval ? ', needs approval' : ', no approval');
    }
    get hasHistory() { return (this.v.history || []).length > 0; }
    get historyRows() {
        return (this.v.history || []).map((h, i) => ({ key: 'h' + i, ncName: h.ncName, href: this.href(h.ncId),
            meta: h.type + ' ' + this.fmt(h.qty) + (h.lot ? ' · Lot ' + h.lot : '') }));
    }

    // ---- step 2: Dispose by Lot
    get lotForms() {
        const types = this.v.types || [];
        return (this.v.lots || []).map((l) => {
            const fi = this.forms.findIndex((f) => f.impactedId === l.impactedId);
            const f = fi >= 0 ? this.forms[fi] : null;
            const planned = f ? f.rows.reduce((a, r) => a + this.num(r.qty), 0) : 0;
            const over = f && planned > this.num(l.left);
            return {
                impactedId: l.impactedId, lot: l.lot, partName: l.partName, idx: fi, open: !!f, draftName: l.draftName,
                suggestText: this.v.suggestType + ' ' + this.fmt(l.left),
                doneText: !f ? 'All ' + this.fmt(l.impacted) + ' Disposed' : null,
                // too many is an error; fewer is allowed today and the rest stays on the lot
                qtyMsg: !f ? null
                    : over ? 'Your Disposition Quantity is ' + this.fmt(l.left) + (f.rows.length > 1 ? ', please make sure your splits are equal to the Disposition Quantity.' : '.')
                    : planned > 0 && planned < this.num(l.left) ? 'You\'ve entered ' + this.fmt(planned) + ', there are ' + this.fmt(this.num(l.left) - planned) + ' remaining items left to Disposition.'
                    : null,
                rows: f ? f.rows.map((r, ri) => ({
                    ...r, idx: ri, canRemove: f.rows.length > 1, needsWhy: r.type === USE_AS_IS,
                    typeOpts: types.map((t) => ({ label: t, pressed: String(r.type === t),
                        cls: 'cq-chip' + (t === this.v.suggestType ? ' ai' : '') }))
                })) : []
            };
        });
    }
    row(event) {
        const li = Number(event.currentTarget.dataset.lot);
        const ri = Number(event.currentTarget.dataset.row);
        return { li, ri };
    }
    update(li, fn) {
        this.forms = this.forms.map((f, i) => (i === li ? { ...f, rows: fn(f.rows.map((r) => ({ ...r }))) } : f));
        this.error = undefined;
    }
    handleType(event) {
        const { li, ri } = this.row(event);
        const t = event.currentTarget.dataset.type;
        this.update(li, (rows) => { rows[ri].type = t; return rows; });
    }
    handleField(event) {
        const { li, ri } = this.row(event);
        const k = event.currentTarget.dataset.f;
        const val = event.target.value;
        this.update(li, (rows) => { rows[ri][k] = k === 'qty' ? (val === '' ? null : Number(val)) : val; return rows; });
    }
    handleSplit(event) {
        const li = Number(event.currentTarget.dataset.lot);
        const lot = this.v.lots.find((l) => l.impactedId === this.forms[li].impactedId);
        this.update(li, (rows) => {
            const planned = rows.reduce((a, r) => a + this.num(r.qty), 0);
            let rest = this.num(lot.left) - planned;
            // splitting a full first row takes one unit off it for the new row
            if (rest <= 0 && rows.length && this.num(rows[rows.length - 1].qty) > 1) {
                rows[rows.length - 1].qty = this.num(rows[rows.length - 1].qty) - 1;
                rest = 1;
            }
            rows.push({ key: 'r' + (this.keySeq++), draftId: null, type: null, qty: rest > 0 ? rest : null,
                completedOn: rows.length ? rows[0].completedOn : this.todayIso(), comment: '', justification: '' });
            return rows;
        });
    }
    handleRemove(event) {
        const { li, ri } = this.row(event);
        this.update(li, (rows) => {
            const gone = rows.splice(ri, 1)[0];
            if (gone.draftId && rows.length) { rows[0].draftId = gone.draftId; }
            return rows;
        });
    }

    // ---- footer
    stepBlocker() {
        if (this.v.needsApproval) { return 'Needs approval: use the Disposition tab'; }
        if (!this.forms.length) { return 'Nothing is left to dispose'; }
        for (const f of this.forms) {
            const lot = this.v.lots.find((l) => l.impactedId === f.impactedId);
            const name = 'Lot ' + lot.lot + ': ';
            for (const r of f.rows) {
                if (!r.type) { return name + 'choose a type'; }
                if (!(this.num(r.qty) > 0)) { return name + 'enter a quantity'; }
                if (!r.completedOn) { return name + 'enter the completed date'; }
                if (r.type === USE_AS_IS && !(r.justification || '').trim()) { return name + 'Use As Is needs a justification'; }
            }
        }
        return null;
    }
    /** A lot with more entered than it has left. Its own message says so under the rows, so the footer stays quiet. */
    get anyOver() {
        return this.forms.some((f) => f.rows.reduce((a, r) => a + this.num(r.qty), 0) > this.num(this.v.lots.find((l) => l.impactedId === f.impactedId).left));
    }
    get blocker() { return this.showDispose ? this.stepBlocker() : null; }
    get cantComplete() { return this.saving || !!this.stepBlocker(); }
    get completeLabel() { return this.saving ? 'Completing…' : 'Complete Disposition'; }
    get cantBack() { return this.step === 0; }
    get cantNext() { return this.step >= STEPS.length - 1; }
    get nextCls() { return this.cantNext ? 'cq-btn-outline' : 'cq-btn-primary'; }

    go(i) {
        this.step = i;
        this.seen = { ...this.seen, [i]: true };
        this.error = undefined;
    }
    handleStep(event) { if (!this.isDone) { this.go(Number(event.detail)); } }
    handleBack() { if (this.step > 0) { this.go(this.step - 1); } }
    handleNext() { if (this.step < STEPS.length - 1) { this.go(this.step + 1); } }

    async handleComplete() {
        if (this.cantComplete || this.anyOver) { return; }
        this.saving = true;
        this.error = undefined;
        const rows = [];
        this.forms.forEach((f) => f.rows.forEach((r) => rows.push({ impactedId: f.impactedId, draftId: r.draftId, type: r.type, qty: this.num(r.qty),
            completedOn: r.completedOn, comment: r.comment, justification: r.justification })));
        try {
            this.result = await completeDispositions({ recordId: this.recordId, payload: JSON.stringify(rows) });
            this.suggestedAtSave = this.v.suggestType;
            try { await notifyRecordUpdateAvailable([{ recordId: this.recordId }]); } catch (e) { /* the page refreshes on its own later */ }
            this.dispatchEvent(new CustomEvent('changed'));
        } catch (e) {
            this.error = this.msg(e, 'The disposition was not completed.');
        } finally {
            this.saving = false;
        }
    }

    // ---- done
    get doneHeading() { return this.result && !this.result.ncComplete ? 'Dispositions Complete' : 'Disposition Complete'; }
    get doneRows() {
        const recs = this.result ? this.result.done : this.allRecords.filter((r) => r.status === 'Complete');
        const rows = recs.map((r) => ({ key: r.id, k: r.name, v: (r.type || '') + ' ' + this.fmt(r.qty) + ' · Complete' + (r.completedOn ? ' on ' + this.dateText(r.completedOn) : '') }));
        const by = {};
        recs.forEach((r) => { if (r.type) { by[r.type] = (by[r.type] || 0) + this.num(r.qty); } });
        const types = Object.keys(by);
        const total = types.reduce((a, t) => a + by[t], 0);
        const chosen = types.map((t) => t + ' ' + this.fmt(by[t]));
        const sug = this.suggestedAtSave || this.v.suggestType;
        if (sug && total > 0) {
            const said = types.length === 1 && types[0] === sug ? ' · As Decided'
                : chosen.length ? ' · You Chose ' + (chosen.length > 1 ? chosen.slice(0, -1).join(', ') + ' and ' + chosen[chosen.length - 1] : chosen[0]) : '';
            rows.push({ key: 'sug', k: 'CQ.AI Suggests', v: sug + ' ' + this.fmt(total) + said });
        }
        if (this.v.investigationId) {
            rows.push({ key: 'next', k: 'Next', v: 'Investigation ' + this.v.investigationName + ' carries on; the NC closes after it.' });
        }
        return rows;
    }
    get doneLeftNote() {
        const rest = this.result && this.result.remainders;
        return rest && rest.length ? 'Units are still left to dispose, so new drafts were made: ' + rest.join(', ') + '.' : null;
    }
    handleFinish() {
        this.result = undefined;
        this.suggestedAtSave = undefined;
        this.step = 0;
        this.seen = { 0: true };
        this.load();
    }
}
