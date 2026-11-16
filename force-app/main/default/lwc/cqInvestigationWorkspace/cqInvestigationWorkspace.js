import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqInvestigationWorkspace.getView';
import saveActions from '@salesforce/apex/CqInvestigationWorkspace.saveActions';
import completeInvestigation from '@salesforce/apex/CqInvestigationWorkspace.completeInvestigation';

const STEPS = ['Investigation at a Glance', 'What Changed', 'Check History', 'Find the Cause', 'Actions', 'Conclusion'];
// Ask CQ.AI ready questions for each step (no commas: the popover splits on them)
const ASK = {
    'Investigation at a Glance': 'What do we already know about this NC?,What is still open on this investigation?,Summarize this nonconformance',
    'What Changed': 'What changed on this part before the problem started?,Which documents changed recently?',
    'Check History': 'Has this problem happened before on this part?,What fixed it last time?',
    'Find the Cause': 'What could cause this defect?,Which root cause codes fit this problem?',
    Actions: 'What actions would stop this coming back?,What is the difference between a correction and a corrective action?',
    Conclusion: 'Which conclusion fits this investigation?,What happens when I complete the investigation?',
    'Investigation Complete': 'What is still open on this NC?,Summarize this investigation'
};
const POLL_MS = 2000;
const POLL_TRIES = 8;

/**
 * CQ.AI Investigation workspace: the investigation's record header, then six steps in the page.
 * Stage 1 builds Investigation at a Glance, Actions and Conclusion with Complete Investigation;
 * What Changed, Check History and Find the Cause show what CQ already holds and are built next.
 * Steps can be opened in any order.
 */
export default class CqInvestigationWorkspace extends NavigationMixin(LightningElement) {
    @api recordId;
    v;
    loadError;
    error;
    notice;
    step = 0;
    seen = { 0: true };
    plans = [];            // Actions step rows: { key, id, title, type, due, userId }
    plansDirty = false;
    conclusion;
    summary = '';
    summaryDrafted = false;
    saving = false;
    result;                // what Complete Investigation did
    waiting = false;       // CQ finishes the submission a few seconds later
    keySeq = 0;

    connectedCallback() { this.load(true); }

    async load(first) {
        try {
            this.v = await getView({ recordId: this.recordId });
            this.loadError = undefined;
            if (first) { this.initForms(); }
        } catch (e) {
            this.loadError = this.msg(e, 'Could not read this investigation.');
        }
    }

    initForms() {
        this.plans = (this.v.plans || []).map((p) => ({ key: 'p' + (this.keySeq++), id: p.id, title: p.title, type: p.type, due: p.due, userId: p.userId }));
        this.plansDirty = false;
        this.conclusion = this.v.conclusion;
        this.summary = this.v.summary || '';
        this.summaryDrafted = false;
    }

