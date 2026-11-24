import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { sortRows, nextSort, heads } from 'c/cqSort';
import getView from '@salesforce/apex/CqFieldActionNotify.getView';
import markSent from '@salesforce/apex/CqFieldActionNotify.markSent';
import followUp from '@salesforce/apex/CqFieldActionNotify.followUp';
import submit from '@salesforce/apex/CqFieldActionNotify.submit';
import closeWithoutResponse from '@salesforce/apex/CqFieldActionNotify.closeWithoutResponse';
import reopen from '@salesforce/apex/CqFieldActionNotify.reopen';

const COLS = [
    { key: 'name', label: 'Customer' }, { key: 'kind', label: 'Type' }, { key: 'caseNumber', label: 'Case' },
    { key: 'shipped', label: 'Shipped', num: true }, { key: 'returning', label: 'Returning', num: true }, { key: 'unknown', label: 'Unknown', num: true },
    { key: 'due', label: 'Due' }, { key: 'status', label: 'Status' }, { key: 'action', label: 'Action', sortable: false }
];

/**
 * Field Action step 4, Notifications. Customer service works one Case per customer (CqFieldActionCases); this step
 * follows them: the notice, who has acknowledged, who is still open, and what each one reported on their Case, by lot.
 * The coordinator submits the acknowledged customers to Recovery in batches (the footer's Submit button); once
 * submitted they leave the list, which keeps the open ones. A customer who never answers is closed without a response.
 */
export default class CqFieldActionNotify extends LightningElement {
    @api recordId;
    v;
    error;
    saving = 0;
    footSig;
    search = '';
    sort = { key: 'due', dir: 'asc' };
    showDone = false;        // also list the customers already submitted or closed without a response
    openCust = {};           // customer rows opened (all start closed)
    closing;                 // the customer being closed without a response
    reason = '';

    async connectedCallback() {
        try { this.apply(await getView({ recordId: this.recordId })); }
        catch (e) { this.error = this.msg(e, 'Could not read notifications.'); }
    }
    msg(e, fallback) { return (e && e.body && e.body.message) || fallback; }
    apply(v) {
        this.v = JSON.parse(JSON.stringify(v));
        this.dispatchEvent(new CustomEvent('notifychange', { detail: { total: this.v.total, notified: this.v.notified, responded: this.v.acked,
            settled: this.v.submitted + this.v.noResponse } }));
    }
    async call(fn, fallback) {
        this.error = undefined;
        this.saving += 1;
        let ok = true;
        try { this.apply(await fn()); notifyRecordUpdateAvailable([{ recordId: this.recordId }]); }
        catch (e) { this.error = this.msg(e, fallback); ok = false; }
        this.saving -= 1;
        return ok;
    }
    get ready() { return !!this.v; }
    get busy() { return this.saving > 0; }
    get locked() { return !this.v.strategyConfirmed || this.v.closed; }
    get needsStrategy() { return this.ready && !this.v.strategyConfirmed; }
    get showStep() { return this.ready && this.v.strategyConfirmed; }
    day(d) { return d ? new Date(d + 'T00:00:00').toLocaleDateString() : ''; }
    num(x) { return x === undefined || x === null ? '—' : String(Number(x)); }
    plural(n, word) { return n + ' ' + word + (n === 1 ? '' : 's'); }

    /** The step's own action sits in the footer before Back and Next: Submit N Responses. */
    renderedCallback() {
        if (!this.v) { return; }
        const n = this.v.toSubmit;
        const detail = { show: this.showStep && !this.locked && n > 0, label: 'Submit ' + this.plural(n, 'Response'), disabled: this.busy, blocker: '' };
        const sig = JSON.stringify(detail);
        if (sig !== this.footSig) { this.footSig = sig; this.dispatchEvent(new CustomEvent('footchange', { detail })); }
    }
    @api confirm() { return this.call(() => submit({ recordId: this.recordId }), 'Could not submit the responses.'); }

    // ---- header
    get settled() { return this.v.submitted + this.v.noResponse; }
    get stateText() {
        if (!this.v.total) { return 'No customers'; }
        if (this.settled === this.v.total) { return 'All Submitted'; }
        return this.v.notified || this.v.acked ? 'In Progress' : 'Not Started';
    }
    get statePill() { return 'cq-pill soft ' + (this.v.total && this.settled === this.v.total ? 'pos' : this.v.notified || this.v.acked ? 'warn' : 'neu'); }

