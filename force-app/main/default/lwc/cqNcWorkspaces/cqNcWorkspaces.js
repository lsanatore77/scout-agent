import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import canInvestigate from '@salesforce/customPermission/CQAI_Can_Investigate';
import canDisposition from '@salesforce/customPermission/CQAI_Can_Disposition';
import isAdmin from '@salesforce/userPermission/ModifyAllData';

const TAGS = { 'C-CQ-INVESTIGATION-WORKSPACE': 'investigation', 'C-CQ-DISPOSITION-WORKSPACE': 'disposition' };

/**
 * The NC record page in Disposition / Investigate: one workspace at a time (decided with Lou 27 Nov 2026). Can Investigate
 * shows the Investigation workspace, Can Disposition the Disposition workspace (permission sets CQAI_Can_Investigate and
 * CQAI_Can_Disposition); administrators always see both. With both, the Investigation workspace opens first and a small
 * Change Workspace link under Edit in the workspace header opens a menu to switch (Disposition Workspace, Investigation
 * Workspace). The header (cqWsShell) asks this page for the choices with the cqworkspacehost event, so the workspaces
 * themselves pass nothing. A workspace is loaded the first time it is opened and then kept, so switching back does not
 * reload it. The page state c__part = investigation or disposition opens that side (for links from the Quality home).
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
        this.template.addEventListener('cqworkspacehost', this.answerHost);
    }
    disconnectedCallback() { this.template.removeEventListener('cqworkspacehost', this.answerHost); }

    /** A workspace header asks which workspaces it can switch to; the event arrives retargeted to the workspace element. */
    answerHost = (event) => {
        const current = TAGS[event.target && String(event.target.tagName).toUpperCase()];
        if (!current) { return; }
        event.stopPropagation();
        const ask = event.detail;
        ask.choices = this.choices;
        ask.current = current;
        ask.pick = (key) => this.open(key);
    };
    get choices() {
        const list = [];
        if (this.canDisp) { list.push({ key: 'disposition', label: 'Disposition Workspace' }); }
        if (this.canInv) { list.push({ key: 'investigation', label: 'Investigation Workspace' }); }
        return list;
    }

    open(p) {
        this.part = p;
        if (p) { this.seen = { ...this.seen, [p]: true }; }
    }
    get none() { return !this.canInv && !this.canDisp; }
    get loadInv() { return this.canInv && !!this.seen.investigation; }
    get loadDisp() { return this.canDisp && !!this.seen.disposition; }
    get invCls() { return this.part === 'investigation' ? 'pane' : 'pane hidden'; }
    get dispCls() { return this.part === 'disposition' ? 'pane' : 'pane hidden'; }
}
