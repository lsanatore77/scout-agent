import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSetup from '@salesforce/apex/CqEventIntake.getSetup';
import submitReport from '@salesforce/apex/CqEventIntake.submitReport';
import getTrend from '@salesforce/apex/CqEventIntake.getTrend';
import quickLog from '@salesforce/apex/CqEventIntake.quickLog';
import getLots from '@salesforce/apex/CqEventLots.getLots';

const NOT_KNOWN = 'NOT_KNOWN';

const PART_DISPLAY = { primaryField: 'compliancequest__Part_Number__c', additionalFields: ['Name'] };
const PART_MATCH = { primaryField: { fieldPath: 'compliancequest__Part_Number__c' }, additionalFields: [{ fieldPath: 'Name' }] };

/**
 * Report a Problem (a CQ.AI tab): Full Report sends a Quality Event for review with the answers to the company's
 * Event Questions; Quick Log logs a trend-only NC for an approved Quick Log Category and closes it, and CQ.AI opens a
 * Trend event when the category reaches its limit.
 */
export default class CqEventIntake extends NavigationMixin(LightningElement) {
    setup;
    loadError;
    tab = 'report';
    error;
    busy = false;

    // Full Report
    problem = '';
    title = '';
    partId;
    lot = '';
    units = '';
    lots = [];             // lot numbers CQ has for the chosen part
    answers = {};          // questionId -> answer
    sent;                  // { id, name, urgent }

    // Quick Log
    catId;
    qPartId;
    qLot = '';
    qLots = [];
    qty = 1;
    note = '';
    trend;                 // CqEventIntake.Trend for the chosen category and part
    logged;                // CqEventIntake.Logged

    partDisplay = PART_DISPLAY;
    partMatch = PART_MATCH;

    connectedCallback() { this.load(); }
    async load() {
        try {
            this.setup = await getSetup();
        } catch (e) {
            this.loadError = this.msg(e, 'Could not read the questions.');
        }
    }
    msg(e, fallback) { return (e && e.body && e.body.message) || (e && e.message) || fallback; }
    get ready() { return !!this.setup; }

    // ---- tabs
    get isReport() { return this.tab === 'report'; }
    get isQuick() { return this.tab === 'quick'; }
    get reportTabCls() { return 'tab' + (this.isReport ? ' on' : ''); }
    get quickTabCls() { return 'tab' + (this.isQuick ? ' on' : ''); }
    handleTab(event) { this.tab = event.currentTarget.dataset.t; this.error = undefined; }

