import { LightningElement, api } from 'lwc';
import getPackage from '@salesforce/apex/AskCqWorkspaceController.getPackage';
import addSelected from '@salesforce/apex/AskCqWorkspaceController.addSelected';

const PAGE_SIZE = 5;
const TYPE_ORDER = ['Nonconformance', 'CAPA', 'Change Order', 'Inspection', 'Investigation'];
const TYPE_LABEL = { 'Nonconformance': 'NC', 'CAPA': 'CAPA', 'Change Order': 'Change', 'Inspection': 'Inspection', 'Investigation': 'Investigation' };

/**
 * Workspace table: the live relevance package for the complaint of the PHR on screen, one tab per
 * record type, five rows a page. "✦ Suggested" rows start switched on; a ✦ on each row asks Ask CQ
 * why the record is there; one Submit adds every switched-on record (across all tabs) to the PHR.
 */
export default class AskCqRecordsDemo extends LightningElement {
    @api recordId;
    all = [];
    staged = new Set();
    error;
    notice;
    busy = false;
    loading = true;
    header;
    tab;
    pages = {};   // tab -> current page (1-based)
    includeBom = true;   // off = only the complaint's own part and lot; on = also records linked through the assembly (BOM)

    connectedCallback() { this.load(); }

    async load() {
        this.loading = true;
        this.error = undefined;
        try {
            const p = await getPackage({ recordId: this.recordId });
            if (!p.success) {
                this.error = p.errorMessage || 'Could not read the relevant records.';
                this.all = [];
            } else {
                this.header = p;
                this.staged = new Set(p.rows.filter((r) => r.suggested && !r.added).map((r) => r.id));
                this.all = p.rows.map((r) => this.decorate(r));
                if (!this.tab || !this.all.some((r) => r.recordType === this.tab)) {
                    const first = TYPE_ORDER.find((t) => this.all.some((r) => r.recordType === t));
                    this.tab = first || (this.all[0] && this.all[0].recordType);
                }
            }
        } catch (e) {
            this.error = (e.body && e.body.message) || 'Could not read the relevant records.';
        } finally {
            this.loading = false;
        }
    }

    decorate(r) {
        const colour = (r.colour || 'Grey').toLowerCase();
        const on = this.staged.has(r.id);
        const recordType = r.recordType || (String(r.id || '').startsWith('a2N') ? 'Investigation' : 'Other');   // investigations come untyped from the engine
        return {
            ...r,
            recordType,
            score: r.relevance == null ? '\u2014' : (r.relevance / 100).toFixed(2),
            badgeClass: 'badge ' + colour,
            match: r.relatedBy || r.matchedBy,
            viaBom: r.relatedBy === 'Component of the part' || r.relatedBy === 'Product sharing a component',
            canToggle: !r.added,
            on,
            switchClass: 'switch' + (on ? ' on' : ''),
            partText: r.partName || '\u2014',
            lotText: r.lotNumber || '\u2014',
            titleText: r.title || '\u2014',
            rootCauseText: r.rootCause || '\u2014',
            why: r.suggested ? 'Why is ' + r.recordNumber + ' suggested for this review?' : 'Why is ' + r.recordNumber + ' ' + colour + '?'
        };
    }

    // ----- tabs and pages -----

