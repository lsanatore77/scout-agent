import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import load from '@salesforce/apex/CqTriageInbox.load';
import takeOwnership from '@salesforce/apex/CqTriageInbox.takeOwnership';
import reassignTo from '@salesforce/apex/CqTriageInbox.reassignTo';
import reassign from '@salesforce/apex/CqTriageInbox.reassign';

const VIEWS = { waiting: 'Waiting for Triage', mine: 'My NCs' };

/**
 * The Triage Inbox, list view style (decided with Lou 25 Nov 2026; mockup "Triage Inbox Mockup", board ListView).
 * A list view picker switches between Waiting for Triage (the NCs in your triage queues, oldest first) and My NCs (the
 * open NCs you own, by stage). Take Ownership takes one NC and you stay on the inbox; a line at the top says it is yours,
 * with Open, or who took it first. Reassign hands an NC you own to another queue member who can own NCs.
 * The view can be opened directly with the page state c__view = waiting or mine (the Quality Management home does).
 */
export default class CqTriageInbox extends NavigationMixin(LightningElement) {
    view;                  // waiting or mine
    data;
    loading = true;
    error;
    msg;                   // { tone, text, id }
    menuOpen = false;
    busyId;

    // reassign popup
    reassignRow;
    people = [];
    pickId;
    note = '';
    saving = false;
    modalError;
    peopleLoading = false;

    @wire(CurrentPageReference)
    setRef(ref) {
        const v = ref && ref.state ? ref.state.c__view : null;
        if (v === 'waiting' || v === 'mine') { this.view = v; this.menuOpen = false; }
    }

    connectedCallback() { this.refresh(); }

    async refresh() {
        this.loading = !this.data;
        this.error = undefined;
        try {
            this.data = await load();
            if (!this.view) { this.view = this.data.inQueue ? 'waiting' : 'mine'; }
        } catch (e) {
            this.error = this.errText(e);
        } finally {
            this.loading = false;
        }
    }

    // ------------------------------------------------------------ the view picker

    get viewName() { return VIEWS[this.view] || VIEWS.waiting; }
    get isWaiting() { return this.view === 'waiting'; }
    get isMine() { return this.view === 'mine'; }
    get menuExpanded() { return String(this.menuOpen); }
    get views() {
        const d = this.data || { waiting: [], mine: [] };
        const list = [];
        if (d.inQueue) { list.push({ key: 'waiting', label: VIEWS.waiting, n: d.waiting.length }); }
        list.push({ key: 'mine', label: VIEWS.mine, n: d.mine.length });
        return list.map((v) => ({ ...v, selected: String(v.key === this.view), cls: 'cq-pick-row vrow' + (v.key === this.view ? ' on' : ''), tick: v.key === this.view ? '✓' : '' }));
    }
    get subLine() {
        const d = this.data;
        if (!d) { return ''; }
        if (this.isWaiting) {
            const n = d.waiting.length;
            return n + (n === 1 ? ' item' : ' items') + ' · Oldest first' + (d.queues.length ? ' · ' + d.queues.join(', ') : '');
        }
        const n = d.mine.length;
        return n + (n === 1 ? ' item' : ' items') + ' · Grouped by stage';
    }
    handleMenu() { this.menuOpen = !this.menuOpen; }
    handleMenuClose() { this.menuOpen = false; }
    handleMenuKey(event) { if (event.key === 'Escape') { this.menuOpen = false; } }
    handleView(event) {
        this.view = event.currentTarget.dataset.key;
        this.menuOpen = false;
        this.msg = undefined;
    }

    // ------------------------------------------------------------ rows

