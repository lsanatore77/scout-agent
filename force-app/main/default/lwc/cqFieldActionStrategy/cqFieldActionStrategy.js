import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqFieldActionStrategy.getView';
import saveField from '@salesforce/apex/CqFieldActionStrategy.saveField';
import setHold from '@salesforce/apex/CqFieldActionStrategy.setHold';
import confirmStrategy from '@salesforce/apex/CqFieldActionStrategy.confirmStrategy';
import { sortRows, nextSort, heads } from 'c/cqSort';

const REMOVAL = 'Removal (Recall)';
const CORRECTION = 'Correction';
const NOTICE = 'Advisory Notice';
const WITHDRAWAL = 'Withdrawal';
const ACTIONS = [[REMOVAL, 'Removal'], [WITHDRAWAL, 'Withdrawal'], [CORRECTION, 'Correction'], [NOTICE, 'Advisory Notice']];
const ACTION_HINT = {
    [REMOVAL]: 'Product comes back to us.',
    [WITHDRAWAL]: 'Product comes back for a minor issue. Not a recall, not reported.',
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
    ['Stop use, quarantine and return', [REMOVAL, WITHDRAWAL]],
    ['Stop use and destroy on site', [REMOVAL, WITHDRAWAL]],
    ['Hold for our technician to correct on site', [CORRECTION]],
    ['Continue use with the added warning', [NOTICE]]
];
const INSTRUCTION_HINT = {
    'Stop use, quarantine and return': 'Customers set the units aside and send them back to us.',
    'Stop use and destroy on site': 'Customers destroy the units and confirm they have.',
    'Hold for our technician to correct on site': 'Units stay where they are until our technician corrects them.',
    'Continue use with the added warning': 'Customers keep using the product and read the new warning.'
};
const LEVELS = [['Level A', 'A · 100%'], ['Level B', 'B · Your share'], ['Level C', 'C · 10%'], ['Level D', 'D · 2%'], ['Level E', 'None']];
const LEVEL_HINT = {
    'Level A': 'Every customer confirms they received the notice and acted on it.',
    'Level B': 'A share between 10% and 100% of customers, which you set.',
    'Level C': '10% of customers are checked.',
    'Level D': '2% of customers are checked.',
    'Level E': 'No check. The regulator must agree.'
};
const METHODS = ['Signed response form, then phone', 'Phone call', 'Site visit'];
// a nonconformance is stored as 'NC NC-000077 · in lot ...'; it is shown once: 'NC-000077 · in lot ...'
const ncOnce = (s) => (s || '').replace(/NC NC-/g, 'NC-');

/** Field Action step 3, Strategy: action and depth, what we tell customers, holds, and the effectiveness check. */
export default class CqFieldActionStrategy extends LightningElement {
    @api recordId;
    v;
    error;
    saving = 0;
    addLot = '';
    footSig;
    tab = 'action';      // action | tell | holds | check
    stockOpen = '';      // the hold row whose on-hand split is showing
    holdSort = null;     // the Holds table's sort ({ key, dir }); rows sort inside their group (finished lots, component lots)
    editing = false;     // a confirmed strategy shows as a summary; Change (or Show Details once closed) opens the tabs
    why;                 // why the strategy differs from CQ.AI's suggestion (Strategy Reason); kept while moving between tabs

