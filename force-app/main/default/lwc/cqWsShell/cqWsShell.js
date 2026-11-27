import { LightningElement, api, wire } from 'lwc';
import getLook from '@salesforce/apex/CqWsSettings.get';

/**
 * cqWsShell: the frame every CQ.AI workspace sits in. The record header (icon, name, key fields, Ask CQ.AI, Edit),
 * the Review Steps rail, the step's own content (the default slot), any error, and the footer (blocker, Back, Next).
 * How it looks comes from CQ.AI Workspace Settings (CqWsSettings): the steps on the left or across the top, and the
 * cqStyles theme, set on this frame's host so every step inside picks it up. A step may put a side column in slot="side".
 * The workspace owns the data and the steps; the shell only draws them and reports clicks as events:
 * step (detail: index), back, next, edit, restart, reopen, open (detail: record id).
 */
export default class CqWsShell extends LightningElement {
    @api recordId;
    @api icon = 'standard:record';
    /** The icon's background colour, when the object's own differs from the icon's default (e.g. '#747e96'). */
    @api iconColor;
    get iconStyle() { return this.iconColor ? '--slds-c-icon-color-background: ' + this.iconColor + '; --sds-c-icon-color-background: ' + this.iconColor + ';' : ''; }
    @api objectLabel;
    @api recordName;
    /** [{ key, label, value, id?, tone? }]: a field with an id shows as a link to that record; tone (pos, warn, crit) colours the value */
    @api fields = [];
    @api showEdit = false;
    @api auditTrail = false;     // shows the Audit Trail link (c-cq-audit-trail) in the header
    @api agentName;
    @api askStep;
    @api askSuggestions;
    /** Ask CQ.AI's pin button under an answer (e.g. Add to Evidence); a pin is passed on as askcqpin. */
    @api pinLabel;
    @api placeholder;           // the Ask CQ.AI box's hint; the popover's own when not set
    get askPlaceholder() { return this.placeholder || 'Ask about this review…'; }
    @api railTitle = 'Review Steps';
    /** [{ label, sub, done, active, locked, mark?, later?, alert? }] in order. mark replaces the step number (e.g. '–'),
     *  later greys a step set aside for later, alert shows its sub line in red. */
    @api steps = [];
    @api canRestart = false;
    @api canReopen = false;
    @api reopenLabel = 'Reopen Review';
    @api resumed = false;
    @api error;
    @api showFoot = false;
    @api blocker;
    @api backDisabled = false;
    @api nextDisabled = false;
    @api nextLabel = 'Next';
    /** Next as an outline button, when the step's own action (in the foot slot) is the primary one. */
    @api nextOutline = false;
    /** A line at the foot of the rail, e.g. '1 of 7 steps complete'. */
    @api progress;
    /** left | top: overrides CQ.AI Workspace Settings > Steps Position for this workspace. */
    @api stepsAt;
    /** A cqStyles theme name: overrides CQ.AI Workspace Settings > Theme for this workspace ('none' for the standard look). */
    @api theme;

    look = { steps: 'left', theme: '' };
    hasSide = false;
    @wire(getLook)
    wiredLook({ data }) { if (data) { this.look = data; this.paintTheme(); } }
    connectedCallback() { this.paintTheme(); this.askHost(); }

