import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqFieldActionRecovery.getView';
import saveLot from '@salesforce/apex/CqFieldActionRecovery.saveLot';
import addCustomer from '@salesforce/apex/CqFieldActionRecovery.addCustomer';
import setCustomer from '@salesforce/apex/CqFieldActionRecovery.setCustomer';
import setDisposition from '@salesforce/apex/CqFieldActionRecovery.setDisposition';
import saveVerdict from '@salesforce/apex/CqFieldActionRecovery.saveVerdict';
import confirmVerdict from '@salesforce/apex/CqFieldActionRecovery.confirmVerdict';

const STATUS_ORDER = ['Sent', 'Acknowledged', 'No reply'];
const DISPOSITIONS = ['Scrap', 'Rework', 'Return to Supplier', 'Release'];
const NEXT_STEPS = ['Widen the scope', 'A further action to customers', 'Extend the check by 30 days'];

/** Field Action step 6, Recovery and Effectiveness: units back, customers confirmed, held stock decided, the verdict. */
export default class CqFieldActionRecovery extends LightningElement {
    @api recordId;
    v;
    error;
    saving = 0;
    editing = '';        // lot row open for editing
    edits = {};          // that row's typed numbers
    newName = ''; newUnits = ''; newLots = '';
    footSig;

    async connectedCallback() { await this.load(); }
    async load() {
        try { this.apply(await getView({ recordId: this.recordId })); }
        catch (e) { this.error = this.msg(e, 'Could not read recovery.'); }
    }
    msg(e, fallback) { return (e && e.body && e.body.message) || fallback; }
    apply(v) {
        this.v = JSON.parse(JSON.stringify(v));
        this.dispatchEvent(new CustomEvent('railchange', { detail: { recovery: this.v.recovery, verdict: this.v.verdict, status: this.v.status } }));
    }
    async call(fn, fallback, after) {
        this.error = undefined;
        this.saving += 1;
        try { this.apply(await fn()); if (after) { after(); } notifyRecordUpdateAvailable([{ recordId: this.recordId }]); }
        catch (e) { this.error = this.msg(e, fallback); }
        this.saving -= 1;
    }
    get ready() { return !!this.v; }
    get busy() { return this.saving > 0; }
    get locked() { return !this.v.strategyConfirmed || this.v.closed; }
    get needsStrategy() { return this.ready && !this.v.strategyConfirmed; }
    get showStep() { return this.ready && this.v.strategyConfirmed; }
    num(x) { return x === undefined || x === null ? '—' : String(Number(x)); }
    bar(pct) { return 'width:' + pct + '%;background:' + (pct >= 100 ? '#2e844a' : '#1d5fd1'); }

    renderedCallback() {
        if (!this.v) { return; }
        const detail = { show: this.showStep, label: this.confirmLabel, disabled: this.cantConfirm, blocker: this.showStep ? this.blocker : '' };
        const sig = JSON.stringify(detail);
        if (sig !== this.footSig) { this.footSig = sig; this.dispatchEvent(new CustomEvent('footchange', { detail })); }
    }
    @api confirm() { return this.handleConfirm(); }

    // ---- header
    get confirmed() { return this.v.recovery === 'Confirmed'; }
    get stateText() {
        if (this.confirmed) { return 'Effective'; }
        if (this.v.verdict === 'Not Effective' && this.v.verdictOn) { return 'Not Effective'; }
        return 'In Progress';
    }
    get statePill() { return 'spill ' + (this.confirmed ? 'ok' : this.stateText === 'Not Effective' ? 'bad' : 'wait'); }
    get intro() {
        const parts = [this.v.action, this.v.depth ? 'to ' + this.v.depth.toLowerCase() + ' level' : '',
            this.v.level ? this.v.level + ' check' + (this.v.checkBy ? ' due ' + new Date(this.v.checkBy + 'T00:00:00').toLocaleDateString() : '') : ''].filter(Boolean);
        return 'Track the product coming back and the customers confirming, against the strategy: ' + parts.join(', ') + '.';
    }

