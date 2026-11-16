import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqInvestigationWorkspace.getView';
import saveActions from '@salesforce/apex/CqInvestigationWorkspace.saveActions';
import completeInvestigation from '@salesforce/apex/CqInvestigationWorkspace.completeInvestigation';
import getChanges from '@salesforce/apex/CqInvestigationChanges.getChanges';
import addChange from '@salesforce/apex/CqInvestigationChanges.addChange';
import addHypothesis from '@salesforce/apex/CqInvestigationChanges.addHypothesis';
import getHistory from '@salesforce/apex/CqInvestigationHistory.getHistory';
import markNotRelevant from '@salesforce/apex/CqInvestigationHistory.markNotRelevant';
import restoreRecord from '@salesforce/apex/CqInvestigationHistory.restore';

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
const LANE_H = 58;       // height of one row of timeline labels
const LABEL_W = 24;      // width of a timeline label, as a percent of the track
const RATING_CLS = { 'Could Explain It': 'chip warn', 'Worth a Look': 'chip ai', 'The Affected Lot': 'chip', Unlikely: 'chip' };
const POLL_TRIES = 8;

/**
 * CQ.AI Investigation workspace: the investigation's record header, then six steps in the page.
 * Built: Investigation at a Glance, What Changed (timeline of changes CQ holds, changes added by hand,
 * Add as Hypothesis), Check History (past records ranked like the Product History Review, and the problem
 * that happened before after a fix), Actions and Conclusion with Complete Investigation. Find the Cause shows
 * what CQ already holds and is built next.
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
            this.changedSub || (this.seen[1] || done ? 'Reviewed' : 'Not Reviewed'),
            this.historySub || (this.seen[2] || done ? 'Reviewed' : 'Not Reviewed'),
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

    async loadChanges() {
        this.wcLoading = true;
        this.wcError = undefined;
        try {
            this.wc = await getChanges({ recordId: this.recordId, days: this.wcDays });
        } catch (e) {
            this.wcError = this.msg(e, 'Could not read the changes.');
        } finally {
            this.wcLoading = false;
        }
    }
    get wcReady() { return !!this.wc && !this.wcLoading; }
    get lookBackOpts() {
        return LOOK_BACK.map((d) => ({ d, label: d + ' Days', pressed: String(d === this.wcDays), cls: 'opt sm' + (d === this.wcDays ? ' on' : '') }));
    }
    handleLookBack(event) {
        const d = Number(event.currentTarget.dataset.d);
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
    joinAnd(a) { return a.length > 1 ? a.slice(0, -1).join(', ') + ' and ' + a[a.length - 1] : a[0]; }

    // the timeline: dots and labels for dated changes, a band for each deviation in effect, the start marker
    get timeline() {
        const v = this.wc;
        if (!v) { return null; }
        const from = this.dn(v.windowStart);
        const to = this.dn(v.startDate) + 2;
        const span = to - from;
        const pct = (iso) => Math.max(0, Math.min(100, ((this.dn(iso) - from) / span) * 100));
        const step = v.days <= 14 ? 3 : v.days <= 30 ? 7 : v.days <= 60 ? 14 : 21;
        const ticks = [];
        for (let d = 0; d <= span - 2; d += step) {
            const dt = new Date((from + d) * 86400000);
            ticks.push({ key: 't' + d, label: MONTHS[dt.getUTCMonth()] + ' ' + dt.getUTCDate(), x: (d / span) * 100 });
        }
        const events = v.items.filter((i) => i.onTimeline && !i.inEffect).map((i) => ({
            key: i.key, x: pct(i.day), head: this.md(i.day) + ' · ' + i.name.replace(/^Lot /, ''),
            text: i.kind === 'lot' ? 'The affected lot is built' : this.shortText(i.whatChanged), kind: i.kind === 'lot' ? 'lot' : 'change' }));
        events.push({ key: 'start', x: pct(v.startDate), head: this.md(v.startDate) + ' · Problem Starts', text: 'Start (' + v.startFrom + ')', kind: 'start' });
        events.sort((a, b) => a.x - b.x);
        // lay labels into lanes: up 1, down 1, up 2, down 2 ... the first lane where it does not overlap
        const lanes = {};
        const order = ['u1', 'd1', 'u2', 'd2', 'u3', 'd3'];
        events.forEach((e) => {
            e.right = e.x > 55;
            const lo = e.right ? e.x - LABEL_W : e.x;
            const hi = e.right ? e.x : e.x + LABEL_W;
            e.lane = order.find((l) => !(lanes[l] || []).some((r) => lo < r[1] && hi > r[0])) || 'u3';
            (lanes[e.lane] = lanes[e.lane] || []).push([lo - 1, hi + 1]);
        });
        const ups = Math.max(1, ...events.filter((e) => e.lane[0] === 'u').map((e) => Number(e.lane[1])));
        const downs = Math.max(0, ...events.filter((e) => e.lane[0] === 'd').map((e) => Number(e.lane[1])));
        const bandsIn = v.items.filter((i) => i.inEffect);
        const bandTop = ups * LANE_H + 6;
        const axis = bandTop + bandsIn.length * 22 + 28;
        const bands = bandsIn.map((i, k) => {
            const a = pct(i.day < v.windowStart ? v.windowStart : i.day);
            const b = i.untilDay && i.untilDay < v.startDate ? pct(i.untilDay) : 100;
            return { key: i.key, style: 'top: ' + (bandTop + k * 22) + 'px; left: ' + a + '%; width: ' + Math.max(b - a, 2) + '%;',
                label: i.name + ' · in effect ' + this.md(i.day) + (i.untilDay ? ' to ' + this.md(i.untilDay) : '') };
        });
        const closeA = pct(this.isoAdd(v.startDate, -14) < v.windowStart ? v.windowStart : this.isoAdd(v.startDate, -14));
        return {
            height: 'height: ' + (axis + 16 + downs * LANE_H) + 'px;',
            axis: 'top: ' + axis + 'px;',
            shade: 'top: ' + (axis - 13) + 'px; left: ' + closeA + '%; width: ' + (pct(v.startDate) - closeA) + '%;',
            ticks: ticks.map((t) => ({ ...t, style: 'top: ' + (axis - 18) + 'px; left: ' + t.x + '%;' + (t.x === 0 ? '' : ' transform: translateX(-50%);') })),
            bands,
            events: events.map((e) => {
                const up = e.lane[0] === 'u';
                const n = Number(e.lane[1]);
                const top = up ? (ups - n) * LANE_H : axis + 16 + (n - 1) * LANE_H;
                const lineTop = up ? top + 44 : axis + 6;
                const lineH = up ? axis - lineTop : top - axis - 6;
                return { key: e.key, kLine: 'l:' + e.key, kDot: 'd:' + e.key, head: e.head, text: e.text,
                    dot: 'top: ' + (axis - 7) + 'px; left: ' + e.x + '%;', dotCls: 'tl-dot ' + e.kind,
                    line: 'top: ' + lineTop + 'px; height: ' + Math.max(lineH, 0) + 'px; left: ' + e.x + '%;', lineCls: 'tl-line ' + e.kind,
                    box: 'top: ' + top + 'px; ' + (e.right ? 'right: ' + (100 - e.x) + '%; margin-right: -10px; text-align: right;' : 'left: ' + e.x + '%; margin-left: -10px;'),
                    boxCls: 'tl-box ' + e.kind };
            })
        };
    }
    isoAdd(iso, days) { const d = new Date((this.dn(iso) + days) * 86400000); return d.toISOString().slice(0, 10); }
    shortText(t) { if (!t) { return ''; } const s = t.split(': ').pop(); return s.length > 60 ? s.slice(0, 57) + '…' : s; }
    get hasBands() { return this.timeline && this.timeline.bands.length > 0; }

    get changeRows() {
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
            const open = this.hypForm && this.hypForm.key === i.key;
            return {
                key: i.key, formKey: i.key + ':form', name: i.name, href: i.recordId && !i.byHand ? this.href(i.recordId) : null, byHand: i.byHand,
                hasHref: !!(i.recordId && !i.byHand), category: i.category, whatChanged: i.whatChanged, foundIn: i.foundIn,
                whenText: i.inEffect ? 'Since ' + this.md(i.day) : this.md(i.day), rel, rating: i.rating, ratingCls: RATING_CLS[i.rating] || 'chip',
                added: i.hypothesis ? '✓ Added as H' + i.hypothesis : null,
                canAdd: !i.hypothesis && i.rating !== 'The Affected Lot' && i.rating !== 'Unlikely' && !open, open
            };
        });
    }
    get hasChanges() { return this.wc && this.wc.items.length > 0; }

    // Add as Hypothesis: an inline form under the row, prefilled from the change
    handleHypOpen(event) {
        const i = this.wc.items.find((x) => x.key === event.currentTarget.dataset.key);
        const t = this.shortText(i.whatChanged);
        this.hypForm = { key: i.key, title: t.charAt(0).toUpperCase() + t.slice(1) + (i.byHand ? '' : ' (' + i.name + ')'), category: i.category, sourceId: i.recordId, sourceName: i.name };
        this.wcError = undefined;
        this.wcNotice = undefined;
    }
    handleHypCancel() { this.hypForm = undefined; }
    handleHypTitle(event) { this.hypForm = { ...this.hypForm, title: event.target.value }; }
    handleHypCat(event) { this.hypForm = { ...this.hypForm, category: event.currentTarget.dataset.c }; }
    get hypCatOpts() {
        const c = this.hypForm ? this.hypForm.category : null;
        const cats = this.wc ? this.wc.categories : this.hist ? this.hist.categories : [];
        return cats.map((x) => ({ label: x, pressed: String(c === x), cls: 'opt sm' + (c === x ? ' on' : '') }));
    }
    get cantAddHyp() { return this.wcSaving || !this.hypForm || !(this.hypForm.title || '').trim() || !this.hypForm.category; }
    async handleHypSave() {
        if (this.cantAddHyp) { return; }
        this.wcSaving = true;
        try {
            const from = this.hypForm.from;
            const n = await addHypothesis({ recordId: this.recordId, payload: JSON.stringify(this.hypForm) });
            const note = 'Added as H' + n + '. Test it in Find the Cause.';
            if (from === 'hist') { this.histNotice = note; } else { this.wcNotice = note; }
            this.hypForm = undefined;
            const loads = [this.loadHistory(true)];
            if (this.wc) { loads.push(this.loadChanges()); }
            await Promise.all(loads);
        } catch (e) {
            if (this.hypForm && this.hypForm.from === 'hist') { this.histError = this.msg(e, 'The hypothesis was not saved.'); } else { this.wcError = this.msg(e, 'The hypothesis was not saved.'); }
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
        return (this.wc ? this.wc.changeCategories : []).map((x) => ({ label: x, pressed: String(c === x), cls: 'opt sm' + (c === x ? ' on' : '') }));
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
            status: h.status, statusCls: h.status === 'Confirmed' ? 'chip ok' : h.status === 'Ruled Out' ? 'chip' : 'chip warn', source: h.source }));
    }
    get hasHyps() { return this.hypRows.length > 0; }

    // ---- step 3: Check History
    hist;                  // CqInvestigationHistory.View
    histLoading = false;
    histError;
    histNotice;
    histShowOthers = false;
    histBusy = false;

    async loadHistory(quiet) {
        if (!quiet) { this.histLoading = true; }
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
        const open = this.hypForm && this.hypForm.key === 'h:' + i.key;
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
            key: i.key, formKey: i.key + ':form', name: i.name, href: this.href(i.recordId),
            sub: (i.status || '') + (i.day ? ' · ' + this.mdIso(i.day) : ''), what: i.whatHappened,
            cause, causeNote, causeIsNone: !i.causeHead, invHref: i.investigationId ? this.href(i.investigationId) : null,
            fix, fixHref: i.capaId ? this.href(i.capaId) : null, capaTitle: i.capaTitle, fixNote, effective: this.isEffective(i),
            matchText: (i.colour || 'Grey') + ' · ' + (i.score || 0), matchCls: 'chip m-' + (i.colour || 'Grey').toLowerCase(), why: i.why,
            added: i.hypothesis ? '✓ Added as H' + i.hypothesis : null, canAdd: !i.hypothesis && !open, open
        };
    }
    get histRows() { return this.hist ? this.hist.items.map((i) => this.histRow(i)) : []; }
    get hasHistRows() { return this.histRows.length > 0; }
    get otherRows() { return this.hist ? this.hist.others.map((i) => this.histRow(i)) : []; }
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
        const what = (i.whatHappened || i.name).split(':')[0];
        const cause = i.causeNote && i.causeHead ? i.causeNote : what;
        this.hypForm = { from: 'hist', key: 'h:' + i.key, title: cause.charAt(0).toUpperCase() + cause.slice(1) + ', as in ' + i.name, category: i.category,
            sourceId: i.recordId, sourceName: i.name };
        this.histNotice = undefined;
        this.histError = undefined;
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
        if (i === 1 && !this.wc && !this.wcLoading) { this.loadChanges(); }
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
