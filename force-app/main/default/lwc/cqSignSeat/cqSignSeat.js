import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import USERNAME from '@salesforce/schema/User.Username';
import { askPolicies } from 'c/cqEsign';

/**
 * The signature seat, the one way any screen signs (the standard: docs/esignature.md). It shows who signs and where the
 * signature stands. For the signer (mine) it also shows the comment, the meaning of the signature from CQ's policy, the
 * password and the buttons, and asks CQ's policy for each action first. Whether a password and a comment are needed is
 * CQ's policy. The password must be typed: autofill, paste and drop are refused. It is never rendered, never stored, and
 * cleared after every attempt. The screen's own submit(detail) signs and acts in one request on the server (CqEsign.sign).
 *
 * actions: [{ action, label, doing, signing, needsComment, commentWhy }], the first is the main one, for example
 *   { action: 'approve', label: 'Approve', doing: 'Approving', signing: 'approving' }.
 * submit: a function the screen passes ((detail) => Promise), detail = { ref, action, comment, password }; a rejected
 *   promise shows its message under the buttons.
 * Above the password the signer sees their own Salesforce username, read-only (Lou, 27 Nov), so it is clear whose
 * signature this is. It is shown, never sent: the server signs as the running user.
 */
export default class CqSignSeat extends LightningElement {
    @api recordId;
    @api policyKey;          // the key CQ's answer is kept under in the tab: the object's API name
    @api actions = [];
    @api seat;               // the role that signs, for example Recall Coordinator
    @api person;             // who holds it
    @api sub;                // a line under the person: waiting for, signed on, owner of
    @api quote;              // the comment given with a signature already made
    @api status;             // the pill: Waiting, Your Signature, Signed, Sent Back
    @api tone = 'neu';       // the pill's tone: you, pos, crit, warn, neu
    @api meaning;            // what signing means when CQ's policy gives no purpose
    @api commentHint = '';   // the comment box's hint when CQ's policy does not ask for a comment
    @api ref;                // passed back in submit's detail: the step, seat or record this seat is for
    @api submit;
    @api disabled = false;

    signs = {};
    loading = false;
    acting = '';
    actingSign = false;
    comment = '';
    error = '';
    pwWarn = '';
    _pw = '';
    _asked = false;

    @wire(getRecord, { recordId: USER_ID, fields: [USERNAME] }) me;
    get username() { return (this.me && this.me.data && getFieldValue(this.me.data, USERNAME)) || ''; }

    _mine = false;
    @api
    get mine() { return this._mine; }
    set mine(v) {
        this._mine = !!v;
        if (this._mine && !this._asked && this.recordId) { this.loadPolicies(false); }
    }
    connectedCallback() { if (this._mine && !this._asked) { this.loadPolicies(false); } }

    /** The seat waits for CQ's answer, so a button never goes without the password box when one is needed. */
    async loadPolicies(fresh) {
        this._asked = true;
        const list = (this.actions || []).map((a) => a.action);
        if (!list.length) { return; }
        this.loading = true;
        try { this.signs = (await askPolicies(this.recordId, list, this.policyKey, fresh)) || {}; }
        catch (e) { this.signs = list.reduce((o, a) => ({ ...o, [a]: { unknown: true } }), {}); }
        this.loading = false;
    }
    signOf(action) { return (this.signs || {})[action] || {}; }
    get first() { return (this.actions || [])[0] || {}; }
    get needSign() { return (this.actions || []).some((a) => this.signOf(a.action).required); }
    get unknown() { return !this.loading && (this.actions || []).some((a) => this.signOf(a.action).unknown); }
    get commentRequired() { return (this.actions || []).some((a) => this.signOf(a.action).required && this.signOf(a.action).comment); }
    get hint() { return this.commentRequired ? 'Required with your signature.' : this.commentHint; }
    get signMeaning() {
        const p = this.signOf(this.first.action).purpose;
        return 'By signing, you ' + (p ? 'confirm: ' + p : (this.meaning || 'confirm this')) + '. Type your password; it is not saved.';
    }
    get rowCls() { return 'seat' + (this._mine ? ' yours' : ''); }
    get pillCls() { return 'cq-pill soft ' + (this.tone || 'neu'); }
    get busy() { return this.disabled || this.loading || !!this.acting; }
    get covering() { return !!this.acting || this.loading; }
    get coverLine() {
        if (!this.acting) { return 'Getting your signature ready…'; }
        const a = (this.actions || []).find((x) => x.action === this.acting) || {};
        return this.actingSign ? 'Checking your signature with CQ and ' + (a.signing || 'signing') + '…' : (a.doing || 'Saving') + '…';
    }
    get buttons() {
        return (this.actions || []).map((a, i) => {
            const sign = this.signOf(a.action).required;
            const text = this.acting === a.action ? (sign ? 'Signing…' : (a.doing || 'Saving') + '…') : (sign ? 'Sign and ' : '') + a.label;
            return { key: a.action, action: a.action, text, cls: i === 0 ? 'cq-btn-primary' : 'cq-btn-outline' };
        });
    }
    get unknownLine() {
        return 'Could not check whether this needs an electronic signature. ' + (this.first.label || 'Signing')
            + ' is held until it can be checked; refresh to try again.';
    }

