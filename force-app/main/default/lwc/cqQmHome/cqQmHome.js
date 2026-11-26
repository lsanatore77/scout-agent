import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import USER_NAME from '@salesforce/schema/User.Name';
import loadHome from '@salesforce/apex/CqQmHome.load';
import myApprovals from '@salesforce/apex/CqApprovals.mine';
import act from '@salesforce/apex/CqApprovals.act';
import CqNcReportModal from 'c/cqNcReportModal';

const INBOX = 'Triage_Inbox';
const SUB_MAX = 42;   // the approval detail line: cut at a whole word, then the full text on hover
const NC_OBJECT = 'compliancequest__SQX_Nonconformance__c';
const SOON = [
    { key: 'complaints', name: 'Complaints', desc: 'Customer complaints, reportability and responses.', icon: 'standard:case' },
    { key: 'capa', name: 'CAPA', desc: 'Corrective and preventive actions and effectiveness checks.', icon: 'standard:record_update' },
    { key: 'audits', name: 'Audits', desc: 'Internal and supplier audits and their findings.', icon: 'standard:survey' },
    { key: 'docs', name: 'Controlled Documents', desc: 'Procedures, forms and specifications, with approvals.', icon: 'standard:document' },
    { key: 'training', name: 'Training', desc: 'Training assigned to you and your team.', icon: 'standard:education' },
    { key: 'personnel', name: 'Personnel', desc: 'People, roles and qualifications.', icon: 'standard:user' }
];

/**
 * The Quality Management home (decided with Lou 25 Nov 2026; mockup "Triage Inbox Mockup", board Home).
 * A card per process: Nonconformance has a line for each role the person has (Triage, My NCs, or what they reported),
 * each opening its view of the Triage Inbox; the processes not built yet show as Coming Soon.
 * Waiting for Your Approval lists CQ approval steps assigned to the person: Approve and Reject open the signature seat
 * (c-cq-sign-seat, docs/esignature.md) in a popup. Needs You lists the records that most need the person.
 */
export default class CqQmHome extends NavigationMixin(LightningElement) {
    home;
    approvals = [];
    loading = true;
    error;
    apError;
    msg;            // { tone, text }
    acting;         // { item, action }
    soon = SOON;

    @wire(getRecord, { recordId: USER_ID, fields: [USER_NAME] }) user;
    get myName() { return getFieldValue(this.user && this.user.data, USER_NAME) || 'You'; }

    connectedCallback() { this.refresh(); }

    async refresh() {
        this.error = undefined; this.apError = undefined;
        const [h, a] = await Promise.all([
            loadHome().catch((e) => { this.error = this.errText(e); return null; }),
            myApprovals().catch((e) => { this.apError = this.errText(e); return []; })
        ]);
        this.home = h;
        this.approvals = a || [];
        this.loading = false;
    }

    // ------------------------------------------------------------ the Nonconformance card

