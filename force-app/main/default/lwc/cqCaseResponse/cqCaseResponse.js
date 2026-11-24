import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import caseView from '@salesforce/apex/CqFieldActionCases.caseView';
import saveCaseLine from '@salesforce/apex/CqFieldActionCases.saveCaseLine';

/**
 * On a Case that notifies a customer about a field action: the lots the customer received, and what they reported for
 * each (used, returning, destroyed). The Notifications and Recovery steps of the field action read these figures.
 * On any other Case the panel shows nothing.
 */
export default class CqCaseResponse extends LightningElement {
    @api recordId;
    v;
    error;

    async connectedCallback() {
        try { this.v = await caseView({ caseId: this.recordId }); }
        catch (e) { this.error = (e && e.body && e.body.message) || 'Could not read the response.'; }
    }
    get show() { return !!this.v && this.v.fieldAction; }
    get faHref() { return '/lightning/r/Field_Action__c/' + this.v.fieldActionId + '/view'; }
    get rows() {
        const val = (x) => (x === undefined || x === null ? '' : x);
        return this.v.lines.map((l) => ({ lot: l.lot, shipped: l.shipped === undefined || l.shipped === null ? '—' : String(l.shipped),
            used: val(l.used), returning: val(l.returning), destroyed: val(l.destroyed),
            unknown: l.unknown === undefined || l.unknown === null ? '—' : String(l.unknown),
            unknownCls: 'num ' + (l.unknown ? 'warnc b' : l.unknown === 0 ? 'okc b' : ''),
            usedLabel: 'Units used, lot ' + l.lot, retLabel: 'Units returning, lot ' + l.lot, desLabel: 'Units destroyed, lot ' + l.lot }));
    }
    /** A figure on a lot: saved when the box is left (or Enter is pressed). */
    async handleFigure(event) {
        const d = event.target.dataset;
        const raw = event.target.value;
        const now = raw === '' ? null : Number(raw);
        this.error = undefined;
        if (now !== null && (isNaN(now) || now < 0)) { this.error = 'Units cannot be negative.'; return; }
        try {
            this.v = await saveCaseLine({ caseId: this.recordId, lot: d.lot, field: d.f, value: now });
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (e) { this.error = (e && e.body && e.body.message) || 'Could not save that figure.'; }
    }
    handleKey(event) { if (event.key === 'Enter') { event.target.blur(); } }
}
