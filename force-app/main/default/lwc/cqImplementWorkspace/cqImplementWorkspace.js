import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqImplementWorkspace.getView';
import completeAction from '@salesforce/apex/CqImplementWorkspace.complete';
import skipAction from '@salesforce/apex/CqImplementWorkspace.skip';
import verifyAction from '@salesforce/apex/CqImplementWorkspace.verify';
import reassignAction from '@salesforce/apex/CqImplementWorkspace.reassign';
import remindAction from '@salesforce/apex/CqImplementWorkspace.sendReminder';
import closeAction from '@salesforce/apex/CqImplementWorkspace.close';
import containAction from '@salesforce/apex/CqImplementWorkspace.completeContainment';

const OBJ = 'compliancequest__SQX_Action__c';
const CN_OBJ = 'compliancequest__SQX_Containment__c';
const REOPEN = 'compliancequest__SQX_Action__c.cqext__cqui_Reopen';   // CQ's own Reopen: Send Back
const NC_OBJ = 'compliancequest__SQX_Nonconformance__c';
const NC_REOPEN_IMPL = 'compliancequest__SQX_Nonconformance__c.cqext__cqui_Reopenimplementation';
const NC_ESCALATE = 'compliancequest__SQX_Nonconformance__c.cqext__cqui_Escalatecapa';
const ASK = 'Which corrections are late?,What was done on each correction?,What happens when all corrections are done?';
const DAY = 86400000;
const SEAT_ACTIONS = {
    containment: { action: 'containment_complete', label: 'Complete Containment', doing: 'Completing', signing: 'completing the containment' },
    complete: { action: 'implementation_complete', label: 'Complete Correction', doing: 'Completing', signing: 'completing the correction' },
    skip: { action: 'implementation_skip', label: 'Skip Correction', doing: 'Skipping', signing: 'skipping the correction' },
    verify: { action: 'implementation_verify', label: 'Verify Correction', doing: 'Verifying', signing: 'verifying the correction' }
};

/**
 * CQ.AI Implement workspace, the NC owner's view of everything that must finish before the NC can close (Lou, 27 Nov):
 * its containments (added in Triage, finished here) and its corrections, in Implement and Verification. The owner chases
 * what is open (Send Reminder, Reassign) and verifies what is done when CQ asks for it. An assignee completes their own.
 * Every row action opens one pop-up holding its form and, when CQ's policy asks, the signature (c-cq-sign-seat popup), so
 * the only signature on the page itself is Close. Send Back opens CQ's own Reopen in a new tab.
 * When every correction is done (CQ completes the NC: Verification) the owner closes it under the tables: Effective or
 * Ineffective, the closing summary, and the signature. Anything still open (a containment) is listed there and holds the
 * signature until it is done. Ineffective offers Reopen Implementation or Escalate to a CAPA (CQ's own actions, new tab).
 */
