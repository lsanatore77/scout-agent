import { LightningElement, api } from 'lwc';
import saveTriage from '@salesforce/apex/CqTriageAssistant.saveTriage';
import createContainment from '@salesforce/apex/CqTriageContainment.create';
import getRisk from '@salesforce/apex/CqTriageRisk.getRisk';
import saveRisk from '@salesforce/apex/CqTriageRisk.saveRisk';
import userId from '@salesforce/user/Id';

const STEPS = ['Containment', 'Data Check', 'Risk', 'Path'];
const SEV = ['Negligible', 'Low', 'Moderate', 'Significant', 'Catastrophic'];
const LIK = ['Improbable', 'Remote', 'Occasional', 'Probable', 'Frequent'];
const band = (n) => (n >= 15 ? 'High' : n >= 6 ? 'Medium' : 'Low');
const RANGES = { Low: 'Low is 1 to 5.', Medium: 'Medium is 6 to 12.', High: 'High is 15 to 25.' };
const ASKS = ['More photos', 'Measurements', 'When it started', 'Other lots affected?'];
const DISPS = ['Rework', 'Use as is', 'Scrap', 'Return to supplier'];

/** Triage Assistant: four steps over the facts in Triage at a Glance. CQ.AI suggests, the triager decides. */
export default class CqTriageAssistant extends LightningElement {
    @api recordId;
    @api glance;
    @api hasPhoto = false;

    step = 0;
    maxStep = 0;
    done = false;
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
    path = '';
    disp = '';
    logWhy = '';
    summary = [];

    async connectedCallback() {
        const d = new Date(Date.now() + 86400000);
        const p = (n) => String(n).padStart(2, '0');
        this.due = d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate());
        try {
            this.rk = await getRisk({ recordId: this.recordId });
        } catch (e) {
            this.rk = { count: 0, recent: [], severity: 3, severityAssumed: true, severityWhy: 'Assumed: could not read the record', likelihood: 1, likelihoodWhy: 'Could not count recent NCs', escaped: false };
        }
        this.sev = this.rk.severity;
        this.lik = this.rk.likelihood;
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
    get invHeadline() { return this.card('inv').headline || ''; }
    get linked() { return this.invHeadline.startsWith('Linked: '); }
    get invName() {
        const h = this.invHeadline;
        return h.startsWith('Join ') ? h.substring(5) : this.linked ? h.substring(8) : null;
    }
    get suggestedPath() { return this.invName ? 'join' : this.invHeadline === 'Open new' ? 'new' : 'log'; }

