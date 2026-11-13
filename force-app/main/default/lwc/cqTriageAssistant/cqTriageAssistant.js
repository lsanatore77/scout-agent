import { LightningElement, api } from 'lwc';
import saveTriage from '@salesforce/apex/CqTriageAssistant.saveTriage';

const STEPS = ['Containment', 'Data Check', 'Risk', 'Path'];
const RISKS = ['Low', 'Medium', 'High'];
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
    custom = [];
    newAct = '';
    due;
    data = '';
    asks = {};
    askNote = '';
    risk;
    riskWhy = '';
    path = '';
    disp = '';
    logWhy = '';
    summary = [];

    connectedCallback() {
        this.risk = this.suggestedRisk;
        const d = new Date(Date.now() + 86400000);
        const p = (n) => String(n).padStart(2, '0');
        this.due = d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate());
    }

    // ---- facts from the glance
    get g() { return this.glance || {}; }
    card(id) { return (this.g.cards || []).find((c) => c.id === id) || { facts: [] }; }
    fact(cardId, k) { return (this.card(cardId).facts || []).find((f) => f.k === k); }
    get title() { return (this.g.name || '') + (this.g.title ? ' · ' + this.g.title : ''); }
    get suggestedRisk() { const h = this.card('risk').headline; return RISKS.includes(h) ? h : 'Medium'; }
    get contained() { return this.card('cont').headline === 'Contained'; }
    get invHeadline() { return this.card('inv').headline || ''; }
    get linked() { return this.invHeadline.startsWith('Linked: '); }
    get invName() {
        const h = this.invHeadline;
        return h.startsWith('Join ') ? h.substring(5) : this.linked ? h.substring(8) : null;
    }
    get suggestedPath() { return this.invName ? 'join' : this.invHeadline === 'Open new' ? 'new' : 'log'; }

    // ---- step rail (same pattern as the PHR workspace)
    get steps() {
        const subs = [
            this.noAction ? 'No action' : this.chosenActs.length ? this.chosenActs.length + ' action' + (this.chosenActs.length > 1 ? 's' : '') + ' chosen' : 'Not decided',
            this.data === 'ok' ? 'Good enough' : this.data === 'ask' ? 'More information requested' : 'Not checked',
            this.maxStep > 2 || this.done ? this.risk + (this.riskChanged ? ' (changed)' : '') : 'CQ.AI suggests ' + this.suggestedRisk,
            this.path === 'join' ? this.joinLabel : this.path === 'new' ? 'New investigation' : this.path === 'log' ? 'Log only' : 'Not chosen'
        ];
        return STEPS.map((label, i) => {
            const stepDone = this.done || i < this.maxStep;
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
            { t: this.contained ? 'Containment is already recorded on this NC.' : 'No containment is recorded on this NC yet.', warn: !this.contained },
            same && { t: same.v + '.', warn: same.warn },
            comp && { t: 'Complaints: ' + comp.v + '.', warn: comp.warn },
            { t: 'Hold status and shipments are not known (no ERP connection).', muted: true }
        ].filter(Boolean);
        return lines.map((l, i) => ({ key: 'f' + i, text: l.t, cls: 'fline' + (l.warn ? ' bad' : l.muted ? ' muted' : '') }));
    }
    get suggestedAct() { return this.contained ? 'No action' : this.g.lot ? 'Hold lot ' + this.g.lot : 'Hold the affected stock'; }
    get actions() {
        const lot = this.g.lot;
        const defs = [
            ['hold', 'Hold', lot ? 'Hold lot ' + lot : 'Hold the affected stock', !this.contained],
            ['check', 'Check', '100% inspect remaining stock of this part', false],
            ['stop', 'Stop', 'Stop the process until the cause is known', false],
            ['none', 'No action', 'It is already under control', this.contained]
        ];
        this.custom.forEach((t, i) => defs.splice(defs.length - 1, 0, ['own' + i, t, 'Your own action. Click to remove.', false, true]));
        return defs.map(([id, label, why, cq, mine]) => {
            const on = mine || !!this.acts[id];
            return { id, label, why, cq, mine, on, pressed: on ? 'true' : 'false', tick: on ? '✓' : '', cls: 'act' + (on ? ' on' : cq ? ' sug' : '') };
        });
    }
    get noAction() { return !!this.acts.none; }
    get chosenActs() { return this.actions.filter((a) => a.on && a.id !== 'none').map((a) => (a.mine ? a.label : a.why)); }
    get hasActs() { return this.chosenActs.length > 0; }
    get cantAdd() { return !this.newAct.trim(); }
    handleAct(event) {
        const id = event.currentTarget.dataset.id;
        if (id.startsWith('own')) { this.custom = this.custom.filter((t, i) => 'own' + i !== id); return; }
        const on = !this.acts[id];
        if (id === 'none') { this.acts = { none: on }; if (on) { this.custom = []; } return; }
        this.acts = { ...this.acts, none: false, [id]: on };
    }
    handleAddAct() {
        const t = this.newAct.trim();
        if (!t) { return; }
        this.custom = [...this.custom, t];
        this.acts = { ...this.acts, none: false };
        this.newAct = '';
    }
    handleAddKey(event) { if (event.key === 'Enter') { this.newAct = event.target.value; this.handleAddAct(); } }

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

    // ---- step 3: risk
    get riskFacts() { return (this.card('risk').facts || []).map((f, i) => ({ key: 'r' + i, k: f.k, v: f.v, cls: 'tv' + (f.warn ? ' red' : '') })); }
    get riskOpts() { return RISKS.map((l) => ({ id: l, label: l, cls: 'opt wide' + (this.risk === l ? ' on' : l === this.suggestedRisk ? ' sug' : '') })); }
    get riskChanged() { return this.risk !== this.suggestedRisk; }
    handleRisk(event) { this.risk = event.currentTarget.dataset.id; }

    // ---- step 4: path
    get joinLabel() { return (this.linked ? 'Continue with ' : 'Join ') + this.invName; }
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
            if (!this.hasActs && !this.noAction) { return 'Choose an action, or No action'; }
            if (this.hasActs && !this.due) { return 'Set a due date'; }
            if (this.noAction && !this.noActionWhy.trim()) { return 'Say why no action is needed'; }
        }
        if (this.step === 1) {
            if (!this.data) { return 'Is the data good enough?'; }
            if (this.dataAsk && !this.askList.length && !this.askNote.trim()) { return 'Say what you need'; }
        }
        if (this.step === 2 && this.riskChanged && !this.riskWhy.trim()) { return 'Give a reason'; }
        if (this.step === 3) {
            if (!this.path) { return 'Choose a path'; }
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
            { k: 'Containment', v: this.noAction ? 'No action: ' + this.noActionWhy.trim() : this.chosenActs.join('; ') },
            { k: 'Data Check', v: this.dataAsk ? 'More information requested: ' + [...this.askList, this.askNote.trim()].filter(Boolean).join(', ') : 'Good enough' },
            { k: 'Risk', v: this.risk + (this.riskChanged ? ' (changed from CQ.AI ' + this.suggestedRisk + ': ' + this.riskWhy.trim() + ')' : ' (as CQ.AI suggested)') },
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
        try {
            const t = await saveTriage({
                recordId: this.recordId,
                risk: this.risk,
                path: this.path === 'join' ? 'Join Investigation' : this.path === 'new' ? 'New Investigation' : 'Log Only',
                notes: rows.map((r) => r.k + ': ' + r.v).join('\n'),
                containment: !this.noAction,
                investigate: this.path !== 'log',
                containmentTitles: this.noAction ? [] : this.chosenActs,
                dueDate: this.due
            });
            if (t && t.created && t.created.length) { rows.push({ k: 'Created', v: 'Containment ' + t.created.join(', ') }); }
            this.summary = rows.map((r) => ({ ...r, key: r.k }));
            this.warning = t && t.warning;
            this.done = true;
            this.dispatchEvent(new CustomEvent('done'));
        } catch (e) {
            this.error = (e && e.body && e.body.message) || 'Could not save the triage.';
        }
        this.saving = false;
    }
}
