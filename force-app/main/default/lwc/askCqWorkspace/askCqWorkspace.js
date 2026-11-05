import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getStatus from '@salesforce/apex/AskCqWorkspaceController.getStatus';
import getChecklist from '@salesforce/apex/AskCqWorkspaceController.getChecklist';
import saveAnswer from '@salesforce/apex/AskCqWorkspaceController.saveAnswer';
import acceptSuggestion from '@salesforce/apex/AskCqWorkspaceController.acceptSuggestion';

const CHECKLIST_AGENT = '0XxW400000010ijKAA';   // Scout Checklist (dev). Blank = the PHR Agent from AskCqSecrets.
const OPTION_ORDER = ['Yes', 'No', 'N/A'];

/** Yes before No before anything else, whatever order the result type lists them in. */
function orderOptions(options) {
    const rank = (o) => { const i = OPTION_ORDER.findIndex((x) => x.toLowerCase() === String(o).toLowerCase()); return i < 0 ? 99 : i; };
    return [...(options || [])].sort((a, b) => rank(a) - rank(b));
}

/**
 * PHR workspace: highlights header, review steps down the left (a green check when a step is done),
 * the step's work area beside it, and one Ask CQ popover (Scout through the Agent API) shared by
 * every step. Checklist suggestions are pre-selected in purple from the same logic the Checklist
 * agent uses; clicking the purple answer accepts it, clicking another answer makes it the user's.
 */
export default class AskCqWorkspace extends NavigationMixin(LightningElement) {
    @api recordId;
    status;
    checklist = [];
    current = 'records';
    error;
    saveNote;

    connectedCallback() { this.refresh(); }

    async refresh() {
        try {
            this.status = await getStatus({ phrId: this.recordId });
            this.error = undefined;
            if (this.current === 'checklist') { await this.loadChecklist(); }
        } catch (e) {
            this.error = (e.body && e.body.message) || 'Could not read the review.';
        }
    }

    async loadChecklist() {
        const qs = await getChecklist({ phrId: this.recordId });
        this.checklist = qs.map((q) => {
            const pending = !q.answered && !!q.suggestedAnswer;        // suggestion shown, not accepted yet
            const shownAnswer = q.answered ? q.answer : (pending ? q.suggestedAnswer : null);
            const purple = q.suggested || pending;
            return {
                ...q,
                showPill: q.suggested || pending,
                evidence: q.answered ? q.notes : (pending ? q.suggestedBasis : ''),
                buttons: orderOptions(q.options).map((o) => ({
                    key: q.id + ':' + o,
                    value: o,
                    cls: 'yn' + (o === shownAnswer ? (purple ? ' sug' : ' sel') : ''),
                    pressed: o === shownAnswer
                })),
                why: q.suggested || pending
                    ? 'Why is the suggested answer to "' + q.question + '" ' + shownAnswer + '?'
                    : 'Explain the checklist question "' + q.question + '".'
            };
        });
        this.suggestedPending = this.checklist.filter((q) => !q.answered && q.suggestedAnswer).length;
    }
    suggestedPending = 0;

    // ----- steps -----

    get steps() {
        const s = this.status || {};
        const sugg = this.suggestedPending ? ' · ' + this.suggestedPending + ' suggested' : '';
        const defs = [
            { key: 'records', n: 1, label: 'Relevant Records',
              done: (s.recordsAdded || 0) > 0,
              sub: (s.recordsAdded || 0) > 0 ? s.recordsAdded + ' added to the PHR' : 'None added yet' },
            { key: 'checklist', n: 2, label: 'Checklist',
              done: (s.questionsTotal || 0) > 0 && s.questionsAnswered === s.questionsTotal,
              sub: (s.questionsTotal || 0) > 0 ? s.questionsAnswered + ' of ' + s.questionsTotal + ' answered' + sugg : 'No questions' },
            { key: 'summary', n: 3, label: 'PHR Summary',
              done: !!s.summarySaved,
              sub: s.summarySaved ? 'Saved to the PHR' : 'Not drafted' },
            { key: 'reports', n: 4, label: 'Reports',
              done: (s.reportCount || 0) > 0,
              sub: (s.reportCount || 0) > 0 ? s.reportCount + ' attached' : 'None yet' }
        ];
        return defs.map((d) => ({
            ...d,
            notDone: !d.done,
            cls: 'step' + (d.key === this.current ? ' active' : '') + (d.done ? ' done' : '')
        }));
    }
    get progress() {
        const done = this.steps.filter((s) => s.done).length;
        return done + ' of ' + this.steps.length + ' steps complete';
    }

