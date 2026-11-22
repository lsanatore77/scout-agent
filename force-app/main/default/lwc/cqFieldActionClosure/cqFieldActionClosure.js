import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqFieldActionRecovery.getView';
import saveClosure from '@salesforce/apex/CqFieldActionRecovery.saveClosure';
import closeFieldAction from '@salesforce/apex/CqFieldActionRecovery.closeFieldAction';
import createCapaApex from '@salesforce/apex/CqFieldActionRecovery.createCapa';

/** The step an open checklist item is settled on (the workspace opens it on a gostep event), and its name. */
const STEP_OF = { scope: 'scope', strategy: 'strategy', units: 'recovery', customers: 'recovery', tasks: 'recovery', holds: 'recovery', verdict: 'recovery' };
const STEP_LABEL = { scope: 'Scope', strategy: 'Strategy', recovery: 'Recovery' };

/** Field Action step 7, Closure: the checklist, the closing summary, what follows, and Close Field Action. */
export default class CqFieldActionClosure extends LightningElement {
    @api recordId;
    v;
    error;
    saving = 0;
    footSig;
    typed;               // the summary as typed, before it is saved

    connectedCallback() { this._loading = this.load(); }
    async load() {
        try { this.apply(await getView({ recordId: this.recordId })); }
        catch (e) { this.error = this.msg(e, 'Could not read closure.'); }
    }
    msg(e, fallback) { return (e && e.body && e.body.message) || fallback; }
    apply(v) {
        this.v = JSON.parse(JSON.stringify(v));
        this.dispatchEvent(new CustomEvent('railchange', { detail: { recovery: this.v.recovery, verdict: this.v.verdict, status: this.v.status } }));
    }
    async call(fn, fallback) {
        this.error = undefined;
        this.saving += 1;
        try { this.apply(await fn()); notifyRecordUpdateAvailable([{ recordId: this.recordId }]); }
        catch (e) { this.error = this.msg(e, fallback); }
        this.saving -= 1;
    }
    get ready() { return !!this.v; }
    get busy() { return this.saving > 0; }
    get locked() { return this.v.closed; }

    renderedCallback() {
        if (!this.v) { return; }
        // a textarea shows its text through its value property, so it is set here (not while someone is typing in it)
        const ta = this.template.querySelector('textarea.ta');
        if (ta && this.template.activeElement !== ta && ta.value !== this.summaryText) { ta.value = this.summaryText; }
        const detail = { show: true, label: this.closeLabel, disabled: this.cantClose, blocker: this.blocker };
        const sig = JSON.stringify(detail);
        if (sig !== this.footSig) { this.footSig = sig; this.dispatchEvent(new CustomEvent('footchange', { detail })); }
    }
    @api confirm() { return this.handleClose(); }
    /** Ask CQ.AI's Create CAPA link lands here. */
    @api async createCapa() { await this._loading; return this.handleCreateCapa(); }

    get stateText() { return this.v.closed ? 'Closed' : this.v.canClose ? 'Ready to Close' : 'Open Items'; }
    get statePill() { return 'cq-pill soft ' + (this.v.closed ? 'pos' : this.v.canClose ? 'neu' : 'warn'); }
    get closedLine() {
        return this.v.closed ? 'Closed by ' + this.v.closedBy + ' · ' + new Date(this.v.closedOn).toLocaleString() : '';
    }
    get intro() {
        return this.v.closed ? 'This field action is closed and takes no more changes.'
            : 'Check that everything is done, record the closing summary and what follows, then close. A closed field action is locked.';
    }

