import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTrail from '@salesforce/apex/CqAuditTrail.get';

// The filters across the top of the pop-up. Signatures opens its own panel; the rest filter the timeline.
const FILTERS = [
    ['all', 'All'],
    ['cq', 'CQ.AI Suggestions'],
    ['changed', 'Changed From CQ.AI'],
    ['sign', 'Signatures']
];
const RESULT_CLS = { Accepted: 'res pos', Changed: 'res warn', 'Not Answered Yet': 'res neu', Replaced: 'res neu' };

/**
 * Audit Trail: a small link for a workspace header. It opens a pop-up with the record's whole audit trail, newest first:
 * changes, CQ.AI Suggestions with the facts and records they rest on, what people decided on each, and signatures.
 * Read only. The trail is read fresh each time the pop-up opens.
 */
export default class CqAuditTrail extends NavigationMixin(LightningElement) {
    @api recordId;
    open = false;
    loading = false;
    error;
    trail;
    filter = 'all';
    expanded = {};      // suggestion ids with their facts open

    async handleOpen() {
        this.open = true; this.filter = 'all'; this.expanded = {}; this.error = undefined;
        this.loading = true;
        try { this.trail = await getTrail({ recordId: this.recordId }); }
        catch (e) { this.error = (e && e.body && e.body.message) || 'Could not read the audit trail.'; }
        this.loading = false;
        // focus the close button so the keyboard is inside the dialog
        Promise.resolve().then(() => { const x = this.template.querySelector('.cq-modal-x'); if (x) { x.focus(); } });
    }
    handleClose() { this.open = false; }
    handleKey(event) { if (event.key === 'Escape') { this.handleClose(); } }
    handleBack(event) { if (event.target === event.currentTarget) { this.handleClose(); } }

    get entries() { return (this.trail && this.trail.entries) || []; }
    get signs() { return (this.trail && this.trail.signatures) || []; }
    get subtitle() { return (this.trail ? this.trail.name + ' · ' : '') + 'Every change, signature and CQ.AI Suggestion, newest first'; }

    count(id) {
        if (id === 'all') { return this.entries.length; }
        if (id === 'cq') { return this.entries.filter((e) => e.kind === 'suggestion').length; }
        if (id === 'changed') { return this.entries.filter((e) => e.kind === 'decision' && e.changed).length; }
        return this.signs.filter((s) => !s.waiting).length;
    }
    get filters() {
        return FILTERS.map(([id, label]) => ({
            id, label: label + ' ' + this.count(id), pressed: this.filter === id ? 'true' : 'false',
            cls: 'chip' + (this.filter === id ? ' on' : '')
        }));
    }
    handleFilter(event) { this.filter = event.currentTarget.dataset.id; }
    get isSign() { return this.filter === 'sign'; }

    fmt(d) {
        if (!d) { return '—'; }
        return new Date(d).toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
    }
    get rows() {
        const list = this.entries.filter((e) =>
            this.filter === 'cq' ? e.kind === 'suggestion' : this.filter === 'changed' ? e.kind === 'decision' && e.changed : true);
        return list.map((e) => {
            const open = !!this.expanded[e.id];
            const facts = e.facts || [];
            return {
                ...e,
                when: this.fmt(e.at),
                tagCls: e.cq ? 'tag cq' : 'tag',
                isSuggestion: e.kind === 'suggestion',
                isChange: e.kind === 'decision' && e.changed,
                hasResult: !!e.result,
                resultText: e.result === 'Accepted' || e.result === 'Changed' ? e.result + (e.resultBy ? ' by ' + e.resultBy : '') : e.result,
                resultCls: RESULT_CLS[e.result] || 'res neu',
                // the first fact shows; the rest open on request
                firstFact: facts.length ? facts[0] : '',
                moreFacts: open ? facts.slice(1).map((f, i) => ({ key: e.id + 'f' + i, text: f })) : [],
                hasMore: facts.length > 1,
                moreLabel: open ? 'Hide facts' : 'Show all ' + facts.length + ' facts',
                expandedAttr: open ? 'true' : 'false',
                hasSources: (e.sources || []).length > 0,
                srcs: (e.sources || []).map((s, i) => ({ key: e.id + 's' + i, label: s.label, id: s.id, link: !!s.id })),
                linkLine: e.suggestionAt ? 'Answers the CQ.AI Suggestion of ' + this.fmt(e.suggestionAt) : ''
            };
        });
    }
    get noRows() { return !this.loading && !this.error && !this.isSign && this.rows.length === 0; }
    get emptyLine() {
        return this.filter === 'changed' ? 'No one has chosen differently from CQ.AI on this record.'
            : this.filter === 'cq' ? 'No CQ.AI Suggestions recorded yet.' : 'Nothing recorded yet.';
    }
    handleFacts(event) {
        const id = event.currentTarget.dataset.id;
        this.expanded = { ...this.expanded, [id]: !this.expanded[id] };
    }
    handleSource(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) { return; }
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, actionName: 'view' } });
    }

    get signLine() { return (this.trail && this.trail.signLine) || ''; }
    get signRows() {
        return this.signs.map((s) => ({
            ...s, when: s.waiting ? '—' : this.fmt(s.at), seatText: s.seat || '—', commentText: s.comment || '—',
            verifiedText: s.waiting ? '' : s.verified, meaningCls: s.waiting ? 'wait' : 'mean'
        }));
    }
    get noSigns() { return this.signs.length === 0; }
}
