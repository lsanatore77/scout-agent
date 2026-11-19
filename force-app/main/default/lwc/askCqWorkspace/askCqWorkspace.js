import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getStatus from '@salesforce/apex/AskCqWorkspaceController.getStatus';
import getChecklist from '@salesforce/apex/AskCqWorkspaceController.getChecklist';
import saveChecklist from '@salesforce/apex/AskCqWorkspaceController.saveChecklist';
import saveDraft from '@salesforce/apex/AskCqWorkspaceController.saveDraft';

const OPTION_ORDER = ['Yes', 'No', 'N/A'];
const STEP_ORDER = ['records', 'checklist', 'summary', 'reports'];

/** Yes before No before anything else, whatever order the result type lists them in. */
function orderOptions(options) {
    const rank = (o) => { const i = OPTION_ORDER.findIndex((x) => x.toLowerCase() === String(o).toLowerCase()); return i < 0 ? 99 : i; };
    return [...(options || [])].sort((a, b) => rank(a) - rank(b));
}

/**
 * PHR workspace: highlights header, review steps down the left (a green check when a step is done),
 * the step's work area beside it, and one Ask CQ popover (Scout through the Agent API) shared by
 * every step. Checklist suggestions are pre-selected in purple from the same logic the Checklist
 * agent uses. Clicking only stages an answer. Save keeps the answers as a draft on the PHR, so the user can
 * leave and come back; Submit Checklist puts them on the checklist itself (every question answered), and a
 * suggestion left as it is is submitted as accepted. The suggested answer keeps its purple mark when the
 * user picks another, so what CQ.AI suggested stays on screen. Back and Next sit under every step.
 */
export default class AskCqWorkspace extends NavigationMixin(LightningElement) {
    @api recordId;
    status;
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

    raw = [];            // the questions as submitted, with what CQ.AI suggests for each
    draft = {};          // answers chosen on screen: question id -> answer
    serverDraft = {};    // the draft as last saved on the PHR
    saving = false;
    blocker = '';
    leaveArmed = false;  // the user has been warned once about unsaved answers

    async loadChecklist() {
        this.raw = await getChecklist({ phrId: this.recordId });
        const d = {};
        this.raw.forEach((q) => { if (q.draftAnswer) { d[q.id] = q.draftAnswer; } });
        this.serverDraft = d;
        this.draft = { ...d };
        this.blocker = '';
        this.leaveArmed = false;
    }

    /** The answer on screen before any click: the saved one, else CQ.AI's suggestion. */
    baseline(q) { return q.answered ? q.answer : (q.suggestedAnswer || null); }
    shown(q) { return Object.prototype.hasOwnProperty.call(this.draft, q.id) ? this.draft[q.id] : this.baseline(q); }
    /** What CQ.AI suggests: worked out now, else the suggestion that was accepted earlier. */
    aiAnswer(q) { return q.suggestedAnswer || (q.suggested ? q.answer : null); }
    aiBasis(q) { return q.suggestedBasis || (q.suggested ? q.notes : ''); }

    get checklist() {
        return this.raw.map((q) => {
            const shown = this.shown(q);
            const ai = this.aiAnswer(q);
            return {
                ...q,
                showPill: !!ai,
                evidence: ai ? (this.aiBasis(q) || q.notes) : q.notes,
                buttons: orderOptions(q.options).map((o) => ({
                    key: q.id + ':' + o,
                    value: o,
                    cls: 'cq-chip' + (o === ai ? ' ai' : ''),     // the suggestion stays purple, chosen or not
                    pressed: String(o === shown)
                })),
                why: ai
                    ? 'Why is the suggested answer to "' + q.question + '" ' + ai + '?'
                    : 'Explain the checklist question "' + q.question + '".'
            };
        });
    }
    get suggestedPending() { return this.raw.filter((q) => !q.answered && q.suggestedAnswer).length; }
    /** Everything Submit Checklist would write: answers that differ from what is on the checklist, untouched suggestions included. */
    get toSubmit() {
        return this.raw.filter((q) => {
            const s = this.shown(q);
            // also an answer that matches the suggestion but was never marked as one, so the record says where it came from
            return s && (s !== (q.answered ? q.answer : null) || (s === this.aiAnswer(q) && !q.suggested));
        })
            .map((q) => { const s = this.shown(q); const ai = s === this.aiAnswer(q);
                return { id: q.id, answer: s, suggested: ai, basis: ai ? this.aiBasis(q) : null }; });
    }
    /** A draft with only the answers that differ from what the checklist would show anyway. */
    clean(map) {
        const out = {};
        this.raw.forEach((q) => {
            if (Object.prototype.hasOwnProperty.call(map, q.id) && map[q.id] && map[q.id] !== this.baseline(q)) { out[q.id] = map[q.id]; }
        });
        return out;
    }
    /** Answers chosen on screen that Save has not kept yet. */
    get dirty() { return JSON.stringify(this.clean(this.draft)) !== JSON.stringify(this.clean(this.serverDraft)); }
    get hasSavedDraft() { return Object.keys(this.clean(this.serverDraft)).length > 0; }
    get allAnswered() { return this.raw.length > 0 && this.raw.every((q) => !!this.shown(q)); }

    // ----- steps -----