export default class CqImplementWorkspace extends LightningElement {
    @api recordId;
    v;
    loadError;
    error;
    note;              // what the last action did
    modalId;           // the containment or correction the pop-up is for
    modalKind;         // containment, complete, skip, verify, reassign
    modalError;
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
    isLateCn(k) { return k.open && k.due && this.daysTo(k.due) < 0; }
    dueLine(due) {
        const n = this.daysTo(due);
        return n === 0 ? 'Due today' : n > 0 ? 'Due in ' + n + (n === 1 ? ' day' : ' days') : -n + (n === -1 ? ' day late' : ' days late');
    }

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
        const cns = this.v.containments || [];
        const done = rows.filter((r) => r.status !== 'Open').length;
        return { total: rows.length, done, late: rows.filter((r) => this.isLate(r)).length + cns.filter((k) => this.isLateCn(k)).length,
                 verify: rows.filter((r) => r.toVerify).length, mineVerify: rows.filter((r) => r.canVerify).length,
                 cnTotal: cns.length, cnDone: cns.filter((k) => !k.open).length };
    }
    get cards() {
        const c = this.counts;
        const list = [];
        if (c.cnTotal) {
            list.push({ key: 'cn', label: 'Containment', n: c.cnDone + ' of ' + c.cnTotal + ' done', numCls: 'cq-statcard-v' + (c.cnDone === c.cnTotal ? ' ok' : ' bad') });
        }
        list.push({ key: 'done', label: 'Corrections', n: c.done + ' of ' + c.total + ' done', numCls: 'cq-statcard-v' + (c.total && c.done === c.total ? ' ok' : '') });
        list.push({ key: 'late', label: 'Overdue', n: String(c.late), numCls: 'cq-statcard-v' + (c.late ? ' bad' : '') });
        list.push({ key: 'ver', label: 'To Verify', n: c.verify + (c.mineVerify ? ' (' + (c.mineVerify === c.verify ? 'you' : c.mineVerify + ' yours') + ')' : ''), numCls: 'cq-statcard-v' });
        return list;
    }
    get cardsCls() { return 'cq-statcards tcards' + (this.counts.cnTotal ? ' four' : ''); }
    get hasRows() { return (this.v.rows || []).length > 0; }
    get hasContainments() { return (this.v.containments || []).length > 0; }
    get corrCls() { return this.hasContainments ? 'divided' : ''; }

    // ---- the containment table
    get cnRows() {
        const v = this.v;
        return (v.containments || []).map((k) => {
            const late = this.isLateCn(k);
            let statusText = k.status || 'Draft'; let statusCls = 'cq-pill soft neu';
            if (late) { statusText = 'Overdue'; statusCls = 'cq-pill soft crit'; }
            else if (!k.open) { statusCls = 'cq-pill soft pos'; }
            const dueSub = k.open ? (k.due ? this.dueLine(k.due) : '') : k.completedOn ? 'Done ' + this.dateText(k.completedOn) + (k.completedBy ? ' by ' + k.completedBy : '') : '';
            return {
                ...k, key: k.id, href: '/lightning/r/' + k.id + '/view', dueText: this.dateText(k.due), dueSub, dueSubCls: late ? 'sub crit' : 'sub',
                statusText, statusCls, titleText: k.title || k.name,
                assigneeText: k.mine ? (k.assignee || '—') + ' (you)' : k.assignee || '—',
                showComplete: k.open && k.mine,
                showRemind: k.open && !k.mine && v.isOwner && v.canNotify && !!k.assigneeId,
                showReassign: k.open && v.isOwner
            };
        });
    }

    // ---- the correction table
    get rows() {
        const v = this.v;
        return (v.rows || []).map((r) => {
            const late = this.isLate(r);
            let statusText = r.status; let statusCls = 'cq-pill soft neu';
            if (late) { statusText = 'Overdue'; statusCls = 'cq-pill soft crit'; }
            else if (r.status === 'Complete') { statusCls = 'cq-pill soft pos'; }
            let dueSub = '';
            if (r.status === 'Open' && r.due) { dueSub = this.dueLine(r.due); }
            else if (r.status === 'Complete' && r.completedOn) { dueSub = 'Done ' + this.dateText(r.completedOn) + (r.completedBy ? ' by ' + r.completedBy : ''); }
            let verText = 'Not required';
            if (r.verifiedOn) { verText = 'Verified ' + this.dateText(r.verifiedOn) + (r.verifiedBy ? ' by ' + r.verifiedBy : ''); }
            else if (r.toVerify) { verText = r.canVerify ? 'To Verify (You)' : 'To Verify: ' + (r.verifier || v.owner || 'the NC owner'); }
            else if (r.needsVerification) { verText = 'After it is done: ' + (r.verifier || 'the NC owner'); }
            const isOpen = r.status === 'Open';
            return {
                ...r, key: r.id,
                href: '/lightning/r/' + r.id + '/view', dueText: this.dateText(r.due), dueSub, dueSubCls: late ? 'sub crit' : 'sub',
                statusText, statusCls, verText, verCls: r.canVerify ? 'you' : '',
                assigneeText: r.mine ? (r.assignee || '—') + ' (you)' : r.assignee || '—',
                showComplete: isOpen && r.mine,
                showRemind: isOpen && !r.mine && v.isOwner && v.canNotify && !!r.assigneeId,
                showReassign: isOpen && v.isOwner,
                showVerify: r.canVerify
            };
        });
    }
    get nextLine() {
        const v = this.v; const c = this.counts;
        const open = c.total - c.done;
        const cnOpen = c.cnTotal - c.cnDone;
        const waiting = c.verify;
        if (v.closed) { return v.ncName + ' is closed' + (v.resolution ? ', ' + v.resolution : '') + '.'; }
        if (!c.total && !cnOpen) { return 'No corrections on ' + v.ncName + ' yet. They are added in the investigation.'; }
        const parts = [];
        if (cnOpen) { parts.push(cnOpen + (cnOpen === 1 ? ' containment is' : ' containments are') + ' open'); }
        if (open) { parts.push(open + (open === 1 ? ' correction is' : ' corrections are') + ' open'); }
        if (waiting) { parts.push(waiting + ' to verify'); }
        if (parts.length) {
            return parts.join(' and ') + '. When everything is done' + (waiting ? ' and verified' : '') + ', ' + v.ncName + ' can be closed in Verification.';
        }
        if (v.canClose) { return 'Everything is done. Close ' + v.ncName + ' below.'; }
        return v.stageKey === 'verification' || v.stage === 'Verification'
            ? 'Every correction is done. ' + v.ncName + ' is in Verification, where the owner closes it.'
            : 'Every correction is done.';
    }

    // ---- the pop-up: one for every row action
    openModal(id, kind) {
        this.modalId = id; this.modalKind = kind; this.modalError = undefined; this.error = undefined; this.note = undefined;
        this.whatWasDone = ''; this.skipReason = ''; this.howChecked = ''; this.reassignTo = undefined; this.files = [];
        this.completedOn = this.todayIso();
        this._seatActions = undefined;
    }
    closeModal() { this.modalId = undefined; this.modalKind = undefined; this.modalError = undefined; }
    handleOpenContain(event) { this.openModal(event.currentTarget.dataset.id, 'containment'); }
    handleOpenComplete(event) { this.openModal(event.currentTarget.dataset.id, 'complete'); }
    handleOpenVerify(event) { this.openModal(event.currentTarget.dataset.id, 'verify'); }
    handleOpenReassign(event) { this.openModal(event.currentTarget.dataset.id, 'reassign'); }
    handleCancel() { if (!this.busy) { this.closeModal(); } }
    handleModalKey(event) { if (event.key === 'Escape') { this.handleCancel(); } }
    get showModal() { return !!this.modalKind; }
    get modalRow() { return (this.v.rows || []).find((r) => r.id === this.modalId); }
    get modalCn() { return (this.v.containments || []).find((k) => k.id === this.modalId); }
    get modalItem() { return this.modalCn || this.modalRow || {}; }
    get modalTitle() {
        const it = this.modalItem;
        const k = this.modalKind;
        const verb = k === 'containment' ? 'Complete Containment' : k === 'complete' ? 'Complete Correction' : k === 'skip' ? 'Skip Correction'
            : k === 'verify' ? 'Verify Correction' : 'Reassign';
        return verb + ' ' + (it.name || '');
    }
    get modalSub() {
        const it = this.modalItem;
        return [it.title, this.v.ncName, it.due ? 'Due ' + this.dateText(it.due) : null].filter((x) => x).join(' · ');
    }
    get isContainModal() { return this.modalKind === 'containment'; }
    get isWorkModal() { return this.modalKind === 'complete' || this.modalKind === 'skip'; }
    get isVerifyModal() { return this.modalKind === 'verify'; }
    get isReassignModal() { return this.modalKind === 'reassign'; }
    get hasSeat() { return !!SEAT_ACTIONS[this.modalKind]; }
    get seatPolicyKey() { return this.isContainModal ? CN_OBJ : OBJ; }
    get seatName() { return this.isVerifyModal ? 'Verified By' : 'Completed By'; }

    // ---- complete or skip (a correction), complete (a containment)
    get isSkip() { return this.modalKind === 'skip'; }
    get isComplete() { return this.modalKind === 'complete'; }
    handleSkipMode() { this.modalKind = 'skip'; this._seatActions = undefined; }
    handleCompleteMode() { this.modalKind = 'complete'; this._seatActions = undefined; }
    handleDone(event) { this.whatWasDone = event.target.value; }
    handleDate(event) { this.completedOn = event.target.value; }
    handleReason(event) { this.skipReason = event.target.value; }
    handleUploadFinished(event) { this.files = [...this.files, ...(event.detail.files || []).map((f) => ({ key: f.documentId, name: f.name }))]; }
    get hasNewFiles() { return this.files.length > 0; }
    get today() { return this.todayIso(); }
    get acceptTypes() { return ['.pdf', '.png', '.jpg', '.jpeg', '.xlsx', '.xls', '.csv', '.docx', '.doc', '.txt']; }
    get workBlocker() {
        if (this.isSkip) { return this.skipReason.trim() ? null : 'Say why it is no longer needed'; }
        if (!this.whatWasDone.trim()) { return this.isContainModal ? 'Say what was contained' : 'Say what was done'; }
        if (!this.completedOn) { return 'Enter the completion date'; }
        if (this.completedOn > this.todayIso()) { return 'The completion date cannot be in the future'; }
        return null;
    }

    // ---- verify
    handleChecked(event) { this.howChecked = event.target.value; }
    get verifyBlocker() { return this.howChecked.trim() ? null : 'Say how you checked it'; }
    handleSendBack() {
        const id = this.modalId;
        const back = encodeURIComponent('/lightning/r/' + id + '/view');
        window.open('/lightning/action/quick/' + REOPEN + '?objectApiName=' + OBJ + '&context=RECORD_DETAIL&recordId=' + id + '&backgroundContext=' + back, '_blank');
    }
    get modalFilesText() { return (this.modalItem.files || []).join(', '); }
    get modalHasFiles() { return (this.modalItem.files || []).length > 0; }
    get modalDoneText() { const r = this.modalItem; return r.remark || (r.skipReason ? 'Skipped: ' + r.skipReason : '—'); }
    get modalDoneOn() { const r = this.modalItem; return r.completedOn ? this.dateText(r.completedOn) + (r.completedBy ? ' by ' + r.completedBy : '') : '—'; }

    // ---- the pop-up's signature (c-cq-sign-seat popup)
    get modalBlocker() { return this.isVerifyModal ? this.verifyBlocker : this.workBlocker; }
    get cantSign() { return this.busy || !!this.modalBlocker; }
    get seatActions() {
        const key = this.modalKind;
        if (!this._seatActions || this._seatActions.key !== key) {
            const list = SEAT_ACTIONS[key] ? [SEAT_ACTIONS[key]] : [];
            list.key = key;
            this._seatActions = list;
        }
        return this._seatActions;
    }
    get signFor() { const it = this.modalItem; return it.name ? 'Signs for: ' + it.name + ', ' + (it.title || '') : ''; }
    get seatMeaning() {
        const k = this.modalKind;
        return k === 'containment' ? 'confirm the containment was done as described'
            : k === 'skip' ? 'confirm this correction is no longer needed, for the reason given'
            : k === 'verify' ? 'confirm the correction was done and works' : 'confirm the correction was done as described';
    }
    modalSubmit = async ({ comment, password }) => {
        const b = this.modalBlocker;
        if (b) { throw new Error(b + '.'); }
        const it = this.modalItem;
        const args = { comment: comment || null, password: password || null };
        const k = this.modalKind;
        await this.run(async () => {
            if (k === 'containment') {
                return (await containAction({ ...args, containmentId: it.id, whatWasContained: this.whatWasDone.trim(), completedOn: this.completedOn })).message;
            }
            if (k === 'verify') { return (await verifyAction({ ...args, actionId: it.id, verifiedComment: this.howChecked.trim() })).message; }
            if (k === 'skip') { await skipAction({ ...args, actionId: it.id, reason: this.skipReason.trim() }); return it.name + ' skipped.'; }
            await completeAction({ ...args, actionId: it.id, whatWasDone: this.whatWasDone.trim(), completedOn: this.completedOn });
            return it.name + ' completed.';
        }, 'That was not saved.', true);
    };

    // ---- reassign and remind
    get userFilter() { return { criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }] }; }
    handlePick(event) { this.reassignTo = event.detail.recordId; }
    get cantReassign() { return this.busy || !this.reassignTo; }
    async handleReassign() {
        const it = this.modalItem;
        try { await this.run(async () => (await reassignAction({ actionId: it.id, userId: this.reassignTo })).message, 'It was not reassigned.', false); }
        catch (e) { this.modalError = e.message; }
    }
    async handleRemind(event) {
        const id = event.currentTarget.dataset.id;
        try { await this.run(async () => (await remindAction({ actionId: id })).message, 'The reminder was not sent.', false); }
        catch (e) { this.error = e.message; }
    }

    /** Does one thing, then closes the pop-up, says what happened and reads the NC again. A refusal is thrown back. */
    async run(fn, failed, refreshPage) {
        this.busy = true; this.error = undefined; this.note = undefined; this.modalError = undefined;
        try {
            this.note = await fn();
            this.closeModal();
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
    get blockers() {
        return (this.v.openBeforeClose || []).map((b) => {
            const cn = (this.v.containments || []).find((k) => k.id === b.id);
            return { ...b, key: b.id, href: '/lightning/r/' + b.id + '/view', canDo: !!(cn && cn.mine), statusText: b.status || 'Draft' };
        });
    }
    get hasBlockers() { return this.blockers.length > 0; }
    get blockerHead() {
        const n = this.blockers.length;
        return n + (n === 1 ? ' record on ' : ' records on ') + this.v.ncName + (n === 1 ? ' is' : ' are') + ' still open. CQ closes the NC only when ' + (n === 1 ? 'it is' : 'they are') + ' done.';
    }
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
        if (this.hasBlockers) { return 'Finish the open records first'; }
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
        if (c.cnTotal) { rows.push({ key: 'cn', k: 'Containment', v: c.cnDone + ' of ' + c.cnTotal + ' done' }); }
        if (v.capaName) { rows.push({ key: 'capa', k: 'CAPA', v: v.capaName }); }
        return rows;
    }
}
