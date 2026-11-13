import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getGlance from '@salesforce/apex/CqTriageController.getGlance';
import getPhotoVersionId from '@salesforce/apex/CqTriagePhoto.getPhotoVersionId';
import savePhoto from '@salesforce/apex/CqTriagePhoto.savePhoto';
import getTriage from '@salesforce/apex/CqTriageAssistant.getTriage';

/** Triage at a Glance on a Nonconformance: the problem, then four cards. Purple cards are CQ.AI suggestions. */
export default class CqTriageGlance extends NavigationMixin(LightningElement) {
    @api recordId;
    g;
    error;
    open = {};
    showGaps = false;
    photoId;
    uploading = false;
    dragging = false;
    photoError;
    triage;
    showAssistant = false;

    connectedCallback() { this.load(); }

    @api
    async load() {
        try { this.g = await getGlance({ recordId: this.recordId }); this.error = undefined; }
        catch (e) { this.error = (e && e.body && e.body.message) || 'Could not read this nonconformance.'; }
        this.loadPhoto();
        try { this.triage = await getTriage({ recordId: this.recordId }); }
        catch (e) { this.triage = undefined; }
    }

    get triaged() { return !!(this.triage && this.triage.setOn); }
    get triageLine() {
        const t = this.triage || {};
        return 'Triaged' + (t.setBy ? ' by ' + t.setBy : '') + ' \u00b7 Risk ' + t.risk + ' \u00b7 ' + t.path;
    }
    get triageNotes() { return (this.triage && this.triage.notes) || ''; }
    get hasPhoto() { return !!this.photoId; }
    handleAssistant() { this.showAssistant = true; }
    handleAssistantClose() { this.showAssistant = false; }
    handleTriageDone() { this.load(); }

    async loadPhoto() {
        try { this.photoId = await getPhotoVersionId({ recordId: this.recordId }); }
        catch (e) { this.photoId = null; }
    }

    get photoUrl() { return this.photoId ? '/sfc/servlet.shepherd/version/download/' + this.photoId : null; }
    get photoCls() { return 'photo' + (this.photoId ? ' has' : '') + (this.dragging ? ' drag' : ''); }
    get addLabel() { return this.uploading ? 'Saving\u2026' : 'Add a photo'; }

    handlePick() { this.template.querySelector('input.file').click(); }
    handleFile(event) {
        const f = event.target.files && event.target.files[0];
        event.target.value = '';
        if (f) { this.upload(f); }
    }
    handleDragOver(event) { event.preventDefault(); this.dragging = true; }
    handleDragLeave() { this.dragging = false; }
    handleDrop(event) {
        event.preventDefault();
        this.dragging = false;
        const f = event.dataTransfer && event.dataTransfer.files && event.dataTransfer.files[0];
        if (f) { this.upload(f); }
    }

    async upload(file) {
        if (this.uploading) { return; }
        if (!/^image\//.test(file.type || '')) { this.photoError = 'Choose an image file.'; return; }
        this.uploading = true;
        this.photoError = undefined;
        try {
            const base64Data = await this.shrink(file);
            const fileName = (file.name || 'photo').replace(/\.[^.]+$/, '') + '.jpg';
            this.photoId = await savePhoto({ recordId: this.recordId, fileName, base64Data });
        } catch (e) {
            this.photoError = (e && e.body && e.body.message) || 'Could not save the photo.';
        }
        this.uploading = false;
    }

    /** Resizes to at most 1600px on the long side and returns JPEG base64, so large phone photos save quickly. */
    shrink(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onerror = () => reject(new Error('read'));
            reader.onload = () => {
                const img = new Image();
                img.onerror = () => reject(new Error('image'));
                img.onload = () => {
                    const s = Math.min(1, 1600 / Math.max(img.width, img.height));
                    const c = document.createElement('canvas');
                    c.width = Math.max(1, Math.round(img.width * s));
                    c.height = Math.max(1, Math.round(img.height * s));
                    const ctx = c.getContext('2d');
                    ctx.fillStyle = '#fff';
                    ctx.fillRect(0, 0, c.width, c.height);
                    ctx.drawImage(img, 0, 0, c.width, c.height);
                    resolve(c.toDataURL('image/jpeg', 0.85).split(',')[1]);
                };
                img.src = reader.result;
            };
            reader.readAsDataURL(file);
        });
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