    // ---- 1. the notice
    get hasMessage() { return !!(this.v.message || '').trim(); }
    get sentLine() {
        const v = this.v;
        if (!v.total) { return 'No customers yet: they come from the lot shipments of the lots in scope.'; }
        return 'Sent to ' + v.notified + ' of ' + this.plural(v.total, 'customer') + (v.sentOn ? ' · first sent ' + this.day(v.sentOn) : '');
    }
    get dueLine() { return this.v.dueOn ? 'Responses due ' + this.day(this.v.dueOn) : ''; }
    get cantMarkSent() { return this.locked || this.busy || this.v.unsent === 0; }
    get markLabel() {
        if (this.v.total && this.v.unsent === 0) { return 'Notice Sent to All'; }
        return this.v.notified > 0 ? 'Mark Sent to the Other ' + this.v.unsent : 'Mark Notice Sent';
    }
    get cantFollowUp() { return this.locked || this.busy || this.v.pending === 0; }
    get followLabel() { return this.v.pending ? 'Log Follow-Up for ' + this.v.pending + ' Pending' : 'Log Follow-Up'; }
    handleMarkSent() { if (!this.cantMarkSent) { this.call(() => markSent({ recordId: this.recordId }), 'Could not mark the notice sent.'); } }
    handleFollowUp() { if (!this.cantFollowUp) { this.call(() => followUp({ recordId: this.recordId }), 'Could not log the follow-up.'); } }

    // ---- counts, from the Cases; View Cases opens the Field Action Cases report filtered to this field action
    get cards() {
        const v = this.v;
        const base = v.reportId ? '/lightning/r/Report/' + v.reportId + '/view?fv0=' + encodeURIComponent(v.name) : '';
        return [['all', 'Customers', v.total, ''], ['acked', 'Acknowledged', v.acked, 'Acknowledged'],
            ['pending', 'Pending Acknowledgment', v.pending, 'Pending Acknowledgment'], ['overdue', 'Overdue', v.overdue, 'Overdue']]
            .map(([key, label, n, fv]) => ({ key, label, n, href: base ? base + (fv ? '&fv1=' + encodeURIComponent(fv) : '') : '',
                linkLabel: 'View Cases: ' + label,
                numCls: 'cq-statcard-v' + (key === 'acked' && n ? ' ok' : key === 'overdue' && n ? ' bad' : '') }));
    }

