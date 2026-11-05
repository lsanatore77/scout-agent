import { LightningElement, api } from 'lwc';
import getStatus from '@salesforce/apex/AskCqWorkspaceController.getStatus';
import getChecklist from '@salesforce/apex/AskCqWorkspaceController.getChecklist';

const CHECKLIST_AGENT = '0XxW400000010ijKAA';   // Scout Checklist (dev). Blank = the PHR Agent from AskCqSecrets.

/**
 * PHR workspace: review steps down the left (a green check when a step is done), the step's work
 * area in the middle, and one Ask CQ popover (Scout through the Agent API) shared by every step.
 */
export default class AskCqWorkspace extends LightningElement {
    @api recordId;
    status;
    checklist = [];
    current = 'records';
    error;

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
        this.checklist = qs.map((q) => ({
            ...q,
            number: q.number_x,
            answerText: q.answer || 'Not answered',
            cls: 'q ' + (q.answered ? 'done' : 'open'),
            why: q.answered
                ? 'Why is the answer to "' + q.question + '" ' + q.answer + '?'
                : 'Answer the checklist question "' + q.question + '" from the records on this review.'
        }));
    }

    // ----- steps -----

    get steps() {
        const s = this.status || {};
        const defs = [
            { key: 'records', n: 1, label: 'Relevant records',
              done: (s.recordsAdded || 0) > 0,
              sub: (s.recordsAdded || 0) > 0 ? s.recordsAdded + ' added to the PHR' : 'None added yet' },
            { key: 'checklist', n: 2, label: 'Checklist',
              done: (s.questionsTotal || 0) > 0 && s.questionsAnswered === s.questionsTotal,
              sub: (s.questionsTotal || 0) > 0 ? s.questionsAnswered + ' of ' + s.questionsTotal + ' answered' : 'No questions' },
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
    get title() { return this.status ? this.status.phrName : 'Product History Review'; }
    get subtitle() {
        if (!this.status) { return ''; }
        return [this.status.complaintName, this.status.phrStatus].filter(Boolean).join(' · ');
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
            case 'checklist': return 'Answer the checklist,What is the scrap rate?,Which questions still need an answer?';
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
}
