import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getView from '@salesforce/apex/CqCorrectionWorkspace.getView';
import completeAction from '@salesforce/apex/CqCorrectionWorkspace.complete';
import skipAction from '@salesforce/apex/CqCorrectionWorkspace.skip';

const OBJ = 'compliancequest__SQX_Action__c';
const EXTEND = 'compliancequest__SQX_Action__c.cqext__cqui_Extensionrequest';   // CQ's own Request Extension (extensions go through CQ's approval)
const ASK = 'What does this correction ask me to do?,Which procedure applies here?,What happens when I complete it?';
const DAY = 86400000;

/**
 * CQ.AI Correction workspace, the assignee's view of a CQ action in Implement (Lou, 27 Nov): what to do, why it matters,
 * the procedure to follow (optional: a controlled document linked on the NC or named in the correction), and Complete or
 * Skip with the signature seat. Request Extension opens CQ's own action. Anyone but the assignee sees it read-only.
 * The NC owner's view of all corrections is a separate workspace on the NC.
 */
export default class CqCorrectionWorkspace extends NavigationMixin(LightningElement) {
    @api recordId;
    v;
    loadError;
    error;
    saving = false;
    mode = 'complete';     // or 'skip'
    whatWasDone = '';
    completedOn;
    skipReason = '';
    files = [];            // evidence attached in this visit: { key, name }
    thumbFailed = {};      // documents whose preview image did not load: a document icon instead
    result;
    _seatActions;

    connectedCallback() {
        this.completedOn = this.todayIso();
        this.load();
    }

    async load() {
        try {
            this.v = await getView({ recordId: this.recordId });
            this.loadError = undefined;
        } catch (e) {
            this.loadError = this.msg(e, 'Could not read this correction.');
        }
    }