    // ---- Full Report
    get showForm() { return this.isReport && !this.sent; }
    get showSent() { return this.isReport && !!this.sent; }
    handleField(event) { this[event.currentTarget.dataset.f] = event.target.value; this.error = undefined; }
    handlePart(event) {
        this.partId = event.detail ? event.detail.recordId : null;
        this.lot = '';
        this.loadLots(this.partId).then((l) => { this.lots = l; });
    }
    handleLot(event) { this.lot = event.detail.value; }
    async loadLots(partId) {
        if (!partId) { return []; }
        try { return await getLots({ partId }); } catch (e) { this.error = this.msg(e, 'Could not read the lots.'); return []; }
    }
    options(list) { return [...list.map((l) => ({ label: l, value: l })), { label: 'Not Known', value: NOT_KNOWN }]; }
    lotValue(v) { return v && v !== NOT_KNOWN ? v : ''; }
    get lotOptions() { return this.options(this.lots); }
    get noLots() { return !this.partId; }
    get lotPlaceholder() { return this.partId ? 'Choose a lot' : 'Lot (choose the part first)'; }
    get questions() {
        return (this.setup.questions || []).map((q, i) => {
            const a = this.answers[q.id];
            const isChoice = q.answerType === 'Choice' || q.answerType === 'Yes or No';
            return {
                id: q.id, label: (i + 1) + '. ' + q.question, required: !!q.required, help: q.help,
                cls: 'cq-field' + (q.answerType === 'Number' ? ' w-num' : q.answerType === 'Date' ? ' w-date' : ''),
                isChoice, isText: q.answerType === 'Text', isNumber: q.answerType === 'Number', isDate: q.answerType === 'Date',
                value: a || '',
                opts: isChoice ? q.choices.map((c) => ({ key: q.id + c, label: c, qid: q.id, pressed: String(a === c), cls: 'cq-chip' })) : []
            };
        });
    }
    handleAnswer(event) {
        const d = event.currentTarget.dataset;
        this.answers = { ...this.answers, [d.q]: d.v !== undefined ? d.v : event.target.value };
        this.error = undefined;
    }
    get urgent() {
        return (this.setup.questions || []).some((q) => {
            const a = (this.answers[q.id] || '').toLowerCase();
            return a && (q.urgentWhen || []).some((u) => u.toLowerCase() === a);
        });
    }
    get injured() {
        const q = (this.setup.questions || []).find((x) => x.role === 'Injury');
        return !!q && (this.answers[q.id] || '').toLowerCase() === 'yes';
    }
    get urgentText() {
        return this.injured ? 'Get help first and follow your site’s injury procedure. This goes for review as urgent.'
            : 'This goes for review as urgent. It goes to the top of the event review queue.';
    }
    get reportBlocker() {
        if (!(this.problem || '').trim()) { return 'Describe the problem'; }
        if (!(this.title || '').trim()) { return 'Give it a title'; }
        const missing = (this.setup.questions || []).find((q) => q.required && !(this.answers[q.id] || '').trim());
        if (missing) { return 'Answer: ' + missing.question; }
        return '';
    }
    get cantSend() { return this.busy || !!this.reportBlocker; }
    get sendLabel() { return this.busy ? 'Sending…' : 'Send for Review'; }
    get capturedText() { return 'Captured for you: ' + this.setup.reporter + ' · aware date ' + new Date().toLocaleString([], { dateStyle: 'short', timeStyle: 'short' }) + '.'; }
    async handleSend() {
        if (this.cantSend) { return; }
        this.busy = true;
        this.error = undefined;
        try {
            const payload = {
                title: this.title.trim(), problem: this.problem.trim(), partId: this.partId, lot: this.lotValue(this.lot), units: this.units,
                answers: Object.keys(this.answers).map((k) => ({ questionId: k, answer: this.answers[k] }))
            };
            this.sent = await submitReport({ payload: JSON.stringify(payload) });
        } catch (e) {
            this.error = this.msg(e, 'The report was not sent.');
        } finally {
            this.busy = false;
        }
    }
    get sentTitle() { return this.sent ? this.sent.name + ' Sent for Review' + (this.sent.urgent ? ' as Urgent' : '') : ''; }
    handleAnother() {
        this.sent = undefined;
        this.problem = ''; this.title = ''; this.partId = null; this.lot = ''; this.lots = []; this.units = ''; this.answers = {};
        const pk = this.template.querySelector('c-cq-part-picker.rpart'); if (pk) { pk.clear(); }
    }
    handleOpenEvent(event) {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: event.currentTarget.dataset.id, objectApiName: 'Quality_Event__c', actionName: 'view' } });
    }

    // ---- Quick Log
    get cats() {
        return (this.setup.categories || []).map((c) => ({ ...c, pressed: String(c.id === this.catId), cls: 'card' + (c.id === this.catId ? ' on' : '') }));
    }
    get hasCats() { return (this.setup.categories || []).length > 0; }
    get cat() { return (this.setup.categories || []).find((c) => c.id === this.catId); }
    handleCat(event) { this.catId = event.currentTarget.dataset.id; this.logged = undefined; this.refreshTrend(); }
    handleQPart(event) {
        this.qPartId = event.detail ? event.detail.recordId : null;
        this.logged = undefined;
        this.qLot = '';
        this.loadLots(this.qPartId).then((l) => { this.qLots = l; });
        this.refreshTrend();
    }
    handleQLot(event) { this.qLot = event.detail.value; }
    get qLotOptions() { return this.options(this.qLots); }
    get noQLots() { return !this.qPartId; }
    get qLotPlaceholder() { return this.qPartId ? 'Lot (optional)' : 'Lot (choose the part first)'; }
    handleQField(event) { this[event.currentTarget.dataset.f] = event.target.value; }
    handleDec() { if (this.qty > 1) { this.qty = Number(this.qty) - 1; } }
    handleInc() { this.qty = Number(this.qty) + 1; }
    get cantDec() { return this.qty <= 1; }
    async refreshTrend() {
        this.trend = undefined;
        if (!this.catId) { return; }
        try {
            this.trend = await getTrend({ categoryId: this.catId, partId: this.qPartId });
        } catch (e) {
            this.error = this.msg(e, 'Could not read the count.');
        }
    }
    get trendHead() { return 'Trend · ' + (this.cat ? this.cat.name : 'Pick a category'); }
    get needsPart() { return this.cat && this.cat.scope !== 'All Parts' && !this.qPartId; }
    get showCount() { return !!this.trend && !this.needsPart; }
    get totalText() { return this.trend ? String(Number(this.trend.total)) : ''; }
    get ofText() {
        const c = this.cat;
        if (!c) { return ''; }
        return 'of ' + c.limitCount + ' in the last ' + c.days + ' days, ' + (c.scope === 'All Parts' ? 'all parts' : 'same part' + (this.trend && this.trend.partNumber ? ' (' + this.trend.partNumber + ')' : ''));
    }
    get pct() { return this.trend && this.cat && this.cat.limitCount ? Math.min(100, Math.round((Number(this.trend.total) / this.cat.limitCount) * 100)) : 0; }
    get barStyle() {
        const p = this.pct;
        return 'width: ' + p + '%; background: ' + (p >= 100 ? '#b42318' : p >= 70 ? '#c77700' : '#1d5fd1') + ';';
    }
    get trendNote() {
        const c = this.cat;
        if (!c) { return 'Pick a category to see its count.'; }
        if (this.needsPart) { return 'Choose the part to see its count.'; }
        if (!this.trend) { return ''; }
        const left = c.limitCount - Number(this.trend.total);
        return left > 0 ? left + ' more and CQ.AI opens an event for review with all these quick logs linked.' : 'At the limit: the next quick log opens an event for review.';
    }
    get ruleDisposition() { return this.cat ? this.cat.disposition || '—' : '—'; }
    get ruleOpens() { return this.cat ? this.cat.limitCount + ' in ' + this.cat.days + ' days, ' + (this.cat.scope === 'All Parts' ? 'all parts' : 'same part') : '—'; }
    get ruleApproved() {
        const c = this.cat;
        if (!c || !c.approvedBy) { return '—'; }
        return c.approvedBy + (c.approvedOn ? ', ' + new Date(c.approvedOn + 'T00:00:00').toLocaleDateString() : '');
    }
    get quickBlocker() {
        if (!this.catId) { return 'Pick what it was'; }
        if (!this.qPartId) { return 'Choose the part'; }
        if (!(Number(this.qty) >= 1)) { return 'Enter how many'; }
        return '';
    }
    get cantLog() { return this.busy || !!this.quickBlocker; }
    get logLabel() { return this.busy ? 'Logging…' : 'Log It'; }
    async handleLog() {
        if (this.cantLog) { return; }
        this.busy = true;
        this.error = undefined;
        try {
            this.logged = await quickLog({ categoryId: this.catId, partId: this.qPartId, lot: this.lotValue(this.qLot), quantity: Number(this.qty), note: this.note });
            this.trend = this.logged.trend;
            if (this.logged.triggered) { this.trend = await getTrend({ categoryId: this.catId, partId: this.qPartId }); }
            this.qty = 1;
            this.note = '';
        } catch (e) {
            this.error = this.msg(e, 'The quick log was not saved.');
        } finally {
            this.busy = false;
        }
    }
    get loggedText() {
        const l = this.logged;
        if (!l) { return ''; }
        const t = l.triggered ? '' : ' ' + Number(l.trend.total) + ' of ' + l.trend.limitCount + ' in ' + l.trend.days + ' days.';
        return l.ncName + ' logged and closed: ' + (this.cat ? this.cat.name : 'quick log') + '.' + t;
    }
    get triggeredText() {
        const l = this.logged;
        return l && l.triggered ? ' CQ.AI opened ' + l.eventName + ' for review. All ' + l.linked + ' quick logs behind the count are linked to it, so the reviewer sees the whole trend.' : '';
    }
    get showTriggered() { return !!this.logged && this.logged.triggered; }
}
