import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqFieldActionRecovery.getView';
import setDisposition from '@salesforce/apex/CqFieldActionRecovery.setDisposition';
import saveVerdict from '@salesforce/apex/CqFieldActionRecovery.saveVerdict';
import confirmVerdict from '@salesforce/apex/CqFieldActionRecovery.confirmVerdict';
import createSuggested from '@salesforce/apex/CqFieldActionTasks.createSuggested';
import addTask from '@salesforce/apex/CqFieldActionTasks.addTask';
import setTask from '@salesforce/apex/CqFieldActionTasks.setTask';

const DISPOSITIONS = ['Scrap', 'Rework', 'Return to Supplier', 'Release'];
const NEXT_STEPS = ['Widen the scope', 'A further action to customers', 'Extend the check by 30 days'];
const TYPES = ['Send recall notice', 'Collect response', 'Track return', 'Confirm destruction', 'Confirm correction', 'Other'];
const UNIT_TYPES = ['Track return', 'Confirm destruction', 'Confirm correction'];
const NEW_CUSTOMER = '__new';
const NO_CUSTOMER = '__none';

/**
 * Field Action step 6, Recovery and Effectiveness: units back per lot, the customers and their recall tasks,
 * held stock decided, and the verdict. Recall tasks are standard Tasks on the field action (CqFieldActionTasks).
 */
export default class CqFieldActionRecovery extends LightningElement {
    @api recordId;
    v;
    error;
    saving = 0;
    footSig;
    filter = 'all';          // all | open | done | over | week
    closedCust = {};         // customer rows folded away
    reviewing = false;       // CQ.AI's suggested tasks open for review
    keep = {};               // suggestion key -> false when unticked
    adding = false;          // the Add Task form
    form = {};
    unitsFor = '';           // task whose units are being edited
    unitsVal = '';