    get ready() { return !!this.v; }
    msg(e, fallback) { return (e && e.body && e.body.message) || (e && e.message) || fallback; }
    todayIso() { const d = new Date(); const p = (n) => String(n).padStart(2, '0'); return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()); }
    dateText(iso) { return iso ? new Date(iso + 'T00:00:00').toLocaleDateString() : '—'; }
    href(id) { return '/lightning/r/' + id + '/view'; }
    daysTo(iso) { return Math.round((new Date(iso + 'T00:00:00').getTime() - new Date(this.todayIso() + 'T00:00:00').getTime()) / DAY); }

    // ---- header
    get headerFields() {
        const v = this.v;
        return [
            { key: 'nc', label: 'For', value: v.ncName, id: v.ncId },
            { key: 'part', label: 'Part · Lot', value: [v.partNumber, v.lot].filter((x) => x).join(' · ') || '—' },
            { key: 'due', label: 'Due', value: this.dueText, tone: this.overdue ? 'crit' : undefined },
            { key: 'owner', label: 'NC Owner', value: v.ncOwner || '—' },
            { key: 'status', label: 'Status', value: v.status || '—' }
        ];
    }
    get overdue() { return this.v.status === 'Open' && this.v.due && this.daysTo(this.v.due) < 0; }
    get dueText() {
        const v = this.v;
        if (!v.due) { return '—'; }
        if (v.status !== 'Open') { return this.dateText(v.due); }
        const n = this.daysTo(v.due);
        const rel = n === 0 ? 'today' : n > 0 ? 'in ' + n + (n === 1 ? ' day' : ' days') : -n + (n === -1 ? ' day late' : ' days late');
        return this.dateText(v.due) + ' (' + rel + ')';
    }
    handleShellOpen(event) { window.open(this.href(event.detail), '_blank'); }
    get askSuggestions() { return ASK; }

    // ---- the cards at the top
    get assignedLine() { return 'Assigned by ' + (this.v.assignedBy || 'the NC owner') + (this.v.opened ? ' on ' + this.dateText(this.v.opened) : ''); }
    get problemText() { return this.v.problem || this.v.ncTitle || 'No description on the NC.'; }
    get hasRootCauses() { return (this.v.rootCauses || []).length > 0; }
    get rootLine() { return (this.v.rootCauses || []).join(' · '); }
    get othersLine() {
        const n = this.v.othersOpen;
        return n ? n + (n === 1 ? ' other correction is' : ' other corrections are') + ' open on ' + this.v.ncName + '.' : null;
    }
    get hasProcedures() { return (this.v.procedures || []).length > 0; }
    get cardsCls() { return 'cards' + (this.hasProcedures ? ' three' : ''); }
    get procRows() {
        return (this.v.procedures || []).map((p) => ({
            ...p,
            key: p.id,
            hasThumb: !!p.versionId && !this.thumbFailed[p.id],
            thumbUrl: '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' + p.versionId,
            revLine: ['Rev ' + (p.revision || '—'), p.effective ? 'Effective ' + this.dateText(p.effective) : null].filter((x) => x).join(' · '),
            hint: !p.contentDocumentId ? 'No file on this revision yet. Open it in CQ.' : this.v.viewerOk ? 'Click the page to read it here.' : 'Opens in CQ, where its print and download rules apply.',
            openLabel: 'Open ' + p.docNumber
        }));
    }
    handleThumbError(event) { this.thumbFailed = { ...this.thumbFailed, [event.currentTarget.dataset.id]: true }; }
    /** The file opens in Salesforce's viewer over the page when CQ's print and download control allows it; otherwise, and
     *  when there is no file, CQ's own document page opens in a new tab. */
    handleOpenProc(event) {
        const p = (this.v.procedures || []).find((x) => x.id === event.currentTarget.dataset.id);
        if (!p) { return; }
        if (p.contentDocumentId && this.v.viewerOk) {
            this[NavigationMixin.Navigate]({ type: 'standard__namedPage', attributes: { pageName: 'filePreview' },
                state: { recordIds: p.contentDocumentId, selectedRecordId: p.contentDocumentId } });
            return;
        }
        window.open(this.href(p.id), '_blank');
    }
    handleOpenInCq(event) { window.open(this.href(event.currentTarget.dataset.id), '_blank'); }

    // ---- what is shown
    get showForm() { return this.v.canAct && !this.result; }
    get showReadOnly() { return !this.v.canAct && !this.result; }
    get showDone() { return !!this.result; }
    get isSkip() { return this.mode === 'skip'; }
    get isComplete() { return this.mode === 'complete'; }
    get formTitle() { return this.isSkip ? 'Skip Your Correction' : 'Complete Your Correction'; }
    get readOnlyTitle() {
        const s = this.v.status;
        if (s === 'Complete') { return 'Correction Complete'; }
        if (s === 'Skipped') { return 'Correction Skipped'; }
        return 'Assigned to ' + (this.v.assignee || 'someone else');
    }
    get readOnlyRows() {
        const v = this.v;
        const rows = [];
        if (v.status === 'Open') {
            rows.push({ key: 'who', k: 'Assignee', v: (v.assignee || '—') + '. Only they can complete it.' });
            rows.push({ key: 'due', k: 'Due', v: this.dueText });
        } else {
            rows.push({ key: 's', k: 'Status', v: v.status || '—' });
            if (v.completedOn) { rows.push({ key: 'on', k: 'Completed On', v: this.dateText(v.completedOn) }); }
            if (v.completedBy) { rows.push({ key: 'by', k: 'Completed By', v: v.completedBy }); }
            if (v.remark) { rows.push({ key: 'r', k: 'What Was Done', v: v.remark }); }
        }
        if (v.needsVerification) { rows.push({ key: 'ver', k: 'Verification', v: 'Verified by ' + (v.verifier || 'the named verifier') + ' once it is done' }); }
        return rows;
    }

    // ---- the form
    get today() { return this.todayIso(); }
    handleDone(event) { this.whatWasDone = event.target.value; this.error = undefined; }
    handleDate(event) { this.completedOn = event.target.value; this.error = undefined; }
    handleReason(event) { this.skipReason = event.target.value; this.error = undefined; }
    handleSkipMode() { this.mode = 'skip'; this.error = undefined; }
    handleCompleteMode() { this.mode = 'complete'; this.error = undefined; }
    handleUploadFinished(event) {
        const got = (event.detail.files || []).map((f) => ({ key: f.documentId, name: f.name }));
        this.files = [...this.files, ...got];
    }
    get hasFiles() { return this.files.length > 0; }
    get acceptTypes() { return ['.pdf', '.png', '.jpg', '.jpeg', '.xlsx', '.xls', '.csv', '.docx', '.doc', '.txt']; }
    /** CQ's own Request Extension, in a new tab: extensions go through CQ's approval. */
    handleExtend() {
        const back = encodeURIComponent('/lightning/r/' + this.recordId + '/view');
        window.open('/lightning/action/quick/' + EXTEND + '?objectApiName=' + OBJ + '&context=RECORD_DETAIL&recordId=' + this.recordId + '&backgroundContext=' + back, '_blank');
    }
    blocker() {
        if (this.isSkip) { return (this.skipReason || '').trim() ? null : 'Say why it is no longer needed'; }
        if (!(this.whatWasDone || '').trim()) { return 'Say what was done'; }
        if (!this.completedOn) { return 'Enter the completion date'; }
        if (this.completedOn > this.todayIso()) { return 'The completion date cannot be in the future'; }
        return null;
    }
    get blockerText() { return this.blocker(); }
    get cantSubmit() { return this.saving || !!this.blocker(); }

    // ---- the assignee's signature (c-cq-sign-seat): CQ's Action policy, Completing Action or Skipping Action
    get seatActions() {
        const key = this.mode;
        if (!this._seatActions || this._seatActions.key !== key) {
            const list = this.isSkip
                ? [{ action: 'implementation_skip', label: 'Skip Correction', doing: 'Skipping', signing: 'skipping the correction' }]
                : [{ action: 'implementation_complete', label: 'Complete Correction', doing: 'Completing', signing: 'completing the correction' }];
            list.key = key;
            this._seatActions = list;
        }
        return this._seatActions;
    }
    get signFor() { return 'Signs for: ' + this.v.name + ', ' + (this.v.title || ''); }
    get signMeaning() {
        return this.isSkip ? 'confirm this correction is no longer needed, for the reason given'
            : 'confirm the correction was done as described above';
    }
    get seatHint() { return this.isSkip ? 'Optional' : 'Optional, for example who helped or where the records are kept.'; }

    /** The seat's one button signs and acts in one request; a refusal is thrown back so the seat shows it. */
    seatSubmit = async ({ comment, password }) => {
        const b = this.blocker();
        if (b) { throw new Error(b + '.'); }
        this.saving = true;
        this.error = undefined;
        try {
            const args = { recordId: this.recordId, comment: comment || null, password: password || null };
            this.result = this.isSkip
                ? await skipAction({ ...args, reason: this.skipReason.trim() })
                : await completeAction({ ...args, whatWasDone: this.whatWasDone.trim(), completedOn: this.completedOn });
            this.result = { ...this.result, mode: this.mode };
            if (this.result.status) { this.v = { ...this.v, status: this.result.status }; }   // the header's Status, without a reload
            try { await notifyRecordUpdateAvailable([{ recordId: this.recordId }, ...(this.v.ncId ? [{ recordId: this.v.ncId }] : [])]); } catch (e) { /* the page refreshes on its own later */ }
            this.dispatchEvent(new CustomEvent('changed'));
        } catch (e) {
            throw new Error(this.msg(e, this.isSkip ? 'The correction was not skipped.' : 'The correction was not completed.'));
        } finally {
            this.saving = false;
        }
    };

    // ---- done
    get doneHeading() { return this.result && this.result.mode === 'skip' ? 'Correction Skipped' : 'Correction Complete'; }
    get doneRows() {
        const r = this.result;
        const rows = [];
        if (r.mode === 'skip') {
            rows.push({ key: 'why', k: 'Reason', v: this.skipReason.trim() });
        } else {
            rows.push({ key: 'what', k: 'What Was Done', v: this.whatWasDone.trim() });
            rows.push({ key: 'on', k: 'Completed On', v: this.dateText(this.completedOn) });
            if (this.files.length) { rows.push({ key: 'ev', k: 'Evidence', v: this.files.map((f) => f.name).join(', ') }); }
        }
        if (r.signed) { rows.push({ key: 'sig', k: 'Signature', v: 'Signed by you' }); }
        rows.push({ key: 'st', k: 'Status', v: r.status || '—' });
        let next;
        if (r.othersOpen) { next = r.othersOpen + (r.othersOpen === 1 ? ' other correction is' : ' other corrections are') + ' still open on ' + this.v.ncName + '. The NC owner sees this one as done.'; }
        else if (r.ncStage) { next = 'Nothing is left open on ' + this.v.ncName + '; it is in ' + r.ncStage + ', where the NC owner closes it.'; }
        if (this.v.needsVerification && r.mode !== 'skip') { next = (next ? next + ' ' : '') + (this.v.verifier || 'The named verifier') + ' will verify it.'; }
        if (next) { rows.push({ key: 'n', k: 'Next', v: next }); }
        return rows;
    }
    handleFinish() {
        this.result = undefined;
        this.mode = 'complete';
        this.load();
    }
}
