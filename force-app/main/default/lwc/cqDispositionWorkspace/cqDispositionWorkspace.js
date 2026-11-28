import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqDispositionWorkspace.getView';
import completeDispositions from '@salesforce/apex/CqDispositionWorkspace.completeDispositions';
import saveLot from '@salesforce/apex/CqTriageImpact.saveLot';

// Ask CQ.AI ready questions for each step (no commas: the popover splits on them)
const ASK = {
    'Disposition at a Glance': 'Why does CQ.AI suggest this disposition?,What was done with this part before?,What is still open on this NC?',
    'Dispose by Lot': 'Why does CQ.AI suggest this disposition?,When is Rework safe before the root cause is known?,What does my signature confirm?',
    'Disposition Complete': 'What is still open on this NC?,Summarize this nonconformance'
};
const STEPS = ['Disposition at a Glance', 'Dispose by Lot'];
const USE_AS_IS = 'Use As Is';
const REWORK = 'Rework';
const HOLD = 'Hold';      // CQ.AI suggests waiting for the root cause: not a disposition type, so no type starts selected

/**
 * CQ.AI Disposition workspace: the nonconformance's record header, then two steps in the page.
 * Disposition at a Glance shows the problem, CQ.AI's suggestion, the lots and what was done on this part before.
 * Dispose by Lot records what was done with each lot (a lot can be split across types) and Complete Disposition
 * saves and completes the dispositions in CQ in one step. Steps can be opened in any order.
 *
 * Evidence-led (option B): What's Wrong shows the failure code, severity, specification against actual, the photo and the
 * investigation. Scrap and Return To Vendor can be done at any time; Rework and Use As Is need the root cause, or a reason.
 * The dispositioner signs once (c-cq-sign-seat, CQ's Nonconformance > Completing Disposition policy) for every lot and split.
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
    signedNow = false;
    saving = false;
    keySeq = 0;
    pendingQty;         // the quantity typed for the NC's own lot when it is not stored yet
    savingLot = false;
    lotError;
    seatActions = [{ action: 'completedisposition', label: 'Complete Disposition', doing: 'Completing', signing: 'completing the disposition' }];

    connectedCallback() { this.load(); }

    async load() {
        try {
            this.v = await getView({ recordId: this.recordId });
            this.loadError = undefined;
            this.pendingQty = this.v.pendingLot && this.v.defective > 0 ? this.num(this.v.defective) : null;
            this.initForms();
        } catch (e) {
            this.loadError = this.msg(e, 'Could not read this nonconformance.');
        }
    }

    initForms() {
        const today = this.todayIso();
        this.forms = (this.v.lots || []).filter((l) => l.left > 0).map((l) => ({
            impactedId: l.impactedId,
            rows: [{ key: 'r' + (this.keySeq++), draftId: l.draftId, type: this.startType, qty: this.num(l.left), completedOn: today, comment: '', justification: '' }]
        }));
    }

    get ready() { return !!this.v; }
    /** The type a lot starts with: CQ.AI's suggestion, none when it says to hold the lot. */
    get startType() { return this.v.suggestType && this.v.suggestType !== HOLD ? this.v.suggestType : null; }
    get isHold() { return this.v.suggestType === HOLD; }
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
    /** The NC's lot, and how many more lots it has: "L26-1102 +1". */
    get lotText() {
        const names = (this.v.lots || []).map((l) => l.lot).filter((n) => n);
        if (this.v.pendingLot) { names.push(this.v.pendingLot); }
        const key = (n) => String(n).trim().toUpperCase();
        const first = this.v.lot || names[0];
        if (!first) { return '—'; }
        const rest = new Set(names.map(key).filter((n) => n !== key(first)));
        return first + (rest.size ? ' +' + rest.size : '');
    }
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
    get noLots() { return this.lotCount === 0 && !this.v.pendingLot; }
    // ---- the NC's own lot without a quantity yet (NC-000049): asked for before it can be disposed
    get hasPending() { return !!this.v.pendingLot; }
    get pendingText() { return 'Lot ' + this.v.pendingLot + ' needs a quantity before it can be disposed.'; }
    get pendingGlance() { return this.pendingText + ' Add it in Dispose by Lot.'; }
    get cantSaveLot() { return this.savingLot || !(this.num(this.pendingQty) > 0); }
    get saveLotLabel() { return this.savingLot ? 'Saving…' : 'Save Quantity'; }
    handlePendingQty(event) { const x = event.target.value; this.pendingQty = x === '' ? null : Number(x); this.lotError = undefined; }
    async handleSavePending() {
        if (this.cantSaveLot) { return; }
        this.savingLot = true;
        this.lotError = undefined;
        try {
            await saveLot({ recordId: this.recordId, impactedId: null, lot: this.v.pendingLot, quantity: this.num(this.pendingQty) });
            await this.load();
            try { await notifyRecordUpdateAvailable([{ recordId: this.recordId }]); } catch (e) { /* refreshes later */ }
        } catch (e) {
            this.lotError = this.msg(e, 'The quantity was not saved.');
        } finally {
            this.savingLot = false;
        }
    }
    /** The signature is only shown when there is something to sign for. */
    get showSign() { return !this.v.needsApproval && this.forms.length > 0; }
    get dispGridCls() { return this.showSign ? 'dispgrid' : 'dispgrid solo'; }
    get approvalText() { return this.v.needsApproval ? 'Required' : 'Not Required'; }
    // What's Wrong
    get photoUrl() { return this.v.photoId ? '/sfc/servlet.shepherd/version/download/' + this.v.photoId : null; }
    get failureText() { return this.v.failureCode || 'Not set'; }
    get severityText() { return this.v.severity ? this.v.severity.replace(/^(\d+)\s*-\s*/, '$1 · ') : '—'; }
    get defectiveText() { return this.units(this.v.defective); }
    get unitsText() {
        const bits = [this.units(this.totalLeft) + ' left to dispose'];
        if (this.v.defective) { bits.push(this.fmt(this.v.defective) + ' defective'); }
        return bits.join(' · ');
    }
    get invStatusText() { return this.v.causeKnown ? 'Root Cause Found' : this.v.investigationOpen ? 'Open' : this.dash(this.v.investigationStatus); }
    get invPillCls() { return 'cq-pill soft ' + (this.v.causeKnown ? 'pos' : this.v.investigationOpen ? 'warn' : 'neu'); }
    get causeLine() {
        if (this.v.causeKnown) { return this.v.causeText; }
        return 'Root cause not found yet' + (this.v.investigationDue ? ' · due ' + this.dateText(this.v.investigationDue) : '');
    }
    get confidenceText() { return this.v.confidence + ' Confidence'; }
    get hasFactors() { return (this.v.suggestFactors || []).length > 0; }
    get factorRows() { return (this.v.suggestFactors || []).map((t, i) => ({ key: 'f' + i, text: t })); }
    get suggestHeadline() {
        if (!this.v.suggestType || this.totalLeft === 0) { return 'Nothing to Dispose'; }
        const open = (this.v.lots || []).filter((l) => l.left > 0);
        if (this.isHold) {
            const lots = open.map((l) => l.lot).join(', ');
            return 'Keep ' + (open.length === 1 ? 'Lot ' : 'Lots ') + lots + ' on Hold Until ' + (this.v.investigationName || 'the Investigation') + ' Finds the Cause';
        }
        if (open.length === 1) { return this.v.suggestType + ' ' + this.units(open[0].left) + ' of Lot ' + open[0].lot; }
        return this.v.suggestType + ' ' + this.units(this.totalLeft);
    }
    get lotRows() {
        return (this.v.lots || []).map((l) => ({
            impactedId: l.impactedId, partName: l.partName || '—', lot: l.lot,
            // the part number as a link, its full name on hover, so the row stays on one line (Lou, 27 Nov)
            partLabel: l.partNumber || l.partName || '—', partHref: l.partId ? '/lightning/r/compliancequest__SQX_Part__c/' + l.partId + '/view' : null,
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
    /** Dispositions on This Part: one card per disposition type with how many records it has (none shows 0). */
    get historyByType() {
        const count = {};
        (this.v.history || []).forEach((h) => { count[h.type] = (count[h.type] || 0) + 1; });
        const types = [...(this.v.types || [])];
        Object.keys(count).forEach((t) => { if (!types.includes(t)) { types.push(t); } });
        return types.map((t) => {
            const n = count[t] || 0;
            return { type: t, text: n + (n === 1 ? ' Record' : ' Records'), cls: 'cq-tile' + (n ? '' : ' none') };
        });
    }

    // ---- step 2: Dispose by Lot
    get disposeIntro() {
        const start = this.isHold ? 'CQ.AI suggests holding these lots, so no type starts selected; Scrap now is reasonable if you cannot hold the stock.'
            : 'CQ.AI\'s suggestion starts selected; click another type to change it.';
        return 'Record what was done with each lot. ' + start + ' Scrap and Return To Vendor can be completed at any time; '
            + (this.v.reasonNeeded ? 'Rework and Use As Is need a reason while the root cause is not known.' : 'Use As Is needs a justification.');
    }
    /** What a row needs besides its type and quantity: a reason for Rework before the cause is known, and for Use As Is always. */
    rowRules(type) {
        const early = !!this.v.reasonNeeded;
        const inv = this.v.investigationName ? this.v.investigationName + ' is still open, so' : 'No root cause is recorded, so';
        if (type === REWORK && early) {
            return { needsWhy: true, whyLabel: 'Why Rework Now',
                waitText: inv + ' it is not yet clear that rework fixes what went wrong. Wait for the investigation, or say why rework is safe now.',
                whyHint: 'For example, the leak is at the hub bond only; re-bonding to the work instruction and a 100% pressure test bring each unit back to spec',
                whyNote: 'Saved on the disposition as its justification.' };
        }
        if (type === USE_AS_IS) {
            return { needsWhy: true, whyLabel: early ? 'Why Use As Is Now' : 'Justification',
                waitText: early ? inv + ' it is not yet clear the units are safe to release. Wait for the investigation, or say why they can be used as is.' : null,
                whyHint: 'For example, engineering assessment EA-0042 shows no effect on performance',
                whyNote: 'Use As Is releases nonconforming units, so it needs a reason on the record.' };
        }
        if (type && type !== REWORK && early) { return { nowOk: type + ' does not depend on the root cause, so it can be completed now.' }; }
        return {};
    }
    get lotForms() {
        const types = this.v.types || [];
        return (this.v.lots || []).map((l) => {
            const fi = this.forms.findIndex((f) => f.impactedId === l.impactedId);
            const f = fi >= 0 ? this.forms[fi] : null;
            const planned = f ? f.rows.reduce((a, r) => a + this.num(r.qty), 0) : 0;
            const over = f && planned > this.num(l.left);
            return {
                impactedId: l.impactedId, lot: l.lot, partName: l.partName, idx: fi, open: !!f, draftName: l.draftName,
                suggestText: !this.v.suggestType ? null : this.isHold ? 'Hold until the root cause is known (Scrap if the stock cannot be held)' : this.v.suggestType + ' ' + this.fmt(l.left),
                doneText: !f ? 'All ' + this.fmt(l.impacted) + ' Disposed' : null,
                // too many is an error; fewer is allowed today and the rest stays on the lot
                qtyMsg: !f ? null
                    : over ? 'Your Disposition Quantity is ' + this.fmt(l.left) + (f.rows.length > 1 ? ', please make sure your splits are equal to the Disposition Quantity.' : '.')
                    : planned > 0 && planned < this.num(l.left) ? 'You\'ve entered ' + this.fmt(planned) + ', there are ' + this.fmt(this.num(l.left) - planned) + ' remaining items left to Disposition.'
                    : null,
                rows: f ? f.rows.map((r, ri) => ({
                    ...r, idx: ri, canRemove: f.rows.length > 1, needsWhy: false, nowOk: null, waitText: null, ...this.rowRules(r.type),
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
        if (this.v.pendingLot && !this.forms.length) { return 'Lot ' + this.v.pendingLot + ' needs a quantity'; }
        if (!this.forms.length) { return 'Nothing is left to dispose'; }
        for (const f of this.forms) {
            const lot = this.v.lots.find((l) => l.impactedId === f.impactedId);
            const name = 'Lot ' + lot.lot + ': ';
            for (const r of f.rows) {
                if (!r.type) { return name + 'choose a type'; }
                if (!(this.num(r.qty) > 0)) { return name + 'enter a quantity'; }
                if (!r.completedOn) { return name + 'enter the completed date'; }
                if (r.type === USE_AS_IS && !(r.justification || '').trim()) { return name + 'Use As Is needs a justification'; }
                if (r.type === REWORK && this.v.reasonNeeded && !(r.justification || '').trim()) { return name + 'say why Rework is safe before the cause is known'; }
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
    /** What the signature covers: every lot and split, as the server records it with the signature. */
    get signFor() {
        const out = [];
        this.forms.forEach((f) => {
            const lot = this.v.lots.find((l) => l.impactedId === f.impactedId);
            const parts = f.rows.filter((r) => r.type && this.num(r.qty) > 0).map((r) => this.fmt(r.qty) + ' ' + r.type);
            const total = f.rows.reduce((a, r) => a + this.num(r.qty), 0);
            if (parts.length) { out.push('Lot ' + lot.lot + ': ' + parts.join(', ') + ' (' + this.fmt(total) + (total === 1 ? ' unit)' : ' units)')); }
        });
        return out.length ? 'Signs for ' + out.join('; ') : 'Choose a type for each lot';
    }
    get signMeaning() { return 'confirm the dispositions recorded above for every lot and split are what was done'; }
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

    /** The seat's one button signs and completes in one request; a refusal is thrown back so the seat shows it. */
    seatSubmit = async ({ comment, password }) => {
        if (this.anyOver) { throw new Error('A lot has more entered than it has left to dispose.'); }
        await this.complete(comment, password);
    };

    async complete(comment, password) {
        if (this.cantComplete) { return; }
        this.saving = true;
        this.error = undefined;
        const rows = [];
        this.forms.forEach((f) => f.rows.forEach((r) => rows.push({ impactedId: f.impactedId, draftId: r.draftId, type: r.type, qty: this.num(r.qty),
            completedOn: r.completedOn, comment: r.comment, justification: r.justification })));
        try {
            this.result = await completeDispositions({ recordId: this.recordId, payload: JSON.stringify(rows), comment: comment || null, password: password || null });
            this.suggestedAtSave = this.v.suggestType;
            this.signedNow = !!password;
            try { await notifyRecordUpdateAvailable([{ recordId: this.recordId }]); } catch (e) { /* the page refreshes on its own later */ }
            this.dispatchEvent(new CustomEvent('changed'));
        } catch (e) {
            throw new Error(this.msg(e, 'The disposition was not completed.'));
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
        if (this.result) { rows.push({ key: 'sig', k: this.signedNow ? 'Signed By' : 'Completed By', v: 'You · for every lot and split above' }); }
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
