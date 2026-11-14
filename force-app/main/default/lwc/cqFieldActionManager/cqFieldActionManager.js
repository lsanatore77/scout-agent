import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqFieldActionScope.getView';
import getGenealogy from '@salesforce/apex/CqFieldActionScope.genealogy';
import addLot from '@salesforce/apex/CqFieldActionScope.addLot';
import removeLot from '@salesforce/apex/CqFieldActionScope.removeLot';
import saveLot from '@salesforce/apex/CqFieldActionScope.saveLot';
import submitScope from '@salesforce/apex/CqFieldActionScope.submitScope';
import actOnStep from '@salesforce/apex/CqFieldActionScope.act';

// The seven steps of a field action. This batch builds the first two; the rest open in later batches.
const STEPS = [
    { label: 'Field Action at a Glance', ready: true },
    { label: 'Scope', ready: true },
    { label: 'Strategy', ready: false },
    { label: 'Notifications', ready: false, needsScope: true },
    { label: 'Regulatory Report', ready: false, needsScope: true },
    { label: 'Recovery and Effectiveness', ready: false },
    { label: 'Closure', ready: false }
];
const SCOPE = 1;
const STEP_LABEL = { Open: 'Pending', Approved: 'Approved', Rejected: 'Sent Back', Void: 'Not Required', Skipped: 'Not Required' };
const STATE_LABEL = { 'Full Scope': 'Full Scope', 'Being Defined': 'Being Defined', 'With Committee': 'With Committee', Approved: 'Scope Approved' };
const PAGE = 8;        // lots left out of scope shown before "Show all"

/** Field Action workspace: the coordinator's steps from what was decided through closure. */
export default class CqFieldActionManager extends NavigationMixin(LightningElement) {
    @api recordId;
    v;
    error;
    saving = false;
    step = 0;
    // scope step
    edits = {};          // lot row id -> { shipped, onHand, location } being typed
    adding = '';         // lot being added, waiting for its reason
    removing = '';       // lot being removed, waiting for its reason
    reason = '';
    showAllLots = false;
    gen;                 // genealogy of the selected lot
    genLot = '';
    genLoading = false;
    // scope approval
    team = {};
    emergency = false;
    emergencyUser = '';
    emergencyReason = '';
    comment = '';