    // ---- 1. recovery by lot: the columns follow the action. A removal brings units back or has them destroyed on site;
    // a correction fixes them where they are (some may still come back); an advisory notice leaves them in use.
    get isRemoval() { return this.v.action === 'Removal (Recall)'; }
    get isCorrection() { return this.v.action === 'Correction'; }
    get isNotice() { return this.v.action === 'Advisory Notice'; }
    get showRecovery() { return !this.isNotice; }
    get showDestroyed() { return !this.isCorrection; }
    get showCorrected() { return this.isCorrection; }
    get tableHint() {
        return 'Shipped comes from the lot shipments. Click ' + (this.isCorrection ? 'Corrected or Returned' : 'Returned or Destroyed') + ' to edit them.';
    }
    get lotRows() {
        return this.v.lots.map((l) => {
            const e = this.edits;
            const isEditing = this.editing === l.id;
            const pct = l.pct === undefined || l.pct === null ? 0 : l.pct;
            return { ...l, isEditing, notEditing: !isEditing,
                shippedText: this.num(l.shipped), returnedText: this.num(l.returned), destroyedText: this.num(l.destroyed),
                correctedText: this.num(l.corrected), fieldText: this.num(l.field),
                fieldCls: 'num b ' + (l.field ? 'warnc' : l.field === 0 ? 'okc' : ''),
                hasPct: l.shipped !== undefined && l.shipped !== null, pctText: pct + '%', barStyle: this.bar(pct),
                returnedVal: e.returned !== undefined ? e.returned : l.returned, destroyedVal: e.destroyed !== undefined ? e.destroyed : l.destroyed,
                correctedVal: e.corrected !== undefined ? e.corrected : l.corrected,
                editLabel: 'Edit units back for lot ' + l.lot };
        });
    }
    get recoveryLine() {
        if (!this.v.shippedKnown) { return 'Units shipped are not recorded on the Scope step'; }
        const pct = this.v.shipped ? Math.floor(100 * this.v.recovered / this.v.shipped) : 100;
        return this.v.recovered + ' of ' + this.v.shipped + ' units recovered · ' + pct + '%';
    }
    handleStartEdit(event) { if (this.locked) { return; } this.editing = event.currentTarget.dataset.id; this.edits = {}; }
    handleCancelEdit() { this.editing = ''; this.edits = {}; }
    handleQty(event) {
        const f = event.target.dataset.f;
        this.edits = { ...this.edits, [f]: event.target.value === '' ? null : Number(event.target.value) };
    }
    async handleSaveLot(event) {
        const id = event.currentTarget.dataset.id;
        const row = this.v.lots.find((l) => l.id === id);
        const e = this.edits;
        const pick = (k) => (e[k] !== undefined ? e[k] : row[k]);
        await this.call(() => saveLot({ recordId: this.recordId, rowId: id, returned: pick('returned'), destroyed: pick('destroyed'), corrected: pick('corrected') }),
            'Could not save those numbers.', () => { this.editing = ''; this.edits = {}; });
    }

    // ---- 2. customers
    get respPct() { return this.v.total ? Math.floor(100 * this.v.acked / this.v.total) : 0; }
    get respLine() { return this.v.total ? this.v.acked + ' of ' + this.v.total + ' acknowledged · ' + this.respPct + '%' : 'No customers yet'; }
    get respBar() { return this.bar(this.respPct); }
    get targetText() {
        if (this.v.target === 0) { return 'No check needed'; }
        return (this.v.level || 'Target') + ' target ' + this.v.target + '%' + (this.v.checkBy ? ' by ' + new Date(this.v.checkBy + 'T00:00:00').toLocaleDateString() : '');
    }
    get custRows() {
        return this.v.customers.map((c) => ({ ...c,
            detail: [c.units !== undefined && c.units !== null ? c.units + ' units' : '', c.lots || '',
                c.followUps ? c.followUps + ' follow-up' + (c.followUps === 1 ? '' : 's') : '',
                c.source === 'Shipment' ? 'from lot shipments' : 'added by hand'].filter(Boolean).join(' · '),
            canRemove: c.source !== 'Shipment',
            pillCls: 'pillbtn ' + (c.status === 'Acknowledged' ? 'ok' : c.status === 'No reply' ? 'bad' : ''),
            statusLabel: 'Status for ' + c.name + ': ' + c.status + '. Click to change.',
            followLabel: 'Add a follow-up for ' + c.name, removeLabel: 'Remove ' + c.name }));
    }
    get hasCustomers() { return this.v.customers.length > 0; }
    async handleStatus(event) {
        const c = this.v.customers.find((x) => x.id === event.currentTarget.dataset.id);
        const next = STATUS_ORDER[(STATUS_ORDER.indexOf(c.status) + 1) % STATUS_ORDER.length];
        await this.call(() => setCustomer({ recordId: this.recordId, customerId: c.id, change: next }), 'Could not change that status.');
    }
    async handleFollowUp(event) {
        await this.call(() => setCustomer({ recordId: this.recordId, customerId: event.currentTarget.dataset.id, change: 'followup' }), 'Could not add the follow-up.');
    }
    async handleRemove(event) {
        await this.call(() => setCustomer({ recordId: this.recordId, customerId: event.currentTarget.dataset.id, change: 'remove' }), 'Could not remove that customer.');
    }
    handleNew(event) { this[event.target.dataset.f] = event.target.value; }
    get cantAddCustomer() { return this.locked || this.busy || !this.newName.trim(); }
    async handleAddCustomer() {
        if (this.cantAddCustomer) { return; }
        await this.call(() => addCustomer({ recordId: this.recordId, name: this.newName, units: this.newUnits === '' ? null : Number(this.newUnits), lots: this.newLots }),
            'Could not add that customer.', () => { this.newName = ''; this.newUnits = ''; this.newLots = ''; });
    }

