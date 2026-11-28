import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqImplementWorkspace.getView';
import completeAction from '@salesforce/apex/CqImplementWorkspace.complete';
import skipAction from '@salesforce/apex/CqImplementWorkspace.skip';
import verifyAction from '@salesforce/apex/CqImplementWorkspace.verify';
import reassignAction from '@salesforce/apex/CqImplementWorkspace.reassign';
import remindAction from '@salesforce/apex/CqImplementWorkspace.sendReminder';
import closeAction from '@salesforce/apex/CqImplementWorkspace.close';

const OBJ = 'compliancequest__SQX_Action__c';
const REOPEN = 'compliancequest__SQX_Action__c.cqext__cqui_Reopen';   // CQ's own Reopen: Send Back
const NC_OBJ = 'compliancequest__SQX_Nonconformance__c';
const NC_REOPEN_IMPL = 'compliancequest__SQX_Nonconformance__c.cqext__cqui_Reopenimplementation';
const NC_ESCALATE = 'compliancequest__SQX_Nonconformance__c.cqext__cqui_Escalatecapa';
const ASK = 'Which corrections are late?,What was done on each correction?,What happens when all corrections are done?';
const DAY = 86400000;

/**
 * CQ.AI Implement workspace, the NC owner's view of every correction on the NC (Lou, 27 Nov). The owner chases what is
 * open (Send Reminder, Reassign) and verifies what is done when CQ asks for it. An owner who is also an assignee completes
 * their own correction in a panel under its row, with the same checks and signature as the assignee's page. One panel is
 * open at a time. Send Back opens CQ's own Reopen in a new tab.
 * When every correction is done (CQ completes the NC: Verification) the owner closes it under the table: Effective or
 * Ineffective, the closing summary, and the signature. Ineffective offers Reopen Implementation or Escalate to a CAPA
 * (CQ's own actions, new tab) before closing. No override: the section only shows once CQ has completed the NC.
 */
export default class CqImplementWorkspace extends LightningElement {
    @api recordId;
    v;
    loadError;
    error;
    note;              // what the last action did
    openId;            // the row whose panel is open
    openKind;          // complete, skip, verify, reassign
    whatWasDone = '';
    completedOn;
    skipReason = '';
    howChecked = '';
    reassignTo;
    files = [];
    busy = false;
    _seatActions;
    resolution;        // Effective or Ineffective
    closeSummary = '';
    _closeActions = [{ action: 'close', label: 'Close the Nonconformance', doing: 'Closing', signing: 'closing the nonconformance' }];

    connectedCallback() {
        this.completedOn = this.todayIso();
        this.load();
    }

    async load() {
        try {
            this.v = await getView({ recordId: this.recordId });
            this.loadError = undefined;
        } catch (e) {
            this.loadError = this.msg(e, 'Could not read the corrections on this NC.');
        }
    }