    // ---- step rail (same pattern as the PHR workspace): a step ticks only when it has a valid answer
    get valid() {
        return [
            (this.hasActs && !!this.due) || (this.noAction && !!this.noActionWhy.trim()) || this.hasAdded,
            this.data === 'ok' || (this.dataAsk && (this.askList.length > 0 || !!this.askNote.trim())),
            this.maxStep > 2,
            this.done
        ];
    }
    get steps() {
        const n = this.chosenActs.length + this.added.length;
        const subs = [
            this.noAction ? 'No action' : n ? n + ' action' + (n > 1 ? 's' : '') : 'Not decided',
            this.data === 'ok' ? 'Good enough' : this.data === 'ask' ? 'More information requested' : 'Not checked',
            this.maxStep > 2 || this.done ? this.risk + ' \u00b7 score ' + this.score + (this.riskChanged ? ' (changed)' : '') : 'CQ.AI suggests ' + this.suggestedRisk,
            this.path === 'join' ? this.joinLabel : this.path === 'new' ? 'New investigation' : this.path === 'log' ? 'Log only' : 'Not chosen'
        ];
        const valid = this.valid;
        return STEPS.map((label, i) => {
            const stepDone = this.done || valid[i];
            return { i, n: i + 1, label, sub: subs[i], done: stepDone, notDone: !stepDone,
                cls: 'step' + (!this.done && i === this.step ? ' active' : '') + (stepDone ? ' done' : ''), locked: this.done || i > this.maxStep };
        });
    }
    get progress() { return this.steps.filter((x) => x.done).length + ' of ' + STEPS.length + ' steps complete'; }
    get is0() { return !this.done && this.step === 0; }
    get is1() { return !this.done && this.step === 1; }
    get is2() { return !this.done && this.step === 2; }
    get is3() { return !this.done && this.step === 3; }
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
            key: 's' + sv, label: sv + ' - ' + SEV[sv - 1],
            cells: [1, 2, 3, 4, 5].map((lk) => {
                const n = sv * lk;
                const on = sv === this.sev && lk === this.lik;
                const sug = sv === r.severity && lk === r.likelihood;
                return { key: sv + '-' + lk, s: sv, l: lk, text: band(n), sug, pressed: on ? 'true' : 'false',
                    title: (sug ? 'CQ.AI Suggests. ' : '') + band(n) + ': score ' + n + ' of 25 (' + sv + ' - ' + SEV[sv - 1] + ' severity x ' + lk + ' - ' + LIK[lk - 1] + ' likelihood). ' + RANGES[band(n)],
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

    // ---- step 4: path
    get joinLabel() { return (this.linked ? 'Continue with ' : 'Join ') + this.invName; }
    get pathValue() {
        return this.path === 'join' ? (this.linked ? 'Continue with Investigation' : 'Join Investigation') : this.path === 'new' ? 'New Investigation' : 'Log Only';
    }
    get pathOpts() {
        const defs = [];
        if (this.invName) { defs.push(['join', this.joinLabel, this.card('inv').why]); }
        defs.push(['new', 'New investigation', 'Start a fresh investigation. This NC is flagged as needing one.']);
        defs.push(['log', 'Log only', 'No investigation. You set the disposition now.']);
        return defs.map(([id, label, why]) => ({ id, label, why, cq: id === this.suggestedPath, cls: 'pathopt' + (this.path === id ? ' on' : id === this.suggestedPath ? ' sug' : '') }));
    }
    get pathLog() { return this.path === 'log'; }
    get dispOpts() { return DISPS.map((d) => ({ value: d, selected: this.disp === d })); }
    handlePath(event) { this.path = event.currentTarget.dataset.id; }

    handleInput(event) { this[event.target.dataset.f] = event.target.value; }

    // ---- navigation
    get blocker() {
        if (this.step === 0) {
            if (!this.hasActs && !this.noAction && !this.hasAdded) { return 'Choose an action, add a containment, or No action'; }
            if (this.hasActs && !this.due) { return 'Set a due date'; }
            if (this.noAction && !this.noActionWhy.trim()) { return 'Say why no action is needed'; }
        }
        if (this.step === 1) {
            if (!this.data) { return 'Is the data good enough?'; }
            if (this.dataAsk && !this.askList.length && !this.askNote.trim()) { return 'Say what you need'; }
        }
        if (this.step === 2 && !this.rk) { return 'Working out the risk'; }
        if (this.step === 3) {
            if (!this.path) { return 'Click a path above to choose it'; }
            if (this.pathLog && (!this.disp || !this.logWhy.trim())) { return 'Disposition and reason needed'; }
        }
        return '';
    }
    get cantNext() { return !!this.blocker || this.saving; }
    get cantBack() { return this.step === 0 || this.saving; }
    get nextLabel() { return this.saving ? 'Saving…' : this.step === 3 ? 'Complete triage' : 'Next'; }
    handleBack() { if (this.step > 0) { this.step -= 1; } }
    handleStep(event) {
        const i = Number(event.currentTarget.dataset.i);
        if (!this.done && i <= this.maxStep) { this.step = i; }
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
            { k: 'Path', v: this.path === 'join' ? this.joinLabel : this.path === 'new' ? 'New investigation' : 'Log only: ' + this.disp + ' (' + this.logWhy.trim() + ')' }
        ];
    }

    async handleNext() {
        if (this.blocker || this.saving) { return; }
        if (this.step < 3) {
            this.step += 1;
            this.maxStep = Math.max(this.maxStep, this.step);
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
                path: this.pathValue,
                notes: rows.map((r) => r.k + ': ' + r.v).join('\n'),
                containment: this.hasActs || this.hasAdded,
                investigate: this.path !== 'log',
                containmentTitles: this.chosenActs,
                dueDate: this.due
            });
            if (t && t.created && t.created.length) { rows.push({ k: 'Created', v: 'Containment ' + t.created.join(', ') }); }
            this.summary = rows.map((r) => ({ ...r, key: r.k }));
            this.warning = [t && t.warning, riskWarning].filter(Boolean).join(' ') || undefined;
            this.done = true;
            this.dispatchEvent(new CustomEvent('done'));
        } catch (e) {
            this.error = (e && e.body && e.body.message) || 'Could not save the triage.';
        }
        this.saving = false;
    }
}
