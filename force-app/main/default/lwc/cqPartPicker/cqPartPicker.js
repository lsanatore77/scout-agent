import { LightningElement, api } from 'lwc';
import suggested from '@salesforce/apex/CqEventParts.suggested';
import search from '@salesforce/apex/CqEventParts.search';

/**
 * Part picker for Report a Problem. On click it shows Suggested Parts (most recently used on events, NCs and
 * complaints); typing 2 or more letters searches by part number or name. Fires change with detail.recordId.
 */
export default class CqPartPicker extends LightningElement {
    @api placeholder = 'Search part number or name';
    term = '';
    open = false;
    loading = false;
    items = [];
    picked;            // { id, partNumber, name }
    suggestions;       // cached Suggested Parts
    timer;

    get showList() { return this.open && !this.picked; }
    get heading() { return this.term.trim().length >= 2 ? 'Matching Parts' : 'Suggested Parts'; }
    get hasItems() { return this.items.length > 0; }
    get emptyText() { return this.loading ? 'Searching…' : this.term.trim().length >= 2 ? 'No parts match.' : 'No suggestions yet. Type a part number or name.'; }
    get rows() { return this.items.map((p) => ({ ...p, label: p.partNumber || p.name, sub: p.partNumber ? p.name : '' })); }
    get pickedLabel() { return this.picked ? (this.picked.partNumber ? this.picked.partNumber + ' · ' + this.picked.name : this.picked.name) : ''; }

    // Open the list where it fits: below when there is room, above when there is not, and never taller than the
    // space available. A list that runs past the bottom of the page makes the page grow and the screen jump.
    up = false;
    maxH = 320;
    place() {
        const w = this.template.querySelector('.wrap');
        if (!w) { return; }
        const r = w.getBoundingClientRect();
        const below = window.innerHeight - r.bottom - 12;
        const above = r.top - 12;
        this.up = below < 220 && above > below;
        this.maxH = Math.max(120, Math.min(320, Math.floor(this.up ? above : below)));
    }
    get listCls() { return 'list' + (this.up ? ' up' : ''); }
    get listStyle() { return 'max-height: ' + this.maxH + 'px;'; }

    async handleFocus() {
        this.place();
        this.open = true;
        if (this.term.trim().length < 2) { await this.loadSuggested(); }
    }
    async loadSuggested() {
        if (!this.suggestions) {
            this.loading = true;
            try { this.suggestions = await suggested(); } catch (e) { this.suggestions = []; } finally { this.loading = false; }
        }
        this.items = this.suggestions;
    }
    handleInput(event) {
        this.term = event.target.value;
        if (!this.open) { this.place(); }
        this.open = true;
        clearTimeout(this.timer);
        if (this.term.trim().length < 2) { this.loadSuggested(); return; }
        const t = this.term;
        this.loading = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.timer = setTimeout(async () => {
            try { const r = await search({ term: t }); if (t === this.term) { this.items = r; } } catch (e) { this.items = []; } finally { this.loading = false; }
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
        const p = this.items.find((x) => x.id === event.currentTarget.dataset.id);
        if (p) { this.pick(p); }
    }
    pick(p) {
        this.picked = p;
        this.open = false;
        this.term = '';
        this.dispatchEvent(new CustomEvent('change', { detail: { recordId: p.id } }));
    }
    handleClear() {
        this.picked = undefined;
        this.items = this.suggestions || [];
        this.dispatchEvent(new CustomEvent('change', { detail: { recordId: null } }));
    }
    @api clear() { this.picked = undefined; this.term = ''; }
    /** Fill the part from outside (a chosen lot) without firing change. */
    @api setPart(p) {
        this.picked = p && p.id ? { id: p.id, partNumber: p.partNumber, name: p.name } : undefined;
        this.term = '';
        this.open = false;
    }
}