    /* Change Workspace: when this workspace sits in a page that switches between workspaces (cqNcWorkspaces), the page
       answers this event with the choices, the one this workspace is, and how to switch. Nowhere else answers it, so
       every other workspace shows no link. The workspaces themselves pass nothing. */
    wsChoices = [];
    wsCurrent;
    wsPick;
    wsOpen = false;
    askHost() {
        const ask = {};
        this.dispatchEvent(new CustomEvent('cqworkspacehost', { bubbles: true, composed: true, detail: ask }));
        if (ask.choices && ask.pick) { this.wsChoices = ask.choices; this.wsCurrent = ask.current; this.wsPick = ask.pick; }
    }
    get hasWorkspaces() { return (this.wsChoices || []).length > 1; }
    get wsExpanded() { return String(this.wsOpen); }
    get wsRows() {
        return this.wsChoices.map((w) => {
            const on = w.key === this.wsCurrent;
            return { ...w, checked: String(on), tick: on ? '\u2713' : '', cls: 'wsitem' + (on ? ' on' : '') };
        });
    }
    toggleWs() { this.wsOpen = !this.wsOpen; }
    closeWs() { this.wsOpen = false; }
    pickWs(event) {
        const key = event.currentTarget.dataset.key;
        this.wsOpen = false;
        if (key !== this.wsCurrent && this.wsPick) { this.wsPick(key); }
    }
    handleWsKey(event) { if (event.key === 'Escape' && this.wsOpen) { event.stopPropagation(); this.wsOpen = false; } }
    get themeName() { const t = this.theme !== undefined && this.theme !== null ? this.theme : this.look.theme; return t && t !== 'none' ? String(t).toLowerCase() : ''; }
    /** The theme is a class on the host (:host(.cq-theme-<name>) in cqStyles), so it reaches the slotted steps and their components. */
    paintTheme() {
        Array.from(this.classList).filter((c) => c.startsWith('cq-theme-')).forEach((c) => this.classList.remove(c));
        if (this.themeName) { this.classList.add('cq-theme-' + this.themeName); }
    }
    get atTop() { return (this.stepsAt || this.look.steps) === 'top'; }
    get bodyCls() { return 'cq-ws-body' + (this.atTop ? ' top' : ''); }
    /** A screen with no steps (a record view such as the Lot record) has no rail. */
    get railCls() { return 'cq-rail' + (this.atTop ? ' top' : '') + (this.steps && this.steps.length ? '' : ' none'); }
    get sideCls() { return 'cq-ws-side' + (this.hasSide ? '' : ' none'); }
    handleSideChange(event) { this.hasSide = event.target.assignedElements().length > 0; }

    get hasFields() { return (this.fields || []).length > 0; }
    get fieldRows() {
        return (this.fields || []).map((f) => {
            const blank = f.value === undefined || f.value === null || f.value === '';
            return { ...f, key: f.key || f.label, value: blank ? '—' : String(f.value), isLink: !!f.id && !blank,
                vcls: 'cq-hl-v' + (f.tone && !blank ? ' tone-' + f.tone : '') };
        });
    }
    get stepRows() {
        return (this.steps || []).map((s, i) => ({
            ...s, i, n: s.mark !== undefined ? s.mark : i + 1,
            current: s.active ? 'step' : null,
            subCls: 'ssub' + (s.alert ? ' alert' : ''),
            cls: 'step' + (s.active ? ' active' : '') + (s.done ? ' done' : '') + (s.later ? ' later' : '')
        }));
    }

    get nextCls() { return this.nextOutline ? 'cq-btn-outline' : 'cq-btn-primary'; }

    fire(name, detail) { this.dispatchEvent(new CustomEvent(name, { detail })); }
    handleStep(event) { this.fire('step', Number(event.currentTarget.dataset.i)); }
    handleBack() { this.fire('back'); }
    handleNext() { this.fire('next'); }
    handleEdit() { this.fire('edit'); }
    handleRestart() { this.fire('restart'); }
    handleReopen() { this.fire('reopen'); }
    handleOpen(event) { this.fire('open', event.currentTarget.dataset.id); }
    /** An action link in an Ask CQ.AI answer (e.g. Create CAPA): passed on to the workspace as askcqaction. */
    handleAskAction(event) { this.fire('askcqaction', event.detail); }
    handleAskPin(event) { this.fire('askcqpin', event.detail); }
    /** Puts a question to the header's Ask CQ.AI (e.g. a Generate with CQ.AI button in a step). */
    @api ask(question) { const p = this.template.querySelector('c-ask-cq-popover'); if (p) { p.ask(question); } }
}
