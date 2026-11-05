import { LightningElement, api } from 'lwc';
import getPackage from '@salesforce/apex/AskCqWorkspaceController.getPackage';
import addSelected from '@salesforce/apex/AskCqWorkspaceController.addSelected';

/**
 * Proof-of-concept workspace table: the live relevance package for the complaint of the PHR on screen,
 * "✦ Suggested" (red) rows switched on already, a ✦ on each row that opens Ask CQ focused on
 * "why is this record here?", and one Submit that adds the switched-on records to the PHR.
 */
export default class AskCqRecordsDemo extends LightningElement {
    @api recordId;
    rows = [];
    staged = new Set();
    error;
    notice;
    busy = false;
    loading = true;
    header;

    connectedCallback() { this.load(); }

    async load() {
        this.loading = true;
        this.error = undefined;
        try {
            const p = await getPackage({ recordId: this.recordId });
            if (!p.success) {
                this.error = p.errorMessage || 'Could not read the relevant records.';
                this.rows = [];
            } else {
                this.header = p;
                // CQ Suggested rows (red) start switched on, unless already on the review.
                this.staged = new Set(p.rows.filter((r) => r.suggested && !r.added).map((r) => r.id));
                this.rows = p.rows.map((r) => this.decorate(r));
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
        return {
            ...r,
            score: r.relevance == null ? '' : (r.relevance / 100).toFixed(2),
            badgeClass: 'badge ' + colour,
            match: r.relatedBy || r.matchedBy,
            canToggle: !r.added,
            on,
            switchClass: 'switch' + (on ? ' on' : ''),
            why: 'Why is ' + r.recordNumber + ' ' + colour + '?'
        };
    }

    get count() { return this.rows.length; }
    get suggestedCount() { return this.rows.filter((r) => r.suggested && !r.added).length; }
    get subtitle() {
        if (!this.header) { return ''; }
        const bits = [];
        if (this.header.complaintName) { bits.push(this.header.complaintName); }
        if (this.header.partName) { bits.push(this.header.partName); }
        if (this.header.lotNumber) { bits.push('lot ' + this.header.lotNumber); }
        return bits.join(' · ');
    }
    get summaryLine() {
        return this.count + ' relevant records · ' + this.suggestedCount + ' suggested · switch on the ones that belong on this review, then Submit';
    }
    get submitLabel() { return this.staged.size ? 'Submit (' + this.staged.size + ')' : 'Submit'; }
    get submitDisabled() { return this.busy || this.loading || this.staged.size === 0; }

    /** ✦ on a row: the workspace owns the Ask CQ popover, so hand it the question. */
    handleWhy(event) {
        const question = event.currentTarget.dataset.q;
        this.dispatchEvent(new CustomEvent('ask', { detail: { question }, bubbles: true, composed: true }));
    }

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        if (this.staged.has(id)) { this.staged.delete(id); } else { this.staged.add(id); }
        this.staged = new Set(this.staged);
        this.rows = this.rows.map((r) => this.decorate(r));
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
