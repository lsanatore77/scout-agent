import { LightningElement, api } from 'lwc';

/**
 * cqWsTabs: a card with a tab bar. The workspace shows the open tab's content in the slot and listens for
 * change (detail: tab id) to switch it.
 */
export default class CqWsTabs extends LightningElement {
    @api label = 'Evidence';
    /** [{ id, label }] */
    @api tabs = [];
    @api active;

    get tabRows() {
        return (this.tabs || []).map((t) => ({ ...t, sel: t.id === this.active ? 'true' : 'false', cls: 'evtab' + (t.id === this.active ? ' on' : '') }));
    }
    handleTab(event) { this.dispatchEvent(new CustomEvent('change', { detail: event.currentTarget.dataset.id })); }
}
