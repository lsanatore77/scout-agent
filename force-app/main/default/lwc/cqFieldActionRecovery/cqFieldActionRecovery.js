import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqFieldActionRecovery.getView';
import setDisposition from '@salesforce/apex/CqFieldActionRecovery.setDisposition';
import markReworkDone from '@salesforce/apex/CqFieldActionRecovery.markReworkDone';
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
const CUST_PAGE = 5;     // customers a page in the Customers and Tasks table; a customer's open rows stay with it
/** Page links: all of them up to 7 pages, otherwise the first, the last and two either side of the current one, with … for gaps. */
function pageLinks(n, cur) {
    const keep = [];
    for (let i = 0; i < n; i++) { if (n <= 7 || i === 0 || i === n - 1 || Math.abs(i - cur) <= 2) { keep.push(i); } }
    const out = [];
    keep.forEach((i, k) => {
        if (k > 0 && i - keep[k - 1] > 1) { out.push({ key: 'g' + i, text: '…', cls: 'pg gap', off: true, label: 'More pages' }); }
        const on = i === cur;
        out.push({ key: 'p' + i, p: i, text: String(i + 1), cls: 'pg' + (on ? ' on' : ''), off: on, current: on ? 'page' : 'false',
            label: 'Page ' + (i + 1) });
    });
    return out;
}

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
    openCust = {};           // customer rows opened (all start closed)
    reviewing = false;       // CQ.AI's suggested tasks open for review
    keep = {};               // suggestion key -> false when unticked
    adding = false;          // the Add Task form
    form = {};
    unitsFor = '';           // task whose units are being edited
    unitsVal = '';
    search = '';             // customer name search
    custPage = 0;
    custMin = 0;             // the table keeps the height of its first page, so the page numbers do not jump

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
    bar(pct) { return 'width:' + pct + '%'; }
    day(d) { return d ? new Date(d + 'T00:00:00').toLocaleDateString() : ''; }

    renderedCallback() {
        if (!this.v) { return; }
        if (this.hasCustPages && !this.custMin && this.custPageNow === 0 && !Object.values(this.openCust).some(Boolean)) {
            const w = this.template.querySelector('.custwrap');
            if (w && w.clientHeight) { this.custMin = w.clientHeight; }
        }
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
    get statePill() { return 'cq-pill soft ' + (this.confirmed ? 'pos' : this.stateText === 'Not Effective' ? 'crit' : 'warn'); }
    get intro() {
        const parts = [this.v.action, this.v.depth ? 'to ' + this.v.depth.toLowerCase() + ' level' : '',
            this.v.level ? this.v.level + ' check' + (this.v.checkBy ? ' due ' + this.day(this.v.checkBy) : '') : ''].filter(Boolean);
        return 'Track the product coming back and the customers confirming, against the strategy: ' + parts.join(', ') + '.';
    }

    // ---- 1. recovery by lot: the columns follow the action. A removal brings units back or has them destroyed on site;
    // a correction fixes them where they are (some may still come back); an advisory notice leaves them in use.
    get isRemoval() { return this.v.action === 'Removal (Recall)' || this.isWithdrawal; }
    get isWithdrawal() { return this.v.action === 'Withdrawal'; }
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
                hasPct: l.shipped !== undefined && l.shipped !== null, pctText: pct + '%', barStyle: this.bar(pct),
                fillCls: 'cq-bar-fill' + (pct >= 100 ? ' done' : '') };
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
                cls: 'cq-statcard' + (this.filter === key ? ' on' : ''),
                numCls: 'cq-statcard-v' + (key === 'done' && n ? ' ok' : key === 'over' && n ? ' bad' : '') }));
    }
    handleCard(event) { const k = event.currentTarget.dataset.key; this.filter = this.filter === k ? 'all' : k; this.custPage = 0; }
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
    /** The customers the table lists: those with tasks matching the card filter, whose name matches the search. */
    get custList() {
        const t = this.t;
        const custs = this.v.customers.map((c) => ({ ...c }));
        const loose = t.tasks.filter((x) => !x.customerId || !custs.some((c) => c.id === x.customerId));
        if (loose.length) { custs.push({ id: NO_CUSTOMER, name: 'Other tasks', other: true }); }
        const q = this.search.trim().toLowerCase();
        return custs.map((c) => {
            const mine = c.other ? loose : t.tasks.filter((x) => x.customerId === c.id);
            return { c, mine, shown: mine.filter((x) => this.keepTask(x)) };
        }).filter((e) => (this.filter === 'all' || e.shown.length > 0) && (!q || (e.c.name || '').toLowerCase().includes(q)));
    }
    get custPageCount() { return Math.max(1, Math.ceil(this.custList.length / CUST_PAGE)); }
    get custPageNow() { return Math.min(this.custPage, this.custPageCount - 1); }
    get hasCustPages() { return this.custList.length > CUST_PAGE; }
    get cantPrevCust() { return this.custPageNow === 0; }
    get cantNextCust() { return this.custPageNow >= this.custPageCount - 1; }
    get custPageItems() { return pageLinks(this.custPageCount, this.custPageNow); }
    get custTableStyle() { return this.hasCustPages && this.custMin ? 'min-height:' + this.custMin + 'px' : ''; }
    handleCustPrev() { this.custPage = Math.max(0, this.custPageNow - 1); }
    handleCustNext() { this.custPage = Math.min(this.custPageCount - 1, this.custPageNow + 1); }
    handleCustPage(event) { this.custPage = Number(event.currentTarget.dataset.p); }
    handleSearch(event) { this.search = event.target.value; this.custPage = 0; }
    get rows() {
        const t = this.t;
        const rows = [];
        const from = this.custPageNow * CUST_PAGE;
        this.custList.slice(from, from + CUST_PAGE).forEach(({ c, mine, shown }) => {
            const open = this.filter !== 'all' || !!this.openCust[c.id];
            const openCount = mine.filter((x) => !x.done).length;
            const lots = c.other ? [] : (t.lotsByCustomer[c.id] || []).slice();
            mine.forEach((x) => { if (x.lot && !lots.includes(x.lot)) { lots.push(x.lot); } });
            rows.push({ key: 'c' + c.id, isCust: true, rowCls: 'cq-row-parent', id: c.id, title: c.name, chevCls: 'cq-rchev' + (open ? ' open' : ''),
                expanded: open ? 'true' : 'false', toggleLabel: (open ? 'Fold ' : 'Show ') + c.name,
                sub: c.other ? openCount + ' open' : [c.units !== undefined && c.units !== null ? c.units + ' units' : '',
                    lots.length + ' lot' + (lots.length === 1 ? '' : 's'), openCount + ' open task' + (openCount === 1 ? '' : 's'),
                    c.source === 'Shipment' ? '' : 'added by hand'].filter(Boolean).join(' · '),
                hasPill: !c.other, pill: c.status, pillCls: 'cq-pill soft ' + (c.status === 'Acknowledged' ? 'pos' : c.status === 'No reply' ? 'crit' : 'neu') });
            if (!open) { return; }
            shown.filter((x) => !x.lot).forEach((x) => rows.push(this.taskRow(x, 'i1')));
            lots.forEach((lot) => {
                const lt = shown.filter((x) => x.lot === lot);
                if (this.filter !== 'all' && !lt.length) { return; }
                const shipped = t.shippedByLine[c.id + '|' + lot];
                const back = mine.filter((x) => x.lot === lot && x.hasUnits).reduce((s, x) => s + Number(x.units || 0), 0);
                rows.push({ key: 'l' + c.id + lot, isLot: true, rowCls: 'cq-row-child', title: lot, inRecall: this.v.lots.some((l) => l.lot === lot),
                    sub: [shipped !== undefined && shipped !== null ? shipped + ' shipped' : '', back + ' back'].filter(Boolean).join(' · ') });
                lt.forEach((x) => rows.push(this.taskRow(x, 'i2')));
            });
        });
        return rows;
    }
    taskRow(x, indent) {
        const editing = this.unitsFor === x.id;
        return { key: 't' + x.id, isTask: true, rowCls: '', id: x.id, title: x.subject, indentCls: indent === 'i2' ? 'cq-ind l2' : 'cq-ind', href: '/lightning/r/Task/' + x.id + '/view',
            done: x.done, checkLabel: (x.done ? 'Reopen ' : 'Complete ') + x.subject,
            hasUnits: x.hasUnits, editingUnits: editing, notEditingUnits: !editing, unitsVal: editing ? this.unitsVal : x.units,
            unitsText: (x.units === undefined || x.units === null ? 'No' : Number(x.units)) + ' unit' + (Number(x.units) === 1 ? '' : 's')
                + (x.type === 'Confirm correction' ? ' corrected' : x.type === 'Confirm destruction' ? ' destroyed' : ' back'),
            owner: x.owner, due: this.day(x.due), dueCls: 'nw' + (x.overdue ? ' badc b' : ''),
            pill: x.done ? 'Done' : x.overdue ? 'Overdue' : 'Open', pillCls: 'cq-pill soft ' + (x.done ? 'pos' : x.overdue ? 'crit' : 'neu') };
    }
    get hasRows() { return this.rows.length > 0; }
    get emptyLine() {
        if (this.search.trim()) { return 'No customer matches “' + this.search.trim() + '”.'; }
        return this.filter !== 'all' ? 'No tasks match.' : this.v.customers.length ? 'No tasks yet.' : 'No customers yet: add lot shipments for the lots in scope, or add a task for a customer by hand.';
    }
    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.openCust = { ...this.openCust, [id]: !this.openCust[id] };
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
    handleAddKey(event) { if (event.key === 'Escape') { this.adding = false; } }
    get custOpts() {
        const f = this.form;
        return [{ value: '', label: 'No Customer', selected: !f.customerId }]
            .concat(this.v.customers.map((c) => ({ value: c.id, label: c.name, selected: f.customerId === c.id })))
            .concat([{ value: NEW_CUSTOMER, label: 'New Customer…', selected: f.customerId === NEW_CUSTOMER }]);
    }
    get isNewCustomer() { return this.form.customerId === NEW_CUSTOMER; }
    get lotOpts() {
        const f = this.form;
        const lots = f.customerId && f.customerId !== NEW_CUSTOMER && (this.t.lotsByCustomer[f.customerId] || []).length
            ? this.t.lotsByCustomer[f.customerId] : this.v.lots.map((l) => l.lot);
        return [{ value: '', label: 'No Lot', selected: !f.lot }].concat(lots.map((l) => ({ value: l, label: l, selected: f.lot === l })));
    }
    get typeOpts() { return TYPES.map((x) => ({ value: x, label: this.typeLabel(x), selected: this.form.type === x })); }
    /** A withdrawal is never called a recall: its notice task reads Send withdrawal notice (the task type stays the same). */
    typeLabel(x) { return this.isWithdrawal && x === 'Send recall notice' ? 'Send withdrawal notice' : x; }
    get ownerOpts() { return this.t.people.map((p) => ({ value: p.id, label: p.name, selected: this.form.ownerId === p.id })); }
    get formHasUnits() { return UNIT_TYPES.includes(this.form.type); }
    get subjectHint() { return this.defaultSubject() || 'What needs doing'; }
    defaultSubject() {
        const f = this.form;
        const c = this.v.customers.find((x) => x.id === f.customerId);
        const who = c ? c.name : this.isNewCustomer ? f.newCustomer : '';
        if (f.type === 'Other') { return ''; }
        return this.typeLabel(f.type) + (f.lot ? ' of lot ' + f.lot : '') + (who ? (f.type === 'Send recall notice' ? ' to ' : f.type === 'Collect response' ? ' from ' : ' for ') + who : '');
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
            kindText: h.kind === 'Finished Lot' ? 'Finished lot'
                : 'Component lot' + (h.reason && h.reason.startsWith('NC ') ? ' · ' + h.reason.split(' ')[1] : ''),
            onHandText: this.num(h.onHand),
            opts: [{ value: '', label: 'Choose…', selected: !h.disposition }].concat(DISPOSITIONS.map((d) => ({
                value: d, label: (d === h.suggested ? '✦ ' : '') + d, selected: d === h.disposition }))),
            label: 'Disposition for ' + h.lot,
            // what else holds the lot (CqLotStatus): a short tag in its own column; the full note only when it is released
            alsoCls: 'cq-pill soft ' + (h.stays && h.stays.status === 'Rejected' ? 'crit' : 'warn'),
            alsoBy: h.stays ? (h.stays.manual ? 'Set by hand' : h.stays.who || '') : '',
            releaseNote: !!h.stays && (h.disposition === 'Release' || !!h.reworkDone) }));
    }
    get hasHolds() { return this.v.holds.length > 0; }
    get alsoHeldCount() { return this.v.holds.filter((h) => !!h.stays).length; }
    get alsoHeldLine() {
        const n = this.alsoHeldCount; const all = this.v.holds.length;
        return n + ' of ' + all + ' lot' + (all === 1 ? ' is' : 's are') + ' also held by something else. Releasing ' + (n === 1 ? 'it' : 'them')
            + ' here won\'t release the lot.';
    }
    get dispLine() { return this.v.decided + ' of ' + this.v.holds.length + ' decided'; }
    async handleDisposition(event) {
        await this.call(() => setDisposition({ recordId: this.recordId, holdId: event.target.dataset.id, disposition: event.target.value }), 'Could not save that disposition.');
    }
    async handleReworkDone(event) {
        await this.call(() => markReworkDone({ recordId: this.recordId, holdId: event.target.dataset.id }), 'Could not mark the rework done.');
    }

    // ---- 4. verdict
    /**
     * What the verdict rests on, with the plain marks used on Scope: ✓ met, ! open but not blocking, ✕ open and blocking.
     * The same facts CQ.AI weighs, so its suggestion can stay a one-line bottom line.
     */
    get verdictChecks() {
        const v = this.v;
        const t = this.t;
        const out = [];
        const lvl = v.level || 'target';
        out.push(this.check('cust', 'Customers acknowledged', v.target === 0 ? 'No check needed'
            : v.total ? v.acked + ' of ' + v.total + ' · ' + lvl + (v.targetMet ? ' met' : ' needs ' + v.target + '%') : 'No customers listed yet',
            v.targetMet, v.ackRequired));
        if (!this.isNotice) {
            const inField = v.shipped - v.recovered;
            out.push(this.check('units', 'Units recovered', !v.shippedKnown ? 'Units shipped are not recorded on the Scope step'
                : inField > 0 ? inField + ' of ' + v.shipped + ' shipped still in the field' : 'All ' + v.shipped + ' shipped units accounted for',
                v.shippedKnown && inField <= 0, false));
        }
        const all = t.open + t.completed;
        if (all) {
            out.push(this.check('tasks', 'Recall tasks', t.completed + ' of ' + all + ' completed' + (t.overdue ? ' · ' + t.overdue + ' overdue' : ''),
                t.open === 0, false));
        }
        out.push(this.check('holds', 'Held stock decided', v.holds.length ? v.decided + ' of ' + v.holds.length + ' lots' : 'No stock was held',
            v.decided >= v.holds.length, true));
        return out;
    }
    /**
     * CQ.AI's suggestion under the verdict. When it suggests Effective its own line is shown; otherwise the open checks are
     * already listed above, so only the bottom line is given here (the agent still gets the full reasons).
     */
    get aiVerdictLine() {
        const v = this.v;
        if (v.aiVerdict) { return v.aiLine; }
        const chk = v.level ? v.level + ' check' : 'check';
        if (!v.checkBy) { return 'Not yet: the checks above are still open.'; }
        const due = new Date(v.checkBy + 'T00:00:00');
        const today = new Date(); today.setHours(0, 0, 0, 0);
        return due >= today ? 'Not yet: wait for the ' + chk + ' due ' + this.day(v.checkBy) + ' before deciding.'
            : 'Not yet: the ' + chk + ' was due ' + this.day(v.checkBy) + ' and the checks above are still open.';
    }
    check(key, label, detail, ok, blocks) {
        const kind = ok ? 'ok' : blocks ? 'bad' : 'warn';
        return { key, label, detail, mark: ok ? '✓' : blocks ? '✕' : '!', markCls: 'cq-mark ' + kind,
            state: ok ? 'Met' : blocks ? 'Open, needed before the verdict' : 'Open' };
    }
    /** How many customers have acknowledged, against the check level's target: shown beside the Customers and Tasks heading. */
    get progressLine() { return this.respLine + ' · ' + this.targetText; }
    get respLine() { return this.v.total ? this.v.acked + ' of ' + this.v.total + ' customers acknowledged' : 'No customers yet'; }
    get targetText() {
        if (this.v.target === 0) { return 'No check needed'; }
        return (this.v.level || 'Target') + ' target ' + this.v.target + '%' + (this.v.checkBy ? ' by ' + this.day(this.v.checkBy) : '');
    }
    get verdicts() {
        return ['Effective', 'Not Effective'].map((t) => ({ key: t, value: t, label: (t === this.v.aiVerdict ? '✦ ' : '') + t,
            pressed: this.v.verdict === t ? 'true' : 'false', cls: t === this.v.aiVerdict ? 'cq-chip ai' : 'cq-chip' }));
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
        if (this.v.verdict === 'Effective' && this.v.ackRequired && !this.v.targetMet) {
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
