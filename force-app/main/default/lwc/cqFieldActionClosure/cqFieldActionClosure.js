import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqFieldActionRecovery.getView';
import saveClosure from '@salesforce/apex/CqFieldActionRecovery.saveClosure';
import getSigner from '@salesforce/apex/CqFieldActionClose.getSigner';
import signAndClose from '@salesforce/apex/CqFieldActionClose.signAndClose';
import { askPolicies, anyRequired } from 'c/cqEsign';
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
    signer;              // the recall coordinator (the owner), who signs and closes; and the signature once made
    needSign = true;     // whether CQ's policy asks for a signature: an administrator may close for the coordinator only when not

    connectedCallback() { this._loading = this.load(); }
    async load() {
        try {
            const [v, s] = await Promise.all([getView({ recordId: this.recordId }), getSigner({ recordId: this.recordId })]);
            this.signer = s;
            this.apply(v);
            if (s.canAdmin && !s.closed) { this.needSign = anyRequired(await askPolicies(this.recordId, ['close'], 'Field_Action__c')); }
        }
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
    get ready() { return !!this.v && !!this.signer; }
    get busy() { return this.saving > 0; }
    get locked() { return this.v.closed; }

    renderedCallback() {
        if (!this.v) { return; }
        // a textarea shows its text through its value property, so it is set here (not while someone is typing in it)
        const ta = this.template.querySelector('textarea.ta');
        if (ta && this.template.activeElement !== ta && ta.value !== this.summaryText) { ta.value = this.summaryText; }
        // closing is signed in the Signature card (c-cq-sign-seat), so the footer keeps only Back and Next
        const detail = { show: false, label: '', disabled: true, blocker: '' };
        const sig = JSON.stringify(detail);
        if (sig !== this.footSig) { this.footSig = sig; this.dispatchEvent(new CustomEvent('footchange', { detail })); }
    }
    @api confirm() { /* closing is signed in the Signature card */ }
    /** Ask CQ.AI's Create CAPA link lands here. */
    @api async createCapa() { await this._loading; return this.handleCreateCapa(); }

    get stateText() { return this.v.closed ? 'Closed' : this.v.canClose ? 'Ready to Close' : 'Open Items'; }
    get statePill() { return 'cq-pill soft ' + (this.v.closed ? 'pos' : this.v.canClose ? 'neu' : 'warn'); }
    get closedLine() {
        return this.v.closed ? 'Closed by ' + this.v.closedBy + ' · ' + new Date(this.v.closedOn).toLocaleString() : '';
    }
    get intro() {
        return this.v.closed ? 'This field action is closed and takes no more changes.'
            : 'Check that everything is done, record the closing summary and what follows, then sign and close. A closed field action is locked.';
    }

    // ---- checklist: plain marks as on Scope and the Verdict (✓ done, ✕ open and stops closing, ! open but does not,
    // – not applicable), grouped so what stops closing comes first. An open item links to the step that settles it.
    get groups() {
        const rows = this.v.checks.map((c) => {
            const open = c.state === 'open';
            const step = STEP_OF[c.key];
            return { ...c,
                mark: c.state === 'ok' ? '✓' : open ? (c.blocks ? '✕' : '!') : '–',
                markCls: 'cq-mark ' + (c.state === 'ok' ? 'ok' : open ? (c.blocks ? 'bad' : 'warn') : 'na'),
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
                detail: detail.charAt(0).toUpperCase() + detail.slice(1), mark: '–', markCls: 'cq-mark na', state: 'Not applicable' }] });
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

    // ---- signature: the shared signature seat (docs/esignature.md); the recall coordinator, the owner, signs and closes
    seatActions = [{ action: 'close', label: 'Close Field Action', doing: 'Closing', signing: 'closing the field action' }];
    get signMine() { return !!this.signer.mine && !this.v.closed; }
    get signPerson() { return this.signer.name + (this.signer.mine ? ' (you)' : ''); }
    get signSub() {
        const s = this.signer;
        if (s.signed) { return 'Signed ' + new Date(s.signedOn).toLocaleString() + ' · electronic signature'; }
        if (this.v.closed) { return 'Closed ' + new Date(this.v.closedOn).toLocaleString() + (this.v.closedBy ? ' by ' + this.v.closedBy : '') + ' · no signature asked'; }
        return s.mine ? 'Waiting for you' : 'Waiting for ' + s.name;
    }
    get signQuote() { return this.signer.signed && this.signer.comment ? '“' + this.signer.comment + '”' : ''; }
    get signStatus() { return this.signer.signed ? 'Signed' : this.v.closed ? 'Closed' : this.signMine ? 'Your Signature' : 'Waiting'; }
    get signTone() { return this.v.closed ? 'pos' : this.signMine ? 'you' : 'warn'; }
    get signCount() { return (this.signer.signed ? 1 : 0) + ' of 1 signed'; }
    get signNote() {
        if (this.v.closed) { return this.signer.signed ? 'Signed with CQ\'s electronic signature. The signature is also in the Audit Trail.' : 'Closed. CQ\'s signature policy asked for no signature; the closing is in the Audit Trail.'; }
        return 'Signatures run on CQ\'s electronic signature. The field action closes when the recall coordinator signs.';
    }
    get signBlocker() { return this.v.closed ? '' : this.blocker; }
    get adminClose() { return !!this.signer.canAdmin && !this.needSign && !this.v.closed; }
    /** The seat signs and closes in one request (CqFieldActionClose.signAndClose); a refusal shows under its button. */
    seatSubmit = async ({ comment, password }) => {
        this.error = undefined; this.saving += 1;
        try {
            this.apply(await signAndClose({ recordId: this.recordId, summary: this.summaryText, comment, password }));
            this.typed = undefined;
            this.signer = await getSigner({ recordId: this.recordId });
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } finally { this.saving -= 1; }
    };
    /** An administrator closes for the coordinator: only when CQ's policy asks for no signature. */
    async handleAdminClose() {
        if (this.cantClose) { return; }
        await this.call(() => signAndClose({ recordId: this.recordId, summary: this.summaryText, comment: null, password: null }), 'Could not close the field action.');
        this.typed = undefined;
        try { this.signer = await getSigner({ recordId: this.recordId }); } catch (e) { /* the card keeps what it had */ }
    }
}