    get waitingRows() {
        return ((this.data && this.data.waiting) || []).map((r) => ({
            ...r,
            url: '/' + r.id,
            part: r.part || '–',
            waitCls: r.old ? 'cq-marktext warn' : '',
            flagList: (r.flags || []).map((f, i) => ({ key: r.id + '-' + i, text: f })),
            busy: this.busyId === r.id,
            takeLabel: this.busyId === r.id ? 'Taking…' : 'Take Ownership',
            cantTake: !this.data.canOwn || !!this.busyId
        }));
    }
    get hasWaiting() { return this.waitingRows.length > 0; }
    get mineGroups() {
        const groups = [];
        let g;
        ((this.data && this.data.mine) || []).forEach((r) => {
            if (!g || g.label !== r.stageLabel) { g = { key: r.stage, label: r.stageLabel, rows: [] }; groups.push(g); }
            g.rows.push({
                ...r,
                url: '/' + r.id,
                part: r.part || '–',
                statusCls: r.statusWarn ? 'cq-marktext warn' : '',
                flagList: (r.flags || []).map((f, i) => ({ key: r.id + '-' + i, text: f })),
                btnCls: r.primary === 'Continue Triage' ? 'cq-btn-primary cq-btn-sm' : 'cq-btn-outline cq-btn-sm'
            });
        });
        return groups;
    }
    get hasMine() { return this.mineGroups.length > 0; }
    get showNoQueue() { return this.data && !this.data.inQueue; }
    get showCantOwn() { return this.data && this.data.inQueue && !this.data.canOwn; }
    get msgCls() { return 'cq-msg msgline ' + (this.msg ? this.msg.tone : ''); }

    handleOpen(event) {
        event.preventDefault();
        this.openRecord(event.currentTarget.dataset.id);
    }
    openRecord(id) {
        if (!id) { return; }
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, actionName: 'view' } });
    }
    handleMsgOpen() { if (this.msg) { this.openRecord(this.msg.id); } }
    handleMsgClose() { this.msg = undefined; }

    async handleTake(event) {
        const id = event.currentTarget.dataset.id;
        if (this.busyId) { return; }
        this.busyId = id;
        this.msg = undefined;
        try {
            const t = await takeOwnership({ ncId: id });
            this.msg = { tone: t.ok ? 'pos' : 'warn', text: t.message, id: t.ok ? t.id : null };
        } catch (e) {
            this.msg = { tone: 'crit', text: this.errText(e) };
        } finally {
            this.busyId = undefined;
        }
        await this.refresh();
    }

    // ------------------------------------------------------------ reassign

    get showReassign() { return !!this.reassignRow; }
    get reassignTitle() { return this.reassignRow ? 'Reassign ' + this.reassignRow.name : ''; }
    get peopleRows() {
        return this.people.map((p) => ({
            ...p,
            checked: p.id === this.pickId,
            cls: 'person' + (p.id === this.pickId ? ' on' : ''),
            load: p.open + ' open'
        }));
    }
    get hasPeople() { return this.people.length > 0; }
    get pickName() { const p = this.people.find((x) => x.id === this.pickId); return p ? p.name : ''; }
    get noteLabel() { return this.pickName ? 'Note for ' + this.pickName.split(' ')[0] : 'Note'; }
    get reassignLabel() { return this.saving ? 'Reassigning…' : this.pickName ? 'Reassign to ' + this.pickName : 'Reassign'; }
    get cantReassign() { return !this.pickId || this.saving; }

    async handleReassign(event) {
        const id = event.currentTarget.dataset.id;
        const row = ((this.data && this.data.mine) || []).find((r) => r.id === id);
        if (!row) { return; }
        this.reassignRow = row; this.people = []; this.pickId = undefined; this.note = ''; this.modalError = undefined;
        this.peopleLoading = true;
        try {
            this.people = (await reassignTo({ ncId: id })) || [];
        } catch (e) {
            this.modalError = this.errText(e);
        } finally {
            this.peopleLoading = false;
        }
    }
    handlePick(event) { this.pickId = event.target.value; }
    handleNote(event) { this.note = event.target.value; }
    handleReassignClose() { if (!this.saving) { this.reassignRow = undefined; } }
    handleModalKey(event) { if (event.key === 'Escape') { this.handleReassignClose(); } }
    async handleReassignSave() {
        if (this.cantReassign) { return; }
        this.saving = true; this.modalError = undefined;
        const name = this.pickName, nc = this.reassignRow.name;
        try {
            const warning = await reassign({ ncId: this.reassignRow.id, userId: this.pickId, note: this.note });
            this.reassignRow = undefined;
            this.msg = warning ? { tone: 'warn', text: warning } : { tone: 'pos', text: nc + ' is reassigned to ' + name + '.' };
            await this.refresh();
        } catch (e) {
            this.modalError = this.errText(e);
        } finally {
            this.saving = false;
        }
    }

    errText(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
    }
}
