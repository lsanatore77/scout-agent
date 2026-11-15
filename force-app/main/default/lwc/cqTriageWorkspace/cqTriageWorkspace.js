import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getGlance from '@salesforce/apex/CqTriageController.getGlance';
import getPhotoVersionId from '@salesforce/apex/CqTriagePhoto.getPhotoVersionId';

/** CQ.AI Triage workspace: the nonconformance's record header, then Triage at a Glance as step 1 and the triage steps, in the page (no popup). */
export default class CqTriageWorkspace extends NavigationMixin(LightningElement) {
    @api recordId;
    g;
    hasPhoto = false;
    error;

    connectedCallback() { this.load(); }

    async load() {
        try { this.g = await getGlance({ recordId: this.recordId }); this.error = undefined; }
        catch (e) { this.error = (e && e.body && e.body.message) || 'Could not read this nonconformance.'; }
        try { this.hasPhoto = !!(await getPhotoVersionId({ recordId: this.recordId })); }
        catch (e) { this.hasPhoto = false; }
    }

    get ready() { return !!this.g; }
    handleChanged() { this.load(); }

    // ---- record header
    dash(x) { return x === undefined || x === null || x === '' ? '\u2014' : String(x); }
    get titleText() { return this.dash(this.g.title); }
    get lotText() { return this.dash(this.g.lot); }
    get typeText() { return this.dash(this.g.ncType); }
    get severityText() { return this.dash(this.g.severity); }
    get statusText() { return this.dash(this.g.status); }
    get ownerText() { return this.dash(this.g.owner); }
    get occurredText() { return this.g.occurred ? new Date(this.g.occurred + 'T00:00:00').toLocaleDateString() : '\u2014'; }
    get partHref() { return '/lightning/r/compliancequest__SQX_Part__c/' + this.g.partId + '/view'; }
    handleEdit() {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage',
            attributes: { recordId: this.recordId, objectApiName: 'compliancequest__SQX_Nonconformance__c', actionName: 'edit' } });
    }
}