    async connectedCallback() {
        try { this.apply(await getView({ recordId: this.recordId }), true); }
        catch (e) { this.error = this.msg(e, 'Could not read this field action.'); }
    }
    msg(e, fallback) { return (e && e.body && e.body.message) || fallback; }
    apply(v, first) {
        this.v = v;
        if (first) {
            this.step = 0;
            this.fillTeam();
        }
    }
    /** The scope committee starts as the committee that approved the decision; each seat can be changed. */
    fillTeam() {
        const team = {};
        const taken = new Set();
        (this.v.defaultTeam || []).forEach((m) => {
            const seat = this.allSeats.find((s) => s.functionId === m.functionId);
            if (!seat) { return; }
            if (seat.emergency) { this.emergencyUser = m.userId; return; }
            if (seat.people.some((p) => p.id === m.userId)) { team[m.functionId] = m.userId; taken.add(m.userId); }
        });
        this.allSeats.forEach((s) => {
            if (s.emergency) { if (!this.emergencyUser && s.people.length) { this.emergencyUser = s.people[0].id; } return; }
            if (team[s.functionId]) { return; }
            const free = s.people.find((p) => !taken.has(p.id));
            if (free) { team[s.functionId] = free.id; taken.add(free.id); }
        });
        this.team = team;
        this.emergency = !!this.v.defaultEmergency;
    }
    get ready() { return !!this.v; }
    dash(x) { return x === undefined || x === null || x === '' ? '—' : String(x); }
    day(d) { return d ? new Date(d).toLocaleDateString() : ''; }
    when(d) { return d ? new Date(d).toLocaleString() : ''; }
    dateOnly(d) { const p = String(d || '').split('-'); return p.length === 3 ? new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2])).toLocaleDateString() : ''; }

    // ---- header
    get partText() { return this.dash(this.v.partNumber); }
    get scopeText() { return this.v.scope ? this.v.scope + ' · ' + (STATE_LABEL[this.v.scopeStatus] || this.v.scopeStatus || 'Not set') : 'Not set'; }
    get classText() { return this.dash(this.v.recallClass); }
    handleEdit() {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: this.recordId, objectApiName: 'Field_Action__c', actionName: 'edit' } });
    }
    async handleRefresh() {
        try { this.apply(await getView({ recordId: this.recordId }), false); this.error = undefined; this.gen = undefined; this.genLot = ''; }
        catch (e) { this.error = this.msg(e, 'Could not refresh this field action.'); }
    }
    handleOpen(event) {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' } });
    }

    // ---- step rail
    get isFull() { return this.v.scope === 'Full'; }
    get isPartial() { return this.v.scope === 'Partial'; }
    get scopeApproved() { return this.isFull || this.v.scopeStatus === 'Approved'; }
    get steps() {
        const n = this.inRows.length;
        const subs = [
            this.v.actionType ? this.v.actionType + (this.v.recallClass ? ' · ' + this.v.recallClass : '') : 'Decided',
            this.isFull ? 'Full · ' + n + ' lot' + (n === 1 ? '' : 's') : this.isPartial ? (STATE_LABEL[this.v.scopeStatus] || 'Being Defined') + ' · ' + n + ' lot' + (n === 1 ? '' : 's') : 'Scope not set',
            'Next batch', this.scopeApproved ? 'Next batch' : 'Needs approved scope', this.scopeApproved ? 'Next batch' : 'Needs approved scope', 'Next batch', 'Next batch'
        ];
        return STEPS.map((s, i) => {
            const done = i === 0 || (i === SCOPE && this.scopeApproved);
            return { i, n: i + 1, label: s.label, sub: subs[i], done, notDone: !done, locked: !s.ready,
                cls: 'step' + (i === this.step ? ' active' : '') + (done ? ' done' : '') };
        });
    }
    get progress() { return this.steps.filter((s) => s.done).length + ' of ' + STEPS.length + ' steps complete'; }
    handleStep(event) { const i = Number(event.currentTarget.dataset.i); if (STEPS[i].ready) { this.step = i; this.error = undefined; } }
    get is0() { return this.ready && this.step === 0; }
    get is1() { return this.ready && this.step === SCOPE; }
    get cantBack() { return this.step === 0; }
    get cantNext() { return this.step >= SCOPE; }
    handleBack() { if (this.step > 0) { this.step -= 1; } }
    handleNext() { if (this.step < SCOPE) { this.step += 1; } }

    // ---- step 1: at a glance
    get tiles() {
        const sum = (k) => this.inRows.reduce((t, l) => t + (l[k] ? Number(l[k]) : 0), 0);
        const shipped = sum('shipped');
        return [
            ['Lots in scope', String(this.inRows.length)],
            ['Units built', this.inRows.some((l) => l.built) ? String(sum('built')) : '—'],
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
    get statePill() {
        const s = this.v.scopeStatus;
        return 'spill state' + (s === 'Approved' || s === 'Full Scope' ? ' ok' : s === 'With Committee' ? ' wait' : '');
    }
    get stateText() { return STATE_LABEL[this.v.scopeStatus] || this.v.scopeStatus || 'Not set'; }
    get scopeIntro() {
        if (this.isFull) { return 'Full scope covers every lot of ' + this.partText + '. Any lot found later is added automatically and logged below. No scope approval is needed.'; }
        if (this.isPartial) { return 'Choose the lots this field action covers, then send the list for approval. Customer notifications and the regulatory report open once the scope is approved.'; }
        return 'This field action has no scope set. It was decided before scope was part of the review.';
    }
    get approvedLine() { return this.v.scopeApprovedOn ? 'Last approved ' + this.when(this.v.scopeApprovedOn) : ''; }
    get canChange() { return this.isPartial && this.v.scopeStatus !== 'With Committee' && this.v.status !== 'Closed'; }
    get inRows() { return (this.v.inScope || []); }
    get lotRows() {
        return this.inRows.map((l) => {
            const e = this.edits[l.id] || {};
            const pending = this.isPartial && !l.approved;
            return { ...l, sel: l.name === this.genLot,
                rowCls: l.name === this.genLot ? 'sel' : '',
                builtText: l.built !== undefined && l.built !== null ? String(l.built) : '—',
                madeText: this.dateOnly(l.made),
                howText: [l.how === 'Review' ? 'From review' : l.how === 'Automatic' ? 'Added automatically' : l.how === 'Coordinator' ? 'Added by coordinator' : '', l.reason].filter(Boolean).join(': '),
                pending, pendingText: pending ? (this.v.scopeApprovedOn ? 'Added since approval' : 'Not yet approved') : '',
                shippedVal: e.shipped !== undefined ? e.shipped : l.shipped, onHandVal: e.onHand !== undefined ? e.onHand : l.onHand,
                locVal: e.location !== undefined ? e.location : l.location || '',
                dirty: !!this.edits[l.id], removing: this.removing === l.name };
        });
    }
    get hasLots() { return this.inRows.length > 0; }
    get removedSince() {
        // lots approved in scope and since removed: still need approval of the removal
        return (this.v.outOfScope || []).filter((l) => l.id && l.approved).map((l) => l.name);
    }
    get hasRemovedSince() { return this.isPartial && this.removedSince.length > 0; }
    get removedSinceText() { return 'Removed since approval: ' + this.removedSince.join(', '); }
    get outRows() {
        const all = (this.v.outOfScope || []);
        const shown = this.showAllLots ? all : all.filter((l) => l.suggested || l.known).slice(0, PAGE);
        const n = (x, w) => x + ' ' + w + (x === 1 ? '' : 's');
        return shown.map((l) => ({ ...l,
            meta: [l.built !== undefined && l.built !== null ? l.built + ' built' : '', l.made ? 'made ' + this.dateOnly(l.made) : '',
                n(l.records || 0, 'record'), l.known ? '' : 'no lot record in CQ'].filter(Boolean).join(' · '),
            adding: this.adding === l.name }));
    }
    get hasOut() { return this.outRows.length > 0; }
    get hiddenOut() { return this.showAllLots ? 0 : (this.v.outOfScope || []).length - this.outRows.length; }
    get hasHiddenOut() { return this.hiddenOut > 0; }
    get hiddenOutLabel() { const n = this.hiddenOut; return 'Show all ' + (this.v.outOfScope || []).length + ' lots left out (' + n + ' more)'; }
    handleShowAllLots() { this.showAllLots = true; }

    handleQty(event) {
        const id = event.target.dataset.id; const f = event.target.dataset.f;
        const cur = { ...(this.edits[id] || {}) };
        cur[f] = f === 'location' ? event.target.value : event.target.value === '' ? null : Number(event.target.value);
        this.edits = { ...this.edits, [id]: cur };
    }
    async handleSaveLot(event) {
        const id = event.currentTarget.dataset.id;
        const row = this.inRows.find((l) => l.id === id);
        const e = this.edits[id] || {};
        await this.run(() => saveLot({ recordId: this.recordId, rowId: id,
            shipped: e.shipped !== undefined ? e.shipped : row.shipped, onHand: e.onHand !== undefined ? e.onHand : row.onHand,
            location: e.location !== undefined ? e.location : row.location }), () => { const x = { ...this.edits }; delete x[id]; this.edits = x; });
    }
    handleStartAdd(event) {
        const lot = event.currentTarget.dataset.id;
        const row = (this.v.outOfScope || []).find((l) => l.name === lot) || {};
        this.adding = lot; this.removing = ''; this.reason = row.why || '';
    }
    handleStartRemove(event) { this.removing = event.currentTarget.dataset.id; this.adding = ''; this.reason = ''; }
    handleCancel() { this.adding = ''; this.removing = ''; this.reason = ''; }
    handleReason(event) { this.reason = event.target.value; }
    get cantConfirm() { return this.saving || !this.reason.trim(); }
    async handleConfirmAdd() {
        const lot = this.adding;
        await this.run(() => addLot({ recordId: this.recordId, lot, reason: this.reason.trim() }), () => { this.adding = ''; this.reason = ''; });
    }
    async handleConfirmRemove() {
        const lot = this.removing;
        await this.run(() => removeLot({ recordId: this.recordId, lot, reason: this.reason.trim() }), () => { this.removing = ''; this.reason = ''; });
    }
    async run(call, after) {
        if (this.saving) { return; }
        this.saving = true; this.error = undefined;
        try {
            this.apply(await call(), false);
            if (after) { after(); }
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (e) { this.error = this.msg(e, 'Could not save that.'); }
        this.saving = false;
    }

    // genealogy
    async handleGenealogy(event) {
        const lot = event.currentTarget.dataset.id;
        if (this.genLot === lot) { this.genLot = ''; this.gen = undefined; return; }
        this.genLot = lot; this.gen = undefined; this.genLoading = true;
        try { this.gen = await getGenealogy({ recordId: this.recordId, lot }); }
        catch (e) { this.error = this.msg(e, 'Could not read the genealogy.'); }
        this.genLoading = false;
    }
    get showGen() { return !!this.genLot; }
    get genTitle() { return 'Lot Genealogy · ' + this.genLot + (this.gen && this.gen.batch ? ' · batch ' + this.gen.batch : ''); }
    get genComponents() {
        const inNames = new Set(this.inRows.map((l) => l.name));
        return ((this.gen && this.gen.components) || []).map((c) => ({ ...c,
            head: c.lot + (c.part ? ' · ' + c.part : '') + (c.partName ? ' · ' + c.partName : ''),
            hasSisters: (c.sisters || []).length > 0,
            sisters: (c.sisters || []).map((s, i) => ({ ...s, key: c.lot + s.lot + i,
                inScopeNow: s.samePart && inNames.has(s.lot),
                canAdd: s.samePart && !inNames.has(s.lot) && this.canChange,
                cls: 'chip' + (s.samePart && inNames.has(s.lot) ? ' in' : !s.samePart ? ' other' : ''),
                text: s.lot + (s.samePart ? '' : ' (' + s.part + ')') })) }));
    }
    get hasGenComponents() { return this.genComponents.length > 0; }
    handleAddSister(event) {
        const lot = event.currentTarget.dataset.id; const comp = event.currentTarget.dataset.comp;
        this.adding = lot; this.removing = ''; this.reason = 'Shares component lot ' + comp + ' with ' + this.genLot;
    }
    get isAdding() { return !!this.adding; }
    get isRemoving() { return !!this.removing; }
    get addTitle() { return 'Add lot ' + this.adding + ' to scope'; }
    get removeTitle() { return 'Remove lot ' + this.removing + ' from scope'; }

    // change log
    get changes() {
        return (this.v.changes || []).map((c, i) => ({ ...c, key: 'c' + i, at: this.when(c.doneAt),
            line: c.change + ' lot ' + c.lot + (c.reason ? ': ' + c.reason : ''), by: c.how === 'Automatic' ? 'Automatic' : c.doneBy }));
    }
    get hasChanges() { return this.changes.length > 0; }

    // ---- scope approval, on CQ Approvals
    get committee() { return this.v.committee || {}; }
    get allSeats() { return (this.v && this.v.committee && this.v.committee.seats) || []; }
    get seats() {
        const taken = (id) => Object.entries(this.team).filter(([f, u]) => u && f !== id).map(([, u]) => u);
        return this.allSeats.filter((s) => !s.emergency).map((s) => {
            const others = taken(s.functionId);
            return { ...s, none: !s.people.length,
                opts: s.people.map((p) => ({ value: p.id, label: p.name + (others.includes(p.id) ? ' (already on the committee)' : ''), selected: this.team[s.functionId] === p.id })) };
        });
    }
    get emergencySeat() { return this.allSeats.find((s) => s.emergency); }
    get emergencyOpts() { const s = this.emergencySeat; return s ? s.people.map((p) => ({ value: p.id, label: p.name, selected: this.emergencyUser === p.id })) : []; }
    get normal() { return !this.emergency; }
    handleSeat(event) { this.team = { ...this.team, [event.target.dataset.id]: event.target.value }; }
    handleEmergency(event) { this.emergency = event.target.checked; }
    handleField(event) { this[event.target.dataset.f] = event.target.value; }
    get members() {
        if (this.emergency) { const s = this.emergencySeat; return s ? [{ functionId: s.functionId, userId: this.emergencyUser }] : []; }
        return this.seats.map((s) => ({ functionId: s.functionId, userId: this.team[s.functionId] }));
    }
    get pendingCount() { return this.lotRows.filter((l) => l.pending).length + (this.hasRemovedSince ? this.removedSince.length : 0); }
    get canSubmitScope() { return this.isPartial && this.v.scopeStatus === 'Being Defined' && this.hasLots && this.pendingCount > 0; }
    get scopeWaiting() { return this.isPartial && this.v.scopeStatus === 'With Committee'; }
    get submitBlocker() {
        if (!this.hasLots) { return 'Put at least one lot in scope'; }
        if (this.emergency) {
            if (!this.emergencyUser) { return 'Choose the emergency approver'; }
            if (!this.emergencyReason.trim()) { return 'Give the reason for the emergency'; }
        } else {
            const m = this.members;
            if (!m.length || m.some((x) => !x.userId)) { return 'Choose a person for every seat'; }
            if (new Set(m.map((x) => x.userId)).size !== m.length) { return 'One person can hold only one seat'; }
        }
        return '';
    }
    get cantSubmit() { return !!this.submitBlocker || this.saving; }
    get submitLabel() { return this.saving ? 'Saving…' : this.emergency ? 'Send to Emergency Approver' : 'Submit Scope to Committee'; }
    async handleSubmitScope() {
        if (this.cantSubmit) { return; }
        await this.run(() => submitScope({ recordId: this.recordId, team: JSON.stringify(this.members), emergency: this.emergency,
            emergencyReason: this.emergencyReason.trim() }));
    }
    get csteps() {
        return (this.committee.steps || []).map((s) => ({ ...s, label: STEP_LABEL[s.status] || s.status, cls: 'cpill ' + (s.status || '').toLowerCase(),
            line: [s.person, s.doneOn ? this.when(s.doneOn) : '', s.doneBy && s.doneBy !== s.person ? 'recorded by ' + s.doneBy : ''].filter(Boolean).join(' · '),
            quote: s.comment ? '“' + s.comment + '”' : '' }));
    }
    get hasSteps() { return this.csteps.length > 0; }
    get canActAny() { return this.csteps.some((s) => s.canAct); }
    get approvalTitle() { return 'Scope Approval' + (this.committee.approvalName ? ' · ' + this.committee.approvalName : ''); }
    get showLastApproval() { return this.hasSteps && !this.scopeWaiting; }
    async handleAct(event) {
        const d = event.currentTarget.dataset;
        if (d.a === 'reject' && !this.comment.trim()) { this.error = 'Add a comment saying why you are sending it back.'; return; }
        await this.run(() => actOnStep({ recordId: this.recordId, stepId: d.id, action: d.a, comment: this.comment.trim() }), () => { this.comment = ''; });
    }
    get sentBack() { return this.isPartial && this.v.scopeStatus === 'Being Defined' ? this.v.sentBack : ''; }
}