    get ready() { return !!this.v; }
    msg(e, fallback) { return (e && e.body && e.body.message) || (e && e.message) || fallback; }
    todayIso() { const d = new Date(); const p = (n) => String(n).padStart(2, '0'); return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()); }
    dateText(iso) { return iso ? new Date(iso + 'T00:00:00').toLocaleDateString() : '—'; }
    daysTo(iso) { return Math.round((new Date(iso + 'T00:00:00').getTime() - new Date(this.todayIso() + 'T00:00:00').getTime()) / DAY); }
    isLate(r) { return r.status === 'Open' && r.due && this.daysTo(r.due) < 0; }

    // ---- header
    get headerFields() {
        const v = this.v;
        return [
            { key: 'part', label: 'Part · Lot', value: [v.partNumber, v.lot].filter((x) => x).join(' · ') || '—' },
            { key: 'stage', label: 'Stage', value: v.stage || '—' },
            { key: 'rc', label: 'Root Cause', value: v.rootCause || '—' },
            { key: 'owner', label: 'Owner', value: v.isOwner && v.owner ? v.owner + ' (you)' : v.owner || '—' }
        ];
    }
    get askSuggestions() { return ASK; }

    // ---- the counts
    get counts() {
        const rows = this.v.rows || [];
        const done = rows.filter((r) => r.status !== 'Open').length;
        return { total: rows.length, done, late: rows.filter((r) => this.isLate(r)).length,
                 verify: rows.filter((r) => r.toVerify).length, mineVerify: rows.filter((r) => r.canVerify).length };
    }
    get cards() {
        const c = this.counts;
        return [
            { key: 'done', label: 'Done', n: c.done + ' of ' + c.total, numCls: 'cq-statcard-v' + (c.total && c.done === c.total ? ' ok' : '') },
            { key: 'late', label: 'Overdue', n: String(c.late), numCls: 'cq-statcard-v' + (c.late ? ' bad' : '') },
            { key: 'ver', label: 'To Verify', n: c.verify + (c.mineVerify ? ' (' + (c.mineVerify === c.verify ? 'you' : c.mineVerify + ' yours') + ')' : ''), numCls: 'cq-statcard-v' }
        ];
    }
    get hasRows() { return (this.v.rows || []).length > 0; }

    // ---- the table
    get rows() {
        const v = this.v;
        return (v.rows || []).map((r) => {
            const late = this.isLate(r);
            const open = this.openId === r.id;
            let statusText = r.status; let statusCls = 'cq-pill soft neu';
            if (late) { statusText = 'Overdue'; statusCls = 'cq-pill soft crit'; }
            else if (r.status === 'Complete') { statusCls = 'cq-pill soft pos'; }
            let dueSub = '';
            if (r.status === 'Open' && r.due) {
                const n = this.daysTo(r.due);
                dueSub = n === 0 ? 'Due today' : n > 0 ? 'Due in ' + n + (n === 1 ? ' day' : ' days') : -n + (n === -1 ? ' day late' : ' days late');
            } else if (r.status === 'Complete' && r.completedOn) {
                dueSub = 'Done ' + this.dateText(r.completedOn) + (r.completedBy ? ' by ' + r.completedBy : '');
            }
            let verText = 'Not required';
            if (r.verifiedOn) { verText = 'Verified ' + this.dateText(r.verifiedOn) + (r.verifiedBy ? ' by ' + r.verifiedBy : ''); }
            else if (r.toVerify) { verText = r.canVerify ? 'To Verify (You)' : 'To Verify: ' + (r.verifier || v.owner || 'the NC owner'); }
            else if (r.needsVerification) { verText = 'After it is done: ' + (r.verifier || 'the NC owner'); }
            const isOpen = r.status === 'Open';
            return {
                ...r, key: r.id, panelKey: r.id + '-p',
                href: '/lightning/r/' + r.id + '/view', dueText: this.dateText(r.due), dueSub, dueSubCls: late ? 'sub crit' : 'sub',
                statusText, statusCls, verText, verCls: r.canVerify ? 'you' : '',
                assigneeText: r.mine ? (r.assignee || '—') + ' (you)' : r.assignee || '—',
                showComplete: isOpen && r.mine,
                showRemind: isOpen && !r.mine && v.isOwner && v.canNotify && !!r.assigneeId,
                showReassign: isOpen && v.isOwner,
                showVerify: r.canVerify,
                rowCls: open ? 'is-open' : '',
                open,
                panelComplete: open && (this.openKind === 'complete' || this.openKind === 'skip'),
                panelVerify: open && this.openKind === 'verify',
                panelReassign: open && this.openKind === 'reassign',
                hasFiles: (r.files || []).length > 0,
                filesText: (r.files || []).join(', '),
                doneText: r.remark || (r.skipReason ? 'Skipped: ' + r.skipReason : '—')
            };
        });
    }
    get nextLine() {
        const v = this.v; const c = this.counts;
        const open = c.total - c.done;
        const waiting = c.verify;
        if (!c.total) { return 'No corrections on ' + v.ncName + ' yet. They are added in the investigation.'; }
        if (open || waiting) {
            const parts = [];
            if (open) { parts.push(open + (open === 1 ? ' correction is' : ' corrections are') + ' open'); }
            if (waiting) { parts.push(waiting + ' to verify'); }
            return parts.join(' and ') + '. When every correction is done' + (waiting ? ' and verified' : '') + ', CQ completes ' + v.ncName + ' and it moves to Verification, where you close it.';
        }
        if (v.closed) { return v.ncName + ' is closed' + (v.resolution ? ', ' + v.resolution : '') + '.'; }
        if (v.canClose) { return 'Every correction is done. Close ' + v.ncName + ' below.'; }
        return v.stageKey === 'verification' || v.stage === 'Verification'
            ? 'Every correction is done. ' + v.ncName + ' is in Verification, where the owner closes it.'
            : 'Every correction is done.';
    }

    // ---- opening and closing a panel
    open(event, kind) {
        const id = event.currentTarget.dataset.id;
        if (this.openId === id && this.openKind === kind) { this.closePanel(); return; }
        this.openId = id; this.openKind = kind; this.error = undefined; this.note = undefined;
        this.whatWasDone = ''; this.skipReason = ''; this.howChecked = ''; this.reassignTo = undefined; this.files = [];
        this.completedOn = this.todayIso();
        this._seatActions = undefined;
    }
    closePanel() { this.openId = undefined; this.openKind = undefined; this.error = undefined; }
    handleOpenComplete(event) { this.open(event, 'complete'); }
    handleOpenVerify(event) { this.open(event, 'verify'); }
    handleOpenReassign(event) { this.open(event, 'reassign'); }
    handleCancel() { this.closePanel(); }
    get openRow() { return (this.v.rows || []).find((r) => r.id === this.openId); }

    // ---- complete or skip the owner's own
    get isSkip() { return this.openKind === 'skip'; }
    get isComplete() { return this.openKind === 'complete'; }
    handleSkipMode() { this.openKind = 'skip'; this._seatActions = undefined; }
    handleCompleteMode() { this.openKind = 'complete'; this._seatActions = undefined; }
    handleDone(event) { this.whatWasDone = event.target.value; }
    handleDate(event) { this.completedOn = event.target.value; }
    handleReason(event) { this.skipReason = event.target.value; }
    handleUploadFinished(event) { this.files = [...this.files, ...(event.detail.files || []).map((f) => ({ key: f.documentId, name: f.name }))]; }
    get hasNewFiles() { return this.files.length > 0; }
    get today() { return this.todayIso(); }
    get acceptTypes() { return ['.pdf', '.png', '.jpg', '.jpeg', '.xlsx', '.xls', '.csv', '.docx', '.doc', '.txt']; }
    get workBlocker() {
        if (this.isSkip) { return this.skipReason.trim() ? null : 'Say why it is no longer needed'; }
        if (!this.whatWasDone.trim()) { return 'Say what was done'; }
        if (!this.completedOn) { return 'Enter the completion date'; }
        if (this.completedOn > this.todayIso()) { return 'The completion date cannot be in the future'; }
        return null;
    }
    get cantWork() { return this.busy || !!this.workBlocker; }

    // ---- verify
    handleChecked(event) { this.howChecked = event.target.value; }
    get verifyBlocker() { return this.howChecked.trim() ? null : 'Say how you checked it'; }
    get cantVerify() { return this.busy || !!this.verifyBlocker; }
    handleSendBack() {
        const id = this.openId;
        const back = encodeURIComponent('/lightning/r/' + id + '/view');
        window.open('/lightning/action/quick/' + REOPEN + '?objectApiName=' + OBJ + '&context=RECORD_DETAIL&recordId=' + id + '&backgroundContext=' + back, '_blank');
    }

    // ---- the signature seat: one per open panel
    get seatActions() {
        const key = this.openKind;
        if (!this._seatActions || this._seatActions.key !== key) {
            let list;
            if (key === 'verify') { list = [{ action: 'implementation_verify', label: 'Verify Correction', doing: 'Verifying', signing: 'verifying the correction' }]; }
            else if (key === 'skip') { list = [{ action: 'implementation_skip', label: 'Skip Correction', doing: 'Skipping', signing: 'skipping the correction' }]; }
            else { list = [{ action: 'implementation_complete', label: 'Complete Correction', doing: 'Completing', signing: 'completing the correction' }]; }
            list.key = key;
            this._seatActions = list;
        }
        return this._seatActions;
    }
    get signFor() { const r = this.openRow; return r ? 'Signs for: ' + r.name + ', ' + (r.title || '') : ''; }
    get workMeaning() { return this.isSkip ? 'confirm this correction is no longer needed, for the reason given' : 'confirm the correction was done as described'; }
    get verifyMeaning() { return 'confirm the correction was done and works'; }

    workSubmit = async ({ comment, password }) => {
        const b = this.workBlocker;
        if (b) { throw new Error(b + '.'); }
        const r = this.openRow;
        await this.run(async () => {
            const args = { actionId: r.id, comment: comment || null, password: password || null };
            if (this.isSkip) { await skipAction({ ...args, reason: this.skipReason.trim() }); return r.name + ' skipped.'; }
            await completeAction({ ...args, whatWasDone: this.whatWasDone.trim(), completedOn: this.completedOn });
            return r.name + ' completed.';
        }, this.isSkip ? 'The correction was not skipped.' : 'The correction was not completed.', true);
    };
    verifySubmit = async ({ comment, password }) => {
        const b = this.verifyBlocker;
        if (b) { throw new Error(b + '.'); }
        const r = this.openRow;
        await this.run(async () => (await verifyAction({ actionId: r.id, verifiedComment: this.howChecked.trim(), comment: comment || null, password: password || null })).message,
            'The correction was not verified.', true);
    };

    // ---- reassign and remind
    get userFilter() { return { criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }] }; }
    handlePick(event) { this.reassignTo = event.detail.recordId; }
    get cantReassign() { return this.busy || !this.reassignTo; }
    async handleReassign() {
        const r = this.openRow;
        try { await this.run(async () => (await reassignAction({ actionId: r.id, userId: this.reassignTo })).message, 'The correction was not reassigned.', false); }
        catch (e) { this.error = e.message; }
    }
    async handleRemind(event) {
        const id = event.currentTarget.dataset.id;
        this.closePanel();
        try { await this.run(async () => (await remindAction({ actionId: id })).message, 'The reminder was not sent.', false); }
        catch (e) { this.error = e.message; }
    }

    /** Does one thing, then closes the panel, says what happened and reads the corrections again. A refusal is thrown back. */
    async run(fn, failed, refreshPage) {
        this.busy = true; this.error = undefined; this.note = undefined;
        try {
            this.note = await fn();
            this.closePanel();
            await this.load();
            if (refreshPage) {
                try { await notifyRecordUpdateAvailable([{ recordId: this.recordId }]); } catch (e) { /* the page refreshes on its own later */ }
            }
        } catch (e) {
            throw new Error(this.msg(e, failed));
        } finally {
            this.busy = false;
        }
    }
    handleDismiss() { this.note = undefined; }

    // ---- close the NC (Verification)
    get showClose() { return this.v.canClose; }
    get showClosed() { return this.v.closed; }
    get resolutionOpts() {
        return [
            { key: 'Effective', title: 'Effective', desc: 'The corrections held. No repeat since they were done.' },
            { key: 'Ineffective', title: 'Ineffective', desc: 'The problem came back, or the fix did not hold.' }
        ].map((o) => ({ ...o, cls: 'rchip' + (this.resolution === o.key ? ' on' : ''), pressed: String(this.resolution === o.key) }));
    }
    handleResolution(event) { this.resolution = event.currentTarget.dataset.key; }
    get isIneffective() { return this.resolution === 'Ineffective'; }
    handleSummary(event) { this.closeSummary = event.target.value; }
    get closeBlocker() {
        if (!this.resolution) { return 'Pick the resolution'; }
        if (!this.closeSummary.trim()) { return 'Write the closing summary'; }
        return null;
    }
    get cantClose() { return this.busy || !!this.closeBlocker; }
    get closeActions() { return this._closeActions; }
    get closeFor() { return 'Signs for: ' + this.v.ncName + (this.resolution ? ', closing as ' + this.resolution : ''); }
    get closeLabelMeaning() { return 'confirm the corrections were reviewed and the nonconformance is resolved as stated'; }
    closeSubmit = async ({ comment, password }) => {
        const b = this.closeBlocker;
        if (b) { throw new Error(b + '.'); }
        await this.run(async () => (await closeAction({ recordId: this.recordId, resolution: this.resolution, summary: this.closeSummary.trim(),
            comment: comment || null, password: password || null })).message, 'The nonconformance was not closed.', true);
    };
    quick(action) {
        const back = encodeURIComponent('/lightning/r/' + this.recordId + '/view');
        window.open('/lightning/action/quick/' + action + '?objectApiName=' + NC_OBJ + '&context=RECORD_DETAIL&recordId=' + this.recordId + '&backgroundContext=' + back, '_blank');
    }
    handleReopenImpl() { this.quick(NC_REOPEN_IMPL); }
    handleEscalate() { this.quick(NC_ESCALATE); }
    get hasCapa() { return !!this.v.capaId; }
    get capaHref() { return '/lightning/r/' + this.v.capaId + '/view'; }
    get closedRows() {
        const v = this.v; const c = this.counts;
        const skipped = (v.rows || []).filter((r) => r.status === 'Skipped').length;
        const rows = [
            { key: 'res', k: 'Resolution', v: v.resolution || '—' },
            { key: 'sum', k: 'Closing Summary', v: v.closeComment || '—' },
            { key: 'on', k: 'Closed On', v: this.dateText(v.closedOn) },
            { key: 'cor', k: 'Corrections', v: (c.done - skipped) + ' complete' + (skipped ? ', ' + skipped + ' skipped' : '') }
        ];
        if (v.capaName) { rows.push({ key: 'capa', k: 'CAPA', v: v.capaName }); }
        return rows;
    }
}
