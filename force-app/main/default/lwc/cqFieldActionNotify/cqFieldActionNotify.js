import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqFieldActionNotify.getView';
import markSent from '@salesforce/apex/CqFieldActionNotify.markSent';
import saveLine from '@salesforce/apex/CqFieldActionNotify.saveLine';
import setResponded from '@salesforce/apex/CqFieldActionNotify.setResponded';
import setTask from '@salesforce/apex/CqFieldActionNotify.setTask';
import createTasks from '@salesforce/apex/CqFieldActionNotify.createTasks';

const FIGURES = ['used', 'returning', 'destroyed'];

/**
 * Field Action step 4, Notifications: the notice that goes to every customer (the key message from Strategy, and when
 * it was sent), and what each customer reported back on its response form, per lot (CqFieldActionNotify). Recovery
 * expects back the units a customer says it is returning.
 */
export default class CqFieldActionNotify extends LightningElement {
    @api recordId;
    v;
    error;
    saving = 0;
    footSig;
    filter = 'all';          // all | notified | responded | waiting | overdue
    openCust = {};           // customer rows opened (all start closed)
    reviewing = false;       // CQ.AI's suggested notice and response tasks open for review
    kept = {};               // suggestion key -> false when unticked

    async connectedCallback() {
        try { this.apply(await getView({ recordId: this.recordId })); }
        catch (e) { this.error = this.msg(e, 'Could not read notifications.'); }
    }
    msg(e, fallback) { return (e && e.body && e.body.message) || fallback; }
    apply(v) {
        this.v = JSON.parse(JSON.stringify(v));
        this.dispatchEvent(new CustomEvent('notifychange', { detail: { total: this.v.total, notified: this.v.notified, responded: this.v.responded } }));
    }
    async call(fn, fallback) {
        this.error = undefined;
        this.saving += 1;
        try { this.apply(await fn()); notifyRecordUpdateAvailable([{ recordId: this.recordId }]); }
        catch (e) { this.error = this.msg(e, fallback); }
        this.saving -= 1;
    }
    get ready() { return !!this.v; }
    get busy() { return this.saving > 0; }
    get locked() { return !this.v.strategyConfirmed || this.v.closed; }
    get needsStrategy() { return this.ready && !this.v.strategyConfirmed; }
    get showStep() { return this.ready && this.v.strategyConfirmed; }
    day(d) { return d ? new Date(d + 'T00:00:00').toLocaleDateString() : ''; }
    num(x) { return x === undefined || x === null ? '—' : String(Number(x)); }

    /** This step has no confirm of its own: the footer keeps only Back and Next. */
    renderedCallback() {
        if (!this.v) { return; }
        const detail = { show: false, label: '', disabled: true, blocker: '' };
        const sig = JSON.stringify(detail);
        if (sig !== this.footSig) { this.footSig = sig; this.dispatchEvent(new CustomEvent('footchange', { detail })); }
    }

    // ---- header
    get stateText() {
        if (!this.v.total) { return 'No customers'; }
        if (this.v.responded === this.v.total) { return 'All responded'; }
        return this.v.notified ? 'In Progress' : 'Not started';
    }
    get statePill() { return 'cq-pill soft ' + (this.v.total && this.v.responded === this.v.total ? 'pos' : this.v.notified ? 'warn' : 'neu'); }
    get isWithdrawal() { return this.v.action === 'Withdrawal'; }
    get noticeWord() { return this.isWithdrawal ? 'withdrawal notice' : 'recall notice'; }

    // ---- 1. the notice
    get hasMessage() { return !!(this.v.message || '').trim(); }
    get sentLine() {
        const v = this.v;
        if (!v.total) { return 'No customers yet: they come from the lot shipments of the lots in scope.'; }
        return 'Sent to ' + v.notified + ' of ' + v.total + ' customer' + (v.total === 1 ? '' : 's') + (v.sentOn ? ' · first sent ' + this.day(v.sentOn) : '');
    }
    get dueLine() { return this.v.dueOn ? 'Responses due ' + this.day(this.v.dueOn) : ''; }
    get unsent() { return this.v.total - this.v.notified; }
    get canMarkSent() { return !this.locked && !this.busy && this.unsent > 0; }
    get cantMarkSent() { return !this.canMarkSent; }
    get markLabel() { return this.unsent > 0 && this.unsent < this.v.total ? 'Mark Sent to the Other ' + this.unsent : 'Mark Notice Sent'; }
    async handleMarkSent() {
        if (!this.canMarkSent) { return; }
        await this.call(() => markSent({ recordId: this.recordId, customerIds: null }), 'Could not mark the notice sent.');
    }

