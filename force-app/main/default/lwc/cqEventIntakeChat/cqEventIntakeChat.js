import { LightningElement, track } from 'lwc';
import getSetup from '@salesforce/apex/CqEventIntake.getSetup';
import fromDescription from '@salesforce/apex/CqEventExtract.fromDescription';
import resolveLot from '@salesforce/apex/CqEventLotLink.resolve';
import submitReport from '@salesforce/apex/CqEventIntake.submitReport';

function msg(e) {
    if (e && e.body && e.body.message) { return e.body.message; }
    if (e && e.message) { return e.message; }
    return 'Something went wrong.';
}

export default class CqEventIntakeChat extends LightningElement {
    @track phase = 'describe';   // describe | review | done
    description = '';
    reporter = '';
    questions = [];
    @track rows = [];
    saidText = '';
    title = '';
    lot = '';
    units = '';
    defect = '';
    partId = null;
    partLabel = '';
    partRaw = '';
    showPicker = true;
    lotStatus = '';             // one | many | none
    @track lotCands = [];
    rawJson = '';
    busy = false;
    error = '';
    sent;

    connectedCallback() {
        getSetup()
            .then((s) => { this.questions = s.questions || []; this.reporter = s.reporter; })
            .catch((e) => { this.error = msg(e); });
    }

    get isDescribe() { return this.phase === 'describe'; }
    get isReview() { return this.phase === 'review'; }
    get isDone() { return this.phase === 'done'; }

    // ---- describe step
    get canAnalyze() { return !!this.description && this.description.trim().length > 2 && !this.busy; }
    get analyzeDisabled() { return !this.canAnalyze; }
    handleDesc(e) { this.description = e.target.value; }

    handleAnalyze() {
        this.busy = true; this.error = '';
        fromDescription({ description: this.description })
            .then((res) => { this.applyResult(res); this.phase = 'review'; this.lookupLot(); })
            .catch((e) => { this.error = msg(e); })
            .finally(() => { this.busy = false; });
    }

    applyResult(res) {
        this.saidText = this.description;
        this.rawJson = res.rawJson;
        this.title = res.title || '';
        const byKey = {}; const byQ = {};
        (res.suggestions || []).forEach((s) => { byKey[s.key] = s; if (s.questionId) { byQ[s.questionId] = s; } });
        if (byKey.lot) { this.lot = byKey.lot.value; }
        if (byKey.units) { this.units = byKey.units.value; }
        if (byKey.defect) { this.defect = byKey.defect.value; }
        if (byKey.part) {
            this.partRaw = byKey.part.rawValue;
            if (byKey.part.recordId) { this.partId = byKey.part.recordId; this.partLabel = byKey.part.value; this.showPicker = false; }
            else { this.showPicker = true; }
        } else { this.showPicker = true; }
        this.rows = this.questions.map((q) => {
            const sug = byQ[q.id];
            return {
                id: q.id, question: q.question, answerType: q.answerType, role: q.role,
                required: q.required, choices: q.choices || [], help: q.help,
                answer: sug ? sug.value : '', fromAi: !!sug
            };
        });
        this.decorate();
    }

    // ---- lot -> part (same resolver the save-trigger uses)
    lookupLot() {
        this.lotStatus = ''; this.lotCands = [];
        if (!this.lot || this.partId) { return; }
        resolveLot({ lotRaw: this.lot })
            .then((m) => {
                if (!m) { return; }
                if (m.matches === 1 && m.partId) {
                    this.partId = m.partId; this.partLabel = m.partLabel;
                    if (m.lotName) { this.lot = m.lotName; }
                    this.showPicker = false; this.lotStatus = 'one';
                } else if (m.matches > 1) {
                    this.lotCands = (m.candidates || []).map((c) => ({
                        lotName: c.lotName, partId: c.partId, label: c.lotName + ' · ' + (c.partLabel || 'unknown part')
                    }));
                    this.showPicker = false; this.lotStatus = 'many';
                } else {
                    this.lotStatus = 'none'; this.showPicker = true;
                }
            })
            .catch(() => { /* leave the picker as the fallback */ });
    }

    get lotOne() { return this.lotStatus === 'one'; }
    get lotMany() { return this.lotStatus === 'many'; }
    get lotNone() { return this.lotStatus === 'none'; }

    handleLot(e) {
        this.lot = e.target.value;
        this.partId = null; this.partLabel = ''; this.showPicker = true;
        this.lookupLot();
    }
    handlePickCand(e) {
        const name = e.currentTarget.dataset.lot;
        const c = this.lotCands.find((x) => x.lotName === name);
        if (c) { this.lot = c.lotName; this.partId = c.partId; this.partLabel = c.label; this.lotStatus = 'one'; this.lotCands = []; this.showPicker = false; }
    }

    decorate() {
        this.rows = this.rows.map((r) => {
            const choice = r.answerType === 'Choice' || r.answerType === 'Yes or No';
            return {
                ...r,
                isChoice: choice,
                isText: !choice,
                needs: r.required && !r.answer,
                badgeAi: r.fromAi,
                badgeNeed: !r.fromAi && r.required && !r.answer,
                opts: (r.choices || []).map((c) => ({ key: r.id + '::' + c, label: c, pressed: String(c === r.answer), cls: 'cq-chip' + (c === r.answer && r.fromAi ? ' ai' : '') }))
            };
        });
    }

    handlePickOpt(e) {
        const id = e.currentTarget.dataset.id; const val = e.currentTarget.dataset.value;
        this.rows = this.rows.map((r) => (r.id === id ? { ...r, answer: val } : r));
        this.decorate();
    }
    handleTextAns(e) {
        const id = e.target.dataset.id; const val = e.target.value;
        this.rows = this.rows.map((r) => (r.id === id ? { ...r, answer: val } : r));
        this.decorate();
    }
    handleTitle(e) { this.title = e.target.value; }
    handleUnits(e) { this.units = e.target.value; }
    handlePartChange(e) { this.partId = e.detail.recordId; this.showPicker = false; this.partLabel = ''; this.lotStatus = ''; }
    changePart() { this.showPicker = true; this.partId = null; this.partLabel = ''; this.lotStatus = ''; }

    get missing() { return this.rows.filter((r) => r.required && !r.answer).length; }
    get missingLabel() { const n = this.missing; return n === 1 ? 'Answer 1 more' : 'Answer ' + n + ' more'; }
    get hasMissing() { return this.missing > 0; }
    get titleMissing() { return !this.title || !this.title.trim(); }
    get canSubmit() { return !this.busy && !this.titleMissing && !this.hasMissing; }
    get submitDisabled() { return !this.canSubmit; }

    handleSubmit() {
        this.busy = true; this.error = '';
        const answers = this.rows.filter((r) => r.answer).map((r) => ({ questionId: r.id, answer: r.answer }));
        const payload = JSON.stringify({
            title: this.title, problem: this.description, lot: this.lot,
            partId: this.partId, units: this.units, answers
        });
        submitReport({ payload })
            .then((res) => { this.sent = res; this.phase = 'done'; })
            .catch((e) => { this.error = msg(e); })
            .finally(() => { this.busy = false; });
    }

    handleBack() { this.phase = 'describe'; }

    handleRestart() {
        this.phase = 'describe'; this.description = ''; this.rows = []; this.title = '';
        this.lot = ''; this.units = ''; this.defect = ''; this.partId = null; this.partLabel = '';
        this.partRaw = ''; this.showPicker = true; this.lotStatus = ''; this.lotCands = [];
        this.rawJson = ''; this.sent = undefined; this.error = '';
    }
}
