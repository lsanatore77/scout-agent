import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqFieldActionStrategy.getView';
import saveField from '@salesforce/apex/CqFieldActionStrategy.saveField';
import setHold from '@salesforce/apex/CqFieldActionStrategy.setHold';
import confirmStrategy from '@salesforce/apex/CqFieldActionStrategy.confirmStrategy';

const REMOVAL = 'Removal (Recall)';
const CORRECTION = 'Correction';
const NOTICE = 'Advisory Notice';
const ACTIONS = [[REMOVAL, 'Removal'], [CORRECTION, 'Correction'], [NOTICE, 'Advisory Notice']];
const ACTION_HINT = {
    [REMOVAL]: 'Product comes back to us.',
    [CORRECTION]: 'Product is fixed where it is, for example relabelled or reworked on site.',
    [NOTICE]: 'Product stays in use with new information or a warning.'
};
const DEPTHS = [['Distributor', 'Distributor'], ['Hospital', 'Hospital'], ['Patient', 'Patient']];
const DEPTH_HINT = {
    Distributor: 'We contact distributors; they pass it on.',
    Hospital: 'We contact every hospital that received units, directly or through a distributor.',
    Patient: 'Hospitals also contact patients who have the device.'
};
const INSTRUCTIONS = [
    ['Stop use, quarantine and return', REMOVAL],
    ['Stop use and destroy on site', REMOVAL],
    ['Hold for our technician to correct on site', CORRECTION],
    ['Continue use with the added warning', NOTICE]
];
const LEVELS = [['Level A', 'A · 100%'], ['Level B', 'B'], ['Level C', 'C · 10%'], ['Level D', 'D · 2%'], ['Level E', 'None']];
const LEVEL_HINT = {
    'Level A': 'Every customer confirms they received the notice and acted on it.',
    'Level B': 'A share between 10% and 100% of customers, set below.',
    'Level C': '10% of customers are checked.',
    'Level D': '2% of customers are checked.',
    'Level E': 'No check. The regulator must agree.'
};
const METHODS = ['Signed response form, then phone', 'Phone call', 'Site visit'];

/** Field Action step 3, Strategy: action and depth, what we tell customers, holds, and the effectiveness check. */
export default class CqFieldActionStrategy extends LightningElement {
    @api recordId;
    v;
    error;
    saving = 0;
    addLot = '';
    footSig;

    async connectedCallback() {
        try { this.apply(await getView({ recordId: this.recordId })); }
        catch (e) { this.error = this.msg(e, 'Could not read the strategy.'); }
    }
    msg(e, fallback) { return (e && e.body && e.body.message) || fallback; }
    apply(v) {
        this.v = JSON.parse(JSON.stringify(v));
        this.dispatchEvent(new CustomEvent('strategychange', { detail: { status: this.v.status, action: this.v.action } }));
    }
    get ready() { return !!this.v; }
    /** The workspace footer shows Confirm Strategy beside Back and Next, so it is told whenever the button changes. */
    renderedCallback() {
        if (!this.v) { return; }
        const detail = { show: this.showStep, label: this.confirmLabel, disabled: this.cantConfirm, blocker: this.showStep ? this.blocker : '' };
        const sig = JSON.stringify(detail);
        if (sig !== this.footSig) { this.footSig = sig; this.dispatchEvent(new CustomEvent('footchange', { detail })); }
    }
    @api confirm() { return this.handleConfirm(); }
    get busy() { return this.saving > 0; }
    get open() { return this.v.scopeConfirmed && !this.v.closed; }
    get needsScope() { return this.ready && !this.v.scopeConfirmed; }
    get showStep() { return this.ready && this.v.scopeConfirmed; }
    get locked() { return !this.open; }

    // the value on screen: what is saved, else CQ.AI's suggestion
    val(k) {
        const saved = this.v[k];
        if (saved !== undefined && saved !== null && saved !== '') { return saved; }
        const s = this.v['s' + k.charAt(0).toUpperCase() + k.slice(1)];
        return s === undefined ? null : s;
    }
    get action() { return this.val('action'); }
    get depth() { return this.val('depth'); }
    get instruction() { return this.val('instruction'); }
    get message() { return this.val('message') || ''; }
    get level() { return this.val('level'); }
    get method() { return this.val('method'); }
    get checkBy() { return this.val('checkBy') || ''; }
    get percent() { return this.v.percent === undefined || this.v.percent === null ? '' : String(this.v.percent); }

