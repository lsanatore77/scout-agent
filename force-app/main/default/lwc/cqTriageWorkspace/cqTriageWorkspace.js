import { LightningElement, api } from 'lwc';
import getGlance from '@salesforce/apex/CqTriageController.getGlance';
import getPhotoVersionId from '@salesforce/apex/CqTriagePhoto.getPhotoVersionId';

/**
 * CQ.AI Triage workspace: reads the nonconformance, then the Triage Assistant draws the page in the shared frame
 * (c-cq-ws-shell): the record header, Triage at a Glance as step 1 and the triage steps.
 */
export default class CqTriageWorkspace extends LightningElement {
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
}