    // ----- highlights -----

    get title() { return this.status ? this.status.phrName : 'Product History Review'; }
    get complaintName() { return this.status && this.status.complaintName; }
    get complaintLink() { return this.status && this.status.complaintId ? '/' + this.status.complaintId : '#'; }
    get partName() { return (this.status && this.status.partName) || '—'; }
    get lotNumber() { return (this.status && this.status.lotNumber) || '—'; }
    get ownerName() { return (this.status && this.status.ownerName) || '—'; }
    get phrStatus() { return (this.status && this.status.phrStatus) || '—'; }
    get pendingChecklist() { return this.status ? this.status.pendingChecklist : '—'; }

    handleEdit() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.recordId, objectApiName: 'compliancequest__SQX_Product_History_Review__c', actionName: 'edit' }
        });
    }

    get isRecords() { return this.current === 'records'; }
    get isChecklist() { return this.current === 'checklist'; }
    get isSummary() { return this.current === 'summary'; }
    get isReports() { return this.current === 'reports'; }
    get hasSummary() { return !!(this.status && this.status.summarySaved); }
    get summaryHtml() { return this.status ? this.status.summaryHtml : ''; }
    get reports() {
        return (this.status && this.status.reports || []).map((r) => ({
            ...r, key: r.link, label: r.title + (r.version ? ' · v' + r.version : '')
        }));
    }
    get hasReports() { return this.reports.length > 0; }
    get hasChecklist() { return this.checklist.length > 0; }

    /** Which agent and which ready questions the popover carries on this step. */
    get agentId() { return this.current === 'checklist' ? CHECKLIST_AGENT : ''; }
    get suggestions() {
        switch (this.current) {
            case 'checklist': return 'Explain the suggested answers,What is the scrap rate?,Which questions still need an answer?';
            case 'summary': return 'Draft the PHR Summary,What should the summary cover?';
            case 'reports': return 'Generate the report,What does the report include?';
            default: return 'Why are these records relevant?,Which of these share the complaint lot?,What is missing on this complaint?';
        }
    }

    async handleStep(event) {
        this.current = event.currentTarget.dataset.key;
        if (this.current === 'checklist') { await this.loadChecklist(); }
    }

    // ----- Ask CQ -----

    get pop() { return this.template.querySelector('c-ask-cq-popover'); }
    handleAsk(event) {
        const q = event.detail && event.detail.question;
        if (q && this.pop) { this.pop.ask(q); }
    }
    handleWhy(event) { const q = event.currentTarget.dataset.q; if (this.pop) { this.pop.ask(q); } }
    handleDraft() { if (this.pop) { this.pop.ask('Draft the PHR Summary for this complaint.'); } }
    handleReport() { if (this.pop) { this.pop.ask('Generate the Product History Review report and attach it to the complaint.'); } }
    handleChanged() { this.refresh(); }
    handleRefresh() { this.refresh(); }

    // ----- checklist answers -----

    async handleAnswer(event) {
        const id = event.currentTarget.dataset.id;
        const value = event.currentTarget.dataset.value;
        const q = this.checklist.find((x) => x.id === id);
        if (!q) { return; }
        try {
            if (!q.answered && q.suggestedAnswer && value === q.suggestedAnswer) {
                await acceptSuggestion({ answerId: q.id, answer: value, basis: q.suggestedBasis });   // the user agreed with CQ
            } else {
                await saveAnswer({ answerId: q.id, answer: value });                                   // the user's own answer
            }
            this.saveNote = 'Saved.';
            await this.refresh();
        } catch (e) {
            this.error = (e.body && e.body.message) || 'Could not save the answer.';
        }
    }
}
