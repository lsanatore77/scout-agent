import { LightningElement, api } from 'lwc';
import hasDraft from '@salesforce/apex/TriageDraftSummaryController.hasDraft';
import includeDraftSummary from '@salesforce/apex/TriageDraftSummaryController.includeDraftSummary';

const TASK_PREFIX = '00T';

export default class TriageStepsWithSummary extends LightningElement {
    @api recordId;
    @api task;
    @api purpose;

    includeSummary = true;
    saving = false;
    message = '';
    messageIsError = false;
    draftExists = true;
    handled = false;

    get startId() {
        if (this.recordId) return this.recordId;
        if (this.task && typeof this.task === 'object' && this.task.WhatId) return this.task.WhatId;
        return null;
    }

    get hasRecord() {
        return !!this.startId;
    }

    get complaintRecordId() {
        const id = this.startId;
        if (id && id.startsWith(TASK_PREFIX) && this.task && this.task.WhatId) return this.task.WhatId;
        return id;
    }

    get hint() {
        if (!this.includeSummary) return 'The draft summary will not be saved. Only the triage steps are completed.';
        if (!this.draftExists) return 'There is no draft summary on this complaint yet, so nothing will be included.';
        return 'When you finish, the draft summary is also saved to the complaint and its linked investigation.';
    }

    get messageClass() {
        return this.messageIsError
            ? 'slds-text-color_error slds-var-m-top_x-small'
            : 'slds-text-color_success slds-var-m-top_x-small';
    }

    connectedCallback() {
        if (!this.startId) return;
        hasDraft({ recordId: this.startId })
            .then((r) => { this.draftExists = r; })
            .catch(() => { this.draftExists = true; });
    }

    handleToggle(event) {
        this.includeSummary = event.target.checked;
    }

    // CQ's steps grid fires one of these when the user finishes. The first one wins.
    async handleStepsDone() {
        if (this.handled) return;
        this.handled = true;
        if (this.includeSummary && this.draftExists) {
            this.saving = true;
            try {
                const o = await includeDraftSummary({ recordId: this.startId });
                this.messageIsError = !o.success;
                this.message = o.message;
            } catch (e) {
                this.messageIsError = true;
                this.message = 'The triage steps were saved, but the draft summary could not be included: '
                    + ((e && e.body && e.body.message) || (e && e.message) || 'unknown error');
            } finally {
                this.saving = false;
            }
            if (this.messageIsError) {
                this.handled = false;
                return;
            }
        }
        this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
    }
}
