import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { loadStyle } from 'lightning/platformResourceLoader';
import POPUP_STYLES from '@salesforce/resourceUrl/PHR_Triage_Popup_Styles';
import load from '@salesforce/apex/PhrCompleteTriageController.load';
import saveSteps from '@salesforce/apex/PhrCompleteTriageController.saveSteps';
import completeTriage from '@salesforce/apex/PhrCompleteTriageController.completeTriage';
import includeDraftSummary from '@salesforce/apex/TriageDraftSummaryController.includeDraftSummary';

const TRIAGE = 'Triage';
const NO_INVESTIGATION = 'No investigation is linked';
const SUMMARY_RETRIES = 3;
const SUMMARY_WAIT_MS = 2000;

function wait(ms) {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Unknown error';
}

export default class TriageStepsWithSummary extends LightningElement {
    @api recordId;
    @api task;
    @api purpose;
    // Passed in by CQ's dynamic loader (SQX_Dynamic_Component); accepted so CQ can create this component.
    @api activityCode;
    @api objectApiName;
    @api origin;
    @api formParams;
    @api formChanges;
    @api relatedField;
    @api hideSave;
    @api activityCommentField;

    loading = true;
    loadError = '';
    data;
    rows = [];
    selectedTemplateId;
    includeSummary = true;
    comment = '';
    busy = false;
    busyText = '';
    statusMessage = '';
    statusIsError = false;
    newKey = 0;

    get startId() {
        if (this.recordId) return this.recordId;
        if (this.task && typeof this.task === 'object' && this.task.WhatId) return this.task.WhatId;
        return null;
    }

    get inTriage() {
        return this.data && this.data.stage === TRIAGE;
    }

    get notInTriage() {
        return !this.inTriage;
    }

    get noRows() {
        return this.rows.length === 0;
    }

    get templateOptions() {
        return ((this.data && this.data.templates) || []).map((t) => ({ label: t.name, value: t.id }));
    }

    get addDisabled() {
        return this.busy || !this.selectedTemplateId;
    }

    get summaryHint() {
        if (!this.includeSummary) return 'The draft summary is not saved. Only the steps and stage are updated.';
        if (this.data && !this.data.hasDraft) return 'There is no draft summary on this complaint yet, so nothing will be copied.';
        return 'After triage, the draft summary is saved to the complaint and copied to its investigation.';
    }

    get statusClass() {
        return this.statusIsError
            ? 'slds-text-color_error slds-var-m-top_small'
            : 'slds-text-color_success slds-var-m-top_small';
    }

    connectedCallback() {
        // CQ's popup shows a spinner until the component reports it has loaded.
        this.dispatchEvent(new CustomEvent('formload'));
        // Hide CQ's own Cancel and Save in this popup; the screen has its own buttons.
        loadStyle(this, POPUP_STYLES).catch(() => {});
        this.refresh();
    }

    async refresh() {
        this.loading = true;
        this.loadError = '';
        if (!this.startId) {
            this.loadError = 'The complaint for this task could not be found.';
            this.loading = false;
            return;
        }
        try {
            this.data = await load({ recordId: this.startId });
            this.rows = (this.data.steps || []).map((s) => this.toRow(s, false));
        } catch (e) {
            this.loadError = 'The triage steps could not be loaded: ' + errorText(e);
        } finally {
            this.loading = false;
        }
    }

    toRow(s, isNew) {
        const key = s.id || 'new-' + (this.newKey += 1);
        return {
            key,
            id: s.id || null,
            templateId: s.templateId,
            name: s.name,
            label: (s.step != null ? s.step + ' · ' : '') + s.name,
            step: s.step,
            assigneeId: s.assigneeId || null,
            allowedDays: s.allowedDays,
            include: s.include !== false,
            isNew
        };
    }

    updateRow(key, changes) {
        this.rows = this.rows.map((r) => (r.key === key ? { ...r, ...changes } : r));
    }

