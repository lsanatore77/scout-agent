import { LightningElement, track } from 'lwc';
import getSetup from '@salesforce/apex/CqEventIntake.getSetup';
import fromDescription from '@salesforce/apex/CqEventExtract.fromDescription';
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
    questions = [];              // from getSetup
    @track rows = [];            // one per question, with answer + AI metadata
    saidText = '';
    title = '';
    lot = '';
    units = '';
    defect = '';
    partId = null;
    partLabel = '';
    partRaw = '';
    showPicker = true;
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
            .then((res) => { this.applyResult(res); this.phase = 'review'; })
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
                opts: (r.choices || []).map((c) => ({ key: r.id + '::' + c, label: c, cls: c === r.answer ? 'opt on' : 'opt' }))
            };
        });
    }

    // ---- review step
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
    handleLot(e) { this.lot = e.target.value; }
    handleUnits(e) { this.units = e.target.value; }
    handlePartChange(e) { this.partId = e.detail.recordId; this.showPicker = false; this.partLabel = ''; }
    changePart() { this.showPicker = true; this.partId = null; this.partLabel = ''; }

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
        this.partRaw = ''; this.showPicker = true; this.rawJson = ''; this.sent = undefined; this.error = '';
    }
}