    // ---- counts: click one to filter the table, click it again to show everyone
    get cards() {
        const v = this.v;
        return [['notified', 'Notified', v.notified], ['responded', 'Responded', v.responded], ['waiting', 'No Reply Yet', v.waiting], ['overdue', 'Overdue', v.overdue]]
            .map(([key, label, n]) => ({ key, label, n, pressed: this.filter === key ? 'true' : 'false',
                cls: 'cq-statcard' + (this.filter === key ? ' on' : ''),
                numCls: 'cq-statcard-v' + (key === 'responded' && n ? ' ok' : key === 'overdue' && n ? ' bad' : '') }));
    }
    handleCard(event) { const k = event.currentTarget.dataset.key; this.filter = this.filter === k ? 'all' : k; }
    keep(c) {
        const acked = c.status === 'Acknowledged';
        switch (this.filter) {
            case 'notified': return !!c.sentOn || acked;
            case 'responded': return acked;
            case 'waiting': return !acked && !!c.sentOn;
            case 'overdue': return !acked && !!c.sentOn && (c.overdue || c.status === 'No reply');
            default: return true;
        }
    }
    get filterLine() {
        if (this.filter === 'all') { return ''; }
        return 'Showing ' + this.cards.find((x) => x.key === this.filter).label.toLowerCase();
    }