    handleInclude(event) {
        this.updateRow(event.target.dataset.key, { include: event.target.checked });
    }

    handleAssignee(event) {
        this.updateRow(event.target.dataset.key, { assigneeId: (event.detail && event.detail.recordId) || null });
    }

    handleTemplate(event) {
        this.selectedTemplateId = event.detail.value;
    }

    handleAddStep() {
        const t = (this.data.templates || []).find((x) => x.id === this.selectedTemplateId);
        if (!t) return;
        this.rows = [
            ...this.rows,
            this.toRow({ templateId: t.id, name: t.name, step: t.step, assigneeId: t.defaultAssigneeId, allowedDays: t.allowedDays, include: true }, true)
        ];
        this.selectedTemplateId = null;
    }

    handleSummaryToggle(event) {
        this.includeSummary = event.target.checked;
    }

    handleComment(event) {
        this.comment = event.target.value;
    }

    handleCancel() {
        this.close();
    }

    setStatus(message, isError) {
        this.statusMessage = message;
        this.statusIsError = isError;
    }

    async handleComplete() {
        if (!this.rows.some((r) => r.include)) {
            this.setStatus('Choose at least one step before completing triage.', true);
            return;
        }
        this.busy = true;
        this.setStatus('', false);
        const complaintId = this.data.complaintId;
        try {
            // 1. Steps (own transaction).
            this.busyText = 'Saving the steps';
            const stepsPayload = this.rows.map((r) => ({
                id: r.id, templateId: r.templateId, name: r.name, step: r.step,
                assigneeId: r.assigneeId, allowedDays: r.allowedDays, include: r.include
            }));
            const s = await saveSteps({ recordId: complaintId, stepsJson: JSON.stringify(stepsPayload) });
            if (!s.success) {
                this.setStatus(s.message, true);
                return;
            }

            // 2. Move the complaint forward through CQ's Initiate (own transaction).
            this.busyText = 'Completing triage';
            const t = await completeTriage({ recordId: complaintId, comment: this.comment });
            if (!t.success) {
                this.setStatus(t.message, true);
                await this.refresh();
                return;
            }

            // 3. Draft summary to the complaint and the new investigation (own transaction).
            let summaryMessage = '';
            if (this.includeSummary && this.data.hasDraft) {
                this.busyText = 'Saving the draft summary';
                summaryMessage = await this.saveSummaryWithRetry(complaintId);
            }

            const message = t.message + (summaryMessage ? ' ' + summaryMessage : '');
            this.dispatchEvent(new ShowToastEvent({ title: 'Triage completed', message, variant: 'success' }));
            try {
                await notifyRecordUpdateAvailable([{ recordId: complaintId }]);
            } catch (ignore) {
                // the page refreshes on its own if this is not available
            }
            // Tell CQ's popup the work is saved (it refreshes to the record), then close it.
            this.dispatchEvent(new CustomEvent('formsaved', { detail: { recordId: complaintId } }));
            this.close();
        } catch (e) {
            this.setStatus('Something went wrong: ' + errorText(e), true);
        } finally {
            this.busy = false;
            this.busyText = '';
        }
    }

    // CQ may create the investigation a moment after triage, so try a few times before giving up.
    async saveSummaryWithRetry(complaintId) {
        let last = '';
        for (let i = 0; i < SUMMARY_RETRIES; i += 1) {
            try {
                const o = await includeDraftSummary({ recordId: complaintId });
                last = o.message || '';
                if (!o.success) return 'The draft summary could not be saved: ' + last;
                if (last.indexOf(NO_INVESTIGATION) === -1) return last;
            } catch (e) {
                return 'The draft summary could not be saved: ' + errorText(e);
            }
            await wait(SUMMARY_WAIT_MS);
        }
        return last;
    }

    close() {
        this.dispatchEvent(new CustomEvent('close'));
        this.dispatchEvent(new CustomEvent('cqclosedynamicloader'));
    }
}
