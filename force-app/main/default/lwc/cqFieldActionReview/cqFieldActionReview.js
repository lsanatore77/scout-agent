import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getGlance from '@salesforce/apex/CqTriageController.getGlance';
import setFieldAction from '@salesforce/apex/CqTriageController.setFieldAction';

/** Field Action Review on a Nonconformance: CQ.AI suggests, the triager decides. Saved on the NC. */
export default class CqFieldActionReview extends NavigationMixin(LightningElement) {
    @api recordId;
    fa;
    asking = false;
    reason = '';
    busy = false;
    error;

    connectedCallback() { this.load(); }

    async load() {
        try { this.fa = (await getGlance({ recordId: this.recordId })).fieldAction; this.error = undefined; }
        catch (e) { this.error = this.msg(e); }
    }

    get status() { return this.fa && this.fa.status; }
    get isSent() { return this.status === 'Sent for Review'; }
    get isDone() { return !!this.status && !this.asking; }
    get isOpen() { return !!this.fa && !this.status && !this.asking; }
    get statusText() { return this.asking ? 'Sending for review' : this.status || 'Not set'; }
    get boxClass() { return 'box' + (this.isSent ? ' sent' : ''); }
    get noteClass() { return 'note' + (this.isSent ? ' red' : ''); }
    get cannotSend() { return this.busy || !this.reason.trim(); }
    get doneNote() {
        if (!this.isDone) { return ''; }
        const who = this.fa.setBy ? ' by ' + this.fa.setBy : '';
        return this.isSent
            ? 'Sent for review' + who + '. Reason: ' + (this.fa.reason || '')
            : 'Set to Not Needed' + who + '.';
    }
    // the Field Action Review created by Send for Review
    get hasReview() { return this.isDone && this.isSent && !!this.fa.reviewId; }
    get reviewLine() {
        const f = this.fa;
        return f.reviewStatus === 'Decided' ? 'Decided: ' + (f.reviewOutcome || '') : f.reviewStatus;
    }
    get hasFa() { return this.hasReview && !!this.fa.faId; }
    get decided() { return !!this.fa && (this.fa.reviewStatus === 'Decided' || (this.fa.reviewStatus === 'Closed' && !!this.fa.reviewOutcome)); }
    get canChange() { return this.isDone && !(this.isSent && this.decided); }
    handleOpen(event) {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' } });
    }

    handleAsk() { this.asking = true; this.reason = ''; }
    handleCancel() { this.asking = false; }
    handleReason(event) { this.reason = event.target.value; }
    handleNotNeeded() { this.save('Not Needed', null); }
    handleSend() { this.save('Sent for Review', this.reason); }
    handleChange() { this.save(null, null); }

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