    async connectedCallback() { await this.load(); }
    async load() {
        try { this.apply(await getView({ recordId: this.recordId })); }
        catch (e) { this.error = this.msg(e, 'Could not read recovery.'); }
    }
    msg(e, fallback) { return (e && e.body && e.body.message) || fallback; }
    apply(v) {
        this.v = JSON.parse(JSON.stringify(v));
        this.dispatchEvent(new CustomEvent('railchange', { detail: { recovery: this.v.recovery, verdict: this.v.verdict, status: this.v.status,
            overdue: this.t.overdue } }));
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
    get t() { return (this.v && this.v.tasks) || { tasks: [], suggestions: [], people: [], lotsByCustomer: {}, shippedByLine: {}, open: 0, completed: 0, overdue: 0, dueWeek: 0 }; }
    num(x) { return x === undefined || x === null ? '—' : String(Number(x)); }
    bar(pct) { return 'width:' + pct + '%;background:' + (pct >= 100 ? '#2e844a' : '#1d5fd1'); }
    day(d) { return d ? new Date(d + 'T00:00:00').toLocaleDateString() : ''; }

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
            this.v.level ? this.v.level + ' check' + (this.v.checkBy ? ' due ' + this.day(this.v.checkBy) : '') : ''].filter(Boolean);
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
        return 'Shipped comes from the lot shipments. ' + (this.isCorrection ? 'Corrected and Returned add' : 'Returned and Destroyed add')
            + ' up from the units on the tasks below.';
    }
    get lotRows() {
        return this.v.lots.map((l) => {
            const pct = l.pct === undefined || l.pct === null ? 0 : l.pct;
            return { ...l, shippedText: this.num(l.shipped), returnedText: this.num(l.returned), destroyedText: this.num(l.destroyed),
                correctedText: this.num(l.corrected), fieldText: this.num(l.field),
                fieldCls: 'num b ' + (l.field ? 'warnc' : l.field === 0 ? 'okc' : ''),
                hasPct: l.shipped !== undefined && l.shipped !== null, pctText: pct + '%', barStyle: this.bar(pct) };
        });
    }
    get recoveryLine() {
        if (!this.v.shippedKnown) { return 'Units shipped are not recorded on the Scope step'; }
        const pct = this.v.shipped ? Math.floor(100 * this.v.recovered / this.v.shipped) : 100;
        return this.v.recovered + ' of ' + this.v.shipped + ' units recovered · ' + pct + '%';
    }

    // ---- task cards: click one to filter the table, click it again to show everything
    get cards() {
        const t = this.t;
        return [['open', 'Open Tasks', t.open], ['done', 'Completed Tasks', t.completed], ['over', 'Overdue Tasks', t.overdue], ['week', 'Due This Week', t.dueWeek]]
            .map(([key, label, n]) => ({ key, label, n, pressed: this.filter === key ? 'true' : 'false',
                cls: 'tcard' + (this.filter === key ? ' on' : ''),
                numCls: 'tnum' + (key === 'done' && n ? ' okc' : key === 'over' && n ? ' badc' : '') }));
    }
    handleCard(event) { const k = event.currentTarget.dataset.key; this.filter = this.filter === k ? 'all' : k; }
    keepTask(x) {
        switch (this.filter) {
            case 'open': return !x.done;
            case 'done': return x.done;
            case 'over': return x.overdue;
            case 'week': return x.dueWeek;
            default: return true;
        }
    }
    get filterLine() {
        if (this.filter === 'all') { return ''; }
        const c = this.cards.find((x) => x.key === this.filter);
        return 'Showing ' + c.label.toLowerCase();
    }

    // ---- 2. customers and tasks: customer, then the lots shipped to them, then the tasks on each
    get rows() {
        const t = this.t;
        const rows = [];
        const custs = this.v.customers.map((c) => ({ ...c }));
        const loose = t.tasks.filter((x) => !x.customerId || !custs.some((c) => c.id === x.customerId));
        if (loose.length) { custs.push({ id: NO_CUSTOMER, name: 'Other tasks', other: true }); }
        custs.forEach((c) => {
            const mine = c.other ? loose : t.tasks.filter((x) => x.customerId === c.id);
            const shown = mine.filter((x) => this.keepTask(x));
            if (this.filter !== 'all' && !shown.length) { return; }
            const open = this.filter !== 'all' || !this.closedCust[c.id];
            const openCount = mine.filter((x) => !x.done).length;
            const lots = c.other ? [] : (t.lotsByCustomer[c.id] || []).slice();
            mine.forEach((x) => { if (x.lot && !lots.includes(x.lot)) { lots.push(x.lot); } });
            rows.push({ key: 'c' + c.id, isCust: true, id: c.id, title: c.name, chev: open ? '▾' : '▸',
                toggleLabel: (open ? 'Fold ' : 'Show ') + c.name,
                sub: c.other ? openCount + ' open' : [c.units !== undefined && c.units !== null ? c.units + ' units' : '',
                    lots.length + ' lot' + (lots.length === 1 ? '' : 's'), openCount + ' open task' + (openCount === 1 ? '' : 's'),
                    c.source === 'Shipment' ? '' : 'added by hand'].filter(Boolean).join(' · '),
                hasPill: !c.other, pill: c.status, pillCls: 'spill ' + (c.status === 'Acknowledged' ? 'ok' : c.status === 'No reply' ? 'bad' : '') });
            if (!open) { return; }
            shown.filter((x) => !x.lot).forEach((x) => rows.push(this.taskRow(x, 'i1')));
            lots.forEach((lot) => {
                const lt = shown.filter((x) => x.lot === lot);
                if (this.filter !== 'all' && !lt.length) { return; }
                const shipped = t.shippedByLine[c.id + '|' + lot];
                const back = mine.filter((x) => x.lot === lot && x.hasUnits).reduce((s, x) => s + Number(x.units || 0), 0);
                rows.push({ key: 'l' + c.id + lot, isLot: true, title: lot,
                    sub: [shipped !== undefined && shipped !== null ? shipped + ' shipped' : '', back + ' back'].filter(Boolean).join(' · ') });
                lt.forEach((x) => rows.push(this.taskRow(x, 'i2')));
            });
        });
        return rows;
    }
    taskRow(x, indent) {
        const editing = this.unitsFor === x.id;
        return { key: 't' + x.id, isTask: true, id: x.id, title: x.subject, indentCls: 'ind ' + indent, href: '/lightning/r/Task/' + x.id + '/view',
            done: x.done, checkLabel: (x.done ? 'Reopen ' : 'Complete ') + x.subject,
            hasUnits: x.hasUnits, editingUnits: editing, notEditingUnits: !editing, unitsVal: editing ? this.unitsVal : x.units,
            unitsText: (x.units === undefined || x.units === null ? 'No' : Number(x.units)) + ' unit' + (Number(x.units) === 1 ? '' : 's')
                + (x.type === 'Confirm correction' ? ' corrected' : x.type === 'Confirm destruction' ? ' destroyed' : ' back'),
            owner: x.owner, due: this.day(x.due), dueCls: 'nw' + (x.overdue ? ' badc b' : ''),
            pill: x.done ? 'Done' : x.overdue ? 'Overdue' : 'Open', pillCls: 'spill ' + (x.done ? 'ok' : x.overdue ? 'bad' : '') };
    }
    get hasRows() { return this.rows.length > 0; }
    get emptyLine() {
        return this.filter !== 'all' ? 'No tasks match.' : this.v.customers.length ? 'No tasks yet.' : 'No customers yet: add lot shipments for the lots in scope, or add a task for a customer by hand.';
    }
    get allOpen() { return !this.v.customers.some((c) => this.closedCust[c.id]); }
    get allChev() { return this.allOpen ? '▾' : '▸'; }
    get allLabel() { return this.allOpen ? 'Fold all customers' : 'Show all customers'; }
    handleToggleAll() {
        const fold = this.allOpen;
        const m = {};
        if (fold) { this.v.customers.forEach((c) => { m[c.id] = true; }); m[NO_CUSTOMER] = true; }
        this.closedCust = m;
    }
    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.closedCust = { ...this.closedCust, [id]: !this.closedCust[id] };
    }
    async handleCheck(event) {
        const id = event.target.dataset.id;
        const change = event.target.checked ? 'done' : 'open';
        await this.call(() => setTask({ recordId: this.recordId, taskId: id, change, units: null }), 'Could not change that task.');
    }
    handleEditUnits(event) {
        if (this.locked) { return; }
        const id = event.currentTarget.dataset.id;
        const x = this.t.tasks.find((k) => k.id === id);
        this.unitsFor = id; this.unitsVal = x.units === undefined || x.units === null ? '' : x.units;
    }
    handleUnitsInput(event) { this.unitsVal = event.target.value; }
    handleUnitsCancel() { this.unitsFor = ''; }
    async handleUnitsSave() {
        const id = this.unitsFor;
        await this.call(() => setTask({ recordId: this.recordId, taskId: id, change: 'units', units: this.unitsVal === '' ? null : Number(this.unitsVal) }),
            'Could not save those units.', () => { this.unitsFor = ''; });
    }

    // ---- CQ.AI's suggested tasks
    get hasSuggestions() { return !this.locked && this.t.suggestions.length > 0; }
    get suggestRows() {
        return this.t.suggestions.map((s) => ({ ...s, checked: this.keep[s.key] !== false, due: this.day(s.due),
            label: 'Create: ' + s.subject }));
    }
    get keptCount() { return this.t.suggestions.filter((s) => this.keep[s.key] !== false).length; }
    get createLabel() { return 'Create ' + this.keptCount + ' Task' + (this.keptCount === 1 ? '' : 's'); }
    get cantCreate() { return this.busy || this.keptCount === 0; }
    handleReview() { this.reviewing = !this.reviewing; this.keep = {}; }
    handleKeep(event) { this.keep = { ...this.keep, [event.target.dataset.key]: event.target.checked }; }
    async handleCreate() {
        const keys = this.t.suggestions.filter((s) => this.keep[s.key] !== false).map((s) => s.key);
        await this.call(() => createSuggested({ recordId: this.recordId, keys }), 'Could not create those tasks.', () => { this.reviewing = false; this.keep = {}; });
    }

    // ---- + Add Task: one task for a customer (or a new one), a lot, an owner and a due date
    handleOpenAdd() {
        this.adding = !this.adding;
        this.form = { customerId: '', newCustomer: '', lot: '', type: 'Track return', subject: '', ownerId: this.t.me, due: '', units: '' };
    }
    get custOpts() {
        const f = this.form;
        return [{ value: '', label: 'No customer', selected: !f.customerId }]
            .concat(this.v.customers.map((c) => ({ value: c.id, label: c.name, selected: f.customerId === c.id })))
            .concat([{ value: NEW_CUSTOMER, label: 'New customer…', selected: f.customerId === NEW_CUSTOMER }]);
    }
    get isNewCustomer() { return this.form.customerId === NEW_CUSTOMER; }
    get lotOpts() {
        const f = this.form;
        const lots = f.customerId && f.customerId !== NEW_CUSTOMER && (this.t.lotsByCustomer[f.customerId] || []).length
            ? this.t.lotsByCustomer[f.customerId] : this.v.lots.map((l) => l.lot);
        return [{ value: '', label: 'No lot', selected: !f.lot }].concat(lots.map((l) => ({ value: l, label: l, selected: f.lot === l })));
    }
    get typeOpts() { return TYPES.map((x) => ({ value: x, label: x, selected: this.form.type === x })); }
    get ownerOpts() { return this.t.people.map((p) => ({ value: p.id, label: p.name, selected: this.form.ownerId === p.id })); }
    get formHasUnits() { return UNIT_TYPES.includes(this.form.type); }
    get subjectHint() { return this.defaultSubject() || 'What needs doing'; }
    defaultSubject() {
        const f = this.form;
        const c = this.v.customers.find((x) => x.id === f.customerId);
        const who = c ? c.name : this.isNewCustomer ? f.newCustomer : '';
        if (f.type === 'Other') { return ''; }
        return f.type + (f.lot ? ' of lot ' + f.lot : '') + (who ? (f.type === 'Send recall notice' ? ' to ' : f.type === 'Collect response' ? ' from ' : ' for ') + who : '');
    }
    get cantAdd() {
        const f = this.form;
        return this.busy || (!f.subject.trim() && !this.defaultSubject()) || (this.isNewCustomer && !f.newCustomer.trim());
    }
    handleForm(event) {
        const k = event.target.dataset.f;
        const next = { ...this.form, [k]: event.target.value };
        if (k === 'customerId') { next.lot = ''; }
        this.form = next;
    }
    async handleAdd() {
        if (this.cantAdd) { return; }
        const f = this.form;
        const values = { customerId: f.customerId && f.customerId !== NEW_CUSTOMER ? f.customerId : '', newCustomer: this.isNewCustomer ? f.newCustomer : '',
            lot: f.lot, type: f.type, subject: f.subject.trim() || this.defaultSubject(), ownerId: f.ownerId || '', due: f.due || '',
            units: this.formHasUnits && f.units !== '' ? String(f.units) : '' };
        await this.call(() => addTask({ recordId: this.recordId, values }), 'Could not add that task.', () => { this.adding = false; });
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
    get respLine() { return this.v.total ? this.v.acked + ' of ' + this.v.total + ' customers acknowledged' : 'No customers yet'; }
    get targetText() {
        if (this.v.target === 0) { return 'No check needed'; }
        return (this.v.level || 'Target') + ' target ' + this.v.target + '%' + (this.v.checkBy ? ' by ' + this.day(this.v.checkBy) : '');
    }
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