    // ---- 2. responses: a customer, then its notice and response tasks and the lots it received, with the figures it reported
    get rows() {
        const rows = [];
        this.v.customers.filter((c) => this.keep(c)).forEach((c) => {
            const open = !!this.openCust[c.id];
            const sum = (k) => c.lines.reduce((s, l) => s + (l[k] === undefined || l[k] === null ? 0 : Number(l[k])), 0);
            const has = (k) => c.lines.some((l) => l[k] !== undefined && l[k] !== null);
            const shippedKnown = c.lines.some((l) => l.shipped !== undefined && l.shipped !== null);
            const anySaid = FIGURES.some((k) => has(k));
            const acked = c.status === 'Acknowledged';
            const unknown = c.lines.reduce((s, l) => s + (l.unknown === undefined || l.unknown === null ? 0 : Number(l.unknown)), 0);
            rows.push({ key: 'c' + c.id, isCust: true, rowCls: 'cq-row-parent', id: c.id, title: c.name,
                chevCls: 'cq-rchev' + (open ? ' open' : ''), expanded: open ? 'true' : 'false', toggleLabel: (open ? 'Fold ' : 'Show ') + c.name,
                sub: [c.type || '', acked && c.respondedOn ? 'Responded ' + this.day(c.respondedOn) : '', c.sentOn ? 'Notice sent ' + this.day(c.sentOn) : 'Notice not sent',
                    c.lines.length + ' lot' + (c.lines.length === 1 ? '' : 's')].filter(Boolean).join(' · '),
                shipped: shippedKnown ? String(sum('shipped')) : '—',
                used: has('used') ? String(sum('used')) : '—', returning: has('returning') ? String(sum('returning')) : '—',
                destroyed: has('destroyed') ? String(sum('destroyed')) : '—',
                unknown: anySaid && shippedKnown ? String(unknown) : '—', unknownCls: 'num b ' + (anySaid && shippedKnown ? (unknown ? 'warnc' : 'okc') : ''),
                pill: acked ? 'Acknowledged' : !c.sentOn ? 'Not sent' : c.status === 'No reply' || c.overdue ? 'No reply' : 'Waiting',
                pillCls: 'cq-pill soft ' + (acked ? 'pos' : c.status === 'No reply' || c.overdue ? 'crit' : 'neu'),
                actLabel: acked ? 'Undo' : 'Record Response', acked: acked ? 'true' : 'false',
                actAria: (acked ? 'Take back the response from ' : 'Record the response from ') + c.name });
            if (!open) { return; }
            c.tasks.forEach((t) => rows.push({ key: 't' + t.id, isTask: true, rowCls: '', id: t.id, title: t.subject, done: t.done,
                href: '/lightning/r/Task/' + t.id + '/view', checkLabel: (t.done ? 'Reopen ' : 'Complete ') + t.subject,
                owner: t.owner, due: this.day(t.due), dueCls: 'nw' + (t.overdue ? ' badc b' : ''),
                pill: t.done ? 'Done' : t.overdue ? 'Overdue' : 'Open', pillCls: 'cq-pill soft ' + (t.done ? 'pos' : t.overdue ? 'crit' : 'neu') }));
            c.lines.forEach((l) => {
                const val = (k) => (l[k] === undefined || l[k] === null ? '' : l[k]);
                rows.push({ key: 'l' + c.id + l.lot, isLot: true, rowCls: '', cust: c.id, lot: l.lot, inRecall: true,
                    shipped: this.num(l.shipped), used: val('used'), returning: val('returning'), destroyed: val('destroyed'),
                    unknown: l.unknown === undefined || l.unknown === null ? '—' : String(l.unknown),
                    unknownCls: 'num ' + (l.unknown ? 'warnc b' : l.unknown === 0 ? 'okc b' : ''),
                    usedLabel: 'Units used, lot ' + l.lot + ', ' + c.name, retLabel: 'Units returning, lot ' + l.lot + ', ' + c.name,
                    desLabel: 'Units destroyed, lot ' + l.lot + ', ' + c.name });
            });
        });
        return rows;
    }
    get hasRows() { return this.rows.length > 0; }
    get emptyLine() { return this.filter !== 'all' ? 'No customers match.' : 'No customers yet: they come from the lot shipments of the lots in scope.'; }
    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.openCust = { ...this.openCust, [id]: !this.openCust[id] };
    }
    /** A figure on a lot: saved when the box is left (or Enter is pressed). */
    async handleFigure(event) {
        const d = event.target.dataset;
        const raw = event.target.value;
        const now = raw === '' ? null : Number(raw);
        if (now !== null && (isNaN(now) || now < 0)) { this.error = 'Units cannot be negative.'; return; }
        await this.call(() => saveLine({ recordId: this.recordId, customerId: d.cust, lot: d.lot, field: d.f, value: now }), 'Could not save that figure.');
    }
    handleFigureKey(event) { if (event.key === 'Enter') { event.target.blur(); } }
    async handleRespond(event) {
        const d = event.currentTarget.dataset;
        await this.call(() => setResponded({ recordId: this.recordId, customerId: d.id, responded: d.acked !== 'true' }), 'Could not record the response.');
    }
    async handleCheck(event) {
        const id = event.target.dataset.id;
        await this.call(() => setTask({ recordId: this.recordId, taskId: id, done: event.target.checked }), 'Could not change that task.');
    }

    // ---- CQ.AI's suggested notice and response tasks
    get suggestions() { return this.v.suggestions || []; }
    get hasSuggestions() { return !this.locked && this.suggestions.length > 0; }
    get suggestRows() {
        return this.suggestions.map((s) => ({ ...s, checked: this.kept[s.key] !== false, due: this.day(s.due), label: 'Create: ' + s.subject }));
    }
    get keptCount() { return this.suggestions.filter((s) => this.kept[s.key] !== false).length; }
    get createLabel() { return 'Create ' + this.keptCount + ' Task' + (this.keptCount === 1 ? '' : 's'); }
    get cantCreate() { return this.busy || this.keptCount === 0; }
    handleReview() { this.reviewing = !this.reviewing; this.kept = {}; }
    handleKeep(event) { this.kept = { ...this.kept, [event.target.dataset.key]: event.target.checked }; }
    async handleCreate() {
        const keys = this.suggestions.filter((s) => this.kept[s.key] !== false).map((s) => s.key);
        await this.call(() => createTasks({ recordId: this.recordId, keys }), 'Could not create those tasks.');
        if (!this.error) { this.reviewing = false; this.kept = {}; }
    }
}
