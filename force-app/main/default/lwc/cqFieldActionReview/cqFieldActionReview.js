import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getGlance from '@salesforce/apex/CqTriageController.getGlance';
import setFieldAction from '@salesforce/apex/CqTriageController.setFieldAction';

/**
 * Field Action Review on a Nonconformance: CQ.AI suggests, the triager decides. Saved on the NC as soon as it is chosen.
 * One card, built like the other Next Steps decisions: name and state, the suggestion, then the two choices as chips.
 * The card never grows: who set it and why sit behind Details. Send for Review asks for the reason in a popup, and
 * shows as chosen while that popup is open. Once the review has been decided the choice can no longer change.
 */
export default class CqFieldActionReview extends NavigationMixin(LightningElement) {
    @api recordId;
    fa;
    asking = false;
    reason = '';
    busy = false;
    focusNext = false;
    detailing = false;
    error;

    connectedCallback() { this.load(); }

    async load() {
        try { this.fa = (await getGlance({ recordId: this.recordId })).fieldAction; this.error = undefined; }
        catch (e) { this.error = this.msg(e); }
    }

    get status() { return this.fa && this.fa.status; }
    get isSent() { return this.status === 'Sent for Review'; }
    get isDone() { return !!this.status && !this.asking; }
    // a review can exist without a decision on the NC (opened from the review side): show it, don't ask again
    get reviewOnly() { return !!this.fa && !this.status && !!this.fa.reviewId; }
    get isOpen() { return !!this.fa && !this.status && !this.reviewOnly && !this.asking; }
    get statusText() { return this.asking ? 'Sending for review' : this.status || (this.reviewOnly ? 'Review opened' : 'Not set'); }
    get cannotSend() { return this.busy || !this.reason.trim(); }
    get doneNote() {
        if (!this.isDone) { return ''; }
        const who = this.fa.setBy ? ' by ' + this.fa.setBy : '';
        return this.isSent
            ? 'Sent for review' + who + '. Reason: ' + (this.fa.reason || '')
            : 'Set to Not Needed' + who + '.';
    }
    // the Field Action Review created by Send for Review
    get hasReview() { return ((this.isDone && this.isSent) || this.reviewOnly) && !this.asking && !!this.fa.reviewId; }
    get reviewLine() {
        const f = this.fa;
        return f.reviewStatus === 'Decided' ? 'Decided: ' + (f.reviewOutcome || '') : f.reviewStatus;
    }
    get hasFa() { return this.hasReview && !!this.fa.faId; }
    get decided() { return !!this.fa && (this.fa.reviewStatus === 'Decided' || (this.fa.reviewStatus === 'Withdrawn' && !!this.fa.reviewOutcome)); }
    /** The choice is fixed once the review is decided, or when a review was opened from the review side. */
    get locked() { return this.busy || !this.fa || this.reviewOnly || (this.isSent && this.decided); }
    get opts() {
        const sug = this.fa && this.fa.suggestion;
        return [['Not Needed', 'Not Needed', 'Not Needed'], ['Sent for Review', 'Send for Review', 'Send for Review']].map(([id, label, sugName]) => ({
            id, label,
            cls: 'cq-chip' + (sug === sugName ? ' ai' : ''),     // the suggested choice is purple, chosen or not
            pressed: String(this.asking ? id === 'Sent for Review' : this.status === id),     // Send shows as chosen while its popup is open
            off: this.locked
        }));
    }
    get rowError() { return !!this.error && !this.asking; }
    get canDetail() { return this.isDone; }
    get details() {
        const f = this.fa || {};
        const rows = [{ k: 'Decision', v: this.status }];
        if (f.setBy) { rows.push({ k: 'Set By', v: f.setBy }); }
        if (f.setOn) { rows.push({ k: 'Set On', v: new Date(f.setOn).toLocaleString() }); }
        if (this.isSent) { rows.push({ k: 'Reason', v: f.reason || '' }); }
        if (this.hasReview) { rows.push({ k: 'Review', v: f.reviewName + ' · ' + this.reviewLine }); }
        return rows;
    }
    handleDetails() { this.detailing = true; }
    handleCloseDetails() { this.detailing = false; }
    handleOpen(event) {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' } });
    }

    handlePick(event) {
        const id = event.currentTarget.dataset.id;
        if (this.locked || id === this.status) { return; }
        if (id === 'Sent for Review') { this.asking = true; this.reason = ''; this.error = undefined; this.focusNext = true; }
        else { this.save('Not Needed', null); }
    }
    handleCancel() { this.asking = false; this.error = undefined; }
    handleKey(event) { if (event.key === 'Escape') { this.handleCancel(); this.detailing = false; } }
    renderedCallback() {
        if (!this.focusNext || !this.asking) { return; }
        const ta = this.template.querySelector('textarea.reason');
        if (ta) { ta.focus(); this.focusNext = false; }
    }
    handleReason(event) { this.reason = event.target.value; }
    handleSend() { if (!this.cannotSend) { this.save('Sent for Review', this.reason); } }

    async save(decision, reason) {
        this.busy = true; this.error = undefined;
        try {
            this.fa = await setFieldAction({ recordId: this.recordId, decision, reason });
            this.asking = false;
            this.dispatchEvent(new CustomEvent('changed', { bubbles: true, composed: true }));
        } catch (e) { this.error = this.msg(e); }
        finally { this.busy = false; }
    }
    msg(e) { return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.'; }
}
