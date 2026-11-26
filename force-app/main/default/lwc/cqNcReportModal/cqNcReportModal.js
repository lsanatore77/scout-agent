import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import duplicates from '@salesforce/apex/CqNcReport.duplicates';
import fillIn from '@salesforce/apex/CqNcReport.fillIn';
import suggestDescription from '@salesforce/apex/CqNcReport.suggestDescription';
import create from '@salesforce/apex/CqNcReport.create';
import addToExisting from '@salesforce/apex/CqNcReport.addToExisting';
import attachFile from '@salesforce/apex/CqNcReport.attachFile';
import mentions from '@salesforce/apex/CqNcReport.mentions';

const LOT_LIKE = /\b[A-Za-z0-9]{1,12}(?:-[A-Za-z0-9]{1,12}){1,4}\b/;
const MAX_FILE_BYTES = 3 * 1024 * 1024;
const TYPES = ['Internal', 'Supplier', 'Customer'];
// @ then the start of a lot or part, right before the cursor (after a space or at the start of the text)
const MENTION = /(^|\s)@([^\s@]{1,40})$/;

/**
 * Report a Nonconformance: a two-step popup anyone can use to raise an NC directly.
 * Step 1: what happened (a possible duplicate shows under the box while they type). Step 2: CQ.AI's wording and the
 * fields CQ.AI filled in, then Create and Send to Triage. Nothing is saved before Create (or Merge).
 * Design decided with Lou, 25 Nov 2026 (mockup "Report a Nonconformance Mockup").
 * A LightningModal, so it opens over the whole page from the utility bar, a list button or a page (c-cq-nc-report
 * opens it). It closes with { recordId } when the person asks to open an NC, which the opener navigates to.
 */
export default class CqNcReportModal extends LightningModal {
    @api options;
    step = 1;              // 1, 2, 'done' or 'merged'
    text = '';
    files = [];            // { key, name, size, base64 }
    fileNote;

    dups = [];
    dupFromStep2 = false;
    dupDismissed = false;
    dupTimer;
    lastDupText;

    reading = false;
    fill;                  // what CQ.AI filled in
    wording;               // CQ.AI's suggested description
    useWording = false;
    choseWording = false;  // the person pressed Use This or Keep Mine
    editing = false;
    v = {};                // the values to save: title, part, lot, quantity, type, failure
    pickerStarted = false;

    // @ in the description: an optional shortcut to pick the exact lot or part (Lou, 25 Nov 2026; new NCs only for now)
    mentionItems = [];     // what the search offered
    mentionActive = 0;     // the highlighted item
    mentionStart = -1;     // where the @ is in the text
    mentionEnd = -1;       // the cursor
    mentionTimer;
    mentionSeq = 0;
    picks = {};            // { lot: { lot, partId, partNumber, partName }, part: { partId, partNumber, partName } }
    caretAfter;            // where to put the cursor after a pick
    mentionPos = { left: 0, top: 0 };   // where the list opens: just under the @, kept inside the box

    focused = false;
    saving = false;
    error;
    result;
    get ncUrl() { return this.result ? '/' + this.result.id : '#'; }

    // ------------------------------------------------------------ open and close

    handleClose() {
        clearTimeout(this.dupTimer);
        this.close();
    }
    reset() {
        this.focused = false;
        this.step = 1; this.text = ''; this.files = []; this.fileNote = undefined;
        this.dups = []; this.dupFromStep2 = false; this.dupDismissed = false; this.lastDupText = undefined;
        this.reading = false; this.fill = undefined; this.wording = undefined; this.useWording = false; this.choseWording = false;
        this.editing = false; this.v = {}; this.pickerStarted = false;
        this.closeMentions(); this.picks = {};
        this.saving = false; this.error = undefined; this.result = undefined;
    }

    renderedCallback() {
        if (this.caretAfter != null) {
            const box = this.template.querySelector('textarea[data-id="desc"]');
            if (box) { box.value = this.text; box.focus(); box.setSelectionRange(this.caretAfter, this.caretAfter); }
            this.caretAfter = undefined;
        }
        if (this.step === 1 && !this.focused) {
            const box = this.template.querySelector('textarea[data-id="desc"]');
            if (box) { box.focus(); this.focused = true; }
        }
        // with no part found, the picker opens by itself, starting from CQ.AI's word
        if (this.isStep2 && !this.reading && this.showPartPicker && !this.pickerStarted) {
            const picker = this.template.querySelector('c-cq-part-picker');
            if (picker) {
                this.pickerStarted = true;
                if (this.fill && this.fill.partTerm) { picker.startSearch(this.fill.partTerm); }
            }
        }
    }