    get ready() { return !!this.v; }
    msg(e, fallback) { return (e && e.body && e.body.message) || (e && e.message) || fallback; }
    num(x) { return x === undefined || x === null ? 0 : Number(x); }
    fmt(x) { const n = this.num(x); return Number.isInteger(n) ? String(n) : String(+n.toFixed(2)); }
    dateText(iso) { return iso ? new Date(iso + 'T00:00:00').toLocaleDateString() : '—'; }
    dash(x) { return x === undefined || x === null || x === '' ? '—' : String(x); }
    href(id) { return '/lightning/r/' + id + '/view'; }
    plural(n, one, many) { return this.fmt(n) + ' ' + (this.num(n) === 1 ? one : many); }
    todayIso(add) { const d = new Date(); d.setDate(d.getDate() + (add || 0)); const p = (n) => String(n).padStart(2, '0'); return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()); }

    // ---- header
    get statusText() { return this.dash(this.v.status); }
    get riskText() { return this.dash(this.v.risk); }
    get riskCls() { return 'v lvl ' + (this.v.risk ? this.v.risk.toLowerCase() : ''); }
    get dueText() { return this.dateText(this.v.due); }
    get ownerText() { return this.dash(this.v.owner); }
    get lotText() { return this.dash(this.v.lot); }
    get ncHref() { return this.href(this.v.ncId); }
    get partHref() { return '/lightning/r/compliancequest__SQX_Part__c/' + this.v.partId + '/view'; }
    handleEdit() {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage',
            attributes: { recordId: this.v.investigationId, objectApiName: 'compliancequest__SQX_Investigation__c', actionName: 'edit' } });
    }

    // ---- Ask CQ.AI, told which step is open
    get askStep() { return this.showDone ? 'Investigation Complete' : STEPS[this.step]; }
    get askSuggestions() { return ASK[this.askStep]; }

    // ---- what is shown
    get isDone() { return !!this.result || this.v.isComplete || this.v.inApproval || this.v.submitted; }
    get showDone() { return this.isDone; }
    get showGlance() { return !this.isDone && this.step === 0; }
    get showChanged() { return !this.isDone && this.step === 1; }
    get showHistory() { return !this.isDone && this.step === 2; }
    get showCause() { return !this.isDone && this.step === 3; }
    get showActions() { return !this.isDone && this.step === 4; }
    get showConclusion() { return !this.isDone && this.step === 5; }

    get steps() {
        const done = this.isDone;
        const causes = (this.v.causes || []).length;
        const subs = [
            done || this.step !== 0 ? 'Reviewed' : 'Start Here',
            this.seen[1] || done ? 'Reviewed' : 'Not Reviewed',
            this.seen[2] || done ? 'Reviewed' : 'Not Reviewed',
            causes ? this.plural(causes, 'Root Cause', 'Root Causes') : 'No Root Cause Yet',
            this.plans.length ? this.plural(this.plans.length, 'Action', 'Actions') + (this.plansDirty ? ' · Not Saved' : '') : 'No Actions Yet',
            done ? (this.v.conclusion || this.conclusion || 'Submitted') + ' · ' + this.doneWord : this.conclusion || 'Not Concluded'
        ];
        const stepDone = [done || this.step !== 0, done || !!this.seen[1], done || !!this.seen[2], done || causes > 0,
            done || (this.plans.length > 0 && !this.plansDirty), done];
        return STEPS.map((label, i) => ({
            i, n: i + 1, label, sub: subs[i], done: stepDone[i], notDone: !stepDone[i],
            cls: 'step' + (!done && i === this.step ? ' active' : '') + (stepDone[i] ? ' done' : '')
        }));
    }
    get progress() { return this.steps.filter((s) => s.done).length + ' of 6 steps complete'; }
    get doneWord() { return this.v.inApproval || (this.result && this.result.needsApproval) ? 'In Approval' : 'Complete'; }

    // ---- step 1: Investigation at a Glance
    get problemText() { return this.v.description || this.v.title || 'No description on this NC.'; }
    get unitsText() { return this.v.defective ? this.plural(this.v.defective, 'Unit', 'Units') : '—'; }
    get dispTile() { return !this.v.dispositionRequired ? 'Not Required' : this.v.dispositionComplete ? 'Complete' : 'Open'; }
    get approvalText() { return this.v.needsApproval ? 'Required' : 'Not Required'; }
    get standsText() {
        const bits = [];
        bits.push(this.v.risk ? 'The NC was triaged ' + this.v.risk + ' risk' : 'The NC has been triaged');
        if (this.v.dispositionRequired) {
            bits.push(this.v.dispositionComplete ? 'and its disposition is complete' + (this.v.dispositionText ? ' (' + this.v.dispositionText + ')' : '')
                : 'and its disposition is still open');
        }
        return bits.join(' ') + '.';
    }
    get gapsText() {
        const gaps = [];
        if (!(this.v.causes || []).length) { gaps.push('no root cause is recorded yet'); }
        if (!this.plans.length) { gaps.push('no actions are planned'); }
        const open = (this.v.tools || []).filter((t) => t.status !== 'Complete');
        if (open.length) { gaps.push(this.plural(open.length, 'analysis tool is', 'analysis tools are') + ' still open'); }
        if (!gaps.length) { return null; }
        const s = gaps.length > 1 ? gaps.slice(0, -1).join(', ') + ' and ' + gaps[gaps.length - 1] : gaps[0];
        return s.charAt(0).toUpperCase() + s.slice(1) + '.';
    }
    get nextText() {
        if (!(this.v.causes || []).length) { return 'Review What Changed and Check History, then record the cause in Find the Cause.'; }
        if (!this.plans.length) { return 'Plan the actions that fix the cause, then conclude.'; }
        return 'Check the actions, then conclude and complete the investigation.';
    }
    get knownRows() {
        const v = this.v;
        const causes = v.causes || [];
        const tools = v.tools || [];
        const openTools = tools.filter((t) => t.status !== 'Complete').length;
        const rows = [
            { key: 'tri', source: v.ncName + ' Triage', href: this.ncHref, says: [v.risk ? 'Risk ' + v.risk : null, v.path].filter((x) => x).join('; ') || 'Triaged',
                chip: 'Triaged', chipCls: 'chip ok' }
        ];
        if (v.dispositionRequired) {
            rows.push({ key: 'disp', source: v.ncName + ' Disposition', href: this.ncHref, says: v.dispositionText || 'No disposition completed yet',
                chip: v.dispositionComplete ? 'Complete' : 'Open', chipCls: v.dispositionComplete ? 'chip ok' : 'chip warn' });
        }
        rows.push({ key: 'rc', source: 'Root Causes', says: causes.length ? causes.map((c) => c.code || c.category).join('; ') : 'None recorded yet',
            chip: causes.length ? this.plural(causes.length, 'Recorded', 'Recorded') : 'To Find', chipCls: causes.length ? 'chip ok' : 'chip warn' });
        rows.push({ key: 'ap', source: 'Actions', says: this.plans.length ? this.planMix : 'None planned yet',
            chip: this.plans.length ? 'Planned' : 'To Plan', chipCls: this.plans.length ? 'chip ok' : 'chip warn' });
        if (tools.length) {
            rows.push({ key: 'tl', source: 'Analysis Tools', says: tools.map((t) => (t.type || 'Tool') + ' ' + t.name).join('; '),
                chip: openTools ? this.plural(openTools, 'Open', 'Open') : 'Complete', chipCls: openTools ? 'chip warn' : 'chip ok' });
        }
        return rows.map((r) => ({ ...r, hasHref: !!r.href }));
    }
    get planMix() {
        const by = {};
        this.plans.forEach((p) => { if (p.type) { by[p.type] = (by[p.type] || 0) + 1; } });
        return Object.keys(by).map((t) => by[t] + ' ' + t).join(', ');
    }

    // ---- steps 2 to 4: what CQ holds today
    get hasCauses() { return (this.v.causes || []).length > 0; }
    get causeRows() {
        return (this.v.causes || []).map((c) => ({ key: c.id, href: this.href(c.id), category: this.dash(c.category), code: this.dash(c.code),
            description: this.dash(c.description), verified: c.verified ? 'Verified' : 'Not Verified', vCls: c.verified ? 'chip ok' : 'chip' }));
    }
    get hasTools() { return (this.v.tools || []).length > 0; }
    get toolRows() {
        return (this.v.tools || []).map((t) => ({ key: t.id, href: this.href(t.id), name: t.name, type: this.dash(t.type), status: this.dash(t.status),
            sCls: t.status === 'Complete' ? 'chip ok' : 'chip warn' }));
    }

    // ---- step 5: Actions
    get planRows() {
        const types = this.v.planTypes || [];
        return this.plans.map((p, i) => ({ ...p, idx: i,
            typeOpts: types.map((t) => ({ label: t, pressed: String(p.type === t), cls: 'opt sm' + (p.type === t ? ' on' : '') })) }));
    }
    get hasPlans() { return this.plans.length > 0; }
    editPlan(i, fn) {
        this.plans = this.plans.map((p, j) => (j === i ? fn({ ...p }) : p));
        this.plansDirty = true;
        this.error = undefined;
        this.notice = undefined;
    }
    handlePlanType(event) {
        const t = event.currentTarget.dataset.type;
        this.editPlan(Number(event.currentTarget.dataset.i), (p) => { p.type = t; return p; });
    }
    handlePlanField(event) {
        const k = event.currentTarget.dataset.f;
        const val = event.target.value;
        this.editPlan(Number(event.currentTarget.dataset.i), (p) => { p[k] = val; return p; });
    }
    handlePlanOwner(event) {
        const id = event.detail ? event.detail.recordId : null;
        this.editPlan(Number(event.currentTarget.dataset.i), (p) => { p.userId = id; return p; });
    }
    handleAddPlan() {
        this.plans = [...this.plans, { key: 'p' + (this.keySeq++), id: null, title: '', type: null, due: this.todayIso(30), userId: null }];
        this.plansDirty = true;
        this.notice = undefined;
    }
    handleRemovePlan(event) {
        const i = Number(event.currentTarget.dataset.i);
        this.plans = this.plans.filter((p, j) => j !== i);
        this.plansDirty = true;
        this.notice = undefined;
    }
    planBlocker() {
        for (let i = 0; i < this.plans.length; i++) {
            const p = this.plans[i];
            const name = 'Action ' + (i + 1) + ': ';
            if (!(p.title || '').trim()) { return name + 'say what is to be done'; }
            if (!p.type) { return name + 'choose a type'; }
            if (!p.due) { return name + 'enter a due date'; }
        }
        return null;
    }
    planPayload() {
        return JSON.stringify(this.plans.map((p) => ({ id: p.id, title: (p.title || '').trim(), type: p.type, due: p.due, userId: p.userId })));
    }
    async handleSaveActions() {
        if (this.cantSaveActions) { return; }
        this.saving = true;
        this.error = undefined;
        try {
            const saved = await saveActions({ recordId: this.v.investigationId, payload: this.planPayload() });
            this.plans = saved.map((p) => ({ key: 'p' + (this.keySeq++), id: p.id, title: p.title, type: p.type, due: p.due, userId: p.userId }));
            this.plansDirty = false;
            this.notice = 'Saved as ' + this.plural(saved.length, 'CQ action plan', 'CQ action plans') + ' on ' + this.v.investigationName + '.';
        } catch (e) {
            this.error = this.msg(e, 'The actions were not saved.');
        } finally {
            this.saving = false;
        }
    }

    // ---- step 6: Conclusion
    get conclusionOpts() {
        return (this.v.conclusions || []).map((c) => ({ label: c, pressed: String(this.conclusion === c), cls: 'opt' + (this.conclusion === c ? ' on' : '') }));
    }
    handleConclusion(event) { this.conclusion = event.currentTarget.dataset.c; this.error = undefined; }
    handleSummary(event) { this.summary = event.target.value; this.summaryDrafted = false; this.error = undefined; }
    get draftSummary() {
        const v = this.v;
        const paras = [];
        paras.push((v.description || v.title || '').trim());
        if (v.dispositionText) { paras.push('Disposition: ' + v.dispositionText + '.'); }
        const causes = v.causes || [];
        if (causes.length) {
            paras.push('Root cause: ' + causes.map((c) => [c.category, c.code].filter((x) => x).join(', ') + (c.description ? ': ' + c.description : '')).join('; ') + '.');
        }
        const acts = this.plans.filter((p) => (p.title || '').trim());
        if (acts.length) { paras.push('Actions: ' + acts.map((p) => p.title.trim() + (p.type ? ' (' + p.type + ')' : '')).join('; ') + '.'); }
        return paras.filter((p) => p).join('\n\n');
    }
    handleDraft() { this.summary = this.draftSummary; this.summaryDrafted = true; this.error = undefined; }
    get canDraft() { return !!this.draftSummary; }
    get cantDraft() { return !this.canDraft; }
    get noCauseWarn() { return this.conclusion === 'Confirmed' && !(this.v.causes || []).length; }
    get completeLabel() {
        if (this.saving) { return this.v.needsApproval ? 'Submitting…' : 'Completing…'; }
        return this.v.needsApproval ? 'Submit for Approval' : 'Complete Investigation';
    }
    get onCompleteText() {
        const nc = this.v.ncName || 'the NC';
        return this.v.needsApproval
            ? 'CQ saves the conclusion, summary and actions, and sends the investigation for approval. Once it is approved, ' + nc + ' moves to Implement and the actions are made.'
            : 'CQ saves the conclusion, summary and actions, completes the investigation and moves ' + nc + ' to Implement. Each action plan becomes a CQ action with its owner and due date.';
    }
    conclusionBlocker() {
        if (!this.conclusion) { return 'Choose a conclusion'; }
        if (!(this.summary || '').trim()) { return 'Write the investigation summary'; }
        const pb = this.planBlocker();
        if (pb) { return pb + ' (Actions step)'; }
        return null;
    }

    // ---- footer
    get blocker() {
        if (this.showActions) { return this.planBlocker(); }
        if (this.showConclusion) { return this.conclusionBlocker(); }
        return null;
    }
    get cantSaveActions() { return this.saving || !this.plansDirty || !!this.planBlocker(); }
    get saveActionsLabel() { return this.saving ? 'Saving…' : 'Save Actions'; }
    get cantComplete() { return this.saving || !!this.conclusionBlocker(); }
    get cantBack() { return this.step === 0; }
    get cantNext() { return this.step >= STEPS.length - 1; }
    get nextCls() { return 'btn' + (this.cantNext ? '' : ' primary'); }

    go(i) {
        this.step = i;
        this.seen = { ...this.seen, [i]: true };
        this.error = undefined;
        this.notice = undefined;
        if (i === 5 && !(this.summary || '').trim() && this.canDraft) { this.handleDraft(); }
    }
    handleStep(event) { if (!this.isDone) { this.go(Number(event.currentTarget.dataset.i)); } }
    handleBack() { if (this.step > 0) { this.go(this.step - 1); } }
    handleNext() { if (this.step < STEPS.length - 1) { this.go(this.step + 1); } }

    async handleComplete() {
        if (this.cantComplete) { return; }
        this.saving = true;
        this.error = undefined;
        try {
            this.result = await completeInvestigation({ recordId: this.v.investigationId, conclusion: this.conclusion,
                summary: this.summary.trim(), actionsPayload: this.planPayload() });
            this.plansDirty = false;
            this.waitForCq();
        } catch (e) {
            this.error = this.msg(e, 'The investigation was not submitted.');
        } finally {
            this.saving = false;
        }
    }

    /** CQ finishes the submission in the background, a few seconds later; check back until it has. */
    async waitForCq() {
        this.waiting = true;
        for (let i = 0; i < POLL_TRIES; i++) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            await new Promise((resolve) => { setTimeout(resolve, POLL_MS); });
            await this.load(false);
            if (this.v && (this.v.isComplete || this.v.inApproval)) { break; }
        }
        this.waiting = false;
        const ids = [{ recordId: this.v.investigationId }];
        if (this.v.ncId) { ids.push({ recordId: this.v.ncId }); }
        try { await notifyRecordUpdateAvailable(ids); } catch (e) { /* the page refreshes on its own later */ }
        this.dispatchEvent(new CustomEvent('changed'));
    }

    // ---- done
    get doneHeading() {
        if (this.waiting) { return this.result && this.result.needsApproval ? 'Submitting for Approval…' : 'Completing the Investigation…'; }
        if (this.v.inApproval) { return 'Investigation Submitted for Approval'; }
        if (this.v.isComplete) { return 'Investigation Complete'; }
        return 'Investigation Submitted';
    }
    get doneOk() { return !this.waiting && (this.v.isComplete || this.v.inApproval); }
    get stillWaiting() { return !this.waiting && !this.v.isComplete && !this.v.inApproval; }
    get doneRows() {
        const v = this.v;
        const causes = v.causes || [];
        const rows = [
            { key: 'c', k: 'Conclusion', v: this.dash(v.conclusion || this.conclusion) },
            { key: 'rc', k: 'Root Causes', v: causes.length ? causes.map((c) => [c.code || c.category, c.description].filter((x) => x).join(': ')).join(' · ') : 'None recorded' },
            { key: 'a', k: 'Actions', v: this.plans.length ? this.planMix : 'None' },
            { key: 'r', k: 'Response', v: this.dash((this.result && this.result.responseName) || v.responseName) }
        ];
        if (this.result && this.result.toolsCompleted && this.result.toolsCompleted.length) {
            rows.push({ key: 't', k: 'Tools Completed', v: this.result.toolsCompleted.join(', ') });
        }
        if (v.isComplete) {
            rows.push({ key: 'by', k: 'Completed By', v: [v.completedBy, v.completedOn ? this.dateText(v.completedOn) : null].filter((x) => x).join(' · ') || '—' });
            rows.push({ key: 'n', k: 'Next', v: (v.ncName || 'The NC') + ' is in ' + this.dash(v.ncStage) + (v.openActions ? ': ' + this.plural(v.openActions, 'action is', 'actions are') + ' open.' : '.') });
        } else if (v.inApproval) {
            rows.push({ key: 'n', k: 'Next', v: 'The approvers review it; once approved, ' + (v.ncName || 'the NC') + ' moves to Implement.' });
        }
        return rows;
    }
    handleFinish() {
        this.result = undefined;
        this.step = 0;
        this.seen = { 0: true };
        this.load(true);
    }
}