    // ---- checklist: plain marks as on Scope and the Verdict (✓ done, ✕ open and stops closing, ! open but does not,
    // – not applicable), grouped so what stops closing comes first. An open item links to the step that settles it.
    get groups() {
        const rows = this.v.checks.map((c) => {
            const open = c.state === 'open';
            const step = STEP_OF[c.key];
            return { ...c,
                mark: c.state === 'ok' ? '✓' : open ? (c.blocks ? '✕' : '!') : '–',
                markCls: 'mk ' + (c.state === 'ok' ? 'ok' : open ? (c.blocks ? 'no' : 'op') : 'na'),
                state: c.state === 'ok' ? 'Done' : open ? (c.blocks ? 'Open, needed before closing' : 'Open') : 'Not applicable',
                hasGo: open && !!step && !this.v.closed, goStep: step, goLabel: step ? 'Go to ' + STEP_LABEL[step] + ' ›' : '',
                createCapa: c.key === 'capa' && open && !this.v.closed && !this.busy };
        });
        const need = rows.filter((c) => c.state !== 'Not applicable' && c.blocks);
        const finish = rows.filter((c) => c.state !== 'Not applicable' && !c.blocks);
        const na = rows.filter((c) => c.state === 'Not applicable');
        const out = [];
        if (need.length) { out.push({ key: 'need', label: 'Needed to Close', rows: need }); }
        if (finish.length) { out.push({ key: 'finish', label: 'Good to Finish', rows: finish }); }
        if (na.length) {
            const detail = na.map((c) => (c.detail || '').replace(/^Not Applicable: /, '')).join(' · ');
            out.push({ key: 'na', label: 'Not Applicable', rows: [{ key: 'na', text: na.map((c) => c.text).join(' · '),
                detail: detail.charAt(0).toUpperCase() + detail.slice(1), mark: '–', markCls: 'mk na', state: 'Not applicable' }] });
        }
        return out;
    }
    get checkLine() {
        const done = this.v.checks.filter((c) => c.state === 'ok').length;
        const na = this.v.checks.filter((c) => c.state === 'na').length;
        const stops = this.v.checks.filter((c) => c.state === 'open' && c.blocks).length;
        return done + ' of ' + (this.v.checks.length - na) + ' done' + (stops ? ' · ' + stops + ' block closing' : '');
    }
    handleGo(event) {
        this.dispatchEvent(new CustomEvent('gostep', { detail: { step: event.currentTarget.dataset.step }, bubbles: true }));
    }

    // ---- summary and links
    get summaryText() { return this.typed !== undefined ? this.typed : this.v.summary || this.v.sSummary || ''; }
    get isDraft() { return !this.v.summary && this.typed === undefined; }
    get canRedraft() { return !this.isDraft && !this.locked; }
    /** Redraft: clear the saved summary, so CQ.AI's current draft (built from the checklist) shows again. */
    async handleRedraft() {
        this.typed = undefined;
        await this.call(() => saveClosure({ recordId: this.recordId, field: 'summary', value: '' }), 'Could not redraft the summary.');
    }
    handleSummaryInput(event) { this.typed = event.target.value; }
    async handleSummary(event) {
        const value = event.target.value;
        await this.call(() => saveClosure({ recordId: this.recordId, field: 'summary', value }), 'Could not save the summary.');
        this.typed = undefined;
    }
    // ---- what follows: create a new CAPA or link an existing one; once linked, a reference with its status
    get hasCapa() { return !!this.v.capaId; }
    get noCapa() { return !this.v.capaId; }
    get capaUrl() { return '/lightning/r/compliancequest__SQX_CAPA__c/' + this.v.capaId + '/view'; }
    get capaStatusCls() { return 'cq-pill soft ' + (this.v.capaStatus === 'Closed' || this.v.capaStatus === 'Complete' ? 'pos' : 'neu'); }
    get cantCreate() { return this.locked || this.busy; }
    get capaOpts() {
        const list = (this.v.capas || []).map((c) => ({ value: c.id, label: c.name + (c.title ? ' · ' + c.title : ''), selected: false }));
        return [{ value: '', label: 'Link an Existing CAPA…', selected: true }].concat(list);
    }
    async handleCapa(event) {
        const value = event.target.value;
        if (!value) { return; }
        await this.call(() => saveClosure({ recordId: this.recordId, field: 'capa', value }), 'Could not link the CAPA.');
    }
    async handleUnlink() {
        await this.call(() => saveClosure({ recordId: this.recordId, field: 'capa', value: '' }), 'Could not unlink the CAPA.');
    }
    async handleCreateCapa() {
        if (this.cantCreate || this.hasCapa) { return; }
        await this.call(() => createCapaApex({ recordId: this.recordId }), 'Could not create the CAPA.');
    }

    // ---- close
    get blocker() {
        if (this.v.closed) { return ''; }
        // the CAPA item reads as its own sentence; the rest as lowercase item names
        const open = this.v.checks.filter((c) => c.state === 'open' && c.blocks).map((c) => (c.key === 'capa' ? c.detail : c.text.toLowerCase()));
        return open.length ? 'Before closing: ' + open.join(', ') : '';
    }
    get cantClose() { return this.v.closed || this.busy || !this.v.canClose; }
    get closeLabel() { return this.busy ? 'Saving…' : this.v.closed ? 'Field Action Closed' : 'Close Field Action'; }
    async handleClose() {
        if (this.cantClose) { return; }
        const summary = this.summaryText;
        await this.call(() => closeFieldAction({ recordId: this.recordId, summary }), 'Could not close the field action.');
        this.typed = undefined;
    }
}
