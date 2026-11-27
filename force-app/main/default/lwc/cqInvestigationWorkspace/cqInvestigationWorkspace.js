import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable, getRecord } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqInvestigationWorkspace.getView';
import saveActions from '@salesforce/apex/CqInvestigationWorkspace.saveActions';
import completeInvestigation from '@salesforce/apex/CqInvestigationWorkspace.completeInvestigation';
import suggestSummary from '@salesforce/apex/CqInvestigationSummary.suggest';
import getChanges from '@salesforce/apex/CqInvestigationChanges.getChanges';
import addChange from '@salesforce/apex/CqInvestigationChanges.addChange';
import addHypothesis from '@salesforce/apex/CqInvestigationChanges.addHypothesis';
import getHistory from '@salesforce/apex/CqInvestigationHistory.getHistory';
import markNotRelevant from '@salesforce/apex/CqInvestigationHistory.markNotRelevant';
import restoreRecord from '@salesforce/apex/CqInvestigationHistory.restore';
import { sortRows, nextSort, heads } from 'c/cqSort';

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
const LOOK_BACK = [14, 30, 60, 90];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const LANE_H = 34;       // height of one row of numbered markers on the What Changed chart
const MARK_GAP = 22;     // markers closer than this (percent of the chart's width) go on the next row up, so their labels do not touch
const WC_PAGE = 5;       // changes per page in the What Changed table, numbered on the chart beside it (Lou, 27 Nov)
const KIND_LABEL = { change: 'Change Order', document: 'Document', revision: 'Part Revision', deviation: 'Deviation', lot: 'Lot', calibration: 'Calibration', manual: 'Added by You' };
const RATING_CLS = { 'Could Explain It': 'cq-pill soft warn', 'Worth a Look': 'cq-pill soft ai', 'The Affected Lot': 'cq-pill soft neu', Unlikely: 'cq-pill soft neu' };
const MATCH_TONE = { red: 'crit', yellow: 'warn' };
const RATING_RANK = { 'Could Explain It': 1, 'Worth a Look': 2, 'The Affected Lot': 3, Unlikely: 4 };   // most likely first when sorted up
// the tables' columns (c/cqSort): each heading sorts its table; the action column does not
const COLS = {
    known: [{ key: 'source', label: 'Source' }, { key: 'says', label: 'What It Says' }, { key: 'chip', label: 'Status' }],
    chg: [{ key: 'n', label: '', sortable: false, cls: 'wc-ncol' }, { key: 'name', label: 'Change' }, { key: 'whatChanged', label: 'What Changed' },
        { key: 'ratingN', label: 'CQ.AI Says' }, { key: 'act', label: '', sortable: false }],
    hist: [{ key: 'name', label: 'Record' }, { key: 'what', label: 'What Happened' }, { key: 'cause', label: 'Root Cause' },
        { key: 'fix', label: 'How It Was Fixed' }, { key: 'matchN', label: 'Match' }, { key: 'act', label: '', sortable: false }],
    oth: [{ key: 'name', label: 'Record' }, { key: 'what', label: 'What Happened' }, { key: 'matchN', label: 'Match' }, { key: 'act', label: '', sortable: false }],
    plan: [{ key: 'title', label: 'Title' }, { key: 'descText', label: 'Description' }, { key: 'type', label: 'Type' },
        { key: 'ownerText', label: 'Owner' }, { key: 'due', label: 'Due' }, { key: 'act', label: '', sortable: false }]
};
const POLL_TRIES = 8;

