import { LightningElement, api } from 'lwc';

/**
 * cqWsChoice: pick one of a few options. variant "cards" lays them side by side (an outcome); "rows" stacks them
 * in one bordered list (which record) with an "after" slot for a form that opens under the list.
 * The suggested option carries a small purple "CQ.AI Suggests". Fires choose (detail: option id).
 */
export default class CqWsChoice extends LightningElement {
    @api label;
    /** The group's name for screen readers when the heading is drawn outside (no label). */
    @api name;
    @api variant = 'cards';
    /** [{ id, title, desc, cq, off }]: off dims an option that does not fit (it can still be chosen) */
    @api options = [];
    @api value;
    @api disabled = false;

    get isRows() { return this.variant === 'rows'; }
    get groupLabel() { return this.label || this.name; }
    get listCls() { return this.isRows ? 'falist' : 'ocgrid'; }
    get rows() {
        return (this.options || []).map((o) => {
            const on = o.id === this.value;
            return { ...o, pressed: on ? 'true' : 'false', cls: (this.isRows ? 'row' : 'oc') + (on ? ' on' : '') + (o.off ? ' off' : '') };
        });
    }
    handleChoose(event) { this.dispatchEvent(new CustomEvent('choose', { detail: event.currentTarget.dataset.id })); }
}
