import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import canInvestigate from '@salesforce/customPermission/CQAI_Can_Investigate';
import canDisposition from '@salesforce/customPermission/CQAI_Can_Disposition';
import isAdmin from '@salesforce/userPermission/ModifyAllData';

/**
 * The NC record page in Disposition / Investigate: one workspace at a time (decided with Lou 27 Nov 2026; mockup
 * "Disposition / Investigation Switch Mockup"). Can Investigate shows the Investigation workspace, Can Disposition the
 * Disposition workspace (permission sets CQAI_Can_Investigate and CQAI_Can_Disposition); administrators always see both.
 * With both, a tab switch above the workspace, Investigation first; never both stacked. A workspace is loaded the first time
 * its tab is opened and then kept, so switching back does not reload it. The page state c__part = investigation or
 * disposition opens that side (for links from the Quality Management home).
 */
export default class CqNcWorkspaces extends LightningElement {
    @api recordId;
    part;
    seen = {};

    get canInv() { return !!canInvestigate || !!isAdmin; }
    get canDisp() { return !!canDisposition || !!isAdmin; }

    @wire(CurrentPageReference)
    setRef(ref) {
        const p = ref && ref.state ? ref.state.c__part : null;
        if ((p === 'investigation' && this.canInv) || (p === 'disposition' && this.canDisp)) { this.open(p); }
    }
    connectedCallback() {
        if (!this.part) { this.open(this.canInv ? 'investigation' : this.canDisp ? 'disposition' : null); }
    }
    open(p) {
        this.part = p;
        if (p) { this.seen = { ...this.seen, [p]: true }; }
    }

    get tabs() {
        const list = [];
        if (this.canInv) { list.push({ key: 'investigation', label: 'Investigation' }); }
        if (this.canDisp) { list.push({ key: 'disposition', label: 'Disposition' }); }
        return list.map((t) => ({ ...t, on: t.key === this.part, selected: String(t.key === this.part), cls: 'part' + (t.key === this.part ? ' on' : ''), id: 'tab-' + t.key }));
    }
    get hasTabs() { return this.tabs.length > 0; }
    get none() { return !this.canInv && !this.canDisp; }
    get loadInv() { return this.canInv && !!this.seen.investigation; }
    get loadDisp() { return this.canDisp && !!this.seen.disposition; }
    get invCls() { return this.part === 'investigation' ? 'pane' : 'pane hidden'; }
    get dispCls() { return this.part === 'disposition' ? 'pane' : 'pane hidden'; }

    handleTab(event) { this.open(event.currentTarget.dataset.key); }
    handleTabKey(event) {
        if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') { return; }
        const keys = this.tabs.map((t) => t.key);
        if (keys.length < 2) { return; }
        event.preventDefault();
        const i = keys.indexOf(this.part);
        const next = keys[(i + (event.key === 'ArrowRight' ? 1 : keys.length - 1)) % keys.length];
        this.open(next);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => { const b = this.template.querySelector('button[data-key="' + next + '"]'); if (b) { b.focus(); } });
    }
}
