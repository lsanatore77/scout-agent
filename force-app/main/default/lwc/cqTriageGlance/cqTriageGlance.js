import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getGlance from '@salesforce/apex/CqTriageController.getGlance';

/** Triage at a Glance on a Nonconformance: the problem, then four cards. Purple cards are CQ.AI suggestions. */
export default class CqTriageGlance extends NavigationMixin(LightningElement) {
    @api recordId;
    g;
    error;
    open = {};
    showGaps = false;

    connectedCallback() { this.load(); }

    @api
    async load() {
        try { this.g = await getGlance({ recordId: this.recordId }); this.error = undefined; }
        catch (e) { this.error = (e && e.body && e.body.message) || 'Could not read this nonconformance.'; }
    }

    get ready() { return !!this.g; }
    get description() { return (this.g && this.g.description) || 'No description on this nonconformance yet.'; }
    get tiles() {
        const g = this.g || {};
        const n = (v) => (v === undefined || v === null ? '—' : String(v));
        return [
            { key: 'part', label: 'Part', value: g.partNumber || g.partName || '—' },
            { key: 'lot', label: 'Lot', value: g.lot || '—' },
            { key: 'qty', label: 'Affected', value: n(g.defectiveQuantity) + ' of ' + n(g.lotQuantity), red: g.defectiveQuantity != null }
        ].map((t) => ({ ...t, cls: 'tv' + (t.red ? ' red' : '') }));
    }
    get cards() {
        return ((this.g && this.g.cards) || []).map((c) => ({
            ...c,
            cls: 'card' + (c.isSuggestion ? ' sug' : ''),
            isOpen: !!this.open[c.id],
            toggleLabel: this.open[c.id] ? '− Less detail' : '+ More detail',
            facts: (c.facts || []).map((f, i) => ({ ...f, key: c.id + i, cls: 'fv' + (f.warn ? ' red' : '') }))
        }));
    }
    get gaps() { return ((this.g && this.g.gaps) || []).map((t, i) => ({ key: 'g' + i, text: t })); }
    get hasGaps() { return this.gaps.length > 0; }
    get gapsLabel() { return (this.showGaps ? 'Hide' : 'Show') + ' missing data (' + this.gaps.length + ')'; }

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.open = { ...this.open, [id]: !this.open[id] };
    }
    handleGaps() { this.showGaps = !this.showGaps; }
    handleEdit() {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: this.recordId, actionName: 'edit' } });
    }
}