    // ---- header
    get stateText() { return this.v.status || 'Not started'; }
    get statePill() { return 'spill state' + (this.v.status === 'Confirmed' ? ' ok' : this.v.status ? ' wait' : ''); }
    get intro() {
        const n = this.v.lotCount;
        const units = this.v.built ? ' (' + this.v.built + ' units built)' : '';
        return 'How this field action will be carried out for the ' + n + ' lot' + (n === 1 ? '' : 's') + ' in scope' + units
            + '. Each choice saves as a draft; Confirm Strategy makes it the plan Notifications works from. CQ.AI\'s picks are marked with ✦.';
    }
    get confirmedLine() {
        if (this.v.status !== 'Confirmed') { return ''; }
        return 'Confirmed' + (this.v.confirmedBy ? ' by ' + this.v.confirmedBy : '') + (this.v.confirmedOn ? ' · ' + new Date(this.v.confirmedOn).toLocaleString() : '');
    }

    // ---- toggles
    seg(list, cur, ai, field) {
        return list.map(([value, label], i) => ({
            key: field + i, value, field, label: (value === ai ? '✦ ' : '') + label,
            pressed: cur === value ? 'true' : 'false',
            cls: 'seg' + (cur === value ? ' on' : '') + (i ? ' sep' : '')
        }));
    }
    get actions() { return this.seg(ACTIONS, this.action, this.v.sAction, 'action'); }
    get depths() { return this.seg(DEPTHS, this.depth, this.v.sDepth, 'depth'); }
    get levels() { return this.seg(LEVELS, this.level, this.v.sLevel, 'level'); }
    get actionHint() { return ACTION_HINT[this.action] || ''; }
    get depthHint() { return DEPTH_HINT[this.depth] || ''; }
    get levelHint() { return LEVEL_HINT[this.level] || ''; }
    get isLevelB() { return this.level === 'Level B'; }
    get needsCheck() { return this.level !== 'Level E'; }
    get instructions() {
        return INSTRUCTIONS.map(([value, forAction], i) => {
            const on = this.instruction === value;
            const fits = forAction === this.action;
            return { key: 'i' + i, value, field: 'instruction', label: value, ai: value === this.v.sInstruction,
                pressed: on ? 'true' : 'false', cls: 'opt' + (on ? ' on' : '') + (fits ? '' : ' off'),
                dot: 'dot' + (on ? ' on' : '') };
        });
    }
    get methods() { return METHODS.map((m) => ({ value: m, label: m, selected: m === this.method })); }

    async handlePick(event) {
        const { field, value } = event.currentTarget.dataset;
        if (this.locked || this.val(field) === value && this.v[field] === value) { return; }
        await this.save(field, value);
    }
    async handleText(event) {
        const field = event.target.dataset.field;
        await this.save(field, event.target.value);
    }
    async save(field, value) {
        this.error = undefined;
        this.v = { ...this.v, [field]: value, status: 'Being Defined' };
        this.saving += 1;
        try { this.apply(await saveField({ recordId: this.recordId, field, value: value === null ? null : String(value) })); }
        catch (e) { this.error = this.msg(e, 'Could not save that choice.'); }
        this.saving -= 1;
    }

