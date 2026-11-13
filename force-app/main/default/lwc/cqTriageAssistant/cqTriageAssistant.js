import { LightningElement, api } from 'lwc';
import saveTriage from '@salesforce/apex/CqTriageAssistant.saveTriage';
import createContainment from '@salesforce/apex/CqTriageContainment.create';
import getRisk from '@salesforce/apex/CqTriageRisk.getRisk';
import saveRisk from '@salesforce/apex/CqTriageRisk.saveRisk';
import getLinks from '@salesforce/apex/CqTriageLinks.getLinks';
import getOne from '@salesforce/apex/CqTriageLinks.getOne';
import saveLinks from '@salesforce/apex/CqTriageLinks.saveLinks';
import getDraft from '@salesforce/apex/CqTriageDraft.getDraft';
import saveDraft from '@salesforce/apex/CqTriageDraft.saveDraft';
import userId from '@salesforce/user/Id';

const STEPS = ['Containment', 'Data Check', 'Risk', 'Investigation Links'];
const SEV = ['Negligible', 'Low', 'Moderate', 'Significant', 'Catastrophic'];
const LIK = ['Improbable', 'Remote', 'Occasional', 'Probable', 'Frequent'];
const band = (n) => (n >= 15 ? 'High' : n >= 6 ? 'Medium' : 'Low');
const ASKS = ['More photos', 'Measurements', 'When it started', 'Other lots affected?'];

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
    linkError;
    summary = [];

    async connectedCallback() {
        this.due = this.tomorrow();
        let draft;
        if (this.inline) {
            try { const d = await getDraft({ recordId: this.recordId }); draft = d ? JSON.parse(d) : null; } catch (e) { draft = null; }
        }
        if (draft && draft.v === 1) {
            ['step', 'maxStep', 'acts', 'noActionWhy', 'due', 'added', 'data', 'asks', 'askNote', 'picks', 'extra'].forEach((k) => { if (draft[k] !== undefined) { this[k] = draft[k]; } });
            this.resumed = this.maxStep > 0;
        }
        this.booted = true;
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
    }

    tomorrow() {
        const d = new Date(Date.now() + 86400000);
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
    get topNav() { return this.inline && !this.done; }
    get footNav() { return !this.inline && !this.done; }
    get showResumed() { return this.resumed && this.live; }
    get canRestart() { return this.inline && (this.done || this.maxStep > 0) && !this.saving; }

    // work in progress is kept on the record (workspace only) and cleared on Complete triage
    persist() {
        if (!this.inline || this.done) { return; }
        const s = {};
        ['step', 'maxStep', 'acts', 'noActionWhy', 'due', 'added', 'data', 'asks', 'askNote', 'sev', 'lik', 'picks', 'extra'].forEach((k) => { s[k] = this[k]; });
        saveDraft({ recordId: this.recordId, draft: JSON.stringify({ v: 1, ...s }) }).catch(() => {});
    }
    handleRestart() {
        this.step = 0; this.maxStep = 0; this.done = false; this.finished = false; this.resumed = false;
        this.error = undefined; this.warning = undefined;
        this.acts = {}; this.noActionWhy = ''; this.due = this.tomorrow(); this.showAdd = false; this.added = [];
        this.data = ''; this.asks = {}; this.askNote = '';
        if (this.rk) { this.sev = this.rk.severity; this.lik = this.rk.likelihood; }
        this.picks = {}; this.extra = []; this.summary = [];
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
            this.maxStep > 2 + this.off,
            this.done
        ];
        return this.inline ? [this.maxStep > 0, ...v] : v;
    }
    get steps() {
        const n = this.chosenActs.length + this.added.length;
        const subs = [
            this.noAction ? 'No action' : n ? n + ' action' + (n > 1 ? 's' : '') : 'Not decided',
            this.data === 'ok' ? 'Good enough' : this.data === 'ask' ? 'More information requested' : 'Not checked',
            this.maxStep > 2 + this.off || this.done ? this.risk + ' \u00b7 score ' + this.score + (this.riskChanged ? ' (changed)' : '') : 'CQ.AI suggests ' + this.suggestedRisk,
            this.linkCount ? this.linkCount + ' to link' : this.done ? 'None linked' : 'Optional'
        ];
        const valid = this.valid;
        const names = this.inline ? ['Triage at a Glance', ...STEPS] : STEPS;
        if (this.inline) { subs.unshift(this.maxStep > 0 || this.done ? 'Reviewed' : 'Start here'); }
        return names.map((label, i) => {
            const stepDone = this.done || valid[i];
            return { i, n: i + 1, label, sub: subs[i], done: stepDone, notDone: !stepDone,
                cls: 'step' + ((!this.done && i === this.step) || (this.finished && i === 0) ? ' active' : '') + (stepDone ? ' done' : ''), locked: this.done || i > this.maxStep };
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
            ['none', 'No action', this.contained ? 'Containment is already raised' : 'It is already under control', this.contained]
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
    get createLabel() { return this.adding ? 'Creating…' : 'Create containment'; }
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
            ['Part and lot', (part || 'No part') + ' · ' + (g.lot ? 'lot ' + g.lot : 'no lot'), !!part && !!g.lot],
            ['How many', g.defectiveQuantity == null ? 'Defective quantity not set' : g.defectiveQuantity + ' of ' + (g.lotQuantity == null ? '?' : g.lotQuantity), g.defectiveQuantity != null],
            ['Severity', sev ? sev.v : 'Not set', !!sev && !sev.warn]
        ];
        return rows.map(([k, v, ok]) => ({ key: k, k, v, ok, icon: ok ? '✓' : '!', cls: 'row slim' + (ok ? '' : ' warn') }));
    }
    get dataComplete() { return this.dataRows.every((r) => r.ok); }
    get dataOpts() {
        return [['ok', 'Good enough, send on', this.dataComplete], ['ask', 'Request more information', false]]
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
                const sevText = sv + ' - ' + SEV[sv - 1] + ' Severity';
                const likText = lk + ' - ' + LIK[lk - 1] + ' Likelihood';
                return { key: sv + '-' + lk, s: sv, l: lk, n, text: band(n), sug, pressed: on ? 'true' : 'false',
                    lvlCls: 'lvl ' + band(n).toLowerCase(), tipSev: sevText, tipLik: likText,
                    aria: band(n) + ', score ' + n + ' of 25, ' + sevText + ' x ' + likText,
                    cls: 'cell ' + (sug ? 'sug' : band(n).toLowerCase()) + (on ? ' on' : '') };
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
        return 'This NC needs its own investigation' + (l.due ? ', due ' + l.due : '') + '.';
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
    get otherLabel() { return 'Other investigations on this part (' + this.otherItems.length + ')'; }
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
                }
            } catch (e) {
                this.linkError = (e && e.body && e.body.message) || 'Could not add that investigation.';
            }
        }
        if (picker && picker.clearSelection) { picker.clearSelection(); }
    }

    handleInput(event) { this[event.target.dataset.f] = event.target.value; }

    // ---- navigation
    get blocker() {
        if (!this.booted) { return 'Loading'; }
        if (this.cur === 0) {
            if (!this.hasActs && !this.noAction && !this.hasAdded) { return 'Choose an action, add a containment, or No action'; }
            if (this.hasActs && !this.due) { return 'Set a due date'; }
            if (this.noAction && !this.noActionWhy.trim()) { return 'Say why no action is needed'; }
        }
        if (this.cur === 1) {
            if (!this.data) { return 'Is the data good enough?'; }
            if (this.dataAsk && !this.askList.length && !this.askNote.trim()) { return 'Say what you need'; }
        }
        if (this.cur === 2 && !this.rk) { return 'Working out the risk'; }
        if (this.cur === 3 && !this.lk) { return 'Looking for related investigations'; }
        return '';
    }
    get cantNext() { return !!this.blocker || this.saving; }
    get cantBack() { return this.step === 0 || this.saving; }
    get nextLabel() { return this.saving ? 'Saving…' : this.step === this.last ? 'Complete triage' : 'Next'; }
    handleBack() { if (this.step > 0) { this.step -= 1; this.persist(); } }
    handleStep(event) {
        const i = Number(event.currentTarget.dataset.i);
        if (!this.done && i <= this.maxStep) { this.step = i; this.persist(); }
    }
    handleClose() { this.dispatchEvent(new CustomEvent('close')); }

    buildSummary() {
        return [
            { k: 'Containment', v: this.noAction ? 'No action: ' + this.noActionWhy.trim()
                : [...this.chosenActs, ...this.added.map((a) => a.name + ' ' + a.title)].join('; ') },
            { k: 'Data Check', v: this.dataAsk ? 'More information requested: ' + [...this.askList, this.askNote.trim()].filter(Boolean).join(', ') : 'Good enough' },
            { k: 'Risk', v: this.risk + ' \u00b7 score ' + this.score + ' (' + this.sevLabel + ' severity x ' + this.likLabel + ' likelihood)'
                + (this.escaped ? ' \u00b7 High because of complaints on the lot' : '')
                + (this.riskChanged ? ' \u00b7 changed from CQ.AI ' + this.suggestedRisk : ' \u00b7 as CQ.AI suggested') },
            { k: 'Investigation', v: this.lk && this.lk.ownName ? 'Continues with ' + this.lk.ownName : 'Needs its own investigation' },
            { k: 'Links', v: this.linkCount ? this.chosenLinks.map((v) => v.name).join(', ') + ' (research only)' : 'None' }
        ];
    }

    async handleNext() {
        if (this.blocker || this.saving) { return; }
        this.resumed = false;
        if (this.step < this.last) {
            this.step += 1;
            this.maxStep = Math.max(this.maxStep, this.step);
            this.persist();
            return;
        }
        this.saving = true;
        this.error = undefined;
        const rows = this.buildSummary();
        let riskWarning;
        try {
            try { await saveRisk({ recordId: this.recordId, severity: this.sev, likelihood: this.lik }); }
            catch (e) { riskWarning = (e && e.body && e.body.message) || 'CQ did not accept Severity and Probability.'; }
            const t = await saveTriage({
                recordId: this.recordId,
                risk: this.risk,
                path: this.lk && this.lk.ownName ? 'Continue with Investigation' : 'New Investigation',
                notes: rows.map((r) => r.k + ': ' + r.v).join('\n'),
                containment: this.hasActs || this.hasAdded,
                investigate: true,
                containmentTitles: this.chosenActs,
                dueDate: this.due
            });
            if (t && t.created && t.created.length) { rows.push({ k: 'Created', v: 'Containment ' + t.created.join(', ') }); }
            let linkWarning;
            const ids = this.chosenLinks.map((v) => v.id);
            if (ids.length) {
                try {
                    const names = await saveLinks({ recordId: this.recordId, investigationIds: ids });
                    if (names && names.length) { rows.push({ k: 'Linked', v: names.join(', ') }); }
                } catch (e) { linkWarning = (e && e.body && e.body.message) || 'CQ did not accept the investigation links.'; }
            }
            this.summary = rows.map((r) => ({ ...r, key: r.k }));
            this.warning = [t && t.warning, riskWarning, linkWarning].filter(Boolean).join(' ') || undefined;
            this.done = true;
            if (this.inline) { saveDraft({ recordId: this.recordId, draft: null }).catch(() => {}); }
            this.dispatchEvent(new CustomEvent('done'));
        } catch (e) {
            this.error = (e && e.body && e.body.message) || 'Could not save the triage.';
        }
        this.saving = false;
    }
}
