import { LightningElement, api } from 'lwc';

/** cqWsProblem: The Problem card on an At a Glance step. Photo on the left; title, description and key figures on the right. */
export default class CqWsProblem extends LightningElement {
    @api title = 'The Problem';
    @api description;
    @api photoUrl;
    @api noPhotoText = 'No photo on the source record';
    /** [{ label, value }] */
    @api tiles = [];

    get photoCls() { return 'photo' + (this.photoUrl ? ' has' : ''); }
    get hasTiles() { return (this.tiles || []).length > 0; }
    get tileRows() {
        return (this.tiles || []).map((t) => ({ key: t.key || t.label, label: t.label,
            value: t.value === undefined || t.value === null || t.value === '' ? '—' : String(t.value) }));
    }
}
