import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { loadStyle } from 'lightning/platformResourceLoader';
import POPUP_STYLES from '@salesforce/resourceUrl/PHR_Triage_Popup_Styles';
import load from '@salesforce/apex/PhrCompleteTriageController.load';
import generateDraft from '@salesforce/apex/PhrCompleteTriageController.generateDraft';
import saveDraft from '@salesforce/apex/PhrCompleteTriageController.saveDraft';
import saveSteps from '@salesforce/apex/PhrCompleteTriageController.saveSteps';
import completeTriage from '@salesforce/apex/PhrCompleteTriageController.completeTriage';

const TRIAGE = 'Triage';
const SCREEN_DRAFT = 'draft';
const SCREEN_STEPS = 'steps';

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Unknown error';
}

/**
 * PHR Complete Triage: replaces CQ's triage popup in eNBA.
 * Screen 1 shows the draft investigation summary (the saved one, or a newly generated one).
 * Screen 2 holds the workflow steps. Complete triage saves the steps, initiates the complaint the CQ way,
 * then saves the draft once (formatting, report link and copy to linked investigations come from that save).
 */
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
    screen = SCREEN_DRAFT;

    // Screen 1
    draftHtml = '';
    draftIsNew = false;
    draftEdited = false;
    generating = false;
    draftError = '';
    editing = false;
    skipSummary = false;

    // Screen 2
    rows = [];
    selectedTemplateId;
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

    get onDraftScreen() {
        return this.screen === SCREEN_DRAFT;
    }

    get screenLabel() {
        return this.onDraftScreen
            ? 'Step 1 of 2: review the draft summary'
            : 'Step 2 of 2: moves to In Progress when you complete triage';
    }

    get hasDraftText() {
        return !!(this.draftHtml && this.draftHtml.trim());
    }

    get draftSourceLabel() {
        if (this.generating || !this.hasDraftText) return '';
        if (this.draftEdited) return 'Edited, not saved yet';
        return this.draftIsNew ? 'New draft, not saved yet' : 'Saved draft on this complaint';
    }

    get regenerateLabel() {
        return this.hasDraftText ? 'Regenerate' : 'Generate';
    }

    get editLabel() {
        return this.editing ? 'Done editing' : 'Edit';
    }

    get nextDisabled() {
        return this.generating;
    }

    get summaryNote() {
        if (this.skipSummary || !this.hasDraftText) {
            return 'No draft summary will be saved with this triage.';
        }
        if (this.draftIsNew || this.draftEdited) {
            return 'After triage, the draft summary from the previous screen is saved to the complaint and copied to its investigation.';
        }
        return 'After triage, the complaint\'s draft summary is saved again (with the report link) and copied to its investigation.';
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
        this.refresh(true);
    }

    async refresh(firstLoad) {
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
            if (firstLoad) {
                this.draftHtml = this.data.draftHtml || '';
                this.draftIsNew = false;
            }
        } catch (e) {
            this.loadError = 'The triage steps could not be loaded: ' + errorText(e);
        } finally {
            this.loading = false;
        }
        // No saved draft yet: write one now, so it is ready to review.
        if (firstLoad && !this.loadError && this.inTriage && !this.hasDraftText) {
            this.generate();
        }
    }

    async generate() {
        this.generating = true;
        this.draftError = '';
        this.editing = false;
        try {
            const o = await generateDraft({ recordId: this.data.complaintId });
            if (o.success) {
                this.draftHtml = o.html;
                this.draftIsNew = true;
                this.draftEdited = false;
            } else {
                this.draftError = o.message || 'The draft could not be generated.';
            }
        } catch (e) {
            this.draftError = 'The draft could not be generated: ' + errorText(e);
        } finally {
            this.generating = false;
        }
    }

    // Screen 1 handlers
    handleRegenerate() {
        this.generate();
    }

    handleToggleEdit() {
        this.editing = !this.editing;
    }

    handleDraftEdit(event) {
        this.draftHtml = event.target.value;
        this.draftEdited = true;
    }

    handleSkip() {
        this.skipSummary = true;
        this.editing = false;
        this.screen = SCREEN_STEPS;
    }

    handleNext() {
        this.skipSummary = !this.hasDraftText;
        this.editing = false;
        this.screen = SCREEN_STEPS;
    }

    // Screen 2 handlers
    handleBack() {
        this.screen = SCREEN_DRAFT;
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
                await this.refresh(false);
                return;
            }

            // 3. The draft summary, saved once (own transaction).
            let summaryMessage = '';
            if (!this.skipSummary && this.hasDraftText) {
                this.busyText = 'Saving the draft summary';
                try {
                    const d = await saveDraft({ recordId: complaintId, html: this.draftHtml });
                    summaryMessage = d.success ? d.message : 'The draft summary could not be saved: ' + d.message;
                } catch (e) {
                    summaryMessage = 'The draft summary could not be saved: ' + errorText(e);
                }
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

    close() {
        this.dispatchEvent(new CustomEvent('close'));
        this.dispatchEvent(new CustomEvent('cqclosedynamicloader'));
    }
}