    /** Rows after the Include BOM switch. */
    get shown() {
        return this.includeBom ? this.all : this.all.filter((r) => !r.viaBom);
    }
    get tabs() {
        const types = TYPE_ORDER.filter((t) => this.shown.some((r) => r.recordType === t));
        this.shown.forEach((r) => { if (!types.includes(r.recordType)) { types.push(r.recordType); } });
        return types.map((t) => {
            const rows = this.shown.filter((r) => r.recordType === t);
            const stagedHere = rows.filter((r) => this.staged.has(r.id)).length;
            return {
                key: t,
                label: (TYPE_LABEL[t] || t) + ' (' + rows.length + ')',
                badge: stagedHere ? String(stagedHere) : '',
                cls: 'tab' + (t === this.tab ? ' active' : '')
            };
        });
    }
    get tabRows() { return this.shown.filter((r) => r.recordType === this.tab); }
    get page() { return this.pages[this.tab] || 1; }
    get pageCount() { return Math.max(1, Math.ceil(this.tabRows.length / PAGE_SIZE)); }
    get rows() {
        const start = (this.page - 1) * PAGE_SIZE;
        return this.tabRows.slice(start, start + PAGE_SIZE);
    }
    get pageLabel() {
        const n = this.tabRows.length;
        if (!n) { return ''; }
        const start = (this.page - 1) * PAGE_SIZE + 1;
        const end = Math.min(n, this.page * PAGE_SIZE);
        return start + '–' + end + ' of ' + n;
    }
    get prevDisabled() { return this.page <= 1; }
    get nextDisabled() { return this.page >= this.pageCount; }
    get hasPages() { return this.pageCount > 1; }

    handleTab(event) { this.tab = event.currentTarget.dataset.key; }
    handleBom(event) {
        this.includeBom = event.target.checked;
        this.pages = {};
        if (!this.shown.some((r) => r.recordType === this.tab)) {
            const first = TYPE_ORDER.find((t) => this.shown.some((r) => r.recordType === t));
            this.tab = first || (this.shown[0] && this.shown[0].recordType);
        }
    }
    handlePrev() { if (this.page > 1) { this.pages = { ...this.pages, [this.tab]: this.page - 1 }; } }
    handleNext() { if (this.page < this.pageCount) { this.pages = { ...this.pages, [this.tab]: this.page + 1 }; } }

    // ----- header -----

    get count() { return this.shown.length; }
    get suggestedCount() { return this.shown.filter((r) => r.suggested && !r.added).length; }
    get subtitle() {
        if (!this.header) { return ''; }
        const bits = [];
        if (this.header.complaintName) { bits.push(this.header.complaintName); }
        if (this.header.partName) { bits.push(this.header.partName); }
        if (this.header.lotNumber) { bits.push('lot ' + this.header.lotNumber); }
        return bits.join(' · ');
    }
    get hasSuggested() { return this.suggestedCount > 0; }
    /** "✦ CQ.AI Suggested – 1 Recommendation" above the table; nothing when CQ.AI suggests nothing. */
    get summaryLabel() {
        const n = this.suggestedCount;
        return 'CQ.AI Suggested \u2013 ' + n + (n === 1 ? ' Recommendation' : ' Recommendations');
    }
    get submitLabel() { return this.staged.size ? 'Submit (' + this.staged.size + ')' : 'Submit'; }
    get submitDisabled() { return this.busy || this.loading || this.staged.size === 0; }

    // ----- actions -----

    /** ✦ on a row: the workspace owns the Ask CQ popover, so hand it the question. */
    handleWhy(event) {
        const question = event.currentTarget.dataset.q;
        this.dispatchEvent(new CustomEvent('ask', { detail: { question }, bubbles: true, composed: true }));
    }

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        if (this.staged.has(id)) { this.staged.delete(id); } else { this.staged.add(id); }
        this.staged = new Set(this.staged);
        this.all = this.all.map((r) => this.decorate(r));
    }

    async handleSubmit() {
        if (!this.staged.size) { return; }
        this.busy = true;
        this.error = undefined;
        this.notice = undefined;
        try {
            const res = await addSelected({ recordId: this.recordId, selectedIds: [...this.staged] });
            this.notice = res.message;
            this.staged = new Set();
            await this.load();
            this.dispatchEvent(new CustomEvent('changed', { bubbles: true, composed: true }));
        } catch (e) {
            this.error = (e.body && e.body.message) || 'Could not add the records.';
        } finally {
            this.busy = false;
        }
    }
}
