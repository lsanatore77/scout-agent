import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqFieldActionRecovery.getView';
import saveClosure from '@salesforce/apex/CqFieldActionRecovery.saveClosure';
import closeFieldAction from '@salesforce/apex/CqFieldActionRecovery.closeFieldAction';

/** Field Action step 7, Closure: the checklist, the closing summary, what follows, and Close Field Action. */
export default class CqFieldActionClosure extends LightningElement {
    @api recordId;
    v;
    error;
    saving = 0;
    footSig;
    typed;               // the summary as typed, before it is saved

    async connectedCallback() {
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
        const detail = { show: true, label: this.closeLabel, disabled: this.cantClose, blocker: this.blocker };
        const sig = JSON.stringify(detail);
        if (sig !== this.footSig) { this.footSig = sig; this.dispatchEvent(new CustomEvent('footchange', { detail })); }
    }
    @api confirm() { return this.handleClose(); }

    get stateText() { return this.v.closed ? 'Closed' : this.v.canClose ? 'Ready to Close' : 'Open Items'; }
    get statePill() { return 'spill ' + (this.v.closed ? 'ok' : this.v.canClose ? '' : 'wait'); }
    get closedLine() {
        return this.v.closed ? 'Closed by ' + this.v.closedBy + ' · ' + new Date(this.v.closedOn).toLocaleString() : '';
    }
    get intro() {
        return this.v.closed ? 'This field action is closed and takes no more changes.'
            : 'Check that everything is done, record the closing summary and what follows, then close. A closed field action is locked.';
    }

    // ---- checklist
    get checks() {
        return this.v.checks.map((c) => ({ ...c,
            mark: c.state === 'ok' ? '✓' : c.state === 'na' ? '–' : '!',
            markCls: 'mk ' + c.state }));
    }
    get checkLine() {
        const done = this.v.checks.filter((c) => c.state === 'ok').length;
        const na = this.v.checks.filter((c) => c.state === 'na').length;
        return done + ' of ' + (this.v.checks.length - na) + ' done' + (na ? ' · ' + na + ' not applicable' : '');
    }

    // ---- summary and links
    get summaryText() { return this.typed !== undefined ? this.typed : this.v.summary || this.v.sSummary || ''; }
    get isDraft() { return !this.v.summary && this.typed === undefined; }
    handleSummaryInput(event) { this.typed = event.target.value; }
    async handleSummary(event) {
        const value = event.target.value;
        await this.call(() => saveClosure({ recordId: this.recordId, field: 'summary', value }), 'Could not save the summary.');
        this.typed = undefined;
    }
    get capaOpts() {
        const list = (this.v.capas || []).map((c) => ({ value: c.id, label: c.name + (c.title ? ' · ' + c.title : ''), selected: c.id === this.v.capaId }));
        if (this.v.capaId && !list.some((c) => c.selected)) { list.unshift({ value: this.v.capaId, label: this.v.capaName, selected: true }); }
        return [{ value: '', label: 'Choose a CAPA…', selected: !this.v.capaId }].concat(list);
    }
    async handleCapa(event) {
        const value = event.target.value;
        await this.call(() => saveClosure({ recordId: this.recordId, field: 'capa', value }), 'Could not save the CAPA.');
    }
    get otherText() { return this.v.otherRecords || this.v.sOther || ''; }
    async handleOther(event) {
        const value = event.target.value;
        await this.call(() => saveClosure({ recordId: this.recordId, field: 'other', value }), 'Could not save that.');
    }

    // ---- close
    get blocker() {
        if (this.v.closed) { return ''; }
        const open = this.v.checks.filter((c) => c.state === 'open' && c.blocks).map((c) => c.text.toLowerCase());
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
