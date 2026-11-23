import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getLot from '@salesforce/apex/CqLotRecord.get';

/**
 * cqLotRecord: the Lot record screen on CQ Lot Info. It sits in the shared workspace frame (cqWsShell, no steps) and shows:
 * the lot's own fields in the header; Made, read live from CQ's batch record; What Went Into It, the component lots recorded
 * in the batch steps (sub-assemblies, then materials, flagged ones first); Used In, for a component lot; and in the side
 * column CQ.AI notes, supply data, quality records against this exact lot, and where its stock is.
 * A status tag is only ever a record against that exact lot. A CQ.AI note is a suggestion: it never shows as a status.
 */
const SHOW_MATERIALS = 8;

export default class CqLotRecord extends NavigationMixin(LightningElement) {
    @api recordId;
    v;
    error;
    showAll = false;

    connectedCallback() { this.load(); }

    async load() {
        try {
            this.v = await getLot({ lotId: this.recordId });
            this.error = undefined;
        } catch (e) {
            this.error = (e && e.body && e.body.message) || 'The lot could not be loaded.';
        }
    }

    get ready() { return !!this.v; }
    get recordName() { return this.v ? this.v.name : ''; }
    get objectLabel() { return this.v && this.v.title ? 'Lot · ' + this.v.title : 'Lot'; }
    get headerFields() {
        return (this.v ? this.v.header : []).map((f) => ({ key: f.key, label: f.label, value: f.value, id: f.id, tone: f.tone }));
    }

    get hasMade() { return this.v && this.v.made.length > 0; }
    get madeSource() { return this.v && this.v.batchName ? 'From batch record ' + this.v.batchName : 'From the lot record'; }

    tag(f) {
        const tone = f.tone === 'crit' ? 'crit' : f.tone === 'warn' ? 'warn' : f.tone === 'pos' ? 'pos' : 'neu';
        return { key: f.key, text: f.label, id: f.id, cls: 'cq-pill soft ' + tone, isLink: !!f.id };
    }
    row(c) {
        return {
            key: c.key, lot: c.lot, lotId: c.lotId, hasLot: !!c.lotId,
            part: [c.partNumber, c.partName].filter(Boolean).join(' · '),
            supplier: c.supplier,
            flags: c.flags.map((f) => this.tag(f)),
            aiNote: c.aiNote, hasAi: !!c.aiNote
        };
    }
    get subRows() { return this.v ? this.v.subAssemblies.map((c) => this.row(c)) : []; }
    get materialRows() {
        if (!this.v) { return []; }
        const all = this.v.materials.map((c) => this.row(c));
        return this.showAll ? all : all.slice(0, SHOW_MATERIALS);
    }
    get hasComponents() { return this.v && (this.v.subAssemblies.length + this.v.materials.length) > 0; }
    get hasSubs() { return this.v && this.v.subAssemblies.length > 0; }
    get hasMaterials() { return this.v && this.v.materials.length > 0; }
    get subTitle() { return 'Sub-assemblies (' + this.v.subAssemblies.length + ')'; }
    get materialTitle() { return 'Materials (' + this.v.materials.length + ')'; }
    get moreCount() { return this.v ? this.v.materials.length - SHOW_MATERIALS : 0; }
    get hasMore() { return this.moreCount > 0; }
    get moreLabel() { return this.showAll ? 'Show fewer' : 'Show ' + this.moreCount + ' more'; }
    get componentCount() { return this.v ? this.v.subAssemblies.length + this.v.materials.length : 0; }
    get componentSub() { return this.componentCount + ' component lots recorded in the batch steps'; }

    get hasUsedIn() { return this.v && this.v.usedIn.length > 0; }
    get usedInRows() { return this.v ? this.v.usedIn.map((u) => ({ key: u.key, name: u.label, id: u.id, status: u.value, hasStatus: !!u.value, cls: this.tag({ tone: u.tone }).cls })) : []; }

    get hasAi() { return this.v && this.v.aiNotes.length > 0; }
    get aiRows() { return this.v ? this.v.aiNotes : []; }
    get hasSupply() { return this.v && this.v.supply.length > 0; }
    get supplyRows() {
        return this.v ? this.v.supply.map((s) => ({ ...s, isLink: !!s.id, vcls: 'kv-v' + (s.tone ? ' tone-' + s.tone : '') })) : [];
    }

    quality(list, kind) {
        return list.map((q) => ({ key: q.key, name: q.label, text: q.value, id: q.id, open: q.tone === 'open', kind }));
    }
    get qualityRows() {
        if (!this.v) { return []; }
        return [
            ...this.quality(this.v.complaints, 'Complaint'),
            ...this.quality(this.v.ncs, 'NC'),
            ...this.quality(this.v.fieldActions, 'Field Action')
        ];
    }
    get hasQuality() { return this.qualityRows.length > 0; }

    get hasStock() { return this.v && this.v.onHand !== null && this.v.onHand !== undefined; }
    get placeRows() { return this.v ? this.v.places.map((p) => ({ ...p, href: p.locationId ? '/' + p.locationId : null })) : []; }
    get onHandText() { return this.hasStock ? String(Math.round(this.v.onHand)) : ''; }
    get hasShipped() { return this.v && this.v.shipped !== null && this.v.shipped !== undefined; }
    get shippedText() { return this.hasShipped ? String(Math.round(this.v.shipped)) : ''; }
    get asOfText() {
        if (!this.v || !this.v.stockAsOf) { return null; }
        const d = new Date(this.v.stockAsOf);
        return 'As of ' + d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
    }
    get hasWhere() { return this.hasStock || this.hasShipped; }

    handleMore() { this.showAll = !this.showAll; }
    handleOpen(event) { this.openRecord(event.currentTarget.dataset.id); }
    handleShellOpen(event) { this.openRecord(event.detail); }
    openRecord(id) {
        if (!id) { return; }
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, actionName: 'view' } });
    }
    handleEdit() {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: this.recordId, objectApiName: 'compliancequest__SQX_Lot_Info__c', actionName: 'edit' } });
    }
}
