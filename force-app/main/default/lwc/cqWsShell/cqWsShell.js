import { LightningElement, api } from 'lwc';

/**
 * cqWsShell: the frame every CQ.AI workspace sits in. The record header (icon, name, key fields, Ask CQ.AI, Edit),
 * the Review Steps rail, the step's own content (the default slot), any error, and the footer (blocker, Back, Next).
 * The workspace owns the data and the steps; the shell only draws them and reports clicks as events:
 * step (detail: index), back, next, edit, restart, reopen, open (detail: record id).
 */
export default class CqWsShell extends LightningElement {
    @api recordId;
    @api icon = 'standard:record';
    @api objectLabel;
    @api recordName;
    /** [{ key, label, value, id? }]: a field with an id shows as a link to that record */
    @api fields = [];
    @api showEdit = false;
    @api auditTrail = false;     // shows the Audit Trail link (c-cq-audit-trail) in the header
    @api agentName;
    @api askStep;
    @api askSuggestions;
    @api railTitle = 'Review Steps';
    /** [{ label, sub, done, active, locked }] in order */
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

    get hasFields() { return (this.fields || []).length > 0; }
    get fieldRows() {
        return (this.fields || []).map((f) => {
            const blank = f.value === undefined || f.value === null || f.value === '';
            return { ...f, key: f.key || f.label, value: blank ? '—' : String(f.value), isLink: !!f.id && !blank };
        });
    }
    get stepRows() {
        return (this.steps || []).map((s, i) => ({
            ...s, i, n: i + 1,
            current: s.active ? 'step' : null,
            cls: 'step' + (s.active ? ' active' : '') + (s.done ? ' done' : '')
        }));
    }

    fire(name, detail) { this.dispatchEvent(new CustomEvent(name, { detail })); }
    handleStep(event) { this.fire('step', Number(event.currentTarget.dataset.i)); }
    handleBack() { this.fire('back'); }
    handleNext() { this.fire('next'); }
    handleEdit() { this.fire('edit'); }
    handleRestart() { this.fire('restart'); }
    handleReopen() { this.fire('reopen'); }
    handleOpen(event) { this.fire('open', event.currentTarget.dataset.id); }
}
