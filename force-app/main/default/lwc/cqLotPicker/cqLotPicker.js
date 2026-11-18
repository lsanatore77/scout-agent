import { LightningElement, api } from 'lwc';
import searchLots from '@salesforce/apex/CqEventLots.searchLots';

/**
 * Lot picker for Report a Problem. The lot is the primary choice: on click it shows the newest lots (or the chosen
 * part's lots), typing 2 or more characters searches by lot number. Fires change with
 * detail { lot, partId, partNumber, partName } so the part can fill in from the lot; lot is null when cleared.
 */
export default class CqLotPicker extends LightningElement {
    @api placeholder = 'Search lot number';
    term = '';
    open = false;
    loading = false;
    items = [];
    picked;            // { lot, partId, partNumber, partName }
    suggestions;       // cached lots shown before typing
    timer;
    _partId;

    /** When a part is chosen, only its lots are offered. */
    @api get partId() { return this._partId; }
    set partId(v) {
        const next = v || undefined;
        if (next !== this._partId) { this._partId = next; this.suggestions = undefined; }
    }

    get searching() { return this.term.trim().length >= 2; }
    get showList() { return this.open && !this.picked; }
    get heading() { return this.searching ? 'Matching Lots' : this._partId ? 'Lots for This Part' : 'Newest Lots'; }
    get hasItems() { return this.items.length > 0; }
    get emptyText() { return this.loading ? 'Searching\u2026' : this.searching ? 'No lots match.' : this._partId ? 'No lots on file for this part.' : 'No lots yet. Type a lot number.'; }
    get rows() { return this.items.map((l, i) => ({ ...l, key: String(i), sub: this.partText(l) || 'No part on file' })); }
    get pickedLabel() { const p = this.picked; if (!p) { return ''; } const t = this.partText(p); return t ? p.lot + ' \u00b7 ' + t : p.lot; }
    partText(l) { return [l.partNumber, l.partName && l.partName !== l.partNumber ? l.partName : null].filter(Boolean).join(' \u00b7 '); }

    fetch(term) { return searchLots({ term, partId: this._partId || null }); }
    async handleFocus() {
        this.open = true;
        if (!this.searching) { await this.loadSuggested(); }
    }
    async loadSuggested() {
        if (!this.suggestions) {
            this.loading = true;
            try { this.suggestions = await this.fetch(''); } catch (e) { this.suggestions = []; } finally { this.loading = false; }
        }
        this.items = this.suggestions;
    }
    handleInput(event) {
        this.term = event.target.value;
        this.open = true;
        clearTimeout(this.timer);
        if (!this.searching) { this.loadSuggested(); return; }
        const t = this.term;
        this.loading = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.timer = setTimeout(async () => {
            try { const r = await this.fetch(t.trim()); if (t === this.term) { this.items = r; } } catch (e) { this.items = []; } finally { this.loading = false; }
        }, 250);
    }
    handleKey(event) {
        if (event.key === 'Escape') { this.open = false; }
        if (event.key === 'Enter' && this.items.length) { event.preventDefault(); this.pick(this.items[0]); }
    }
    handleBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.open = false; }, 150);
    }
    handleDown(event) { event.preventDefault(); }   // keep focus in the box while choosing
    handlePick(event) {
        const l = this.items[Number(event.currentTarget.dataset.key)];
        if (l) { this.pick(l); }
    }
    pick(l) {
        this.picked = l;
        this.open = false;
        this.term = '';
        this.dispatchEvent(new CustomEvent('change', { detail: { lot: l.lot, partId: l.partId, partNumber: l.partNumber, partName: l.partName } }));
    }
    handleClear() {
        this.picked = undefined;
        this.items = this.suggestions || [];
        this.dispatchEvent(new CustomEvent('change', { detail: { lot: null } }));
    }
    @api clear() { this.picked = undefined; this.term = ''; }
}