    get steps() {
        const s = this.status || {};
        const sugg = this.suggestedPending ? ' · ' + this.suggestedPending + ' CQ.AI suggested' : '';
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
    get agentName() { return this.current === 'checklist' ? 'Scout_Checklist' : 'PHR_Agent'; }
    get suggestions() {
        switch (this.current) {
            case 'checklist': return 'Explain the CQ.AI suggested answers,What is the scrap rate?,Which questions still need an answer?';
            case 'summary': return 'Generate the PHR Summary,What should the summary cover?';
            case 'reports': return 'Generate the report,What does the report include?';
            default: return 'Why are these records relevant?,Which of these share the complaint lot?,What is missing on this complaint?';
        }
    }

    /** Moves to a step. Clicked answers are never dropped silently: the first try to leave warns, the second leaves. */
    async go(key) {
        if (!key || key === this.current) { return; }
        if (this.current === 'checklist' && this.dirty && !this.leaveArmed) {
            this.blocker = 'You have unsaved answers. Save, or press again to leave without them.';
            this.leaveArmed = true;
            return;
        }
        this.blocker = '';
        this.leaveArmed = false;
        this.saveNote = undefined;
        this.current = key;
        if (key === 'checklist') { await this.loadChecklist(); }
    }
    handleStep(event) { return this.go(event.currentTarget.dataset.key); }
    get stepIndex() { return STEP_ORDER.indexOf(this.current); }
    get hasBack() { return this.stepIndex > 0; }
    get hasNext() { return this.stepIndex < STEP_ORDER.length - 1; }
    handleBack() { return this.go(STEP_ORDER[this.stepIndex - 1]); }
    handleNext() { return this.go(STEP_ORDER[this.stepIndex + 1]); }
    get cantSaveDraft() { return this.saving || !this.dirty; }
    get canSubmit() { return this.isChecklist && this.allAnswered && this.toSubmit.length > 0; }
    get cantSubmit() { return this.saving || !this.canSubmit; }
    /** One blue button in the footer: Submit Checklist while there is something to submit, otherwise Next. */
    get nextCls() { return this.canSubmit ? 'cq-btn-outline' : 'cq-btn-primary'; }
    /** Why Submit is off, or where the draft stands, beside the buttons. */
    get footNote() {
        if (this.blocker) { return this.blocker; }
        if (!this.isChecklist || !this.raw.length) { return ''; }
        if (!this.allAnswered) { return 'Answer every question to submit.'; }
        if (this.dirty) { return ''; }
        return this.hasSavedDraft ? 'Draft saved, not yet submitted.' : '';
    }
    get footCls() { return this.blocker || (this.isChecklist && !this.allAnswered) ? 'blocker' : 'footnote'; }

    // ----- Ask CQ -----

    get pop() { return this.template.querySelector('c-ask-cq-popover'); }
    handleAsk(event) {
        const q = event.detail && event.detail.question;
        if (q && this.pop) { this.pop.ask(q); }
    }
    handleWhy(event) { const q = event.currentTarget.dataset.q; if (this.pop) { this.pop.ask(q); } }
    handleDraft() { if (this.pop) { this.pop.ask('Generate the PHR Summary for this complaint.'); } }
    handleReport() { if (this.pop) { this.pop.ask('Generate the Product History Review report and attach it to the complaint.'); } }
    handleChanged() { this.refresh(); }
    handleRefresh() { this.refresh(); }

    // ----- checklist answers -----

    /** A click only stages the answer; nothing is written until Save or Submit Checklist. */
    handleAnswer(event) {
        const id = event.currentTarget.dataset.id;
        const value = event.currentTarget.dataset.value;
        if (!this.raw.some((x) => x.id === id)) { return; }
        this.draft = { ...this.draft, [id]: value };
        this.saveNote = undefined;
        this.blocker = '';
        this.leaveArmed = false;
    }

    /** Save: keeps the answers chosen so far as a draft on the PHR. Nothing is required, and nothing goes on the checklist. */
    async handleSaveDraft() {
        if (this.saving || !this.dirty) { return; }
        this.saving = true;
        try {
            const d = this.clean(this.draft);
            await saveDraft({ phrId: this.recordId, payload: JSON.stringify(d) });
            this.serverDraft = { ...d };
            this.blocker = '';
            this.leaveArmed = false;
            this.error = undefined;
            this.saveNote = 'Draft saved. Submit Checklist to put the answers on the record.';
        } catch (e) {
            this.error = (e.body && e.body.message) || 'Could not save the draft.';
        } finally {
            this.saving = false;
        }
    }

    /** Submit Checklist: the answers go onto the checklist and the draft is cleared. */
    async handleSubmitChecklist() {
        const rows = this.toSubmit;
        if (!this.canSubmit || this.saving) { return; }
        this.saving = true;
        try {
            await saveChecklist({ phrId: this.recordId, payload: JSON.stringify(rows) });
            this.status = await getStatus({ phrId: this.recordId });
            await this.loadChecklist();
            this.error = undefined;
            this.saveNote = 'Checklist submitted.';
        } catch (e) {
            this.error = (e.body && e.body.message) || 'Could not submit the checklist.';
        } finally {
            this.saving = false;
        }
    }
}