    async connectedCallback() {
        // a click anywhere else, or Escape, closes the On Hand card (as on Scope)
        this.closePop = () => { if (this.keepPop) { this.keepPop = false; } else if (this.stockOpen) { this.stockOpen = ''; } };
        this.escPop = (e) => { if (e.key === 'Escape' && this.stockOpen) { this.stockOpen = ''; } };
        document.addEventListener('click', this.closePop);
        document.addEventListener('keydown', this.escPop);
        try { this.apply(await getView({ recordId: this.recordId })); }
        catch (e) { this.error = this.msg(e, 'Could not read the strategy.'); }
    }
    disconnectedCallback() {
        document.removeEventListener('click', this.closePop);
        document.removeEventListener('keydown', this.escPop);
    }
    msg(e, fallback) { return (e && e.body && e.body.message) || fallback; }
    apply(v) {
        this.v = JSON.parse(JSON.stringify(v));
        if (this.why === undefined) { this.why = this.v.reason || ''; }
        this.dispatchEvent(new CustomEvent('strategychange', { detail: { status: this.v.status, action: this.v.action } }));
    }
    get ready() { return !!this.v; }
    /** The workspace footer shows Confirm Strategy beside Back and Next, so it is told whenever the button changes. */
    renderedCallback() {
        if (!this.v) { return; }
        // a textarea shows its text through its value property, so it is set here (not while someone is typing in it)
        const ta = this.template.querySelector('textarea[data-field="message"]');
        if (ta && this.template.activeElement !== ta && ta.value !== this.message) { ta.value = this.message; }
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
    get statePill() { return 'cq-pill soft ' + (this.v.status === 'Confirmed' ? 'pos' : this.v.status ? 'warn' : 'neu'); }

    // ---- tabs: one section, a tab per part; a green tick when that part is done, an amber ! when it needs fixing (no numbers)
    get tabState() {
        const p = Number(this.percent);
        const checkDone = !!this.level && (!this.isLevelB || (p > 10 && p < 100)) && (!this.needsCheck || (!!this.method && !!this.checkBy));
        return {
            action: this.action && this.depth ? 'ok' : '',
            tell: this.instruction && !this.fits ? 'warn' : this.instruction && this.message.trim() ? 'ok' : '',
            holds: (this.v.holds || []).some((h) => h.hold) ? 'ok' : '',
            check: checkDone ? 'ok' : ''
        };
    }
    get tabs() {
        const n = (this.v.holds || []).filter((h) => h.hold).length;
        const st = this.tabState;
        return [['action', 'Action and Depth'], ['tell', 'What We Tell Customers'], ['holds', 'Holds (' + n + ')'], ['check', 'Effectiveness Check']]
            .map(([key, label]) => ({ key, label, mark: st[key] === 'ok' ? '✓' : st[key] === 'warn' ? '!' : '', sel: this.tab === key ? 'true' : 'false',
                cls: 'tab' + (this.tab === key ? ' on' : ''), numCls: 'tnum' + (st[key] ? ' ' + st[key] : '') }));
    }
    handleTab(event) { this.tab = event.currentTarget.dataset.tab; }
    get isAction() { return this.tab === 'action'; }
    get isTell() { return this.tab === 'tell'; }
    get isHolds() { return this.tab === 'holds'; }
    get isCheck() { return this.tab === 'check'; }
    get confirmedLine() {
        if (this.v.status !== 'Confirmed') { return ''; }
        return 'Confirmed' + (this.v.confirmedBy ? ' by ' + this.v.confirmedBy : '') + (this.v.confirmedOn ? ' · ' + new Date(this.v.confirmedOn).toLocaleString() : '');
    }

    // ---- choices: the shared stacked list (c-cq-ws-choice, rows), two side by side per tab
    options(list, ai, hints) { return list.map(([value, title]) => ({ id: value, title, desc: hints[value] || '', cq: value === ai })); }
    get actionOptions() { return this.options(ACTIONS, this.v.sAction, ACTION_HINT); }
    get depthOptions() { return this.options(DEPTHS, this.v.sDepth, DEPTH_HINT); }
    get levelOptions() { return this.options(LEVELS, this.v.sLevel, LEVEL_HINT); }
    get isLevelB() { return this.level === 'Level B'; }
    get needsCheck() { return this.level !== 'Level E'; }
    get instructionOptions() {
        return INSTRUCTIONS.map(([value, forAction]) => {
            const fits = forAction.includes(this.action);
            return { id: value, title: value, cq: value === this.v.sInstruction, off: !fits,
                desc: INSTRUCTION_HINT[value] + (fits ? '' : ' Only for ' + (forAction[0] === REMOVAL ? 'a removal or withdrawal.' : forAction[0] === CORRECTION ? 'a correction.' : 'an advisory notice.')) };
        });
    }
    get methods() { return METHODS.map((m) => ({ value: m, label: m, selected: m === this.method })); }

    async handleChoose(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.detail;
        if (this.locked || this.val(field) === value && this.v[field] === value) { return; }
        await this.save(field, value);
    }

    // ---- once confirmed: what was chosen, against what CQ.AI suggested; Change opens the tabs again
    get showSummary() { return this.confirmed && !this.editing; }
    get showTabs() { return !this.showSummary; }
    get backToSummary() { return this.confirmed && this.editing; }
    get changeLabel() { return this.locked ? 'Show Details' : 'Change'; }
    handleEdit() { this.editing = true; }
    handleSummary() { this.editing = false; }
    pick(list, value) { const f = list.find(([v]) => v === value); return f ? f[1] : value; }
    vsAi(value, ai, list) {
        if (!ai) { return ''; }
        return value === ai ? 'As CQ.AI suggests' : 'CQ.AI suggested ' + (list ? this.pick(list, ai) : ai);
    }
    get summaryRows() {
        const v = this.v;
        const held = (v.holds || []).filter((h) => h.hold);
        const lots = [...new Set(held.map((h) => h.lot))];
        const check = this.level === 'Level E' ? 'No check'
            : [this.pick(LEVELS, this.level) + (this.isLevelB && this.percent ? ' (' + this.percent + '%)' : ''), this.method,
                this.checkBy ? 'by ' + new Date(this.checkBy + 'T00:00:00').toLocaleDateString() : ''].filter(Boolean).join(' · ');
        return [
            { key: 'a', k: 'Action', v: this.pick(ACTIONS, this.action), d: ACTION_HINT[this.action], ai: this.vsAi(this.action, v.sAction, ACTIONS) },
            { key: 'd', k: 'How Far It Goes', v: this.depth, d: DEPTH_HINT[this.depth], ai: this.vsAi(this.depth, v.sDepth) },
            { key: 'i', k: 'What We Tell Customers', v: this.instruction, d: this.message, ai: this.vsAi(this.instruction, v.sInstruction) },
            { key: 'h', k: 'Holds', v: held.length ? held.length + (held.length === 1 ? ' hold' : ' holds') + ' on ' + lots.length + (lots.length === 1 ? ' lot' : ' lots') : 'No holds',
                d: lots.join(', '), ai: '' },
            { key: 'c', k: 'Effectiveness Check', v: check, d: LEVEL_HINT[this.level], ai: this.vsAi(this.level, v.sLevel, LEVELS) },
            ...(v.reason ? [{ key: 'r', k: 'Why It Differs From CQ.AI', v: v.reason, d: '', ai: '' }] : [])
        ].map((r) => ({ ...r, aiCls: 'sai' + (r.ai.startsWith('As') ? ' same' : '') }));
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
    get holdHeads() {
        return heads([
            { key: 'hold', label: 'Hold', cls: 'hc', sortable: false },
            { key: 'lot', label: 'Lot' },
            { key: 'item', label: 'What' },
            { key: 'onHandN', label: 'On Hand', num: true },
            { key: 'heldN', label: 'Held Since' },
            { key: 'stateText', label: 'Status' }
        ], this.holdSort);
    }
    handleHoldSort(event) { this.holdSort = nextSort(this.holdSort, event.currentTarget.dataset.key); }
    get holdRows() {
        const rows = [];
        const add = (kind, title) => {
            const list = (this.v.holds || []).filter((h) => h.kind === kind);
            if (!list.length) { return; }
            rows.push({ key: 'g' + kind, isGroup: true, title, rowCls: 'grp' });
            const out = [];
            list.forEach((h) => {
                const state = h.hold && h.held ? ['Held', 'cq-pill soft pos'] : h.hold ? ['Not confirmed', 'cq-pill soft warn'] : h.held ? ['Releasing', 'cq-pill soft crit'] : ['', ''];
                out.push({ key: h.id, isGroup: false, rowCls: '', id: h.id, lot: h.lot, hold: h.hold, item: h.item || '',
                    part: h.part ? h.part : '', why: h.kind === 'Component Lot' ? ncOnce(h.reason) : '', ai: h.suggested && h.kind === 'Component Lot',
                    onHand: h.onHand === undefined || h.onHand === null ? '—' : String(h.onHand),
                    stateText: h.outOfScope ? 'No longer in scope' : state[0], stateCls: h.outOfScope ? 'cq-pill soft crit' : state[1],
                    hasState: h.outOfScope || !!state[0], label: (h.hold ? 'Release ' : 'Hold ') + h.lot,
                    places: (h.places || []).map((k, i) => ({ key: h.id + '|' + i, location: k.location, units: String(Number(k.units)),
                        href: k.locationId ? '/lightning/r/compliancequest__SQX_Location__c/' + k.locationId + '/view' : null })),
                    canOpen: (h.places || []).length > 0, stockOpen: this.stockOpen === h.id && (h.places || []).length > 0,
                    stockExpanded: this.stockOpen === h.id ? 'true' : 'false', popLabel: 'On hand for lot ' + h.lot,
                    asOfText: [h.source, h.asOf ? 'as of ' + new Date(h.asOf).toLocaleString() : ''].filter(Boolean).join(' · '),
                    heldText: h.heldOn ? new Date(h.heldOn).toLocaleDateString() : '—', stays: h.stays,
                    onHandN: h.onHand === undefined || h.onHand === null ? null : Number(h.onHand), heldN: h.heldOn ? new Date(h.heldOn).getTime() : null });
            });
            rows.push(...sortRows(out, this.holdSort));
        };
        add('Finished Lot', 'Finished lots in scope');
        add('Component Lot', 'Component lots in these lots');
        return rows;
    }
    /** What CQ.AI suggests holding, and why: every finished lot in scope, and each component lot with a nonconformance. */
    get holdAi() {
        const hs = (this.v.holds || []).filter((h) => h.suggested && !h.outOfScope);
        const fin = hs.filter((h) => h.kind === 'Finished Lot');
        const comps = hs.filter((h) => h.kind === 'Component Lot');
        if (!hs.length) { return null; }
        const parts = [];
        if (fin.length) { parts.push(fin.length + ' Finished Lot' + (fin.length === 1 ? '' : 's') + ' in Scope'); }
        if (comps.length === 1) { parts.push('Component Lot ' + comps[0].lot); }
        else if (comps.length) { parts.push(comps.length + ' Component Lots'); }
        const why = [];
        if (fin.length) { why.push('Every finished lot in scope is held so none of its stock ships while the recall runs.'); }
        comps.forEach((c) => {
            const m = /(NC-\S+) · in lot (\S+)/i.exec(ncOnce(c.reason));
            why.push(m ? c.lot + ' has ' + m[1] + ' against it and went into ' + m[2] + '.' : c.lot + ': ' + ncOnce(c.reason));
        });
        return { headline: 'Hold ' + hs.length + ' Lot' + (hs.length === 1 ? '' : 's') + ': ' + parts.join(' and '), why: why.join(' ') };
    }
    get holdLine() {
        const hs = this.v.holds || [];
        const n = hs.filter((h) => h.hold).length;
        const placed = hs.filter((h) => h.hold && h.held).length;
        return n + ' lot' + (n === 1 ? '' : 's') + ' to hold' + (placed ? ', ' + placed + ' held' : '')
            + '. Holds are placed on Confirm Strategy.';
    }
    get compOptions() {
        return [{ value: '', label: 'Add a Component Lot…', selected: !this.addLot }].concat((this.v.components || []).map((c) => ({
            value: c.lot, selected: c.lot === this.addLot,
            label: c.lot + ' · ' + (c.item || c.part || '') + ' · ' + ncOnce(c.inLot).replace(/^In lot/, 'in lot')
        })));
    }
    get hasComps() { return (this.v.components || []).length > 0; }
    get cantAdd() { return this.locked || !this.addLot || this.busy; }
    /** On hand opens a small card with the split by CQ Location and how fresh the figures are (as on Scope). */
    handleStock(event) {
        const key = event.currentTarget.dataset.key;
        this.stockOpen = this.stockOpen === key ? '' : key;
        this.keepPop = true;
    }
    /** A click inside the On Hand card (a location link, say) keeps it open. */
    handlePopClick() { this.keepPop = true; }
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

    // ---- a choice other than CQ.AI's needs a reason, as on the review (one reason for the action, how far it goes and the check level)
    get differs() {
        const v = this.v; const out = [];
        if (v.sAction && this.action !== v.sAction) { out.push({ key: 'action', label: this.pick(ACTIONS, this.action), ai: this.pick(ACTIONS, v.sAction) }); }
        if (v.sDepth && this.depth !== v.sDepth) { out.push({ key: 'depth', label: this.depth, ai: v.sDepth }); }
        if (v.sLevel && this.level !== v.sLevel) { out.push({ key: 'level', label: this.level, ai: v.sLevel }); }
        return out;
    }
    get needsWhy() { return this.differs.length > 0; }
    get whyOnAction() { return this.differs.some((d) => d.key === 'action' || d.key === 'depth'); }
    get whyOnCheck() { return this.differs.some((d) => d.key === 'level'); }
    get whyLabel() {
        const d = this.differs;
        return d.length === 1 ? 'Why ' + d[0].label + ' instead of ' + d[0].ai + ', as CQ.AI suggests?'
            : 'Why ' + d.map((x) => x.label).join(', ') + ' instead of ' + d.map((x) => x.ai).join(', ') + ', as CQ.AI suggests?';
    }
    get whyHint() { return 'What do you know that the facts in CQ do not show?'; }
    handleWhy(event) { this.why = event.target.value; }

    // ---- confirm
    get fits() {
        const a = this.action; const i = this.instruction;
        const list = INSTRUCTIONS.filter(([, forAction]) => forAction.includes(a)).map(([value]) => value);
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
        if (this.needsWhy && !(this.why || '').trim()) { return 'Say why the strategy differs from CQ.AI'; }
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
                level: this.level, percent: this.percent, method: this.method, checkBy: this.checkBy,
                why: this.needsWhy ? (this.why || '').trim() : null } }));
            this.editing = false;
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (e) { this.error = this.msg(e, 'Could not confirm the strategy.'); }
        this.saving -= 1;
    }
}