/**
 * CQ.AI Investigation workspace: the investigation's record header, then six steps in the page.
 * Built: Investigation at a Glance, What Changed (timeline of changes CQ holds, changes added by hand,
 * Add as Hypothesis), Check History (past records ranked like the Product History Review, and the problem
 * that happened before after a fix), Find the Cause (c-cq-investigation-cause: hypotheses with evidence, Is / Is Not,
 * 5 Why and root causes), Actions and Conclusion with Complete Investigation.
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
    sumWriting = false;    // CQ.AI Suggested Summary: the prompt template is writing
    sumWritten;            // the text CQ.AI wrote last, to tell whether it was edited since
    sumError;
    sumConfirm = false;    // Write It Again over edited text asks first
    sumFill = false;
    saving = false;
    result;                // what Complete Investigation did
    waiting = false;       // CQ finishes the submission a few seconds later
    keySeq = 0;

    connectedCallback() { this.load(true); this.loadHistory(); }

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
        this.plans = (this.v.plans || []).map((p) => ({ key: 'p' + (this.keySeq++), id: p.id, title: p.title, description: p.description, type: p.type, due: p.due, userId: p.userId, userName: p.userName }));
        this.plansDirty = false;
        this.conclusion = this.v.conclusion;
        this.summary = this.v.summary || '';
        this.sumWritten = undefined;
        this.sumConfirm = false;
        this.sumError = undefined;
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
    get riskCls() { return 'cq-hl-v lvl ' + (this.v.risk ? this.v.risk.toLowerCase() : ''); }   // the Risk tile on the glance
    get dueText() { return this.dateText(this.v.due); }
    get ownerText() { return this.dash(this.v.owner); }
    get lotText() { return this.dash(this.v.lot); }
    get ncHref() { return this.href(this.v.ncId); }
    get partHref() { return '/lightning/r/compliancequest__SQX_Part__c/' + this.v.partId + '/view'; }
    /** The header fields the shared frame (c-cq-ws-shell) draws; the risk level in its colour. */
    get headerFields() {
        const tone = { low: 'pos', medium: 'warn', high: 'crit' }[(this.v.risk || '').toLowerCase()];
        return [
            { key: 'nc', label: 'Nonconformance', value: this.v.ncName, id: this.v.ncId },
            { key: 'part', label: 'Part', value: this.v.partNumber, id: this.v.partId },
            { key: 'lot', label: 'Lot', value: this.lotText },
            { key: 'status', label: 'Status', value: this.statusText },
            { key: 'risk', label: 'Risk', value: this.riskText, tone },
            { key: 'due', label: 'Investigation Due', value: this.dueText },
            { key: 'owner', label: 'Owner', value: this.ownerText }
        ];
    }
    /** A header link (the nonconformance, the part) opens in a new tab, as it did before the shared frame. */
    handleShellOpen(event) { window.open(this.href(event.detail), '_blank'); }
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
            this.changedSub || (this.seen[1] || done ? 'Reviewed' : 'Not Reviewed'),
            this.historySub || (this.seen[2] || done ? 'Reviewed' : 'Not Reviewed'),
            this.causeSub(causes),
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
    causeSub(causes) {
        const c = this.causeState;
        if (c && c.confirmed + c.ruledOut + c.open > 0) {
            return [c.confirmed ? c.confirmed + ' Confirmed' : null, c.ruledOut ? c.ruledOut + ' Ruled Out' : null, c.open ? c.open + ' Open' : null].filter((x) => x).join(' · ');
        }
        return causes ? this.plural(causes, 'Root Cause', 'Root Causes') : 'No Root Cause Yet';
    }
    /** The rail as the shared frame draws it. */
    get railSteps() { return this.steps.map((s) => ({ label: s.label, sub: s.sub, done: s.done, active: s.cls.includes('active') })); }
    get notDone() { return !this.showDone; }
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
    get recurGlance() {
        const r = this.recurrence;
        if (!r) { return null; }
        return 'This happened before: ' + r.name + ' (' + this.mdIso(r.day) + ') had the same problem, and ' + r.capaName
            + (this.isEffective(r) ? ' was marked effective on ' + this.mdIso(r.efrDate) + ', yet it came back.' : ' did not stop it coming back.');
    }
    get nextText() {
        if (!(this.v.causes || []).length) { return 'Review What Changed and Check History, then record the cause in Find the Cause.'; }
        if (!this.plans.length) { return 'Plan the actions that fix the cause, then conclude.'; }
        return 'Check the actions, then conclude and complete the investigation.';
    }
    // ---- sorting: one sort per table, by heading click
    sorts = {};
    get knownHeads() { return heads(COLS.known, this.sorts.known); }
    get chgHeads() { return heads(COLS.chg, this.sorts.chg); }
    get histHeads() { return heads(COLS.hist, this.sorts.hist); }
    get othHeads() { return heads(COLS.oth, this.sorts.oth); }
    get planHeads() { return heads(COLS.plan, this.sorts.plan); }
    handleSort(event) {
        const d = event.currentTarget.dataset;
        this.sorts = { ...this.sorts, [d.t]: nextSort(this.sorts[d.t], d.key) };
        if (d.t === 'chg') { this.wcPage = 1; this.wcTip = null; }
        if (d.t === 'hist') { this.histPage = 1; }
    }
    get knownRows() { return sortRows(this.knownList, this.sorts.known); }
    get knownList() {
        const v = this.v;
        const causes = v.causes || [];
        const tools = v.tools || [];
        const openTools = tools.filter((t) => t.status !== 'Complete').length;
        const rows = [
            { key: 'tri', source: v.ncName + ' Triage', href: this.ncHref, says: [v.risk ? 'Risk ' + v.risk : null, v.path].filter((x) => x).join('; ') || 'Triaged',
                chip: 'Triaged', chipCls: 'cq-pill soft pos' }
        ];
        if (v.dispositionRequired) {
            rows.push({ key: 'disp', source: v.ncName + ' Disposition', href: this.ncHref, says: v.dispositionText || 'No disposition completed yet',
                chip: v.dispositionComplete ? 'Complete' : 'Open', chipCls: v.dispositionComplete ? 'cq-pill soft pos' : 'cq-pill soft warn' });
        }
        rows.push({ key: 'rc', source: 'Root Causes', says: causes.length ? causes.map((c) => c.code || c.category).join('; ') : 'None recorded yet',
            chip: causes.length ? this.plural(causes.length, 'Recorded', 'Recorded') : 'To Find', chipCls: causes.length ? 'cq-pill soft pos' : 'cq-pill soft warn' });
        rows.push({ key: 'ap', source: 'Actions', says: this.plans.length ? this.planMix : 'None planned yet',
            chip: this.plans.length ? 'Planned' : 'To Plan', chipCls: this.plans.length ? 'cq-pill soft pos' : 'cq-pill soft warn' });
        if (tools.length) {
            rows.push({ key: 'tl', source: 'Analysis Tools', says: tools.map((t) => (t.type || 'Tool') + ' ' + t.name).join('; '),
                chip: openTools ? this.plural(openTools, 'Open', 'Open') : 'Complete', chipCls: openTools ? 'cq-pill soft warn' : 'cq-pill soft pos' });
        }
        return rows.map((r) => ({ ...r, hasHref: !!r.href }));
    }
    get planMix() {
        const by = {};
        this.plans.forEach((p) => { if (p.type) { by[p.type] = (by[p.type] || 0) + 1; } });
        return Object.keys(by).map((t) => by[t] + ' ' + t).join(', ');
    }

    // ---- step 4: Find the Cause (its own component; the footer's Save Root Causes and blocker come from it)
    causeState;
    handleCauseState(event) { this.causeState = event.detail; }
    get showSaveRoots() { return this.showCause && !!this.causeState && this.causeState.showSave; }
    get cantSaveRoots() { return !this.causeState || !this.causeState.canSave; }
    get saveRootsLabel() { return this.causeState && this.causeState.saving ? 'Saving…' : 'Save Root Causes'; }
    handleSaveRoots() { const c = this.template.querySelector('c-cq-investigation-cause'); if (c) { c.saveRoots(); } }
    async handleCauseChanged() { await this.load(false); }
    handleCauseAddHyp(event) {
        const d = event.detail;
        const t = d.text.replace(/;\s*no hypothesis covers it\.?$/, '').replace(/^[^:]+:\s*/, '').replace(/,\s*[^,]*before the start$/, '');
        this.hypForm = { from: 'cause', key: 'c:' + d.sourceId, title: t.charAt(0).toUpperCase() + t.slice(1) + ' (' + d.name + ')', category: d.category,
            sourceId: d.sourceId, sourceName: d.name, fromName: d.name, fromHref: this.href(d.sourceId), fromText: d.text, fromSub: 'CQ.AI Suggests a Hypothesis' };
        this.hypFocus = true;
    }
    // Ask CQ.AI: Add to Evidence under an answer while Find the Cause is open
    get pinLabel() { return this.showCause ? 'Add to Evidence' : null; }
    handleAskPin(event) { const c = this.template.querySelector('c-cq-investigation-cause'); if (c) { c.pin(event.detail); } }

    // ---- step 5: Actions: a table of the planned actions; Add Action and Edit open a popup
    get planList() {
        return this.plans.map((p, i) => ({ key: p.key, idx: i, title: p.title, descText: this.planDesc(p), type: p.type || '—',
            ownerText: p.userName || (p.userId ? 'Chosen' : 'You'), due: p.due, dueText: this.dateText(p.due), unsaved: !p.id }));
    }
    get planRows() { return sortRows(this.planList, this.sorts.plan); }
    get hasPlans() { return this.plans.length > 0; }
    /** CQ fills an empty description with the title, so the same text is not shown twice. */
    planDesc(p) { return p.description && p.description.trim() !== (p.title || '').trim() ? p.description : ''; }
    planForm;              // the Add Action / Edit popup: { idx (null for a new action), title, description, type, due, userId, userName }
    @wire(getRecord, { recordId: '$planUserId', fields: ['User.Name'] })
    wiredPlanUser({ data }) {
        if (data && this.planForm && this.planForm.userId === data.id) { this.planForm = { ...this.planForm, userName: data.fields.Name.value }; }
    }
    get planUserId() { return this.planForm && this.planForm.userId ? this.planForm.userId : undefined; }
    get planFormOpen() { return !!this.planForm; }
    get planFormTitle() { return this.planForm && this.planForm.idx !== null ? 'Edit Action' : 'Add Action'; }
    get planFormSaveLabel() { return this.planForm && this.planForm.idx !== null ? 'Save Action' : 'Add Action'; }
    get planFormTypes() {
        const t = this.planForm ? this.planForm.type : null;
        return (this.v.planTypes || []).map((x) => ({ label: x, pressed: String(t === x), cls: 'cq-chip' }));
    }
    get planFormBlocker() {
        const f = this.planForm || {};
        if (!(f.title || '').trim()) { return 'Give it a title'; }
        if (!f.type) { return 'Choose a type'; }
        if (!f.due) { return 'Enter a due date'; }
        return '';
    }
    get cantSavePlanForm() { return !!this.planFormBlocker; }
    handleAddPlan() {
        this.planForm = { idx: null, title: '', description: '', type: null, due: this.todayIso(30), userId: null, userName: null };
        this.planFocus = true;
    }
    handleEditPlan(event) {
        const i = Number(event.currentTarget.dataset.i);
        const p = this.plans[i];
        this.planForm = { idx: i, title: p.title, description: this.planDesc(p), type: p.type, due: p.due, userId: p.userId, userName: p.userName };
        this.planFocus = true;
    }
    handlePlanFormInput(event) { this.planForm = { ...this.planForm, [event.currentTarget.dataset.f]: event.target.value }; }
    handlePlanFormType(event) { this.planForm = { ...this.planForm, type: event.currentTarget.dataset.type }; }
    handlePlanFormOwner(event) {
        const id = event.detail ? event.detail.recordId : null;
        this.planForm = { ...this.planForm, userId: id, userName: id ? this.planForm.userName : null };
    }
    handlePlanFormCancel() { this.planForm = undefined; }
    handlePlanFormKey(event) { if (event.key === 'Escape') { this.handlePlanFormCancel(); } }
    handlePlanFormSave() {
        if (this.cantSavePlanForm) { return; }
        const f = this.planForm;
        const row = { title: f.title.trim(), description: (f.description || '').trim(), type: f.type, due: f.due, userId: f.userId, userName: f.userId ? f.userName : null };
        if (f.idx === null) {
            this.plans = [...this.plans, { key: 'p' + (this.keySeq++), id: null, ...row }];
        } else {
            this.plans = this.plans.map((p, j) => (j === f.idx ? { ...p, ...row } : p));
        }
        this.plansDirty = true;
        this.planForm = undefined;
        this.error = undefined;
        this.notice = undefined;
    }
    /** Placeholder: the Action Plan Document (an FDA warning letter response or an 8D customer report) is not built yet. */
    planDocNote;
    handlePlanDoc() { this.planDocNote = 'Not built yet. It will turn these actions into an FDA warning letter response or an 8D customer report.'; }
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
            if (!(p.title || '').trim()) { return name + 'give it a title'; }
            if (!p.type) { return name + 'choose a type'; }
            if (!p.due) { return name + 'enter a due date'; }
        }
        return null;
    }
    planPayload() {
        return JSON.stringify(this.plans.map((p) => ({ id: p.id, title: (p.title || '').trim(), description: (p.description || '').trim(), type: p.type, due: p.due, userId: p.userId })));
    }
    async handleSaveActions() {
        if (this.cantSaveActions) { return; }
        this.saving = true;
        this.error = undefined;
        try {
            const saved = await saveActions({ recordId: this.v.investigationId, payload: this.planPayload() });
            this.plans = saved.map((p) => ({ key: 'p' + (this.keySeq++), id: p.id, title: p.title, description: p.description, type: p.type, due: p.due, userId: p.userId, userName: p.userName }));
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
        return (this.v.conclusions || []).map((c) => ({ label: c, pressed: String(this.conclusion === c), cls: 'cq-chip' }));
    }
    handleConclusion(event) { this.conclusion = event.currentTarget.dataset.c; this.error = undefined; }
    handleSummary(event) { this.summary = event.target.value; this.sumConfirm = false; this.error = undefined; }
    // CQ.AI Suggested Summary: the prompt template writes Problem, Containment, Hypotheses, Root Cause and Actions
    // from the investigation; the actions on screen are sent too, so unsaved ones are included
    get sumLabel() { return this.sumWriting ? 'Writing…' : this.sumWritten !== undefined ? 'Write It Again' : 'CQ.AI Suggested Summary'; }
    get sumNote() {
        if (this.sumWriting) { return null; }
        return this.sumWritten !== undefined ? 'Written by CQ.AI from this investigation. Read it and edit before you complete.'
            : 'Written from the NC, disposition, hypotheses, root causes and actions.';
    }
    get showSumBox() { return !this.sumWriting; }
    handleSuggestSummary() {
        const now = (this.summary || '').trim();
        const edited = now && now !== (this.sumWritten || '').trim();
        if (edited) { this.sumConfirm = true; return; }
        this.writeSummary();
    }
    handleSumReplace() { this.writeSummary(); }
    handleSumKeep() { this.sumConfirm = false; }
    async writeSummary() {
        this.sumConfirm = false;
        this.sumError = undefined;
        this.error = undefined;
        this.sumWriting = true;
        try {
            const text = await suggestSummary({ recordId: this.v.investigationId, actionsPayload: this.planPayload() });
            this.summary = text;
            this.sumWritten = text;
        } catch (e) {
            this.sumError = this.msg(e, 'CQ.AI could not write the summary just now. Try again, or write it yourself.');
        } finally {
            this.sumWriting = false;
            this.sumFill = true;
        }
    }
    get recurWarn() {
        const r = this.recurrence;
        if (!r) { return null; }
        const fixes = this.plans.some((p) => p.type === 'Corrective' || p.type === 'Preventive');
        if (fixes) { return null; }
        return 'This problem happened before (' + r.name + ') and ' + r.capaName + ' did not hold. Plan a corrective or preventive action that deals with why, or escalate to a CAPA.';
    }
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

    // ---- step 2: What Changed
    wc;                    // CqInvestigationChanges.View
    wcDays = 30;
    wcLoading = false;
    wcError;
    hypForm;               // { key, title, category, sourceId, sourceName }
    changeForm;            // { whatChanged, changeDate, category, whereFound, reference }
    wcSaving = false;
    wcNotice;
    wcPage = 1;            // the What Changed table's page
    wcTip;                 // the key of the chart marker being hovered or focused (its bubble shows)
    lbOpen = false;        // the Look back menu

    async loadChanges() {
        this.wcLoading = true;
        this.wcError = undefined;
        this.wcPage = 1;
        this.wcTip = null;
        try {
            this.wc = await getChanges({ recordId: this.recordId, days: this.wcDays });
        } catch (e) {
            this.wcError = this.msg(e, 'Could not read the changes.');
        } finally {
            this.wcLoading = false;
        }
    }
    get wcReady() { return !!this.wc && !this.wcLoading; }
    // Look back: a link on the chart that opens a menu of periods
    get lookBackOpts() {
        return LOOK_BACK.map((d) => ({ d, label: d + ' days', checked: String(d === this.wcDays), tick: d === this.wcDays ? '✓' : '',
            cls: 'wc-lbitem' + (d === this.wcDays ? ' on' : '') }));
    }
    get lbExpanded() { return String(this.lbOpen); }
    toggleLookBack() { this.lbOpen = !this.lbOpen; }
    closeLookBack() { this.lbOpen = false; }
    handleLbKey(event) { if (event.key === 'Escape' && this.lbOpen) { event.stopPropagation(); this.lbOpen = false; } }
    handleLookBack(event) {
        const d = Number(event.currentTarget.dataset.d);
        this.lbOpen = false;
        if (d === this.wcDays) { return; }
        this.wcDays = d;
        this.hypForm = undefined;
        this.loadChanges();
    }
    dn(iso) { const p = iso.split('-'); return Date.UTC(Number(p[0]), Number(p[1]) - 1, Number(p[2])) / 86400000; }
    md(iso) { if (!iso) { return '—'; } const p = iso.split('-'); return MONTHS[Number(p[1]) - 1] + ' ' + Number(p[2]); }
    get startText() { return this.wc ? this.md(this.wc.startDate) : ''; }
    get startFromText() { return this.wc ? (this.wc.startFrom === 'Occurrence Date' ? "the NC's Occurrence Date" : this.wc.startFrom === 'Aware Date' ? "the NC's Aware Date" : 'the day the NC was created') : ''; }
    get changedSub() {
        if (!this.wc) { return null; }
        const could = this.wc.items.filter((i) => i.rating === 'Could Explain It').length;
        const h = this.wc.hypotheses.length;
        return could + ' Could Explain It' + (h ? ' · ' + h + (h === 1 ? ' Hypothesis' : ' Hypotheses') : '');
    }
    get standOut() {
        if (!this.wc) { return null; }
        const items = this.wc.items;
        const could = items.filter((i) => i.rating === 'Could Explain It');
        const lines = [];
        if (could.length) {
            const named = could.map((i) => i.name + ' (' + (i.inEffect ? 'since ' : '') + this.md(i.day) + ')');
            lines.push(could.length + (could.length === 1 ? ' change lands' : ' changes land') + ' within 14 days of the start: ' + this.joinAnd(named) + '.');
        } else {
            lines.push('Nothing CQ holds changed in the 14 days before the start.');
        }
        const dev = items.filter((i) => i.inEffect && i.rating !== 'Could Explain It');
        if (dev.length) { lines.push(dev.length + (dev.length === 1 ? ' supplier deviation was' : ' supplier deviations were') + ' already in effect on the part or its components.'); }
        const lot = items.find((i) => i.kind === 'lot' && i.day);
        if (lot) { lines.push(lot.name + ' was built ' + this.md(lot.day) + '.'); }
        const cal = items.find((i) => i.kind === 'calibration');
        if (cal) { lines.push(cal.name.replace(' Calibration', '') + ': ' + cal.whatChanged.charAt(0).toLowerCase() + cal.whatChanged.slice(1) + '.'); }
        return lines.join(' ');
    }
    /** What Stands Out's opening (to the first colon, else the first sentence) in bold, the rest after it. */
    get standOutLead() {
        const s = this.standOut || '';
        const c = s.indexOf(': ');
        const dot = s.indexOf('. ');
        if (c > -1 && (dot < 0 || c < dot)) { return s.slice(0, c + 1); }
        return dot > -1 ? s.slice(0, dot + 1) : s;
    }
    get standOutRest() { return (this.standOut || '').slice(this.standOutLead.length); }
    joinAnd(a) { return a.length > 1 ? a.slice(0, -1).join(', ') + ' and ' + a[a.length - 1] : a[0]; }

    // the chart: each change on the table's page as a numbered marker (rows up when they crowd), the others as faint dots,
    // a band for each deviation in effect, the start marker; hovering or focusing a number shows its bubble
    get timeline() {
        const v = this.wc;
        if (!v) { return null; }
        const from = this.dn(v.windowStart);
        const to = this.dn(v.startDate) + 2;
        const span = to - from;
        const pct = (iso) => Math.max(0, Math.min(100, ((this.dn(iso) - from) / span) * 100));
        const all = this.changeAll;
        const byKey = new Map(all.map((r) => [r.key, r]));
        const onPage = new Set(this.changeRows.map((r) => r.key));
        const points = v.items.filter((i) => i.onTimeline && !i.inEffect && i.day);
        const lanes = [];
        const marks = points.filter((i) => onPage.has(i.key)).map((i) => ({ i, x: pct(i.day) })).sort((a, b) => a.x - b.x).map((m) => {
            let lane = 0;
            while (lane < 3 && lanes[lane] !== undefined && m.x - lanes[lane] < MARK_GAP) { lane++; }
            lanes[lane] = m.x;
            return { ...m, lane };
        });
        const nLanes = Math.max(1, lanes.length);
        const axis = 30 + nLanes * LANE_H;
        const bandsIn = v.items.filter((i) => i.inEffect);
        const startX = pct(v.startDate);
        const step = v.days <= 14 ? 3 : v.days <= 30 ? 7 : v.days <= 60 ? 14 : 21;
        const ticks = [];
        for (let d = 0; d <= span - 2; d += step) {
            const x = (d / span) * 100;
            if (startX - x < 14) { continue; }
            const dt = new Date((from + d) * 86400000);
            ticks.push({ key: 't' + d, label: MONTHS[dt.getUTCMonth()] + ' ' + dt.getUTCDate(), cls: 'wc-tickl' + (d === 0 ? ' first' : ''), x });
        }
        ticks.push({ key: 'tstart', label: this.md(v.startDate) + ' · Start', cls: 'wc-tickl start', x: startX });
        const closeA = pct(this.isoAdd(v.startDate, -14) < v.windowStart ? v.windowStart : this.isoAdd(v.startDate, -14));
        let tip = null;
        const shown = marks.map((m) => {
            const r = byKey.get(m.i.key) || {};
            const lot = m.i.kind === 'lot';
            const top = axis - 40 - m.lane * LANE_H;
            if (this.wcTip === m.i.key) {
                const shift = m.x > 72 ? 'calc(-100% + 12px)' : m.x < 20 ? '-12px' : '-50%';
                tip = { cls: 'wc-tip' + (lot ? ' lot' : ''), head: m.i.name + ' · ' + this.md(m.i.day), text: m.i.whatChanged, rel: r.rel,
                    style: 'left: ' + m.x + '%; top: ' + (top - 6) + 'px; transform: translate(' + shift + ', -100%);' };
            }
            return { key: m.i.key, kStem: 's:' + m.i.key, kKind: 'k:' + m.i.key, n: r.n,
                aria: r.n + ': ' + m.i.name + ', ' + this.md(m.i.day) + '. ' + (m.i.whatChanged || ''),
                cls: 'wc-num' + (lot ? ' lot' : ''), style: 'left: ' + m.x + '%; top: ' + top + 'px;',
                stemCls: 'wc-stem' + (lot ? ' lot' : ''), stem: 'left: ' + m.x + '%; top: ' + (top + 24) + 'px; height: ' + (axis - top - 24) + 'px;',
                kind: KIND_LABEL[m.i.kind] || m.i.foundIn, kindCls: 'wc-kind' + (lot ? ' lot' : ''),
                kindStyle: 'left: ' + m.x + '%; top: ' + (top + 4) + 'px; transform: ' + (m.x > 75 ? 'translateX(calc(-100% - 16px))' : 'translateX(16px)') + ';' };
        });
        return {
            height: 'height: ' + (axis + 30 + bandsIn.length * 22 + (bandsIn.length ? 4 : 0)) + 'px;',
            axis: 'top: ' + axis + 'px;',
            shade: 'top: ' + (axis - 10) + 'px; left: ' + closeA + '%; width: ' + (startX - closeA) + '%;',
            start: 'top: ' + (axis - 7) + 'px; left: ' + startX + '%;',
            ticks: ticks.map((t) => ({ ...t, style: 'top: ' + (axis + 10) + 'px; left: ' + t.x + '%;' })),
            others: points.filter((i) => !onPage.has(i.key)).map((i) => ({ key: 'o:' + i.key, cls: 'wc-dot' + (i.kind === 'lot' ? ' lot' : ''),
                style: 'top: ' + (axis - 3) + 'px; left: ' + pct(i.day) + '%;' })),
            marks: shown,
            bands: bandsIn.map((i, k) => {
                const a = pct(i.day < v.windowStart ? v.windowStart : i.day);
                const b = i.untilDay && i.untilDay < v.startDate ? pct(i.untilDay) : 100;
                const r = byKey.get(i.key);
                const label = i.name + ' · in effect ' + this.md(i.day) + (i.untilDay ? ' to ' + this.md(i.untilDay) : '');
                return { key: i.key, n: r ? r.n : '', label, style: 'top: ' + (axis + 30 + k * 22) + 'px; left: ' + a + '%; width: ' + Math.max(b - a, 2) + '%;' };
            }),
            tip
        };
    }
    handleTip(event) { this.wcTip = event.currentTarget.dataset.key; }
    handleTipOff() { this.wcTip = null; }
    isoAdd(iso, days) { const d = new Date((this.dn(iso) + days) * 86400000); return d.toISOString().slice(0, 10); }
    shortText(t) { if (!t) { return ''; } const s = t.split(': ').pop(); return s.length > 60 ? s.slice(0, 57) + '…' : s; }
    get hasBands() { return this.timeline && this.timeline.bands.length > 0; }

    /** Every change in the table's order, numbered; the same number marks it on the chart. */
    get changeAll() { return sortRows(this.changeList, this.sorts.chg).map((r, i) => ({ ...r, n: i + 1 })); }
    get wcPageCount() { return Math.max(1, Math.ceil(this.changeList.length / WC_PAGE)); }
    get wcPageNow() { return Math.min(this.wcPage, this.wcPageCount); }
    get changeRows() {
        const p = this.wcPageNow;
        return this.changeAll.slice((p - 1) * WC_PAGE, p * WC_PAGE)
            .map((r) => ({ ...r, numCls: 'wc-num sm' + (!r.onChart ? ' off' : r.inEffect ? ' dev' : r.kind === 'lot' ? ' lot' : '') }));
    }
    get wcPaged() { return this.changeList.length > WC_PAGE; }
    get cantPrevWc() { return this.wcPageNow <= 1; }
    get cantNextWc() { return this.wcPageNow >= this.wcPageCount; }
    get wcPageItems() { return this.pageItems(this.wcPageCount, this.wcPageNow); }
    /** Page numbers for a cqStyles pager: all of them up to 7, else the first, the last and the two beside the current one, with dots between. */
    pageItems(n, now) {
        const want = n <= 7 ? Array.from({ length: n }, (x, i) => i + 1)
            : [...new Set([1, now - 1, now, now + 1, n])].filter((p) => p >= 1 && p <= n).sort((a, b) => a - b);
        const out = [];
        want.forEach((p, i) => {
            if (i && p - want[i - 1] > 1) { out.push({ key: 'g' + p, p: 0, text: '…', cls: 'pg gap', off: true, label: 'More pages' }); }
            out.push({ key: 'p' + p, p, text: String(p), cls: 'pg' + (p === now ? ' on' : ''), off: p === now, current: p === now ? 'page' : null, label: 'Page ' + p });
        });
        return out;
    }
    handleWcPage(event) { const p = Number(event.currentTarget.dataset.p); if (p) { this.wcPage = p; this.wcTip = null; } }
    handleWcPrev() { if (!this.cantPrevWc) { this.wcPage = this.wcPageNow - 1; this.wcTip = null; } }
    handleWcNext() { if (!this.cantNextWc) { this.wcPage = this.wcPageNow + 1; this.wcTip = null; } }
    get changeList() {
        if (!this.wc) { return []; }
        const start = this.dn(this.wc.startDate);
        return this.wc.items.map((i) => {
            const before = i.day ? start - this.dn(i.day) : null;
            let rel;
            if (i.inEffect) { rel = 'In effect' + (i.untilDay && i.untilDay < this.wc.startDate ? ' until ' + this.md(i.untilDay) : ' throughout'); }
            else if (i.rating === 'Unlikely') { rel = 'Unchanged'; }
            else if (before === null) { rel = ''; }
            else if (before === 0) { rel = 'The start date'; }
            else { rel = before + (before === 1 ? ' day before' : ' days before'); }
            return {
                key: i.key, name: i.name, href: i.recordId && !i.byHand ? this.href(i.recordId) : null, byHand: i.byHand, kind: i.kind,
                onChart: !!(i.inEffect || (i.onTimeline && i.day)), inEffect: !!i.inEffect,
                hasHref: !!(i.recordId && !i.byHand), category: i.category, whatChanged: i.whatChanged, foundIn: i.foundIn,
                whenText: i.inEffect ? 'Since ' + this.md(i.day) : this.md(i.day), rel, rating: i.rating, ratingN: RATING_RANK[i.rating] || 5, day: i.day, ratingCls: RATING_CLS[i.rating] || 'cq-pill soft neu',
                added: i.hypothesis ? '✓ Added as H' + i.hypothesis : null,
                canAdd: !i.hypothesis && i.rating !== 'The Affected Lot' && i.rating !== 'Unlikely'
            };
        });
    }
    get hasChanges() { return this.wc && this.wc.items.length > 0; }

    // Add as Hypothesis: a popup, prefilled from the change
    handleHypOpen(event) {
        const i = this.wc.items.find((x) => x.key === event.currentTarget.dataset.key);
        const t = this.shortText(i.whatChanged);
        this.hypForm = { key: i.key, title: t.charAt(0).toUpperCase() + t.slice(1) + (i.byHand ? '' : ' (' + i.name + ')'), category: i.category, sourceId: i.recordId, sourceName: i.name,
            fromName: i.byHand ? 'Added by You' : i.name, fromHref: i.recordId && !i.byHand ? this.href(i.recordId) : null, fromText: i.whatChanged,
            fromSub: [i.foundIn, i.rating].filter((x) => x).join(' · ') };
        this.hypFocus = true;
        this.wcError = undefined;
        this.wcNotice = undefined;
    }
    handleHypCancel() { this.hypForm = undefined; }
    handleHypTitle(event) { this.hypForm = { ...this.hypForm, title: event.target.value }; }
    handleHypKey(event) { if (event.key === 'Escape') { this.handleHypCancel(); } }
    get hypOpen() { return !!this.hypForm; }
    get hypFromHasHref() { return !!(this.hypForm && this.hypForm.fromHref); }
    hypFocus = false;
    planFocus = false;
    renderedCallback() {
        if (this.sumFill) {
            const st = this.template.querySelector('textarea.summary');
            if (st) { this.sumFill = false; st.value = this.summary || ''; }
        }
        if (this.planFocus) {
            const pt = this.template.querySelector('.planta');
            const pd = this.template.querySelector('textarea.plandesc');
            if (pt) {
                this.planFocus = false;
                // the value binding alone can leave them empty on open
                pt.value = (this.planForm && this.planForm.title) || '';
                if (pd) { pd.value = (this.planForm && this.planForm.description) || ''; }
                pt.focus();
            }
        }
        if (!this.hypFocus) { return; }
        const ta = this.template.querySelector('textarea.hypta');
        if (!ta) { return; }
        this.hypFocus = false;
        // set the prefilled text on the element itself: the value binding alone left it empty on first open
        ta.value = (this.hypForm && this.hypForm.title) || '';
        ta.focus();
        const n = ta.value.length;
        try { ta.setSelectionRange(n, n); } catch (e) { /* not all inputs allow it */ }
    }
    handleHypCat(event) { this.hypForm = { ...this.hypForm, category: event.currentTarget.dataset.c }; }
    get hypCatOpts() {
        const c = this.hypForm ? this.hypForm.category : null;
        const cats = this.wc ? this.wc.categories : this.hist ? this.hist.categories : [];
        return cats.map((x) => ({ label: x, pressed: String(c === x), cls: 'cq-chip' }));
    }
    get hypBlocker() {
        const f = this.hypForm;
        if (!f) { return null; }
        const t = (f.title || '').trim();
        if (!t || t.endsWith(':')) { return 'Finish the hypothesis'; }
        if (!f.category) { return 'Choose a category'; }
        return null;
    }
    get cantAddHyp() { return this.wcSaving || !!this.hypBlocker; }
    async handleHypSave() {
        if (this.cantAddHyp) { return; }
        this.wcSaving = true;
        try {
            const from = this.hypForm.from;
            const n = await addHypothesis({ recordId: this.recordId, payload: JSON.stringify({ title: this.hypForm.title.trim(), category: this.hypForm.category, sourceId: this.hypForm.sourceId, sourceName: this.hypForm.sourceName }) });
            const note = 'Added as H' + n + '. Test it in Find the Cause.';
            if (from === 'hist') { this.histNotice = note; } else if (from !== 'cause') { this.wcNotice = note; }
            if (from === 'cause') { const c = this.template.querySelector('c-cq-investigation-cause'); if (c) { c.refresh(); } }
            this.hypForm = undefined;
            const loads = [this.loadHistory(true)];
            if (this.wc) { loads.push(this.loadChanges()); }
            await Promise.all(loads);
        } catch (e) {
            if (this.hypForm && this.hypForm.from === 'hist') { this.histError = this.msg(e, 'The hypothesis was not saved.'); } else if (this.hypForm && this.hypForm.from === 'cause') { this.error = this.msg(e, 'The hypothesis was not saved.'); } else { this.wcError = this.msg(e, 'The hypothesis was not saved.'); }
        } finally {
            this.wcSaving = false;
        }
    }

    // + Add a Change
    handleChangeOpen() {
        this.changeForm = { whatChanged: '', changeDate: this.wc ? this.wc.startDate : null, category: null, whereFound: '', reference: '' };
        this.wcNotice = undefined;
    }
    handleChangeCancel() { this.changeForm = undefined; }
    handleChangeField(event) { this.changeForm = { ...this.changeForm, [event.currentTarget.dataset.f]: event.target.value }; }
    handleChangeCat(event) { this.changeForm = { ...this.changeForm, category: event.currentTarget.dataset.c }; }
    get changeCatOpts() {
        const c = this.changeForm ? this.changeForm.category : null;
        return (this.wc ? this.wc.changeCategories : []).map((x) => ({ label: x, pressed: String(c === x), cls: 'cq-chip' }));
    }
    get changeBlocker() {
        const f = this.changeForm;
        if (!f) { return null; }
        if (!(f.whatChanged || '').trim()) { return 'Say what changed'; }
        if (!f.changeDate) { return 'Enter when'; }
        if (!f.category) { return 'Choose a category'; }
        return null;
    }
    get cantSaveChange() { return this.wcSaving || !!this.changeBlocker; }
    get cantSaveChangeHyp() { return this.cantSaveChange || this.changeForm.category === 'Other'; }
    handleChangeSave() { this.saveChange(false); }
    handleChangeSaveHyp() { this.saveChange(true); }
    async saveChange(withHyp) {
        if (withHyp ? this.cantSaveChangeHyp : this.cantSaveChange) { return; }
        this.wcSaving = true;
        this.wcError = undefined;
        const f = this.changeForm;
        try {
            const id = await addChange({ recordId: this.recordId, payload: JSON.stringify(f) });
            let note = 'Change saved.';
            if (withHyp) {
                const n = await addHypothesis({ recordId: this.recordId, payload: JSON.stringify({ title: f.whatChanged, category: f.category, sourceId: id, sourceName: 'Added by You' }) });
                note = 'Change saved and added as H' + n + '.';
            }
            this.changeForm = undefined;
            this.wcNotice = note;
            await this.loadChanges();
        } catch (e) {
            this.wcError = this.msg(e, 'The change was not saved.');
        } finally {
            this.wcSaving = false;
        }
    }
    get hypRows() {
        return (this.wc ? this.wc.hypotheses : []).map((h) => ({ key: h.id, label: 'H' + h.num + (h.category ? ' · ' + h.category : ''), title: h.title,
            status: h.status, statusCls: h.status === 'Confirmed' ? 'cq-pill soft pos' : h.status === 'Ruled Out' ? 'cq-pill soft neu' : 'cq-pill soft warn', source: h.source }));
    }
    get hasHyps() { return this.hypRows.length > 0; }

    // ---- step 3: Check History
    hist;                  // CqInvestigationHistory.View
    histLoading = false;
    histError;
    histNotice;
    histShowOthers = false;
    histBusy = false;
    histPage = 1;          // the Check History table shows 5 records a page (Lou, 27 Nov)

    async loadHistory(quiet) {
        if (!quiet) { this.histLoading = true; this.histPage = 1; }
        this.histError = undefined;
        try {
            this.hist = await getHistory({ recordId: this.recordId });
        } catch (e) {
            this.histError = this.msg(e, 'Could not read the history.');
        } finally {
            this.histLoading = false;
        }
    }
    get histReady() { return !!this.hist && !this.histLoading; }
    mdIso(iso) { return iso ? this.md(iso) : '—'; }
    isEffective(i) { return !!(i && i.efrResolution && i.efrResolution.indexOf('Effective') >= 0 && i.efrResolution.indexOf('Ineffective') < 0); }
    get recurrence() { return this.hist && this.hist.recurrences.length ? this.hist.recurrences[0] : null; }
    get historySub() {
        if (!this.hist) { return null; }
        const n = this.hist.items.length;
        return (this.recurrence ? '1 Fix Didn’t Hold · ' : '') + (n ? n + ' to Review' : 'Nothing Similar');
    }
    get histStandOut() {
        const h = this.hist;
        if (!h) { return null; }
        const lines = [];
        const r = this.recurrence;
        if (r) {
            lines.push('One past case on this part had the same problem: ' + r.name + ' (' + this.mdIso(r.day) + ')' + (r.causeNote ? ', caused by ' + r.causeNote.charAt(0).toLowerCase() + r.causeNote.slice(1) : '') + '.');
            lines.push('Its fix (' + r.capaName + ')' + (this.isEffective(r) ? ' was marked effective on ' + this.mdIso(r.efrDate) + ',' : ' closed') + ' yet the problem is back.');
        }
        const open = h.items.filter((i) => i.type === 'Nonconformance' && i !== r && (i.status === 'Open' || i.status === 'Draft'));
        if (open.length) { lines.push(this.joinAnd(open.map((i) => i.name)) + (open.length === 1 ? ' is' : ' are') + ' still open on a similar problem.'); }
        const ins = h.items.filter((i) => i.type === 'Inspection');
        if (ins.length) { lines.push(ins.length + (ins.length === 1 ? ' inspection' : ' inspections') + ' on this part failed.'); }
        if (!lines.length) { lines.push(h.items.length ? h.items.length + ' past records match this problem.' : 'Nothing in CQ matches this problem on this part.'); }
        return lines.join(' ');
    }
    get recurBoxes() {
        return (this.hist ? this.hist.recurrences : []).map((r) => ({
            key: 'rec:' + r.key, ncName: r.name, ncHref: this.href(r.recordId), capaName: r.capaName, capaHref: this.href(r.capaId),
            text1: ' had the same problem on ' + this.mdIso(r.day) + (r.causeNote ? ', traced to ' + r.causeNote.charAt(0).toLowerCase() + r.causeNote.slice(1) : '') + '. ',
            text2: ' (' + (r.capaTitle || 'CAPA') + ') closed' + (r.capaClosed ? ' on ' + this.mdIso(r.capaClosed) : '') + ', but the problem came back on ' + this.mdIso(this.hist.startDate) + '.',
            histKey: r.key, efrCls: this.isEffective(r) ? 'lh redtext' : 'lh', effective: this.isEffective(r), efrName: r.efrName, efrHref: r.efrId ? this.href(r.efrId) : null,
            efrText: r.efrId ? (this.isEffective(r)
                ? ' marked ' + r.capaName + ' ' + r.efrResolution + ' on ' + this.mdIso(r.efrDate) + ', yet the same problem came back on ' + this.mdIso(this.hist.startDate) + '.'
                : ' rated ' + r.capaName + ' ' + r.efrResolution + ' on ' + this.mdIso(r.efrDate) + '.') : null,
            noReview: !r.efrId,
            added: r.hypothesis ? '✓ Added as H' + r.hypothesis : null, canAdd: !r.hypothesis
        }));
    }
    get hasRecur() { return this.recurBoxes.length > 0; }
    histRow(i) {
        let cause = i.causeHead;
        let causeNote = i.causeNote;
        if (!cause) {
            cause = i.investigationName ? 'Not found yet' : 'None recorded';
            causeNote = i.investigationName ? i.investigationName + ' is ' + (i.causeNote || 'open') : null;
        }
        let fix = null;
        let fixNote;
        if (i.capaId) {
            fix = i.capaName;
            const bits = [i.capaStatus + (i.capaClosed ? ' ' + this.mdIso(i.capaClosed) : '')];
            if (i.efrId) { bits.push((this.isEffective(i) ? 'marked effective ' : i.efrResolution + ' ') + this.mdIso(i.efrDate) + ' (' + i.efrName + ')'); }
            fixNote = bits.join('; ');
        } else {
            fixNote = i.status === 'Closed' || i.status === 'Complete' ? 'Closed, no CAPA' : i.status;
        }
        return {
            key: i.key, name: i.name, href: this.href(i.recordId),
            sub: (i.status || '') + (i.day ? ' · ' + this.mdIso(i.day) : ''), what: i.whatHappened,
            cause, causeNote, causeIsNone: !i.causeHead, invHref: i.investigationId ? this.href(i.investigationId) : null,
            fix, fixHref: i.capaId ? this.href(i.capaId) : null, capaTitle: i.capaTitle, fixNote, effective: this.isEffective(i),
            matchText: (i.colour || 'Grey') + ' · ' + (i.score || 0), matchN: i.score || 0, matchCls: 'cq-pill soft ' + (MATCH_TONE[(i.colour || 'Grey').toLowerCase()] || 'neu'), why: i.why,
            matchBtnCls: 'mbtn cq-pill soft ' + (MATCH_TONE[(i.colour || 'Grey').toLowerCase()] || 'neu'),
            added: i.hypothesis ? '✓ Added as H' + i.hypothesis : null, canAdd: !i.hypothesis
        };
    }
    /** The Match pill's hover card: which of the three rules the record meets, and why (Lou, 27 Nov). */
    matchCard(i) {
        const st = (i.status || '').toLowerCase();
        const open = st === 'open' || st === 'draft' || st === 'in progress';
        const rule = (key, name, met, why) => ({ key, name, why, mark: met ? '✓' : '–', markCls: 'mmark' + (met ? ' on' : ''), nameCls: 'mname' + (met ? '' : ' off') });
        const rules = [
            rule('p', 'Part', i.partMet, i.partMet ? (i.why || 'Same part').split(' · ')[0] : 'No link to this part'),
            rule('s', 'Problem', i.symptomMet, i.symptomMet ? (i.type === 'Inspection' ? 'A failed inspection' : 'A similar problem') : 'Not a similar problem'),
            rule('c', 'Open or recent', i.currentMet, i.currentMet ? (open ? 'Still open' : 'Made in the last 30 days') : (i.status || 'Closed') + (i.day ? ', ' + this.mdIso(i.day) : ''))
        ];
        if (i.lotMet) { rules.push(rule('l', 'Same lot', true, 'On this NC\'s lot')); }
        const met = [i.partMet, i.symptomMet, i.currentMet].filter((x) => x).length;
        const colour = i.colour || 'Grey';
        return { head: colour + ': meets ' + met + ' of 3 rules', headCls: 'mhead ' + (MATCH_TONE[colour.toLowerCase()] || 'neu'), rules };
    }
    histTip;               // the record whose Match card is showing: { key, style }
    handleMatchTip(event) {
        const el = event.currentTarget;
        const r = el.getBoundingClientRect();
        const below = r.bottom + 190 < window.innerHeight;
        const left = Math.max(8, r.right - 288);
        this.histTip = { key: el.dataset.key, style: 'left: ' + left + 'px; top: ' + (below ? r.bottom + 6 : r.top - 6) + 'px;' + (below ? '' : ' transform: translateY(-100%);') };
    }
    handleMatchTipOff() { this.histTip = undefined; }
    get matchTip() {
        if (!this.histTip) { return null; }
        const i = this.findHist(this.histTip.key);
        return i ? { ...this.matchCard(i), style: this.histTip.style } : null;
    }
    get histAll() { return this.hist ? sortRows(this.hist.items.map((i) => this.histRow(i)), this.sorts.hist) : []; }
    get histPageCount() { return Math.max(1, Math.ceil(this.histAll.length / WC_PAGE)); }
    get histPageNow() { return Math.min(this.histPage, this.histPageCount); }
    get histRows() { const p = this.histPageNow; return this.histAll.slice((p - 1) * WC_PAGE, p * WC_PAGE); }
    get hasHistRows() { return this.histAll.length > 0; }
    get histPaged() { return this.histAll.length > WC_PAGE; }
    get cantPrevHist() { return this.histPageNow <= 1; }
    get cantNextHist() { return this.histPageNow >= this.histPageCount; }
    get histPageItems() { return this.pageItems(this.histPageCount, this.histPageNow); }
    handleHistPage(event) { const p = Number(event.currentTarget.dataset.p); if (p) { this.histPage = p; this.histTip = undefined; } }
    handleHistPrev() { if (!this.cantPrevHist) { this.histPage = this.histPageNow - 1; } }
    handleHistNext() { if (!this.cantNextHist) { this.histPage = this.histPageNow + 1; } }
    get otherRows() { return this.hist ? sortRows(this.hist.others.map((i) => this.histRow(i)), this.sorts.oth) : []; }
    get otherCount() { return this.hist ? this.hist.others.length : 0; }
    get hasOthers() { return this.otherCount > 0; }
    get othersLabel() { return this.histShowOthers ? 'Hide Them' : 'Show Them'; }
    get othersText() {
        const eg = this.hist ? this.hist.others.slice(0, 2).map((i) => i.name + ' ' + (i.whatHappened || '').split(':')[0].toLowerCase()) : [];
        return 'on ' + (this.hist && this.hist.partNumber ? this.hist.partNumber : 'this part') + ' match the part only, not the problem' + (eg.length ? ' (for example ' + eg.join(', ') + ')' : '') + '.';
    }
    handleToggleOthers() { this.histShowOthers = !this.histShowOthers; }
    get dismissedRows() { return this.hist ? this.hist.dismissed.map((d) => ({ key: d.id, id: d.id, name: d.name })) : []; }
    get hasDismissed() { return this.dismissedRows.length > 0; }
    findHist(key) {
        const all = this.hist ? [...this.hist.items, ...this.hist.others] : [];
        return all.find((x) => x.key === key);
    }
    handleHistHypOpen(event) {
        const i = this.findHist(event.currentTarget.dataset.key);
        if (!i) { return; }
        this.hypForm = { from: 'hist', key: 'h:' + i.key, title: this.histHypTitle(i), category: i.category, sourceId: i.recordId, sourceName: i.name,
            fromName: i.name, fromHref: this.href(i.recordId), fromText: i.whatHappened,
            fromSub: i.causeHead ? 'Root cause: ' + i.causeHead + (i.causeNote ? ' · ' + i.causeNote : '') : null };
        this.hypFocus = true;
        this.histNotice = undefined;
        this.histError = undefined;
    }
    /** With a recorded cause, the cause itself; otherwise a start the investigator finishes (the cursor is left at the end). */
    histHypTitle(i) {
        if (i.causeHead && i.causeNote) { return i.causeNote.charAt(0).toUpperCase() + i.causeNote.slice(1) + ', as in ' + i.name; }
        const lot = /lot (\S+)/i.exec(i.whatHappened || '');
        if (i.type === 'Inspection') { return 'Same failure as ' + i.name + (lot ? ' (lot ' + lot[1].replace(/[,.;]$/, '') + ')' : '') + ': '; }
        return 'Same problem as ' + i.name + ': ';
    }
    async handleNotRelevant(event) {
        const i = this.findHist(event.currentTarget.dataset.key);
        if (!i || this.histBusy) { return; }
        this.histBusy = true;
        try {
            await markNotRelevant({ recordId: this.recordId, targetId: i.recordId, targetName: i.name, reason: null });
            this.histNotice = i.name + ' marked Not Relevant. Restore it below if that was a mistake.';
            await this.loadHistory(true);
        } catch (e) {
            this.histError = this.msg(e, 'It was not saved.');
        } finally {
            this.histBusy = false;
        }
    }
    async handleRestore(event) {
        const id = event.currentTarget.dataset.id;
        if (this.histBusy) { return; }
        this.histBusy = true;
        try {
            await restoreRecord({ dismissedId: id });
            this.histNotice = undefined;
            await this.loadHistory(true);
        } catch (e) {
            this.histError = this.msg(e, 'It was not restored.');
        } finally {
            this.histBusy = false;
        }
    }

    // ---- footer
    get blocker() {
        if (this.showCause) { return this.causeState ? this.causeState.blocker : null; }
        if (this.showActions) { return this.planBlocker(); }
        if (this.showConclusion) { return this.conclusionBlocker(); }
        return null;
    }
    get cantSaveActions() { return this.saving || !this.plansDirty || !!this.planBlocker(); }
    get saveActionsLabel() { return this.saving ? 'Saving…' : 'Save Actions'; }
    get cantComplete() { return this.saving || this.sumWriting || !!this.conclusionBlocker(); }
    get cantBack() { return this.step === 0; }
    get cantNext() { return this.step >= STEPS.length - 1; }
    get nextCls() { return this.cantNext ? 'cq-btn-outline' : 'cq-btn-primary'; }

    go(i) {
        if (i === 1 && !this.wc && !this.wcLoading) { this.loadChanges(); }
        this.step = i;
        this.seen = { ...this.seen, [i]: true };
        this.error = undefined;
        this.notice = undefined;
        if (i === 5) { this.sumFill = true; } // the value binding alone can leave the box empty when the step opens
    }
    handleStep(event) { if (!this.isDone) { this.go(Number(event.detail)); } }
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