    // ---- 2. the customers: open ones, and on request those already submitted or closed without a response
    isDone(c) { return c.submitted || c.noResponse; }
    get doneCount() { return this.v.customers.filter((c) => this.isDone(c)).length; }
    get hasDone() { return this.doneCount > 0; }
    get showDonePressed() { return this.showDone ? 'true' : 'false'; }
    get showDoneLabel() {
        const what = this.v.noResponse ? (this.v.submitted ? 'Submitted and Closed' : 'Closed') : 'Submitted';
        return (this.showDone ? 'Hide ' : 'Show ') + what + ' (' + this.doneCount + ')';
    }
    get tableTitle() { return this.showDone ? 'All Customers' : 'Open Customers'; }
    get tallyLine() {
        const v = this.v;
        return [(v.total - this.settled) + ' open', v.submitted + ' submitted to Recovery', v.noResponse ? v.noResponse + ' closed without a response' : '']
            .filter(Boolean).join(' · ');
    }
    get heads() { return heads(COLS, this.sort); }
    handleSort(event) { this.sort = nextSort(this.sort, event.currentTarget.dataset.key); }
    handleSearch(event) { this.search = event.target.value; }
    handleShowDone() { this.showDone = !this.showDone; }
    get rows() {
        const q = this.search.trim().toLowerCase();
        const today = new Date().toISOString().slice(0, 10);
        // pending first, then acknowledged, then closed: the order ties fall back to
        const rank = (c) => (c.acked ? 1 : c.noResponse ? 2 : 0);
        const list = this.v.customers
            .filter((c) => (this.showDone || !this.isDone(c)) && (!q || (c.name || '').toLowerCase().includes(q)))
            .sort((a, b) => rank(a) - rank(b) || (a.name || '').localeCompare(b.name || ''));
        const rows = [];
        sortRows(list, this.sort).forEach((c) => {
            const open = !!this.openCust[c.id];
            const pending = !c.acked && !c.noResponse;
            const known = (x) => x !== undefined && x !== null;
            rows.push({ key: 'c' + c.id, isCust: true, rowCls: 'cq-row-parent', id: c.id, name: c.name, kind: c.kind || '—',
                chevCls: 'cq-rchev' + (open ? ' open' : ''), expanded: open ? 'true' : 'false', toggleLabel: (open ? 'Hide lots for ' : 'Show lots for ') + c.name,
                caseNumber: c.caseNumber, caseHref: c.caseId ? '/lightning/r/Case/' + c.caseId + '/view' : '',
                shippedText: this.num(c.shipped), returningText: this.num(c.returning), unknownText: this.num(c.unknown),
                unknownCls: 'num' + (known(c.unknown) ? ' b ' + (c.unknown ? 'warnc' : 'okc') : ''),
                dueText: c.due ? this.day(c.due) : '—', dueCls: 'nw' + (c.overdue ? ' badc b' : ''),
                status: c.status, pillCls: 'cq-pill soft ' + (c.acked ? 'pos' : c.noResponse ? 'neu' : c.overdue ? 'crit' : 'warn'),
                pillTitle: c.acked ? (c.ackedBy === 'Full Return' ? 'Every unit shipped came back' : 'Responded ' + this.day(c.respondedOn))
                    : c.noResponse ? c.reason : c.overdue && c.due < today ? 'Response overdue' : '',
                canClose: pending && !this.locked, canReopen: c.noResponse && !this.locked,
                closeAria: 'Close ' + c.name + ' without a response', reopenAria: 'Reopen ' + c.name });
            if (!open) { return; }
            rows.push({ key: 'l' + c.id, isLots: true, rowCls: '', lotsLabel: 'Lots shipped to ' + c.name,
                note: c.noResponse && c.reason ? 'Closed without a response: ' + c.reason : c.ackedBy === 'Full Return' ? 'Acknowledged on the returns: every unit shipped came back.' : '',
                lines: c.lines.map((l) => ({ lot: l.lot, shipped: this.num(l.shipped), used: this.num(l.used), returning: this.num(l.returning),
                    destroyed: this.num(l.destroyed), unknown: this.num(l.unknown),
                    unknownCls: 'num' + (known(l.unknown) ? ' b ' + (l.unknown ? 'warnc' : 'okc') : '') })) });
        });
        return rows;
    }
    get hasRows() { return this.rows.length > 0; }
    get emptyLine() {
        if (this.search.trim()) { return 'No customer matches “' + this.search.trim() + '”.'; }
        if (!this.v.total) { return 'No customers yet: they come from the lot shipments of the lots in scope.'; }
        return 'No open customers: everyone has been submitted to Recovery or closed without a response.';
    }
    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.openCust = { ...this.openCust, [id]: !this.openCust[id] };
    }

    // ---- close without a response (a reason is required), and reopen
    handleOpenClose(event) {
        const c = this.v.customers.find((x) => x.id === event.currentTarget.dataset.id);
        if (c) { this.closing = { id: c.id, name: c.name }; this.reason = ''; this.error = undefined; }
    }
    handleCancelClose() { this.closing = undefined; this.reason = ''; this.error = undefined; }
    handleCloseKey(event) { if (event.key === 'Escape') { this.handleCancelClose(); } }
    handleReason(event) { this.reason = event.target.value; }
    get cantConfirmClose() { return this.busy || !this.reason.trim(); }
    async handleConfirmClose() {
        if (this.cantConfirmClose) { return; }
        const id = this.closing.id;
        const ok = await this.call(() => closeWithoutResponse({ recordId: this.recordId, customerId: id, reason: this.reason }), 'Could not close that customer.');
        if (ok) { this.closing = undefined; this.reason = ''; }
    }
    handleReopen(event) {
        const id = event.currentTarget.dataset.id;
        this.call(() => reopen({ recordId: this.recordId, customerId: id }), 'Could not reopen that customer.');
    }
}
