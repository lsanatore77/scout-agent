import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getLeads from '@salesforce/apex/PhrLeadListController.getLeads';
import addLeads from '@salesforce/apex/PhrLeadListController.addLeads';

/**
 * Proof-of-concept workspace table: the relevant records already stored on the PHR, with a ✦ on each
 * row that opens Ask CQ focused on "why is this record here?", and Add to PHR switches committed by
 * one Submit (PhrLeadListController.addLeads, the same Apex the agent uses).
 */
export default class AskCqRecordsDemo extends LightningElement {
    @api recordId;
    rows = [];
    staged = new Set();
    error;
    busy = false;
    wired;

    @wire(getLeads, { phrId: '$recordId' })
    wiredLeads(result) {
        this.wired = result;
        if (result.data) {
            this.error = undefined;
            this.rows = result.data.map((r) => this.decorate(r));
        } else if (result.error) {
            this.error = (result.error.body && result.error.body.message) || 'Could not load the relevant records.';
        }
    }

    decorate(r) {
        const colour = (r.colour || 'Grey').toLowerCase();
        const on = this.staged.has(r.id);
        return {
            ...r,
            score: r.relevance == null ? '' : (r.relevance / 100).toFixed(2),
            badgeClass: 'badge ' + colour,
            rootCause: r.title,
            canToggle: !r.added,
            on,
            switchClass: 'switch' + (on ? ' on' : ''),
            why: 'Why is ' + r.recordNumber + ' ' + colour + '?'
        };
    }

    get count() { return this.rows.length; }
    get stagedCount() { return this.staged.size; }
    get submitLabel() { return this.staged.size ? 'Submit (' + this.staged.size + ')' : 'Submit'; }
    get submitDisabled() { return this.busy || this.staged.size === 0; }
    get suggestions() {
        return 'Why are these records relevant?,Which of these share the complaint lot?,What is the scrap rate?,What is left on this review?';
    }

    handleWhy(event) {
        const q = event.currentTarget.dataset.q;
        const pop = this.template.querySelector('c-ask-cq-popover');
        if (pop) { pop.ask(q); }
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
        try {
            await addLeads({ phrId: this.recordId, leadIds: [...this.staged] });
            this.staged = new Set();
            await refreshApex(this.wired);
        } catch (e) {
            this.error = (e.body && e.body.message) || 'Could not add the records.';
        } finally {
            this.busy = false;
        }
    }
}
