import { LightningElement, api } from 'lwc';
import getNext from '@salesforce/apex/CqTriageNext.getNext';
import completeTriage from '@salesforce/apex/CqTriageNext.completeTriage';
import startTriage from '@salesforce/apex/CqTriageNext.startTriage';
import createContainment from '@salesforce/apex/CqTriageContainment.create';
import getRisk from '@salesforce/apex/CqTriageRisk.getRisk';
import notSameProblem from '@salesforce/apex/CqTriageRepeat.notSame';
import restoreRepeat from '@salesforce/apex/CqTriageRepeat.restore';
import saveRisk from '@salesforce/apex/CqTriageRisk.saveRisk';
import getLinks from '@salesforce/apex/CqTriageLinks.getLinks';
import getOne from '@salesforce/apex/CqTriageLinks.getOne';
import saveLinks from '@salesforce/apex/CqTriageLinks.saveLinks';
import getDraft from '@salesforce/apex/CqTriageDraft.getDraft';
import saveDraft from '@salesforce/apex/CqTriageDraft.saveDraft';
import userId from '@salesforce/user/Id';

const STEPS = ['Containment', 'Data Check', 'Risk', 'Next Steps'];
const SEV = ['Negligible', 'Low', 'Moderate', 'Significant', 'Catastrophic'];
const LIK = ['Improbable', 'Remote', 'Occasional', 'Probable', 'Frequent'];
const band = (n) => (n >= 15 ? 'High' : n >= 6 ? 'Medium' : 'Low');
const ASKS = ['More Photos', 'Measurements', 'When It Started', 'Other Lots Affected?'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const ESCALATE = 'Escalate to CAPA';
const LINK = 'Link to Earlier CAPA';
const NOT_NEEDED = 'Not Needed';
const LINK_PAGE = 5;   // investigations a page on Next Steps

/**
 * Triage Assistant: containment, data check, risk, investigation links. CQ.AI suggests, the triager decides.
 * As a popup it is those four steps. With inline set (Triage workspace) it sits in the page, Triage at a Glance
 * is slotted in as step 1, and work in progress is remembered on the record.
 */
export default class CqTriageAssistant extends LightningElement {
    @api recordId;
    @api glance;
    @api hasPhoto = false;
    @api inline = false;

    step = 0;
    maxStep = 0;
    started = false;    // triage has been started on the server this session (Draft -> Triage)
    seen = {};          // steps opened at least once: any step can be opened, but Complete Triage waits until each has been
    booted = false;
    resumed = false;
    done = false;
    finished = false;
    saving = false;
    error;
    warning;
    acts = {};
    noActionWhy = '';
    due;
    showAdd = false;
    cTitle = '';
    cDesc = '';
    cDue;
    cAssignee = userId;
    adding = false;
    addError;
    added = [];
    data = '';
    asks = {};
    askNote = '';
    rk;
    sev = 3;
    lik = 1;
    lk;
    picks = {};
    extra = [];
    sugPage = 0;
    otherPage = 0;
    linkError;
    summary = [];
    nx;                 // Next Steps: CQ.AI suggestions, default dates and approval matrices
    disp = '';          // 'req' or 'no'
    dispDue;
    dispAppr = false;
    inv = '';           // 'inv' or 'log'
    capa = '';          // the repeat: Escalate to CAPA, Link to Earlier CAPA or Not Needed
    capaReason = '';
    repBusy = false;
    invDue;
    invAppr = false;
    matrixId;

    async connectedCallback() {
        this.due = this.inDays(5);
        let draft;
        if (this.inline) {
            try { const d = await getDraft({ recordId: this.recordId }); draft = d ? JSON.parse(d) : null; } catch (e) { draft = null; }
        }
        if (draft && draft.v === 1) {
            ['step', 'maxStep', 'seen', 'acts', 'noActionWhy', 'due', 'added', 'data', 'asks', 'askNote', 'picks', 'extra', 'disp', 'dispDue', 'dispAppr', 'inv', 'invDue', 'invAppr', 'matrixId', 'capa', 'capaReason'].forEach((k) => { if (draft[k] !== undefined) { this[k] = draft[k]; } });
            // a draft saved before steps could be opened in any order: every step up to the furthest one was seen
            if (!draft.seen) { const m = {}; for (let i = 0; i <= this.maxStep; i++) { m[i] = true; } this.seen = m; }
            this.resumed = this.maxStep > 0;
        }
        this.seen = { ...this.seen, [this.step]: true };
        this.booted = true;
        if (this.step > 0) { this.ensureStarted(); }
        try {
            this.rk = await getRisk({ recordId: this.recordId });
        } catch (e) {
            this.rk = { count: 0, recent: [], severity: 3, severityAssumed: true, severityWhy: 'Assumed: could not read the record', likelihood: 1, likelihoodWhy: 'Could not count recent NCs', escaped: false };
        }
        const keep = draft && draft.v === 1 && draft.sev && draft.lik;
        this.sev = keep ? draft.sev : this.rk.severity;
        this.lik = keep ? draft.lik : this.rk.likelihood;
        try {
            this.lk = await getLinks({ recordId: this.recordId });
        } catch (e) {
            this.lk = { items: [] };
            this.linkError = 'Could not look for related investigations.';
        }
        try {
            this.nx = await getNext({ recordId: this.recordId });
        } catch (e) {
            this.nx = { matrices: [] };
        }
        if (!this.dispDue) { this.dispDue = this.nx.dispDue || this.inDays(5); }
        if (!this.invDue) { this.invDue = this.nx.invDue || this.inDays(60); }
        if (!this.matrixId) { this.matrixId = this.nx.defaultMatrixId; }
        this.preselect();
    }
    /** CQ.AI's suggestion starts selected, so its due date and approval show from the start; the triager clicks the other to change it. */
    preselect() {
        if (!this.nx) { return; }
        if (!this.disp && this.nx.dispSuggest) { this.disp = this.nx.dispSuggest; }
        if (!this.inv && this.nx.invSuggest) { this.inv = this.nx.invSuggest; }
        if (!this.capa && this.rep) { this.capa = ESCALATE; }
    }

    // ---- the repeat: the same problem happened before on the part after a CAPA closed
    get rep() { return this.rk && this.rk.repeat && this.rk.repeat.found ? this.rk.repeat : null; }
    md(iso) { if (!iso) { return ''; } const p = String(iso).split('-'); return MONTHS[Number(p[1]) - 1] + ' ' + Number(p[2]); }
    href(id) { return '/lightning/r/' + id + '/view'; }
    get repBox() {
        const r = this.rep;
        if (!r) { return null; }
        const cause = r.causeNote ? ', traced to ' + r.causeNote.charAt(0).toLowerCase() + r.causeNote.slice(1) : '';
        return {
            ncName: r.ncName, ncHref: this.href(r.ncId), capaName: r.capaName, capaHref: this.href(r.capaId),
            text1: ' had the same problem in ' + this.md(r.ncDay).split(' ')[0] + cause + '. ',
            text2: ' (' + (r.capaTitle || 'CAPA') + ') closed' + (r.capaClosed ? ' on ' + this.md(r.capaClosed) : '') + ', but the problem came back' + (r.startDate ? ' on ' + this.md(r.startDate) : '') + '.',
            efrName: r.efrName, efrHref: r.efrId ? this.href(r.efrId) : null,
            efrText: r.efrId ? (r.effective ? ' marked ' + r.capaName + ' ' + r.efrResolution + ' on ' + this.md(r.efrDate) + ', yet the same problem came back.'
                : ' rated ' + r.capaName + ' ' + r.efrResolution + ' on ' + this.md(r.efrDate) + '.') : null,
            efrCls: r.effective ? 'lh redtext' : 'lh',
            noReview: !r.efrId,
            changes: this.rk.repeatRaised ? 'the risk suggestion goes up one likelihood step, and Next Steps suggests Escalate to CAPA.'
                : 'Next Steps suggests Escalate to CAPA (the likelihood is already at its highest).'
        };
    }
    get repDismissed() {
        const d = this.rk && this.rk.repeat ? this.rk.repeat.dismissed || [] : [];
        return d.map((x) => ({ key: x.id, id: x.id, name: x.name }));
    }
    get hasRepDismissed() { return !this.rep && this.repDismissed.length > 0; }
    get showRepGlance() { return !this.done && !!this.repBox; }
    get showRepDismissed() { return !this.done && this.hasRepDismissed; }
    /** Not the same problem, or put back: the risk and next-step suggestions are worked out again. */
    async refreshAfterRepeat(call) {
        if (this.repBusy) { return; }
        this.repBusy = true;
        const wasSuggested = this.rk && this.sev === this.rk.severity && this.lik === this.rk.likelihood;
        try {
            await call();
            this.rk = await getRisk({ recordId: this.recordId });
            this.nx = await getNext({ recordId: this.recordId });
            if (wasSuggested) { this.sev = this.rk.severity; this.lik = this.rk.likelihood; }
            this.inv = this.nx.invSuggest || this.inv;
            this.capa = this.rep ? (this.capa || ESCALATE) : '';
            if (!this.rep) { this.capaReason = ''; }
            this.persist();
        } catch (e) {
            this.error = (e && e.body && e.body.message) || 'It was not saved.';
        }
        this.repBusy = false;
    }
    handleNotSame() {
        const r = this.rep;
        if (!r) { return; }
        this.refreshAfterRepeat(() => notSameProblem({ recordId: this.recordId, targetId: r.ncId, targetName: r.ncName }));
    }
    handleRepRestore(event) {
        const id = event.currentTarget.dataset.id;
        this.refreshAfterRepeat(() => restoreRepeat({ recordId: this.recordId, dismissedId: id }));
    }
    get likRaised() { return this.rk && this.rk.repeatRaised ? '(raised from ' + this.rk.baseLikelihood + ')' : ''; }
    get repRiskLine() {
        const r = this.rep;
        if (!r) { return ''; }
        const how = 'the same problem came back after ' + r.capaName + (r.effective ? ' was marked effective (' + r.efrName + ')' : ' closed') + '.';
        return this.rk.repeatRaised ? 'Raised one step: ' + how : 'Already at the highest likelihood; ' + how;
    }
    get capaOpts() {
        const r = this.rep;
        if (!r) { return []; }
        return [[ESCALATE, ESCALATE], [LINK, 'Link to ' + r.capaName], [NOT_NEEDED, NOT_NEEDED]].map(([id, label]) => ({ id, label,
            pressed: this.capa === id ? 'true' : 'false', cls: 'opt wide' + (this.capa === id ? ' on' : id === ESCALATE ? ' sug' : '') }));
    }
    handleCapa(event) { this.capa = event.currentTarget.dataset.id; this.persist(); }
    get capaWhy() { return this.nx && this.nx.capaWhy ? this.nx.capaWhy : ''; }
    get capaNeedsReason() { return !!this.rep && !!this.capa && this.capa !== ESCALATE; }
    get capaReasonOff() { return !this.capaNeedsReason; }
    get capaLinkName() { return this.rep ? this.rep.capaName : ''; }

    // tells the page which step is open, so Ask CQ.AI can answer for it
    renderedCallback() {
        const names = this.inline ? ['Triage at a Glance', ...STEPS] : STEPS;
        const now = this.done ? 'Triage complete' : names[this.step] || '';
        if (now !== this._toldStep) {
            this._toldStep = now;
            this.dispatchEvent(new CustomEvent('stepchange', { detail: { step: now } }));
        }
    }

    inDays(n) {
        const d = new Date(Date.now() + n * 86400000);
        const p = (n) => String(n).padStart(2, '0');
        return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate());
    }

    // ---- in the page (Triage workspace) or as a popup
    get off() { return this.inline ? 1 : 0; }
    get cur() { return this.step - this.off; }
    get last() { return STEPS.length - 1 + this.off; }
    get veilCls() { return 'veil' + (this.inline ? ' inline' : ''); }
    get boxCls() { return 'box' + (this.inline ? ' inline' : ''); }
    get dlgRole() { return this.inline ? undefined : 'dialog'; }
    get dlgModal() { return this.inline ? undefined : 'true'; }
    get heading() { return this.inline ? 'CQ.AI Triage' : 'Triage Assistant'; }
    get popup() { return !this.inline; }
    get topNav() { return false; }
    get footNav() { return !this.done; }
    get stepsTitle() { return this.inline ? 'CQ.AI Triage Steps' : 'Triage Steps'; }
    get showResumed() { return this.resumed && this.live; }
    get canRestart() { return this.inline && (this.done || this.maxStep > 0) && !this.saving; }

    // work in progress is kept on the record (workspace only) and cleared on Complete triage
    persist() {
        if (!this.inline || this.done) { return; }
        const s = {};
        ['step', 'maxStep', 'seen', 'acts', 'noActionWhy', 'due', 'added', 'data', 'asks', 'askNote', 'sev', 'lik', 'picks', 'extra', 'disp', 'dispDue', 'dispAppr', 'inv', 'invDue', 'invAppr', 'matrixId', 'capa', 'capaReason'].forEach((k) => { s[k] = this[k]; });
        saveDraft({ recordId: this.recordId, draft: JSON.stringify({ v: 1, ...s }) }).catch(() => {});
    }
    handleRestart() {
        this.step = 0; this.maxStep = 0; this.seen = { 0: true }; this.done = false; this.finished = false; this.resumed = false;
        this.error = undefined; this.warning = undefined;
        this.acts = {}; this.noActionWhy = ''; this.due = this.inDays(5); this.showAdd = false; this.added = [];
        this.data = ''; this.asks = {}; this.askNote = '';
        if (this.rk) { this.sev = this.rk.severity; this.lik = this.rk.likelihood; }
        this.picks = {}; this.extra = []; this.summary = []; this.sugPage = 0; this.otherPage = 0;
        this.disp = ''; this.dispAppr = false; this.inv = ''; this.invAppr = false; this.capa = ''; this.capaReason = '';
        if (this.nx) { this.dispDue = this.nx.dispDue; this.invDue = this.nx.invDue; this.matrixId = this.nx.defaultMatrixId; }
        this.preselect();
        if (this.inline) { saveDraft({ recordId: this.recordId, draft: null }).catch(() => {}); }
    }

    // ---- facts from the glance
    get g() { return this.glance || {}; }
    card(id) { return (this.g.cards || []).find((c) => c.id === id) || { facts: [] }; }
    fact(cardId, k) { return (this.card(cardId).facts || []).find((f) => f.k === k); }
    get title() { return (this.g.name || '') + (this.g.title ? ' · ' + this.g.title : ''); }
    // risk: CQ's Severity x Probability; CQ.AI fills both, the triager can move the cell
    get escaped() { return !!(this.rk && this.rk.escaped); }
    get suggestedScore() { return this.rk ? this.rk.severity * this.rk.likelihood : 0; }
    get suggestedRisk() { return this.escaped ? 'High' : band(this.suggestedScore); }
    get score() { return this.sev * this.lik; }
    get risk() { return this.escaped ? 'High' : band(this.score); }
    get contained() { const h = this.card('cont').headline; return h === 'Contained' || h === 'Containment raised'; }

    // ---- step rail (same pattern as the PHR workspace): a step ticks only when it has a valid answer
    get valid() {
        const v = [
            (this.hasActs && !!this.due) || (this.noAction && !!this.noActionWhy.trim()) || this.hasAdded,
            this.data === 'ok' || (this.dataAsk && (this.askList.length > 0 || !!this.askNote.trim())),
            !!this.seen[2 + this.off],
            this.done
        ];
        return this.inline ? [this.maxStep > 0, ...v] : v;
    }
    get steps() {
        const n = this.chosenActs.length + this.added.length;
        const subs = [
            this.noAction ? 'No action' : n ? n + ' action' + (n > 1 ? 's' : '') : 'Not decided',
            this.data === 'ok' ? 'Good enough' : this.data === 'ask' ? 'More information requested' : 'Not checked',
            this.seen[2 + this.off] || this.done ? this.risk + ' · score ' + this.score + (this.riskChanged ? ' (changed)' : '') : 'CQ.AI suggests ' + this.suggestedRisk,
            this.nextSub
        ];
        const valid = this.valid;
        const names = this.inline ? ['Triage at a Glance', ...STEPS] : STEPS;
        if (this.inline) { subs.unshift(this.maxStep > 0 || this.done ? 'Reviewed' : 'Start here'); }
        return names.map((label, i) => {
            const stepDone = this.done || valid[i];
            const unseen = !this.done && !this.seen[i];
            return { i, n: i + 1, label, sub: unseen ? 'Not Reviewed' : subs[i], done: stepDone, notDone: !stepDone,
                cls: 'step' + ((!this.done && i === this.step) || (this.finished && i === 0) ? ' active' : '') + (stepDone ? ' done' : ''), locked: this.done };
        });
    }
    get progress() { return this.steps.filter((x) => x.done).length + ' of ' + this.steps.length + ' steps complete'; }
    get live() { return this.booted && !this.done; }
    get isGlance() { return (this.live && this.cur === -1) || (this.done && this.finished); }
    get showSummary() { return this.done && !this.finished; }
    handleFinish() { this.finished = true; }
    get is0() { return this.live && this.cur === 0; }
    get is1() { return this.live && this.cur === 1; }
    get is2() { return this.live && this.cur === 2; }
    get is3() { return this.live && this.cur === 3; }
    get working() { return !this.done; }

    // ---- step 1: containment
    get factLines() {
        const g = this.g;
        const same = this.fact('risk', 'Same lot');
        const comp = this.fact('risk', 'Complaints');
        const lines = [
            { t: (g.lot ? 'Lot ' + g.lot : 'No lot recorded') + (g.lotQuantity != null ? ', ' + g.lotQuantity + ' in the lot.' : ', quantity not recorded.'), warn: !g.lot },
            { t: this.contained ? 'Containment on this NC: ' + ((this.fact('cont', 'Containment') || {}).v || 'recorded') + '.' : 'No containment is recorded on this NC yet.', warn: !this.contained },
            same && { t: same.v + '.', warn: same.warn },
            comp && { t: 'Complaints: ' + comp.v + '.', warn: comp.warn },
            { t: 'Hold status and shipments are not known (no ERP connection).', muted: true }
        ].filter(Boolean);
        return lines.map((l, i) => ({ key: 'f' + i, text: l.t, cls: 'fline' + (l.warn ? ' bad' : l.muted ? ' muted' : '') }));
    }
    get suggestedAct() { return this.contained ? 'No further action' : this.g.lot ? 'Hold lot ' + this.g.lot : 'Hold the affected stock'; }
    get actions() {
        const lot = this.g.lot;
        const defs = [
            ['hold', 'Hold', lot ? 'Hold lot ' + lot : 'Hold the affected stock', !this.contained],
            ['check', 'Check', '100% inspect remaining stock of this part', false],
            ['stop', 'Stop', 'Stop the process until the cause is known', false],
            ['none', 'No Action', this.contained ? 'Containment is already raised' : 'It is already under control', this.contained]
        ];
        return defs.map(([id, label, why, cq]) => {
            const on = !!this.acts[id];
            return { id, label, why, cq, on, pressed: on ? 'true' : 'false', tick: on ? '✓' : '', cls: 'act' + (on ? ' on' : cq ? ' sug' : '') };
        });
    }
    get noAction() { return !!this.acts.none; }
    get chosenActs() { return this.actions.filter((a) => a.on && a.id !== 'none').map((a) => a.why); }
    get hasActs() { return this.chosenActs.length > 0; }
    handleAct(event) {
        const id = event.currentTarget.dataset.id;
        const on = !this.acts[id];
        this.acts = id === 'none' ? { none: on } : { ...this.acts, none: false, [id]: on };
    }

    // Add Containment: creates the CQ record straight away
    get hasAdded() { return this.added.length > 0; }
    get cantCreate() { return this.adding || !this.cTitle.trim() || !this.cDue; }
    get createLabel() { return this.adding ? 'Creating…' : 'Create Containment'; }
    handleShowAdd() { this.cDue = this.due; this.addError = undefined; this.showAdd = true; }
    handleCancelAdd() { this.showAdd = false; }
    handleAssignee(event) { this.cAssignee = (event.detail && event.detail.recordId) || null; }
    async handleCreate() {
        if (this.cantCreate) { return; }
        this.adding = true;
        this.addError = undefined;
        try {
            const title = this.cTitle.trim();
            const name = await createContainment({ recordId: this.recordId, title, description: this.cDesc, dueDate: this.cDue, assigneeId: this.cAssignee });
            this.added = [...this.added, { key: name, name, title }];
            this.acts = { ...this.acts, none: false };
            this.cTitle = '';
            this.cDesc = '';
            this.cAssignee = userId;
            this.showAdd = false;
            this.persist();
            this.dispatchEvent(new CustomEvent('changed'));
        } catch (e) {
            this.addError = (e && e.body && e.body.message) || 'Could not create the containment.';
        }
        this.adding = false;
    }

    // ---- step 2: data check
    get dataRows() {
        const g = this.g;
        const sev = this.fact('risk', 'Severity');
        const part = g.partNumber || g.partName;
        const rows = [
            ['Description', g.description ? 'Recorded' : 'None', !!g.description],
            ['Photo', this.hasPhoto ? 'Attached' : 'None attached', !!this.hasPhoto],
            ['Part and Lot', (part || 'No part') + ' · ' + (g.lot ? 'lot ' + g.lot : 'no lot'), !!part && !!g.lot],
            ['How Many', g.defectiveQuantity == null ? 'Defective quantity not set' : g.defectiveQuantity + ' of ' + (g.lotQuantity == null ? '?' : g.lotQuantity), g.defectiveQuantity != null],
            ['Severity', sev ? sev.v : 'Not set', !!sev && !sev.warn]
        ];
        return rows.map(([k, v, ok]) => ({ key: k, k, v, ok, icon: ok ? '✓' : '!', cls: 'row slim' + (ok ? '' : ' warn') }));
    }
    get dataComplete() { return this.dataRows.every((r) => r.ok); }
    get dataOpts() {
        return [['ok', 'Good Enough, Send On', this.dataComplete], ['ask', 'Request More Information', false]]
            .map(([id, label, cq]) => ({ id, label, cls: 'opt' + (this.data === id ? ' on' : cq ? ' sug' : '') }));
    }
    get dataAsk() { return this.data === 'ask'; }
    get askChips() { return ASKS.map((l) => ({ label: l, pressed: this.asks[l] ? 'true' : 'false', cls: 'chip' + (this.asks[l] ? ' on' : '') })); }
    get askList() { return ASKS.filter((l) => this.asks[l]); }
    handleData(event) { this.data = event.currentTarget.dataset.id; }
    handleAsk(event) { const l = event.currentTarget.dataset.id; this.asks = { ...this.asks, [l]: !this.asks[l] }; }

    // ---- step 3: risk heat map
    get heatRows() {
        const r = this.rk || {};
        return [5, 4, 3, 2, 1].map((sv) => ({
            key: 's' + sv, num: String(sv), rest: ' - ' + SEV[sv - 1],
            cells: [1, 2, 3, 4, 5].map((lk) => {
                const n = sv * lk;
                const on = sv === this.sev && lk === this.lik;
                const sug = sv === r.severity && lk === r.likelihood;
                const base = !!r.repeatRaised && sv === r.severity && lk === r.baseLikelihood;
                const sevText = sv + ' - ' + SEV[sv - 1] + ' Severity';
                const likText = lk + ' - ' + LIK[lk - 1] + ' Likelihood';
                return { key: sv + '-' + lk, s: sv, l: lk, n, text: band(n), sug, pressed: on ? 'true' : 'false',
                    lvlCls: 'lvl ' + band(n).toLowerCase(), tipSev: sevText, tipLik: likText,
                    aria: band(n) + ', score ' + n + ' of 25, ' + sevText + ' x ' + likText,
                    cls: 'cell ' + (sug ? 'sug' : band(n).toLowerCase()) + (on ? ' on' : '') + (base ? ' base' : '') };
            })
        }));
    }
    get heatCols() { return LIK.map((l, i) => ({ key: 'l' + i, num: String(i + 1), word: l })); }
    get sevLabel() { return this.sev + ' - ' + SEV[this.sev - 1]; }
    get likLabel() { return this.lik + ' - ' + LIK[this.lik - 1]; }
    get riskReady() { return !!this.rk; }
    get sevHead() { return this.rk ? this.rk.severity + ' - ' + SEV[this.rk.severity - 1] : ''; }
    get likHead() { return this.rk ? this.rk.likelihood + ' - ' + LIK[this.rk.likelihood - 1] : ''; }
    get sevWhy() {
        const r = this.rk || {};
        return r.severityAssumed ? 'No severity is recorded on the NC, its failure code or the part, so Moderate is assumed.' : 'Taken from: ' + r.severityWhy + '.';
    }
    get likWhy() {
        const n = (this.rk && this.rk.count) || 0;
        return (n === 1 ? '1 other nonconformance' : n + ' other nonconformances') + ' on this part in the last 14 days.';
    }
    get recentList() { return this.rk && this.rk.recent && this.rk.recent.length ? this.rk.recent.join(', ') : ''; }
    get escapedWhy() { return this.rk ? this.rk.escapedWhy : ''; }
    get riskCls() { return 'lvl ' + this.risk.toLowerCase(); }
    get sugCls() { return 'lvl ' + this.suggestedRisk.toLowerCase(); }
    get riskChanged() { return !!this.rk && (this.sev !== this.rk.severity || this.lik !== this.rk.likelihood); }
    handleCell(event) {
        this.sev = Number(event.currentTarget.dataset.s);
        this.lik = Number(event.currentTarget.dataset.l);
    }

    // ---- step 4: investigation links (optional, research only; never replaces the NC's own investigation)
    get linksReady() { return !!this.lk; }
    get ownLine() {
        const l = this.lk || {};
        if (l.ownName) { return 'This NC has its own investigation: ' + l.ownName + '.'; }
        return 'This NC gets its own investigation.';
    }
    get linkItems() {
        const base = (this.lk && this.lk.items) || [];
        return [...base, ...this.extra].map((v) => {
            const on = v.linked || !!this.picks[v.id];
            return { ...v, on, pressed: on ? 'true' : 'false', tick: on ? '✓' : '',
                meta: [v.ncName ? 'From ' + v.ncName : '', v.status, v.linked ? 'Already linked' : v.why].filter(Boolean).join(' · '),
                cls: 'act inv' + (on ? ' on' : v.suggested ? ' sug' : '') };
        });
    }
    get sugItems() { return this.linkItems.filter((v) => v.suggested || v.linked || v.mine); }
    get otherItems() { return this.linkItems.filter((v) => !(v.suggested || v.linked || v.mine)); }
    get hasSug() { return this.sugItems.length > 0; }
    get hasOther() { return this.otherItems.length > 0; }
    get noLinks() { return this.linksReady && !this.linkItems.length; }
    /** One page of a list, and its page links: all of them up to 7 pages, otherwise the first, the last and two either side of the current one. */
    pager(list, page, w) {
        const n = Math.max(1, Math.ceil(list.length / LINK_PAGE));
        const cur = Math.min(page, n - 1);
        const keep = [];
        for (let i = 0; i < n; i++) { if (n <= 7 || i === 0 || i === n - 1 || Math.abs(i - cur) <= 2) { keep.push(i); } }
        const items = [];
        keep.forEach((i, k) => {
            if (k > 0 && i - keep[k - 1] > 1) { items.push({ key: w + 'g' + i, text: '…', cls: 'pg gap', off: true, label: 'More pages' }); }
            const on = i === cur;
            items.push({ key: w + 'p' + i, p: String(i), text: String(i + 1), cls: 'pg' + (on ? ' on' : ''), off: on, current: on ? 'page' : 'false', label: 'Page ' + (i + 1) });
        });
        return { w, cur, n, has: list.length > LINK_PAGE, shown: list.slice(cur * LINK_PAGE, (cur + 1) * LINK_PAGE), items, prevOff: cur === 0, nextOff: cur >= n - 1 };
    }
    get sugPg() { return this.pager(this.sugItems, this.sugPage, 'sug'); }
    get otherPg() { return this.pager(this.otherItems, this.otherPage, 'other'); }
    handleLinkPage(event) {
        const d = event.currentTarget.dataset;
        const pg = d.w === 'sug' ? this.sugPg : this.otherPg;
        const p = d.p === 'prev' ? pg.cur - 1 : d.p === 'next' ? pg.cur + 1 : Number(d.p);
        this[d.w + 'Page'] = Math.max(0, Math.min(pg.n - 1, p));
    }
    get otherLabel() { return 'Other Investigations on This Part (' + this.otherItems.length + ')'; }
    get chosenLinks() { return this.linkItems.filter((v) => v.on && !v.linked); }
    get linkCount() { return this.chosenLinks.length; }
    handleLink(event) {
        const id = event.currentTarget.dataset.id;
        const v = this.linkItems.find((x) => x.id === id);
        if (!v || v.linked) { return; }
        this.picks = { ...this.picks, [id]: !this.picks[id] };
    }
    async handlePick(event) {
        const id = event.detail && event.detail.recordId;
        const picker = event.target;
        if (!id) { return; }
        this.linkError = undefined;
        const have = this.linkItems.find((x) => x.id === id || x.id.substring(0, 15) === id.substring(0, 15));
        if (have) {
            if (!have.linked) { this.picks = { ...this.picks, [have.id]: true }; }
        } else {
            try {
                const v = await getOne({ recordId: this.recordId, investigationId: id });
                if (v.ncName && v.ncName === this.g.name) {
                    this.linkError = v.name + " is this NC's own investigation, so it is not linked.";
                } else {
                    this.extra = [...this.extra, { ...v, mine: true }];
                    this.picks = { ...this.picks, [v.id]: true };
                    this.sugPage = Math.ceil(this.sugItems.length / LINK_PAGE) - 1;   // show the one just added
                }
            } catch (e) {
                this.linkError = (e && e.body && e.body.message) || 'Could not add that investigation.';
            }
        }
        if (picker && picker.clearSelection) { picker.clearSelection(); }
    }

    handleInput(event) { this[event.target.dataset.f] = event.target.value; }

    // ---- step 4: next steps (disposition, investigation, approvals). CQ.AI suggests, the triager decides.
    get nextReady() { return !!this.nx && !!this.lk; }
    get dispReq() { return this.disp === 'req'; }
    get invReq() { return this.inv === 'inv'; }
    get dispOpts() { return this.choiceOpts([['req', 'Required'], ['no', 'Not Required']], this.disp, this.nx && this.nx.dispSuggest); }
    get invOpts() { return this.choiceOpts([['inv', 'Investigate'], ['log', 'Log Only']], this.inv, this.nx && this.nx.invSuggest); }
    choiceOpts(defs, chosen, sug) {
        return defs.map(([id, label]) => ({ id, label, pressed: chosen === id ? 'true' : 'false',
            cls: 'opt wide' + (chosen === id ? ' on' : id === sug ? ' sug' : '') }));
    }
    get dispSugText() { return this.nx ? (this.nx.dispSuggest === 'req' ? 'Required' : 'Not Required') : ''; }
    get invSugText() { return this.nx ? (this.nx.invSuggest === 'inv' ? 'Investigate' : 'Log Only') : ''; }
    get dispApprCls() { return 'opt' + (this.dispAppr ? ' on' : ''); }
    get invApprCls() { return 'opt' + (this.invAppr ? ' on' : ''); }
    get dispApprPressed() { return this.dispAppr ? 'true' : 'false'; }
    get invApprPressed() { return this.invAppr ? 'true' : 'false'; }
    get needMatrix() { return (this.dispReq && this.dispAppr) || (this.invReq && this.invAppr); }
    get matrixList() {
        const needD = this.dispReq && this.dispAppr;
        const needI = this.invReq && this.invAppr;
        return ((this.nx && this.nx.matrices) || []).filter((m) => (!needD || m.disp) && (!needI || m.inv));
    }
    get matrixOk() { return this.matrixList.some((m) => m.id === this.matrixId); }
    get matrixOpts() {
        const list = this.matrixList.map((m) => ({ value: m.id, label: m.name, selected: m.id === this.matrixId }));
        return this.matrixOk ? list : [{ value: '', label: 'Choose', selected: true }, ...list];
    }
    get noMatrix() { return this.needMatrix && this.matrixList.length === 0; }
    get matrixName() { const m = ((this.nx && this.nx.matrices) || []).find((x) => x.id === this.matrixId); return m ? m.name : ''; }
    get nextSub() {
        if (!this.disp && !this.inv) { return this.done ? 'Decided' : 'Not decided'; }
        return [this.disp ? (this.dispReq ? 'Disposition' : 'No disposition') : '', this.inv ? (this.invReq ? 'Investigate' : 'Log Only') : '']
            .filter(Boolean).join(' · ');
    }
    handleDisp(event) { this.disp = event.currentTarget.dataset.id; }
    handleInv(event) { this.inv = event.currentTarget.dataset.id; }
    handleDispAppr() { this.dispAppr = !this.dispAppr; }
    handleInvAppr() { this.invAppr = !this.invAppr; }
    handleMatrix(event) { this.matrixId = event.target.value || undefined; }

    // ---- navigation: any step opens from the list, Back and Next always move; Complete Triage waits for every step
    names() { return this.inline ? ['Triage at a Glance', ...STEPS] : STEPS; }
    /** What is missing on one triage step (0 Containment .. 3 Next Steps), or ''. */
    stepBlocker(c) {
        if (c === 0) {
            if (!this.hasActs && !this.noAction && !this.hasAdded) { return 'Choose an action, add a containment, or No Action'; }
            if (this.hasActs && !this.due) { return 'Set a due date'; }
            if (this.noAction && !this.noActionWhy.trim()) { return 'Say why no action is needed'; }
        }
        if (c === 1) {
            if (!this.data) { return 'Is the data good enough?'; }
            if (this.dataAsk && !this.askList.length && !this.askNote.trim()) { return 'Say what you need'; }
        }
        if (c === 2 && !this.rk) { return 'Working out the risk'; }
        if (c === 3) {
            if (!this.lk || !this.nx) { return 'Working out the next steps'; }
            if (!this.disp) { return 'Is a disposition needed?'; }
            if (this.dispReq && !this.dispDue) { return 'Set the disposition due date'; }
            if (!this.inv) { return 'Investigate or Log Only?'; }
            if (this.invReq && !this.invDue) { return 'Set the investigation due date'; }
            if (this.needMatrix && !this.matrixOk) { return 'Choose an approval matrix'; }
            if (this.rep && !this.capa) { return 'Escalate to CAPA?'; }
            if (this.capaNeedsReason && !this.capaReason.trim()) { return 'Say why it is not escalated'; }
        }
        return '';
    }
    /** Shown only beside Complete Triage: steps not opened yet, then the first step with something missing. */
    get blocker() {
        if (!this.booted) { return 'Loading'; }
        if (this.step !== this.last) { return ''; }
        const unseen = this.names().filter((n, i) => !this.seen[i]);
        if (unseen.length) {
            const list = unseen.length === 1 ? unseen[0] : unseen.slice(0, -1).join(', ') + ' and ' + unseen[unseen.length - 1];
            return 'Open ' + list + ' first';
        }
        for (let c = 0; c < STEPS.length; c++) {
            const b = this.stepBlocker(c);
            if (b) { return c === this.cur ? b : STEPS[c] + ': ' + b; }
        }
        return '';
    }
    get cantNext() { return !!this.blocker || this.saving; }
    get cantBack() { return this.step === 0 || this.saving; }
    get nextLabel() { return this.saving ? 'Saving…' : this.step === this.last ? 'Complete Triage' : 'Next'; }
    /**
     * In the workspace, the first step past the glance is the start of triage: a Draft NC moves to Triage through
     * CQ's own Submit (the server leaves any other stage alone). Looking at the glance changes nothing.
     */
    async ensureStarted() {
        if (!this.inline || this.started || this.done) { return; }
        this.started = true;
        try {
            const s = await startTriage({ recordId: this.recordId });
            if (s && s.moved) { this.dispatchEvent(new CustomEvent('changed')); }
            if (s && s.warning) { this.error = s.warning; }
        } catch (e) { this.started = false; }
    }
    go(i) {
        if (i > 0) { this.ensureStarted(); }
        this.step = i;
        this.seen = { ...this.seen, [i]: true };
        this.maxStep = Math.max(this.maxStep, i);
        this.resumed = false;
        this.persist();
    }
    handleBack() { if (this.step > 0) { this.go(this.step - 1); } }
    handleStep(event) {
        const i = Number(event.currentTarget.dataset.i);
        if (!this.done) { this.go(i); }
    }
    handleClose() { this.dispatchEvent(new CustomEvent('close')); }

    buildSummary() {
        return [
            { k: 'Containment', v: this.noAction ? 'No action: ' + this.noActionWhy.trim()
                : [...this.chosenActs, ...this.added.map((a) => a.name + ' ' + a.title)].join('; ') },
            { k: 'Data Check', v: this.dataAsk ? 'More information requested: ' + [...this.askList, this.askNote.trim()].filter(Boolean).join(', ') : 'Good enough' },
            { k: 'Risk', v: this.risk + ' · score ' + this.score + ' (' + this.sevLabel + ' severity x ' + this.likLabel + ' likelihood)'
                + (this.escaped ? ' · High because of complaints on the lot' : '')
                + (this.riskChanged ? ' · changed from CQ.AI ' + this.suggestedRisk : ' · as CQ.AI suggested') },
            { k: 'Disposition', v: this.dispReq ? 'Required, due ' + this.dispDue + (this.dispAppr ? ', needs approval' : '') : 'Not required' },
            { k: 'Investigation', v: !this.invReq ? 'Log only'
                : (this.lk && this.lk.ownName ? 'Continues with ' + this.lk.ownName : 'Needs its own investigation') + ', due ' + this.invDue + (this.invAppr ? ', needs approval' : '') },
            ...(this.needMatrix ? [{ k: 'Approval Matrix', v: this.matrixName }] : []),
            ...(this.rep ? [{ k: 'Repeat of ' + this.rep.ncName, v: this.capa === ESCALATE ? 'Escalate to CAPA (CQ Initiate CAPA)'
                : (this.capa === LINK ? 'Linked to ' + this.rep.capaName : 'Not escalated') + ': ' + this.capaReason.trim() }] : []),
            { k: 'Links', v: this.invReq && this.linkCount ? this.chosenLinks.map((v) => v.name).join(', ') + ' (research only)' : 'None' }
        ];
    }

    async handleNext() {
        if (this.blocker || this.saving) { return; }
        this.resumed = false;
        if (this.step < this.last) { this.go(this.step + 1); return; }
        this.saving = true;
        this.error = undefined;
        const rows = this.buildSummary();
        let riskWarning;
        try {
            try { await saveRisk({ recordId: this.recordId, severity: this.sev, likelihood: this.lik }); }
            catch (e) { riskWarning = (e && e.body && e.body.message) || 'CQ did not accept Severity and Probability.'; }
            const t = await completeTriage({ recordId: this.recordId, payload: JSON.stringify({
                risk: this.risk,
                notes: rows.map((r) => r.k + ': ' + r.v).join('\n'),
                severity: this.sev,
                containment: this.hasActs || this.hasAdded,
                containmentTitles: this.chosenActs,
                containmentDue: this.due,
                disposition: this.dispReq,
                dispositionDue: this.dispDue,
                dispositionApproval: this.dispReq && this.dispAppr,
                investigate: this.invReq,
                investigationDue: this.invDue,
                investigationApproval: this.invReq && this.invAppr,
                matrixId: this.needMatrix ? this.matrixId : null,
                repeatOfId: this.rep ? this.rep.ncId : null,
                repeatCapaId: this.rep ? this.rep.capaId : null,
                repeatDecision: this.rep ? this.capa : null,
                repeatReason: this.capaNeedsReason ? this.capaReason.trim() : null
            }) });
            if (t && t.created && t.created.length) { rows.push({ k: 'Created', v: 'Containment ' + t.created.join(', ') }); }
            if (t && t.moved) { rows.push({ k: 'Next', v: 'Moved to Disposition / Investigate' }); }
            let linkWarning;
            const ids = this.invReq ? this.chosenLinks.map((v) => v.id) : [];
            if (ids.length) {
                try {
                    const names = await saveLinks({ recordId: this.recordId, investigationIds: ids });
                    if (names && names.length) { rows.push({ k: 'Linked', v: names.join(', ') }); }
                } catch (e) { linkWarning = (e && e.body && e.body.message) || 'CQ did not accept the investigation links.'; }
            }
            this.summary = rows.map((r) => ({ ...r, key: r.k }));
            this.warning = [t && t.warning, riskWarning, linkWarning].filter(Boolean).join(' ') || undefined;
            this.done = true;      // Complete Triage cleared the work in progress in its own save; no second save here
            this.dispatchEvent(new CustomEvent('done'));
        } catch (e) {
            this.error = (e && e.body && e.body.message) || 'Could not save the triage.';
        }
        this.saving = false;
    }
}