    // ---- holds
    get holdRows() {
        const rows = [];
        const add = (kind, title) => {
            const list = (this.v.holds || []).filter((h) => h.kind === kind);
            if (!list.length) { return; }
            rows.push({ key: 'g' + kind, isGroup: true, title, rowCls: 'grp' });
            list.forEach((h) => {
                const state = h.hold && h.held ? ['Held', 'spill ok'] : h.hold ? ['Not confirmed', 'spill wait'] : h.held ? ['Releasing', 'spill bad'] : ['', ''];
                rows.push({ key: h.id, isGroup: false, rowCls: '', id: h.id, lot: h.lot, hold: h.hold, item: h.item || '',
                    part: h.part ? h.part : '', why: h.kind === 'Component Lot' ? h.reason || '' : '', ai: h.suggested && h.kind === 'Component Lot',
                    onHand: h.onHand === undefined || h.onHand === null ? '—' : String(h.onHand),
                    stateText: h.outOfScope ? 'No longer in scope' : state[0], stateCls: h.outOfScope ? 'spill bad' : state[1],
                    hasState: h.outOfScope || !!state[0], label: (h.hold ? 'Release ' : 'Hold ') + h.lot });
            });
        };
        add('Finished Lot', 'Finished lots in scope');
        add('Component Lot', 'Component lots in these lots');
        return rows;
    }
    get holdLine() {
        const hs = this.v.holds || [];
        const n = hs.filter((h) => h.hold).length;
        const placed = hs.filter((h) => h.hold && h.held).length;
        return n + ' lot' + (n === 1 ? '' : 's') + ' to hold' + (placed ? ', ' + placed + ' held' : '')
            + '. Holds are placed on Confirm Strategy. On hand comes from the Scope step until inventory is connected.';
    }
    get compOptions() {
        return [{ value: '', label: 'Add a component lot…', selected: !this.addLot }].concat((this.v.components || []).map((c) => ({
            value: c.lot, selected: c.lot === this.addLot,
            label: c.lot + ' · ' + (c.item || c.part || '') + ' · ' + (c.inLot || '').toLowerCase().replace(/^nc/, 'NC')
        })));
    }
    get hasComps() { return (this.v.components || []).length > 0; }
    get cantAdd() { return this.locked || !this.addLot || this.busy; }
    handleAddPick(event) { this.addLot = event.target.value; }
    async handleAdd() {
        if (this.cantAdd) { return; }
        await this.hold(null, this.addLot, true);
        this.addLot = '';
    }
    async handleHold(event) {
        await this.hold(event.target.dataset.id, null, event.target.checked);
    }
    async hold(holdId, lot, on) {
        this.error = undefined;
        this.saving += 1;
        try { this.apply(await setHold({ recordId: this.recordId, holdId, lot, hold: on })); }
        catch (e) { this.error = this.msg(e, 'Could not save that hold.'); try { this.apply(await getView({ recordId: this.recordId })); } catch (x) { /* keep */ } }
        this.saving -= 1;
    }

    // ---- confirm
    get fits() {
        const a = this.action; const i = this.instruction;
        const list = INSTRUCTIONS.filter(([, forAction]) => forAction === a).map(([value]) => value);
        return list.includes(i);
    }
    get blocker() {
        if (!this.action || !this.depth) { return 'Choose the action and how far it goes'; }
        if (!this.instruction) { return 'Choose what customers are told'; }
        if (!this.fits) { return 'The customer instruction does not match the action'; }
        if (!this.message.trim()) { return 'Write the key message'; }
        if (!this.level) { return 'Choose the check level'; }
        if (this.isLevelB) {
            const p = Number(this.percent);
            if (!this.percent || !(p > 10 && p < 100)) { return 'For Level B, check more than 10% and less than 100%'; }
        }
        if (this.needsCheck && (!this.method || !this.checkBy)) { return 'Choose how and by when we check'; }
        return '';
    }
    get confirmed() { return this.v.status === 'Confirmed'; }
    get cantConfirm() { return this.locked || this.busy || !!this.blocker || this.confirmed; }
    get confirmLabel() { return this.busy ? 'Saving…' : this.confirmed ? 'Strategy Confirmed' : 'Confirm Strategy'; }
    async handleConfirm() {
        if (this.cantConfirm) { return; }
        this.error = undefined;
        this.saving += 1;
        try {
            this.apply(await confirmStrategy({ recordId: this.recordId, values: {
                action: this.action, depth: this.depth, instruction: this.instruction, message: this.message,
                level: this.level, percent: this.percent, method: this.method, checkBy: this.checkBy } }));
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (e) { this.error = this.msg(e, 'Could not confirm the strategy.'); }
        this.saving -= 1;
    }
}