    // ------------------------------------------------------------ step 1

    get isStep1() { return this.step === 1; }
    get isStep2() { return this.step === 2; }
    get isDone() { return this.step === 'done'; }
    get isMerged() { return this.step === 'merged'; }
    get stepText() { return this.isStep1 ? 'Step 1 of 2' : this.isStep2 ? 'Step 2 of 2' : ''; }
    get createLabel() { return this.saving ? 'Creating…' : 'Create and Send to Triage'; }
    get cantCreate() { return this.reading || this.saving; }
    get cantNext() { return !this.text || !this.text.trim(); }

    handleText(event) {
        this.text = event.target.value;
        this.findMention(event.target);
        this.dupDismissed = false;
        clearTimeout(this.dupTimer);
        // a plain lookup, no AI: only when something in the text looks like a lot number
        if (!LOT_LIKE.test(this.text)) { this.dups = []; return; }
        const t = this.text;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.dupTimer = setTimeout(() => { this.checkDups(t, null, false); }, 500);
    }
    // ---- @: pick a lot or part

    /** A click moves the cursor: open or close the list for the word it lands in. */
    handleCaret(event) { this.findMention(event.target); }

    findMention(box) {
        clearTimeout(this.mentionTimer);
        const caret = box.selectionStart == null ? this.text.length : box.selectionStart;
        const m = MENTION.exec(this.text.slice(0, caret));
        if (!m) { this.closeMentions(); return; }
        const term = m[2];
        this.mentionStart = caret - term.length - 1;
        this.mentionEnd = caret;
        this.placeMentions(box);
        const seq = ++this.mentionSeq;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.mentionTimer = setTimeout(async () => {
            try {
                const r = await mentions({ term });
                if (seq !== this.mentionSeq) { return; }
                this.mentionItems = r || [];
                this.mentionActive = 0;
            } catch (e) {
                this.mentionItems = [];   // a help, never a blocker
            }
        }, 250);
    }
    /**
     * Where the @ sits in the box, found with a hidden copy of the box that holds the text up to the @ (a textarea
     * does not say where a character is). The list opens under that line (or above it near the bottom), starting at
     * the @, moved left when it would run past the box's right edge.
     */
    placeMentions(box) {
        const mirror = this.template.querySelector('.mirror');
        if (!mirror || !box) { return; }
        try {
            const cs = window.getComputedStyle(box);
            ['fontFamily', 'fontSize', 'fontWeight', 'fontStyle', 'letterSpacing', 'lineHeight', 'textTransform', 'wordSpacing',
                'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft', 'borderTopWidth', 'borderRightWidth',
                'borderBottomWidth', 'borderLeftWidth', 'boxSizing', 'tabSize'].forEach((p) => { mirror.style[p] = cs[p]; });
            mirror.style.width = box.offsetWidth + 'px';
            mirror.textContent = '';
            mirror.appendChild(document.createTextNode(this.text.slice(0, this.mentionStart)));
            const mark = document.createElement('span');
            mark.textContent = '@';
            mirror.appendChild(mark);
            const lineH = parseFloat(cs.lineHeight) || parseFloat(cs.fontSize) * 1.4;
            const listW = Math.min(17 * parseFloat(window.getComputedStyle(document.documentElement).fontSize || 16), box.offsetWidth);
            const left = Math.max(0, Math.min(box.offsetLeft + box.clientLeft + mark.offsetLeft, box.offsetLeft + box.offsetWidth - listW));
            // the list floats over the popup and never makes it grow or scroll: under the line when the popup's content
            // has room below it, else above the line; a list longer than its room scrolls inside itself
            const lineTop = Math.max(0, box.clientTop + mark.offsetTop - box.scrollTop);   // in the box
            const body = this.template.querySelector('.body');
            const boxR = box.getBoundingClientRect();
            const bodyR = body ? body.getBoundingClientRect() : boxR;
            const below = bodyR.bottom - (boxR.top + lineTop + lineH + 2);
            const above = (boxR.top + lineTop - 2) - bodyR.top;
            const WANT = 200;   // about five rows and their group labels
            if (below >= WANT || below >= above) {
                this.mentionPos = { left, top: box.offsetTop + lineTop + lineH + 2, maxH: Math.max(below, 72) };
            } else {
                this.mentionPos = { left, bottom: box.offsetHeight - lineTop + 2, maxH: Math.max(above, 72) };
            }
        } catch (e) {
            this.mentionPos = { left: 0, top: box.offsetTop + box.offsetHeight };   // under the box, as before
        }
    }
    get mentionStyle() {
        const p = this.mentionPos;
        return 'left: ' + p.left + 'px;' + (p.bottom != null ? ' bottom: ' + p.bottom + 'px;' : ' top: ' + p.top + 'px;')
            + (p.maxH ? ' max-height: ' + Math.round(p.maxH) + 'px;' : '');
    }
    closeMentions() {
        clearTimeout(this.mentionTimer);
        this.mentionSeq++;
        this.mentionItems = [];
        this.mentionActive = 0;
        this.mentionStart = -1;
    }
    get mentionOpen() { return this.isStep1 && this.mentionStart >= 0 && this.mentionItems.length > 0; }
    get mentionExpanded() { return String(this.mentionOpen); }
    get mentionActiveId() { return this.mentionOpen ? 'mention-' + this.mentionActive : ''; }
    get mentionGroups() {
        const items = this.mentionItems.map((m, i) => ({
            ...m, key: m.kind + '-' + m.label + '-' + i, index: i, optId: 'mention-' + i,
            cls: 'opt' + (i === this.mentionActive ? ' on' : ''), selected: String(i === this.mentionActive)
        }));
        return [
            { key: 'lot', label: 'Lots', items: items.filter((x) => x.kind === 'lot') },
            { key: 'part', label: 'Parts', items: items.filter((x) => x.kind === 'part') }
        ].filter((g) => g.items.length);
    }
    handleTextKey(event) {
        if (!this.mentionOpen) { return; }
        const n = this.mentionItems.length;
        if (event.key === 'ArrowDown') { event.preventDefault(); this.mentionActive = (this.mentionActive + 1) % n; }
        else if (event.key === 'ArrowUp') { event.preventDefault(); this.mentionActive = (this.mentionActive - 1 + n) % n; }
        else if (event.key === 'Enter' || event.key === 'Tab') { event.preventDefault(); this.pickMention(this.mentionActive); }
        else if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); this.closeMentions(); }
    }
    handleTextBlur() {
        // let a click on the list land first
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.closeMentions(); }, 150);
    }
    handleMentionDown(event) { event.preventDefault(); }   // keep the cursor in the box
    handleMentionClick(event) { this.pickMention(parseInt(event.currentTarget.dataset.index, 10)); }
    pickMention(i) {
        const m = this.mentionItems[i];
        if (!m || this.mentionStart < 0) { return; }
        const words = m.kind === 'lot' ? 'lot ' + m.label : m.label;
        const before = this.text.slice(0, this.mentionStart);
        const after = this.text.slice(this.mentionEnd);
        const glue = after.startsWith(' ') ? '' : ' ';
        this.text = before + words + glue + after;
        this.caretAfter = before.length + words.length + glue.length;
        if (m.kind === 'lot') {
            this.picks = { ...this.picks, lot: { lot: m.label, partId: m.partId, partNumber: m.partNumber, partName: m.partName } };
        } else {
            this.picks = { ...this.picks, part: { partId: m.partId, partNumber: m.partNumber, partName: m.partName } };
        }
        this.closeMentions();
        if (m.kind === 'lot') { this.dupDismissed = false; this.checkDups(this.text, m.label, false); }
    }
    /** The picks still written in the text (one deleted afterwards no longer counts). */
    livePicks() {
        const t = (this.text || '').toUpperCase();
        const lot = this.picks.lot && t.includes(this.picks.lot.lot.toUpperCase()) ? this.picks.lot : null;
        const part = this.picks.part && this.picks.part.partNumber && t.includes(this.picks.part.partNumber.toUpperCase()) ? this.picks.part : null;
        return { lot, part };
    }

    async checkDups(t, lot, fromStep2) {
        if (!fromStep2 && t === this.lastDupText) { return; }
        this.lastDupText = t;
        try {
            const r = await duplicates({ text: t, lot });
            if (fromStep2) {
                if (!this.dups.length && r && r.length) { this.dups = r; this.dupFromStep2 = true; }
            } else if (t === this.text) {
                this.dups = r || [];
            }
        } catch (e) {
            // the check is a help, never a blocker
        }
    }

    get dup() { return !this.dupDismissed && this.dups.length ? this.dups[0] : null; }
    get dupLine() {
        const d = this.dup;
        if (!d) { return ''; }
        return (d.title ? ', ' + d.title.charAt(0).toLowerCase() + d.title.slice(1) : '') + ', same lot';
    }
    get dupMore() { return this.dups.length > 1 ? 'and ' + (this.dups.length - 1) + ' more on this lot' : ''; }
    get showDupStep1() { return this.isStep1 && !!this.dup; }
    get showDupStep2() { return this.isStep2 && !this.reading && !!this.dup && this.dupFromStep2; }
    handleDupOpen(event) {
        event.preventDefault();
        const d = this.dup;
        if (d) { this.close({ recordId: d.id }); }
    }
    handleDupCreate() { this.dupDismissed = true; }

    // files: held here until a record exists, then attached one at a time
    handleAddFiles() { const i = this.template.querySelector('input[data-id="files"]'); if (i) { i.click(); } }
    handleFiles(event) {
        const picked = Array.from(event.target.files || []);
        event.target.value = '';
        picked.forEach((f) => {
            if (f.size > MAX_FILE_BYTES) { this.fileNote = f.name + ' is over 3 MB. Add it on the NC after it is created.'; return; }
            const reader = new FileReader();
            reader.onload = () => {
                const s = String(reader.result || '');
                this.files = [...this.files, { key: f.name + '-' + Date.now() + '-' + Math.random(), name: f.name, size: f.size, base64: s.substring(s.indexOf(',') + 1) }];
            };
            reader.readAsDataURL(f);
        });
    }
    handleRemoveFile(event) {
        const k = event.currentTarget.dataset.key;
        this.files = this.files.filter((f) => f.key !== k);
    }
    get hasFiles() { return this.files.length > 0; }

    async handleNext() {
        if (this.cantNext) { return; }
        clearTimeout(this.dupTimer);
        this.step = 2;
        this.error = undefined;
        if (this.fill && this.fill.text === this.text) { return; }   // nothing changed since the last read
        this.reading = true;
        this.editing = false; this.pickerStarted = false; this.choseWording = false; this.useWording = false;
        const t = this.text;
        // CQ.AI's two calls run side by side
        const [f, w] = await Promise.all([
            fillIn({ text: t }).catch((e) => { this.error = this.msg(e); return null; }),
            suggestDescription({ text: t }).catch(() => null)
        ]);
        if (t !== this.text) { return; }
        this.fill = f ? { ...f, text: t } : { text: t, type: 'Internal' };
        this.wording = w && w.trim() !== t.trim() ? w : undefined;
        this.v = {
            title: this.fill.title || '',
            part: this.fill.partId ? { id: this.fill.partId, partNumber: this.fill.partNumber, name: this.fill.partName } : null,
            lot: this.fill.lot || '',
            quantity: this.fill.quantity == null ? '' : String(this.fill.quantity),
            type: TYPES.includes(this.fill.type) ? this.fill.type : 'Internal',
            failure: this.fill.failure || ''
        };
        // what was picked with @ is exact, so it wins over what CQ.AI read: the lot (with its part), then a picked part
        const pk = this.livePicks();
        if (pk.lot) {
            this.v.lot = pk.lot.lot;
            if (pk.lot.partId) { this.v.part = { id: pk.lot.partId, partNumber: pk.lot.partNumber, name: pk.lot.partName }; }
        }
        if (pk.part) { this.v.part = { id: pk.part.partId, partNumber: pk.part.partNumber, name: pk.part.partName }; }
        this.v = { ...this.v };
        this.reading = false;
        // the lot CQ.AI found may show a duplicate step 1 could not see
        if (!this.dups.length && this.fill.lot) { this.checkDups('', this.fill.lot, true); }
    }

    // ------------------------------------------------------------ step 2

    get showWording() { return !!this.wording; }
    get wordingState() { return this.choseWording ? (this.useWording ? 'Using CQ.AI\'s wording.' : 'Keeping your words.') : ''; }
    handleUseWording() { this.useWording = true; this.choseWording = true; }
    handleKeepMine() { this.useWording = false; this.choseWording = true; }
    get useCls() { return 'cq-btn-ai' + (this.choseWording && this.useWording ? ' on' : ''); }
    get keepCls() { return 'cq-btn-outline' + (this.choseWording && !this.useWording ? ' on' : ''); }
    get usePressed() { return String(this.choseWording && this.useWording); }
    get keepPressed() { return String(this.choseWording && !this.useWording); }

    get filledCount() {
        const f = this.fill || {};
        return [f.title, f.partId, f.lot, f.quantity, f.type, f.failure].filter((x) => x !== undefined && x !== null && x !== '').length;
    }
    get filledHead() {
        const n = this.filledCount;
        return n ? '✦ CQ.AI Filled In ' + n + (n === 1 ? ' Field' : ' Fields') : '✦ CQ.AI Could Not Fill In Any Fields';
    }
    get partLabel() { const p = this.v.part; return p ? (p.partNumber || p.name) : ''; }
    get showPartPicker() { return !this.v.part; }
    get lotText() { return this.v.lot || 'Not found'; }
    get lotNone() { return this.v.lot ? '' : 'none'; }
    get qtyText() { return this.v.quantity || 'Not found'; }
    get qtyNone() { return this.v.quantity ? '' : 'none'; }
    get titleText() { return this.v.title || 'Not found'; }
    get titleNone() { return this.v.title ? 'span' : 'span none'; }
    get failureText() { return this.v.failure || 'Not found'; }
    get failureNone() { return this.v.failure ? 'span' : 'span none'; }
    get typeOptions() { return TYPES.map((t) => ({ value: t, label: t, selected: t === this.v.type })); }
    get editLabel() { return this.editing ? 'Done' : 'Edit'; }

    handleEdit() { this.editing = !this.editing; }
    handleField(event) {
        const k = event.target.dataset.field;
        this.v = { ...this.v, [k]: event.target.value };
    }
    handlePart(event) {
        const d = event.detail || {};
        this.v = { ...this.v, part: d.recordId ? { id: d.recordId, partNumber: d.partNumber, name: d.name } : null };
    }
    handleClearPart() { this.v = { ...this.v, part: null }; this.pickerStarted = true; }

    handleBack() { this.step = 1; this.error = undefined; }

    suggestedMap() {
        const f = this.fill || {};
        return {
            Title: f.title || '', Part: f.partNumber || '', Lot: f.lot || '',
            'Defective Quantity': f.quantity == null ? '' : String(f.quantity), Type: f.type || '', Failure: f.failure || ''
        };
    }

    async handleCreate() {
        if (this.saving) { return; }
        this.saving = true; this.error = undefined;
        const q = parseInt(this.v.quantity, 10);
        const report = {
            description: this.useWording && this.wording ? this.wording : this.text,
            asReported: this.text,
            usedSuggestion: !!(this.useWording && this.wording),
            title: this.v.title, partId: this.v.part ? this.v.part.id : null, lot: this.v.lot,
            quantity: Number.isNaN(q) || q <= 0 ? null : q, type: this.v.type, failure: this.v.failure,
            suggested: this.fill && this.fill.text ? this.suggestedMap() : null
        };
        try {
            const r = await create({ reportJson: JSON.stringify(report) });
            const warnings = [...(r.warnings || []), ...(await this.uploadFiles(r.id))];
            this.result = { ...r, warnings };
            this.step = 'done';
        } catch (e) {
            this.error = this.msg(e);
        } finally {
            this.saving = false;
        }
    }

    async handleMerge() {
        const d = this.dup;
        if (!d || this.saving) { return; }
        this.saving = true; this.error = undefined;
        const q = this.fill && this.fill.quantity ? this.fill.quantity : null;
        try {
            const r = await addToExisting({ ncId: d.id, text: this.text, quantity: q });
            const warnings = [...(r.warnings || []), ...(await this.uploadFiles(r.id))];
            this.result = { ...r, warnings };
            this.step = 'merged';
        } catch (e) {
            this.error = this.msg(e);
        } finally {
            this.saving = false;
        }
    }

    async uploadFiles(recordId) {
        const notes = [];
        for (const f of this.files) {
            try { await attachFile({ recordId, fileName: f.name, base64: f.base64 }); } catch (e) { notes.push(this.msg(e)); }
        }
        return notes;
    }

    // ------------------------------------------------------------ done

    get doneTitle() { return this.result ? this.result.title : ''; }
    get hasWarnings() { return this.result && this.result.warnings && this.result.warnings.length > 0; }
    get warningsText() { return this.hasWarnings ? this.result.warnings.join(' ') : ''; }
    get sentText() { return this.result && this.result.stage === 'Draft' ? 'Created' : 'Sent to Triage'; }
    get doneLine() {
        return this.result && this.result.stage === 'Draft'
            ? 'It is saved in Draft. Open it to send it to Triage.'
            : 'It is waiting in the Nonconformance queue for someone to triage it.';
    }
    handleAnother() { this.reset(); }
    handleOpenNc(event) {
        event.preventDefault();
        if (this.result) { this.close({ recordId: this.result.id }); } else { this.handleClose(); }
    }

    msg(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
    }
}
