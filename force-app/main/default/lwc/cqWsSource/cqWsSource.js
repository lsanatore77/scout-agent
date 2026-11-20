import { LightningElement, api } from 'lwc';

/** cqWsSource: one quiet row naming the source record (link, then grey lines) with a quote beside it. Fires open (detail: record id). */
export default class CqWsSource extends LightningElement {
    @api recordId;
    @api name;
    /** grey lines under the name, e.g. the title and the root cause */
    @api lines = [];
    @api quote;
    /** shown under the quote with the date, e.g. "Sent for review by Lou Admin" */
    @api quoteBy;
    @api quoteOn;

    get lineRows() { return (this.lines || []).filter(Boolean).map((text, i) => ({ key: 'l' + i, text })); }
    handleOpen() { this.dispatchEvent(new CustomEvent('open', { detail: this.recordId })); }
}