    handleComment(event) { this.comment = event.target.value; }

    /** Only typed characters count: autofill, paste and drop are refused, so the signer types the password themselves. */
    handlePwInput(event) {
        const t = event.inputType || '';
        if (t.startsWith('insertText') || t.startsWith('delete') || t === 'insertCompositionText') {
            this._pw = event.target.value; this.pwWarn = '';
            return;
        }
        this.refusePw(event.target);
    }
    handlePwBlock(event) { event.preventDefault(); this.refusePw(event.target); }
    /** The browser filled the field itself (its autofill animation starts): clear it. */
    handlePwAutofill(event) { if ((event.animationName || '').toLowerCase().includes('autofill')) { this.refusePw(event.target); } }
    refusePw(el) {
        if (el) { el.value = ''; }
        this._pw = '';
        this.pwWarn = 'Please type your password. Filled-in or pasted passwords are not accepted for a signature.';
    }
    /**
     * The signature box is a text box drawn with dots, so the browser does not treat it as a password box and offer
     * saved passwords. Where the browser cannot draw the dots it stays a password box, so the password is never shown.
     */
    get pwMasked() {
        try { return typeof CSS !== 'undefined' && !!CSS.supports && CSS.supports('-webkit-text-security', 'disc'); }
        catch (e) { return false; }
    }
    get pwType() { return this.pwMasked ? 'text' : 'password'; }
    get pwAuto() { return this.pwMasked ? 'off' : 'new-password'; }
    get pwStyle() { return this.pwMasked ? '-webkit-text-security: disc;' : ''; }
    clearPw() {
        this._pw = '';
        const el = this.template.querySelector('input.sigpw');
        if (el) { el.value = ''; }
    }

    async handleAct(event) {
        const action = event.currentTarget.dataset.a;
        if (this.busy || typeof this.submit !== 'function') { return; }
        const a = (this.actions || []).find((x) => x.action === action) || {};
        const g = this.signOf(action);
        const said = this.comment.trim();
        this.error = '';
        if (a.needsComment && !said) { this.error = a.commentWhy || 'Add a comment.'; return; }
        if (g.required && g.comment && !said) { this.error = 'A comment is required with your signature.'; return; }
        if (g.required && !this._pw) { this.error = 'Type your password to sign.'; return; }
        const password = g.required ? this._pw : null;
        this.clearPw();                 // never kept, whatever happens next
        this.actingSign = !!g.required; this.acting = action;
        try {
            await this.submit({ ref: this.ref, action, comment: said, password });
            this.comment = '';
        } catch (e) {
            this.error = (e && e.body && e.body.message) || (e && e.message) || 'Could not record that.';
            // went without a signature and was refused: the policy may have changed since it was kept, so ask CQ again
            if (!g.required) { this.loadPolicies(true); }
        }
        this.acting = '';
    }
}
