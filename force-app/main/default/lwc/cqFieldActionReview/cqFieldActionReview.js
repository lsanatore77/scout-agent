import { LightningElement, api } from 'lwc';
import getGlance from '@salesforce/apex/CqTriageController.getGlance';
import setFieldAction from '@salesforce/apex/CqTriageController.setFieldAction';

/** Field Action Review on a Nonconformance: CQ.AI suggests, the triager decides. Saved on the NC. */
export default class CqFieldActionReview extends LightningElement {
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
            ? 'Sent to the Recall Coordinator' + who + '. Reason: ' + (this.fa.reason || '')
            : 'Set to Not Needed' + who + '.';
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