    // ---- 3. held stock
    get holdRows() {
        return this.v.holds.map((h) => ({ ...h,
            what: [h.kind === 'Finished Lot' ? 'Finished lot' : (h.item || 'Component lot'),
                h.onHand !== undefined && h.onHand !== null ? h.onHand + ' on hand' : '',
                h.kind !== 'Finished Lot' && h.reason && h.reason.startsWith('NC ') ? h.reason.split(' ')[1] : ''].filter(Boolean).join(' · '),
            opts: [{ value: '', label: 'Choose…', selected: !h.disposition }].concat(DISPOSITIONS.map((d) => ({
                value: d, label: (d === h.suggested ? '✦ ' : '') + d, selected: d === h.disposition }))),
            label: 'Disposition for ' + h.lot }));
    }
    get hasHolds() { return this.v.holds.length > 0; }
    get dispLine() { return this.v.decided + ' of ' + this.v.holds.length + ' decided'; }
    async handleDisposition(event) {
        await this.call(() => setDisposition({ recordId: this.recordId, holdId: event.target.dataset.id, disposition: event.target.value }), 'Could not save that disposition.');
    }

    // ---- 4. verdict
    get verdicts() {
        return ['Effective', 'Not Effective'].map((t, i) => ({ key: t, value: t, label: (t === this.v.aiVerdict ? '✦ ' : '') + t,
            pressed: this.v.verdict === t ? 'true' : 'false', cls: 'seg' + (this.v.verdict === t ? ' on' : '') + (i ? ' sep' : '') }));
    }
    get notEffective() { return this.v.verdict === 'Not Effective'; }
    get nextOpts() {
        return [{ value: '', label: 'Choose…', selected: !this.v.nextStep }].concat(NEXT_STEPS.map((s) => ({ value: s, label: s, selected: s === this.v.nextStep })));
    }
    get verdictLine() {
        if (!this.v.verdictOn) { return ''; }
        return (this.v.verdict === 'Effective' ? 'Effective' : 'Not Effective: ' + this.v.nextStep) + ' · confirmed by ' + this.v.verdictBy + ', ' + new Date(this.v.verdictOn).toLocaleString();
    }
    async handleVerdict(event) {
        const value = event.currentTarget.dataset.value;
        if (this.locked || value === this.v.verdict) { return; }
        await this.call(() => saveVerdict({ recordId: this.recordId, verdict: value, nextStep: this.v.nextStep }), 'Could not save the verdict.');
    }
    async handleNext(event) {
        await this.call(() => saveVerdict({ recordId: this.recordId, verdict: this.v.verdict, nextStep: event.target.value }), 'Could not save that.');
    }

    // ---- confirm
    get blocker() {
        if (!this.v.verdict) { return 'Choose a verdict'; }
        if (this.v.decided < this.v.holds.length) { return 'Choose what happens to all held stock'; }
        if (this.v.verdict === 'Effective' && !this.v.targetMet) {
            return this.v.total ? (this.v.level || 'The check') + ' needs ' + this.v.target + '% of customers to acknowledge' : 'Add the customers that received these lots';
        }
        if (this.v.verdict === 'Not Effective' && !this.v.nextStep) { return 'Choose what happens next'; }
        return '';
    }
    get done() { return this.confirmed || (this.v.verdict === 'Not Effective' && !!this.v.verdictOn); }
    get cantConfirm() { return this.locked || this.busy || !!this.blocker || this.done; }
    get confirmLabel() { return this.busy ? 'Saving…' : this.done ? 'Verdict Confirmed' : 'Confirm Verdict'; }
    async handleConfirm() {
        if (this.cantConfirm) { return; }
        await this.call(() => confirmVerdict({ recordId: this.recordId }), 'Could not confirm the verdict.');
    }
}