    get roleLine() { return this.home ? this.home.roleLine : ''; }
    get ncLines() {
        return ((this.home && this.home.nc) || []).map((l) => ({
            ...l,
            aria: l.role + ': ' + l.stats.map((s) => s.n + ' ' + s.label).join(', '),
            statList: l.stats.map((s, i) => ({ key: l.key + i, n: s.n, label: s.label, cls: 'sn' + (s.warn ? ' cq-marktext warn' : '') }))
        }));
    }
    /** + on the Nonconformance card: the Report a Nonconformance popup. Opening an NC from it goes there; else the counts refresh. */
    async handleNew() {
        let result;
        try { result = await CqNcReportModal.open({ size: 'small', description: 'Report a Nonconformance' }); } catch (e) { result = null; }
        if (result && result.recordId) {
            this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: result.recordId, actionName: 'view' } });
            return;
        }
        loadHome().then((h) => { this.home = h; }).catch(() => {});
    }
    handleLine(event) { this.go(event.currentTarget.dataset.view); }
    handleNc() {
        const first = (this.home && this.home.nc && this.home.nc[0]) || { view: 'waiting' };
        this.go(first.view);
    }
    go(view) {
        if (view === 'reported') {
            this[NavigationMixin.Navigate]({ type: 'standard__objectPage', attributes: { objectApiName: NC_OBJECT, actionName: 'list' }, state: { filterName: 'Recent' } });
            return;
        }
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: INBOX }, state: { c__view: view } });
    }

    // ------------------------------------------------------------ Needs You

    get needs() {
        return ((this.home && this.home.needs) || []).map((n) => ({
            ...n, url: '/' + n.id, tone: n.warn ? 'warn' : '', whyCls: n.warn ? 'why cq-marktext warn' : 'why cq-sub'
        }));
    }
    get hasNeeds() { return this.needs.length > 0; }

    // ------------------------------------------------------------ approvals

    get approvalRows() {
        return this.approvals.map((a) => ({
            ...a,
            url: a.recordId ? '/' + a.recordId : null,
            asked: this.ago(a.requestedOn),
            sub: [a.objectLabel, a.recordTitle].filter((x) => x).join(' \u00b7 '),
            subShort: this.cut([a.objectLabel, a.recordTitle].filter((x) => x).join(' \u00b7 '), SUB_MAX)
        }));
    }
    get hasApprovals() { return this.approvals.length > 0; }
    get approvalCount() { return this.approvals.length; }

    handleRecord(event) {
        event.preventDefault();
        const id = event.currentTarget.dataset.id;
        if (id) { this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, actionName: 'view' } }); }
    }
    handleApprove(event) { this.openSign(event.currentTarget.dataset.id, 'approve'); }
    handleReject(event) { this.openSign(event.currentTarget.dataset.id, 'reject'); }
    openSign(stepId, action) {
        const item = this.approvals.find((a) => a.stepId === stepId);
        if (item) { this.acting = { item, action }; this.msg = undefined; }
    }
    get showSign() { return !!this.acting; }
    get signTitle() {
        if (!this.acting) { return ''; }
        return (this.acting.action === 'approve' ? 'Approve ' : 'Reject ') + this.acting.item.recordName;
    }
    get signItem() { return this.acting ? this.acting.item : {}; }
    get signActions() {
        if (!this.acting) { return []; }
        return this.acting.action === 'approve'
            ? [{ action: 'approve', label: 'Approve', doing: 'Approving', signing: 'approving' }]
            : [{ action: 'reject', label: 'Reject', doing: 'Rejecting', signing: 'rejecting', needsComment: true,
                commentWhy: 'Add a comment saying why you are rejecting it.' }];
    }
    get signMeaning() {
        if (!this.acting) { return ''; }
        const what = (this.acting.item.what || 'approval').toLowerCase();
        return (this.acting.action === 'approve' ? 'approve this ' : 'reject this ') + what;
    }
    get signHint() { return this.acting && this.acting.action === 'reject' ? 'Required: say why you are rejecting it.' : 'Optional.'; }
    get signSeat() { return this.acting ? (this.acting.item.seat || 'Approver') : ''; }
    get signSub() { return this.acting && this.acting.item.delegated ? 'Delegated to you' : ''; }
    handleSignClose() { this.acting = undefined; }
    handleModalKey(event) { if (event.key === 'Escape') { this.acting = undefined; } }

    /** The seat signs and acts in one request: CqApprovals.act signs through CqEsign first when CQ's policy asks. */
    signSubmit = async ({ ref, action, comment, password }) => {
        const item = this.acting && this.acting.item;
        this.approvals = (await act({ stepId: ref, action, comment, password })) || [];
        this.acting = undefined;
        this.msg = { tone: 'pos', text: (item ? item.recordName + ': ' : '') + (action === 'approve' ? 'approved.' : 'rejected.') };
        loadHome().then((h) => { this.home = h; }).catch(() => {});
    };
    handleMsgClose() { this.msg = undefined; }
    get msgCls() { return 'cq-msg msgline ' + (this.msg ? this.msg.tone : ''); }

    // ------------------------------------------------------------ helpers

    ago(d) {
        if (!d) { return ''; }
        const ms = Date.now() - new Date(d).getTime();
        const h = Math.floor(ms / 3600000);
        if (h < 1) { return 'just now'; }
        if (h < 24) { return h + (h === 1 ? ' hour' : ' hours'); }
        const days = Math.floor(h / 24);
        return days + (days === 1 ? ' day' : ' days');
    }
    /** Shortens text to max characters at a whole word, with no stray punctuation before the ellipsis. */
    cut(s, max) {
        if (!s || s.length <= max) { return s; }
        let t = s.slice(0, max + 1);
        const sp = t.lastIndexOf(' ');
        t = (sp > 0 ? t.slice(0, sp) : t.slice(0, max)).replace(/[\s,;:.\u00b7-]+$/, '');
        return t + '\u2026';
    }
    errText(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
    }
}
