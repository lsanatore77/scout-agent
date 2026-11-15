import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getGlance from '@salesforce/apex/CqTriageController.getGlance';
import getPhotoVersionId from '@salesforce/apex/CqTriagePhoto.getPhotoVersionId';

// Ask CQ.AI ready questions for each triage step (no commas: the popover splits on them)
const ASK = {
    'Triage at a Glance': 'Summarize this nonconformance,What is left on this triage?,What else is open on this part?',
    Containment: 'Why does CQ.AI suggest this containment?,How much of this lot is on hand or shipped?,What containment is on this NC?',
    'Data Check': 'What is missing before this can go on?,Is the data good enough?',
    Risk: 'How was the risk worked out?,Why is the likelihood what it is?',
    'Next Steps': 'Does this need a disposition?,Should this be investigated or logged only?,Which investigations should be linked and why?',
    'Triage complete': 'Summarize this nonconformance,What is still open on this NC?,Does this need a field action review?'
};
const LOT_ASK = 'Which relevant records share the lot?';

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

    // ---- Ask CQ.AI: the Quality agent, told which triage step is open
    askStep = 'Triage at a Glance';
    handleStep(event) { this.askStep = (event.detail && event.detail.step) || ''; }
    get askSuggestions() {
        const base = ASK[this.askStep] || ASK['Triage at a Glance'];
        return this.g && this.g.lot && this.askStep === 'Triage at a Glance' ? base + ',' + LOT_ASK : base;
    }
    handleChanged() { this.load(); }

    // ---- record header
    dash(x) { return x === undefined || x === null || x === '' ? '—' : String(x); }
    get titleText() { return this.dash(this.g.title); }
    get lotText() { return this.dash(this.g.lot); }
    get typeText() { return this.dash(this.g.ncType); }
    get severityText() { return this.dash(this.g.severity); }
    get statusText() { return this.dash(this.g.status); }
    get ownerText() { return this.dash(this.g.owner); }
    get occurredText() { return this.g.occurred ? new Date(this.g.occurred + 'T00:00:00').toLocaleDateString() : '—'; }
    get partHref() { return '/lightning/r/compliancequest__SQX_Part__c/' + this.g.partId + '/view'; }
    handleEdit() {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage',
            attributes: { recordId: this.recordId, objectApiName: 'compliancequest__SQX_Nonconformance__c', actionName: 'edit' } });
    }
}
