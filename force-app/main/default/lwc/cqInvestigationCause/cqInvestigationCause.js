import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getCause from '@salesforce/apex/CqInvestigationCause.getCause';
import setStatus from '@salesforce/apex/CqInvestigationCause.setStatus';
import saveFit from '@salesforce/apex/CqInvestigationCause.saveFit';
import saveIsNot from '@salesforce/apex/CqInvestigationCause.saveIsNot';
import saveEvidence from '@salesforce/apex/CqInvestigationCause.saveEvidence';
import deleteEvidence from '@salesforce/apex/CqInvestigationCause.deleteEvidence';
import saveWhys from '@salesforce/apex/CqInvestigationCause.saveWhys';
import saveRootCauses from '@salesforce/apex/CqInvestigationCause.saveRootCauses';
import findRecords from '@salesforce/apex/CqInvestigationCause.findRecords';
import addHypothesis from '@salesforce/apex/CqInvestigationChanges.addHypothesis';

const NC_NAME = 'compliancequest__SQX_Investigation__c.compliancequest__SQX_Nonconformance__r.Name';
const NC_TITLE = 'compliancequest__SQX_Investigation__c.compliancequest__SQX_Nonconformance__r.compliancequest__NC_Title__c';
const NC_LOT = 'compliancequest__SQX_Investigation__c.compliancequest__SQX_Nonconformance__r.compliancequest__Lot_Number__c';
const TABS = [{ key: 'hyp', label: 'Hypotheses' }, { key: 'isnot', label: 'Is / Is Not' }, { key: 'why', label: '5 Why' }, { key: 'fish', label: 'Fishbone' }, { key: 'roots', label: 'Root Causes' }];
const TEST_TYPES = ['Measure or Inspect', 'Compare', 'Reproduce', 'Remove the Cause', 'Check Records'];
const SUPPORTS = [{ v: 'For', label: 'Supports It' }, { v: 'Against', label: 'Goes Against It' }, { v: 'Inconclusive', label: 'Inconclusive' }];
const TEST_FOR = { Machine: 'Measure or Inspect', Method: 'Compare', Materials: 'Check Records', Measurement: 'Measure or Inspect', People: 'Check Records', 'Environment (Nature)': 'Check Records' };
const STATUS_CLS = { Confirmed: 'cq-pill soft pos', 'Ruled Out': 'cq-pill soft neu', Open: 'cq-pill soft warn' };
const SUP_LABEL = { For: 'Yes', Against: 'Goes Against It', Inconclusive: 'Inconclusive' };
const TAG_CLS = { 'From CQ': 'tag', 'Test Done': 'tag ok', 'Test Planned': 'tag warn', 'From Ask CQ.AI': 'tag ai', 'CQ Record': 'tag' };

/**
 * Find the Cause, step 4 of the CQ.AI Investigation workspace: Hypotheses (with CQ.AI Suggests, the root cause
 * checks, evidence and How Do You Know?), Is / Is Not (CQ's 5W2H), 5 Why (CQ's own 5 Why tool and Why records),
 * Fishbone (a view of the hypotheses on their category's bone, not saved to CQ) and Root Causes (saved as CQ root
 * causes with a Role). CQ.AI Suggests comes from rules over the evidence;
 * the person decides Confirmed or Ruled Out.
 *
 * Events: addhyp (a suggested hypothesis to add with the workspace's popup), causestate (footer blocker and the
 * Save Root Causes button), causechanged (root causes saved). Methods: refresh(), saveRoots(), pin(answer).
 */
export default class CqInvestigationCause extends LightningElement {
    @api recordId;
    v;
    loadError;
    error;
    notice;
    saving = false;
    tab = 'hyp';
    selId;
    howKnow = {};          // hypId -> text being typed
    isRows = [];
    isDirty = false;
    whyHypId;
    whys = [];
    whyDirty = false;
    roots = [];
    rootsDirty = false;
    form;                  // the evidence popup
    hidden = {};           // suggested hypotheses marked Not Relevant this visit
    seq = 0;
    focusForm = false;

    connectedCallback() { this.load(); }

    // the NC, for the head of the fishbone
    @wire(getRecord, { recordId: '$recordId', optionalFields: [NC_NAME, NC_TITLE, NC_LOT] }) inv;
    ncField(f) { return this.inv && this.inv.data ? getFieldValue(this.inv.data, f) : null; }

    async load() {
        try {
            this.apply(await getCause({ recordId: this.recordId }), true);
        } catch (e) {
            this.loadError = this.msg(e, 'Could not read the hypotheses.');
        }
    }

    @api refresh() { return this.load(); }

    /** A fresh view from Apex. Edits in progress on other tabs are kept. */
    apply(v, all) {
        this.v = v;
        this.loadError = undefined;
        if (all || !this.isDirty) { this.isRows = v.rows.map((r) => ({ ...r })); this.isDirty = false; }
        if (!this.selId || !v.hyps.find((h) => h.id === this.selId)) {
            const pick = v.hyps.find((h) => h.status === 'Confirmed') || v.hyps.find((h) => h.status === 'Open') || v.hyps[0];
            this.selId = pick ? pick.id : undefined;
        }
        const whyOk = v.hyps.find((h) => h.id === this.whyHypId && h.status !== 'Ruled Out');
        if (!whyOk) {
            const pick = v.hyps.find((h) => h.id === this.selId && h.status !== 'Ruled Out') || v.hyps.find((h) => h.status === 'Confirmed') || v.hyps.find((h) => h.status !== 'Ruled Out');
            this.whyHypId = pick ? pick.id : undefined;
            this.whyDirty = false;
        }
        if (all || !this.whyDirty) { this.loadWhys(); }
        if (all || !this.rootsDirty) { this.roots = v.roots.map((r) => ({ ...r })); this.rootsDirty = false; }
        this.sendState();
    }

    msg(e, fallback) { return (e && e.body && e.body.message) || (e && e.message) || fallback; }
    href(id) { return '/lightning/r/' + id + '/view'; }
    key() { this.seq += 1; return 'k' + this.seq; }
    get ready() { return !!this.v; }
    hyp(id) { return this.v ? this.v.hyps.find((h) => h.id === id) : undefined; }
    hname(h) { return 'H' + h.num; }

    async run(fn, okNote) {
        this.saving = true;
        this.error = undefined;
        this.notice = undefined;
        try {
            const v = await fn();
            if (v) { this.apply(v, false); }
            if (okNote) { this.notice = okNote; }
            return true;
        } catch (e) {
            this.error = this.msg(e, 'It was not saved.');
            return false;
        } finally {
            this.saving = false;
            this.sendState();
        }
    }

    // ---- footer state for the workspace
    sendState() {
        const hs = this.v ? this.v.hyps : [];
        const count = (s) => hs.filter((h) => h.status === s).length;
        this.dispatchEvent(new CustomEvent('causestate', { detail: {
            showSave: this.tab === 'roots', canSave: this.tab === 'roots' && !this.saving && !this.rootBlocker && this.rootsDirty,
            saving: this.saving, blocker: this.tab === 'roots' ? this.rootBlocker : null,
            confirmed: count('Confirmed'), ruledOut: count('Ruled Out'), open: count('Open'), saved: hs.length ? this.v.roots.filter((r) => r.saved).length : 0
        } }));
    }

    // ---- tabs
    get tabs() {
        return TABS.map((t) => ({ ...t, cls: 'tab' + (t.key === this.tab ? ' on' : ''), sel: String(t.key === this.tab) }));
    }
    handleTab(event) { this.go(event.currentTarget.dataset.t); }
    go(t) {
        this.tab = t;
        this.error = undefined;
        this.notice = undefined;
        this.sendState();
    }
    get onHyp() { return this.tab === 'hyp'; }
    get onIs() { return this.tab === 'isnot'; }
    get onWhy() { return this.tab === 'why'; }
    get onRoots() { return this.tab === 'roots'; }
    get onFish() { return this.tab === 'fish'; }
    get hasHyps() { return this.v && this.v.hyps.length > 0; }
    get noHyps() { return !this.hasHyps; }

    // ================================================================ Hypotheses
    // side by side (Lou, 27 Nov): the list on the left, the one being tested on the right
    get hypRows() {
        return this.v.hyps.map((h) => {
            const sel = h.id === this.selId;
            return {
                id: h.id, num: this.hname(h), title: h.title, category: h.category || '—', suggest: h.suggest,
                askWhy: 'Why does CQ.AI suggest ' + this.hname(h) + ' is ' + (h.suggest || '').toLowerCase() + '? Give the facts.',
                status: h.status, statusCls: STATUS_CLS[h.status] || 'cq-pill soft neu',
                rowCls: 'hrow' + (sel ? ' on' : ''), pressed: String(sel)
            };
        });
    }
    handleSelect(event) { this.selId = event.currentTarget.dataset.id; this.error = undefined; this.notice = undefined; }

    get newHyps() { return (this.v.newHyps || []).filter((n) => !this.hidden[n.key]); }
    get hasNewHyps() { return this.newHyps.length > 0; }
    handleNewHyp(event) {
        const n = this.v.newHyps.find((x) => x.key === event.currentTarget.dataset.key);
        this.dispatchEvent(new CustomEvent('addhyp', { detail: { sourceId: n.sourceId, name: n.name, text: n.text, category: n.category } }));
    }
    handleNewHypHide(event) { this.hidden = { ...this.hidden, [event.currentTarget.dataset.key]: true }; }

    // the selected hypothesis
    get sel() { return this.selId ? this.hyp(this.selId) : undefined; }
    get hasSel() { return !!this.sel; }
    get selHead() { const h = this.sel; return 'Testing ' + this.hname(h) + (h.category ? ' · ' + h.category : ''); }
    get selStatusCls() { return STATUS_CLS[this.sel.status] || 'cq-pill soft neu'; }
    get selCanPlan() { const h = this.sel; return h.suggest === 'Needs Evidence' && h.status === 'Open' && !h.testsPlanned; }
    get hasEvidence() { return this.evidenceRows.length > 0; }
    get noEvidence() { return !this.hasEvidence; }
    // step 4, Decide: the two moves away from the status it has now
    get decideBtns() {
        const s = this.sel.status;
        const all = [{ s: 'Open', label: 'Reopen', cls: 'cq-btn-outline' }, { s: 'Ruled Out', label: 'Rule Out', cls: 'cq-btn-outline' },
            { s: 'Confirmed', label: 'Mark Confirmed', cls: 'cq-btn-primary' }];
        const needText = !this.howKnowText.trim();
        return all.filter((b) => b.s !== s).map((b) => ({ ...b, off: this.saving || (b.s !== 'Open' && needText) }));
    }
    get decideNote() {
        const s = this.sel.status;
        if (s === 'Confirmed') { return 'Confirmed. It goes to Root Causes.'; }
        if (s === 'Ruled Out') { return 'Ruled out. It stays on the investigation with its evidence.'; }
        return this.statusBlocker || 'It stays Open until you confirm it or rule it out.';
    }
    get checks() {
        return this.sel.checks.map((c) => ({ ...c, cls: 'chk ' + (c.ok ? 'ok' : 'todo'), mark: c.ok ? '✓' : '○', isBack: c.key === 'back' && !c.ok }));
    }
    get evidenceRows() { return this.evRows(this.sel.evidence); }
    evRows(list) {
        return (list || []).map((e) => ({
            key: e.key, id: e.id, tag: e.tag, tagCls: TAG_CLS[e.tag] || 'tag', text: e.text, origin: e.origin,
            hasRecord: !!e.recordId, recordHref: e.recordId ? this.href(e.recordId) : null, recordName: e.recordName,
            against: e.supports === 'Against', inconclusive: e.supports === 'Inconclusive', files: e.files ? e.files + (e.files === 1 ? ' file' : ' files') : null,
            canEdit: !e.auto && !!e.id, isPlanned: e.status === 'Planned',
            sup: e.status === 'Planned' ? 'Not run yet' : SUP_LABEL[e.supports] || '—',
            supCls: 'sup ' + (e.status === 'Planned' ? 'none' : e.supports === 'For' ? 'for' : e.supports === 'Against' ? 'against' : 'none')
        }));
    }
    get howKnowText() {
        const h = this.sel;
        if (Object.prototype.hasOwnProperty.call(this.howKnow, h.id)) { return this.howKnow[h.id]; }
        return h.howKnow || h.howKnowDraft || '';
    }
    get howKnowPrefilled() { const h = this.sel; return !h.howKnow && !!h.howKnowDraft && !Object.prototype.hasOwnProperty.call(this.howKnow, h.id); }
    get howKnowDirty() {
        const h = this.sel;
        return h.status !== 'Open' && Object.prototype.hasOwnProperty.call(this.howKnow, h.id) && (this.howKnow[h.id] || '').trim() !== (h.howKnow || '');
    }
    handleHowKnow(event) { this.howKnow = { ...this.howKnow, [this.selId]: event.target.value }; }
    get statusBlocker() { return this.sel && !this.howKnowText.trim() ? 'Say how you know before you confirm or rule it out' : null; }

    async handleStatus(event) {
        const status = event.currentTarget.dataset.s;
        const h = this.sel;
        if (status === h.status) { return; }
        const text = this.howKnowText.trim();
        if (status !== 'Open' && !text) { this.error = 'Say how you know before you mark it ' + status + '.'; return; }
        const id = h.id;
        const ok = await this.run(() => setStatus({ recordId: this.recordId, hypId: id, status, howKnow: text }),
            this.hname(h) + ' is ' + status + '.');
        if (ok) { const k = { ...this.howKnow }; delete k[id]; this.howKnow = k; }
    }
    async handleSaveHowKnow() {
        const h = this.sel;
        const id = h.id;
        const ok = await this.run(() => setStatus({ recordId: this.recordId, hypId: id, status: h.status, howKnow: this.howKnowText.trim() }), 'Saved.');
        if (ok) { const k = { ...this.howKnow }; delete k[id]; this.howKnow = k; }
    }
    handleGoWhy() { this.whyHypId = this.selId; this.loadWhys(); this.go('why'); }

    async handleRemoveEvidence(event) {
        const id = event.currentTarget.dataset.id;
        await this.run(() => deleteEvidence({ recordId: this.recordId, evidenceId: id }), 'Removed.');
    }

    // ================================================================ the evidence popup
    openForm(f) {
        this.form = { kind: 'Test', status: 'Planned', testType: null, detail: '', result: '', supports: null, ownerId: null, due: '', search: '', found: [], ...f };
        this.focusForm = true;
        this.error = undefined;
        this.notice = undefined;
    }
    handleAddTest(event) {
        const whyId = event.currentTarget.dataset.why;
        this.openForm({ kind: 'Test', hypId: whyId ? null : this.selId, whyId: whyId || null, status: 'Done' });
    }
    handlePlan() {
        const h = this.sel;
        this.selId = h.id;
        this.openForm({ kind: 'Test', hypId: h.id, status: 'Planned', testType: TEST_FOR[h.category] || null, detail: h.testHint || '' });
    }
    handleRecordResult(event) {
        const id = event.currentTarget.dataset.id;
        const all = [];
        this.v.hyps.forEach((h) => { h.evidence.forEach((e) => all.push({ e, hypId: h.id })); h.whys.forEach((w) => w.evidence.forEach((e) => all.push({ e, whyId: w.id }))); });
        const hit = all.find((x) => x.e.id === id);
        if (!hit) { return; }
        const e = hit.e;
        this.openForm({ id, kind: 'Test', hypId: hit.hypId || null, whyId: hit.whyId || null, status: 'Done', testType: e.testType,
            detail: e.status === 'Planned' ? (e.text || '').replace(/^[^:]+:\s*/, '') : '', result: e.result || '', supports: e.supports, ownerId: e.ownerId, due: e.due || '', editing: true,
            recordId: e.recordId || null, recordName: e.recordName || null });
    }
    /** An Ask CQ.AI answer to keep: the workspace passes it on from the Ask CQ.AI popover. */
    @api pin(answer) {
        const text = ((answer && answer.text) || '').replace(/\[([^\]]+)\]\([^)]+\)/g, '$1').trim();
        if (!text) { return; }
        const m = ((answer && answer.text) || '').match(/\]\(\/lightning\/r\/(?:[A-Za-z0-9_]+\/)?([a-zA-Z0-9]{15,18})\/view\)/);
        const label = ((answer && answer.text) || '').match(/\[([^\]]+)\]\(\/lightning\/r\//);
        const target = this.sel && this.sel.status !== 'Ruled Out' ? this.selId : (this.v.hyps.find((h) => h.status !== 'Ruled Out') || {}).id;
        this.tab = 'hyp';
        if (target) { this.selId = target; }
        this.openForm({ kind: 'Ask CQ.AI', hypId: target || null, detail: text.length > 2000 ? text.slice(0, 2000) : text, supports: 'For',
            recordId: m ? m[1] : null, recordName: label ? label[1] : null, question: answer && answer.question });
        this.sendState();
    }

    get formOpen() { return !!this.form; }
    get formTitle() {
        const f = this.form;
        if (f.kind === 'CQ Record') { return 'Link a CQ Record'; }
        if (f.kind === 'Ask CQ.AI') { return 'Add to Evidence'; }
        return f.editing ? 'Record the Result' : f.status === 'Planned' ? 'Plan a Test' : 'Add Evidence';
    }
    get formFor() {
        const f = this.form;
        if (f.whyId) {
            for (const h of this.v.hyps) { const w = h.whys.find((x) => x.id === f.whyId); if (w) { return 'Why ' + w.level + ' of ' + this.hname(h) + ': ' + w.text; } }
        }
        const h = this.hyp(f.hypId);
        return h ? this.hname(h) + ': ' + h.title : '';
    }
    get formIsTest() { return this.form.kind === 'Test'; }
    get formIsLink() { return this.form.kind === 'CQ Record'; }
    get formIsPin() { return this.form.kind === 'Ask CQ.AI'; }
    // a Check Records test can attach the CQ record it checked (Link a CQ Record folded in here, Lou 27 Nov)
    get formShowsRecord() { return this.formIsLink || (this.formIsTest && this.form.testType === 'Check Records'); }
    get formRecordLabel() { return this.formIsLink ? 'CQ Record' : 'CQ Record Checked'; }
    get formRecordReq() { return this.formIsLink; }
    get formDone() { return this.form.status === 'Done'; }
    get formPlanned() { return this.form.status === 'Planned'; }
    get formShowsSupports() { return !this.formIsTest || this.formDone; }
    get pinTargets() {
        return this.v.hyps.filter((h) => h.status !== 'Ruled Out').map((h) => ({ id: h.id, label: this.hname(h), pressed: String(h.id === this.form.hypId),
            cls: 'cq-chip' }));
    }
    get testTypeOpts() { return TEST_TYPES.map((t) => ({ label: t, pressed: String(this.form.testType === t), cls: 'cq-chip' })); }
    get testStatusOpts() {
        return [{ v: 'Planned', label: 'Planned' }, { v: 'Done', label: 'Done' }].map((s) => ({ ...s, pressed: String(this.form.status === s.v), cls: 'cq-chip' }));
    }
    get supportOpts() { return SUPPORTS.map((s) => ({ ...s, pressed: String(this.form.supports === s.v), cls: 'cq-chip' + (s.v === 'Against' ? ' neg' : '') })); }
    get detailLabel() { return this.formPlanned ? 'What Will Be Done *' : 'What Was Done *'; }
    get detailPlaceholder() { return this.formPlanned ? 'For example, bond 20 units with a new pin and pressure test them' : 'For example, gauged the locating pin on BF-02'; }
    setForm(k, val) { this.form = { ...this.form, [k]: val }; }
    handleFormPick(event) { this.setForm(event.currentTarget.dataset.k, event.currentTarget.dataset.v); }
    handleFormField(event) { this.setForm(event.currentTarget.dataset.k, event.target.value); }
    handleFormOwner(event) { this.setForm('ownerId', event.detail.recordId || null); }
    handleFormKey(event) { if (event.key === 'Escape') { this.form = undefined; } }
    handleFormCancel() { this.form = undefined; }
    searchTimer;
    handleSearch(event) {
        const term = event.target.value;
        this.setForm('search', term);
        clearTimeout(this.searchTimer);
        if (!term || term.trim().length < 2) { this.setForm('found', []); return; }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.searchTimer = setTimeout(async () => {
            try {
                const found = await findRecords({ term });
                if (this.form) { this.setForm('found', found.map((f) => ({ ...f, key: f.id, line: f.name + ' · ' + f.type }))); }
            } catch (e) { if (this.form) { this.setForm('found', []); } }
        }, 300);
    }
    get hasFound() { return this.form && this.form.found && this.form.found.length > 0; }
    get noneFound() { return this.form && !this.form.recordId && (this.form.search || '').trim().length >= 2 && !this.hasFound; }
    handlePickRecord(event) {
        const f = this.form.found.find((x) => x.id === event.currentTarget.dataset.id);
        this.form = { ...this.form, recordId: f.id, recordName: f.name, recordType: f.type, found: [], search: '' };
    }
    handleClearRecord() { this.form = { ...this.form, recordId: null, recordName: null, recordType: null }; }
    get pickedHref() { return this.form && this.form.recordId ? this.href(this.form.recordId) : null; }
    get formBlocker() {
        const f = this.form;
        if (!f) { return null; }
        if (!f.hypId && !f.whyId) { return 'Choose the hypothesis'; }
        if (f.kind === 'Test') {
            if (!f.testType) { return 'Choose the kind of test'; }
            if (!(f.detail || '').trim()) { return f.status === 'Planned' ? 'Say what will be done' : 'Say what was done'; }
            if (f.status === 'Done' && !(f.result || '').trim()) { return 'Give the result'; }
            if (f.status === 'Done' && !f.supports) { return 'Say whether it supports it'; }
        }
        if (f.kind === 'CQ Record' && !f.recordId) { return 'Choose the CQ record'; }
        if (f.kind === 'Ask CQ.AI' && !(f.detail || '').trim()) { return 'Nothing to add'; }
        return null;
    }
    get cantSaveForm() { return this.saving || !!this.formBlocker; }
    get formSaveLabel() { return this.form.kind === 'Test' ? (this.form.status === 'Planned' ? 'Plan Test' : 'Add Evidence') : this.form.kind === 'CQ Record' ? 'Link Record' : 'Add to Evidence'; }
    async handleFormSave() {
        if (this.cantSaveForm) { return; }
        const f = this.form;
        const p = { id: f.id || null, hypId: f.hypId || null, whyId: f.whyId || null, kind: f.kind, supports: f.supports || null };
        if (f.kind === 'Test') {
            Object.assign(p, { testType: f.testType, status: f.status, detail: f.detail.trim(), result: f.status === 'Done' ? f.result.trim() : null,
                supports: f.status === 'Done' ? f.supports : null, ownerId: f.ownerId || null, due: f.status === 'Planned' && f.due ? f.due : null,
                recordId: f.testType === 'Check Records' ? f.recordId || null : null, recordName: f.testType === 'Check Records' ? f.recordName || null : null });
        } else if (f.kind === 'CQ Record') {
            Object.assign(p, { recordId: f.recordId, recordName: f.recordName, result: (f.result || '').trim() || null });
        } else {
            Object.assign(p, { detail: f.detail.trim(), recordId: f.recordId || null, recordName: f.recordName || null });
        }
        const where = f.whyId ? 'the why' : (this.hyp(f.hypId) ? this.hname(this.hyp(f.hypId)) : 'the hypothesis');
        const ok = await this.run(() => saveEvidence({ recordId: this.recordId, payload: JSON.stringify(p) }), 'Added to ' + where + '.');
        if (ok) {
            this.form = undefined;
            if (f.whyId) { this.loadWhys(); }
        }
    }
    renderedCallback() {
        // a textarea's value binding can leave it empty: set each one from its data-val unless it is being typed in
        const active = this.template.activeElement;
        this.template.querySelectorAll('textarea').forEach((el) => {
            if (el === active) { return; }
            const want = el.dataset.val === undefined ? '' : el.dataset.val;
            if (el.value !== want) { el.value = want; }
        });
        if (this.focusNew) {
            const ta = this.template.querySelector('textarea.newta');
            if (ta) { this.focusNew = false; ta.focus(); }
        }
        if (!this.focusForm) { return; }
        const el = this.template.querySelector('.modal [data-first]');
        if (!el) { return; }
        this.focusForm = false;
        el.focus();
    }

    // ================================================================ Is / Is Not
    get isHyps() { return this.v.hyps.filter((h) => h.status !== 'Ruled Out'); }
    get isTable() {
        return this.isRows.map((r) => ({
            ...r,
            fits: this.isHyps.map((h) => {
                const f = h.fits[r.key];
                return { key: r.key + h.id, hypId: h.id, row: r.key, label: this.hname(h), mark: f === 'fits' ? '✓' : f === 'fails' ? '×' : '○',
                    cls: 'fit ' + (f || 'none'), title: f === 'fits' ? 'Fits: click to mark does not fit' : f === 'fails' ? 'Does not fit: click to clear' : 'Not marked: click to mark fits' };
            })
        }));
    }
    handleIsField(event) {
        const k = event.currentTarget.dataset.k;
        const f = event.currentTarget.dataset.f;
        const val = event.target.value;
        this.isRows = this.isRows.map((r) => (r.key === k ? { ...r, [f]: val } : r));
        this.isDirty = true;
        this.notice = undefined;
    }
    async handleFit(event) {
        const hypId = event.currentTarget.dataset.h;
        const row = event.currentTarget.dataset.r;
        const cur = this.hyp(hypId).fits[row];
        const next = cur === 'fits' ? 'fails' : cur === 'fails' ? '' : 'fits';
        await this.run(() => saveFit({ recordId: this.recordId, hypId, rowKey: row, value: next }));
    }
    get isPrefilledNote() { return this.v.isNotPrefilled && !this.isDirty; }
    get cantSaveIs() { return this.saving || (!this.isDirty && !this.v.isNotPrefilled); }
    async handleSaveIs() {
        if (this.cantSaveIs) { return; }
        const rows = this.isRows.map((r) => ({ key: r.key, isText: r.isText || null, isNotText: r.isNotText || null }));
        const ok = await this.run(() => saveIsNot({ recordId: this.recordId, payload: JSON.stringify(rows) }), 'Saved to CQ’s 5W2H on ' + this.v.investigationName + '.');
        if (ok) { this.isRows = this.v.rows.map((r) => ({ ...r })); this.isDirty = false; }
    }
    get ruleOutHyp() {
        return this.isHyps.find((h) => h.status === 'Open' && Object.keys(h.fits).some((k) => h.fits[k] === 'fails'));
    }
    get ruleOutLabel() { return this.ruleOutHyp ? 'Rule Out ' + this.hname(this.ruleOutHyp) + ' with This' : null; }
    async handleRuleOut() {
        const h = this.ruleOutHyp;
        const fails = Object.keys(h.fits).filter((k) => h.fits[k] === 'fails').map((k) => {
            const r = this.isRows.find((x) => x.key === k) || {};
            return r.label + (r.isNotText ? ': not ' + r.isNotText : '');
        });
        await this.run(() => setStatus({ recordId: this.recordId, hypId: h.id, status: 'Ruled Out', howKnow: 'Does not fit the Is / Is Not: ' + fails.join('; ') + '.' }),
            this.hname(h) + ' is Ruled Out.');
    }

    // ================================================================ 5 Why
    loadWhys() {
        const h = this.whyHypId ? this.hyp(this.whyHypId) : undefined;
        this.whys = h && h.whys.length ? h.whys.map((w) => ({ key: this.key(), id: w.id, text: w.text, isRoot: w.isRoot }))
            : [{ key: this.key(), id: null, text: '', isRoot: false }];
        this.whyDirty = false;
    }
    get whyHyps() {
        return this.v.hyps.filter((h) => h.status !== 'Ruled Out').map((h) => ({ id: h.id, label: this.hname(h) + ' · ' + this.short(h.title),
            pressed: String(h.id === this.whyHypId), cls: 'cq-chip' }));
    }
    short(t) { const s = (t || '').replace(/,\s*as in [A-Z]+-\d+$/, ''); return s.length > 40 ? s.slice(0, 38) + '…' : s; }
    get hasWhyHyp() { return !!this.whyHypId; }
    get whyHyp() { return this.hyp(this.whyHypId); }
    handleWhyHyp(event) {
        if (this.whyDirty) { this.error = 'Save or undo this 5 Why before you open another.'; return; }
        this.whyHypId = event.currentTarget.dataset.id;
        this.loadWhys();
        this.error = undefined;
    }
    get whyRows() {
        const saved = this.whyHyp ? this.whyHyp.whys : [];
        return this.whys.map((w, i) => {
            const s = w.id ? saved.find((x) => x.id === w.id) : null;
            return { ...w, idx: i, label: 'Why ' + (i + 1), cls: 'whybox' + (w.isRoot ? ' root' : ''), rootCls: 'cq-chip', rootPressed: String(!!w.isRoot),
                evidence: s ? this.evRows(s.evidence).map((e) => ({ ...e, line: (e.against ? '× ' : e.isPlanned ? '○ ' : '✓ ') + (e.tag === 'Test Done' || e.tag === 'Test Planned' ? 'Test: ' : e.tag === 'CQ Record' ? 'Linked CQ record: ' : '') + e.text,
                    lineCls: 'wev ' + (e.against ? 'neg' : e.isPlanned ? 'plan' : 'pos') })) : [],
                canEvidence: !!w.id && !this.whyDirty, canRemove: this.whys.length > 1 };
        });
    }
    handleWhyText(event) {
        const i = Number(event.currentTarget.dataset.i);
        const val = event.target.value;
        this.whys = this.whys.map((w, j) => (j === i ? { ...w, text: val } : w));
        this.whyDirty = true;
    }
    handleWhyRoot(event) {
        const i = Number(event.currentTarget.dataset.i);
        this.whys = this.whys.map((w, j) => (j === i ? { ...w, isRoot: !w.isRoot } : w));
        this.whyDirty = true;
    }
    handleWhyAdd() { this.whys = [...this.whys, { key: this.key(), id: null, text: '', isRoot: false }]; this.whyDirty = true; }
    handleWhyRemove(event) {
        const i = Number(event.currentTarget.dataset.i);
        this.whys = this.whys.filter((w, j) => j !== i);
        this.whyDirty = true;
    }
    handleWhyUndo() { this.loadWhys(); this.error = undefined; }
    get whyBlocker() {
        if (!this.whys.some((w) => (w.text || '').trim())) { return 'Write the first why'; }
        return null;
    }
    get cantSaveWhy() { return this.saving || !this.whyDirty || !!this.whyBlocker; }
    async handleSaveWhy() {
        if (this.cantSaveWhy) { return; }
        const h = this.whyHyp;
        const rows = this.whys.map((w) => ({ id: w.id, text: (w.text || '').trim(), isRoot: !!w.isRoot }));
        const ok = await this.run(() => saveWhys({ recordId: this.recordId, hypId: h.id, payload: JSON.stringify(rows) }), 'Saved in CQ’s 5 Why for ' + this.hname(h) + '.');
        if (ok) { this.loadWhys(); }
    }
    get whyToolHref() { return this.whyHyp && this.whyHyp.toolId ? this.href(this.whyHyp.toolId) : null; }
    get whyToolName() { return this.whyHyp ? this.whyHyp.toolName : null; }
    get problemText() { return this.v.problem || 'No description on the NC.'; }

    // ================================================================ Fishbone
    get fishCats() {
        const cats = [...(this.v.categories || [])];
        this.v.hyps.forEach((h) => { if (h.category && !cats.includes(h.category)) { cats.push(h.category); } });
        return cats;
    }
    bone(cat, top) {
        const items = this.v.hyps.filter((h) => h.category === cat).map((h) => ({
            key: h.id, label: this.hname(h) + ' · ' + this.short(h.title),
            title: this.hname(h) + ': ' + h.title, status: h.status,
            cls: 'cause ' + (h.status === 'Confirmed' ? 'ok' : h.status === 'Ruled Out' ? 'out' : 'open'), pillCls: STATUS_CLS[h.status] || 'cq-pill soft neu'
        }));
        return { key: cat, cat, items, top, bottom: !top };
    }
    get fishTop() { const c = this.fishCats; return c.slice(0, Math.ceil(c.length / 2)).map((x) => this.bone(x, true)); }
    get fishBottom() { const c = this.fishCats; return c.slice(Math.ceil(c.length / 2)).map((x) => this.bone(x, false)); }
    get fishHead() { return this.ncField(NC_TITLE) || 'The problem'; }
    get fishHeadSub() { const lot = this.ncField(NC_LOT); return [this.ncField(NC_NAME), lot ? 'lot ' + lot : null].filter((x) => x).join(' · '); }

    // + Add a Hypothesis on a bone: the same popup as Add as Hypothesis, with the category set
    hypNew;
    handleFishAdd(event) { this.hypNew = { category: event.currentTarget.dataset.c, title: '' }; this.focusNew = true; this.error = undefined; this.notice = undefined; }
    focusNew = false;
    get hypNewOpen() { return !!this.hypNew; }
    get hypNewCats() {
        const c = this.hypNew ? this.hypNew.category : null;
        return this.fishCats.map((x) => ({ label: x, pressed: String(c === x), cls: 'cq-chip' }));
    }
    handleNewTitle(event) { this.hypNew = { ...this.hypNew, title: event.target.value }; }
    handleNewCat(event) { this.hypNew = { ...this.hypNew, category: event.currentTarget.dataset.c }; }
    handleNewCancel() { this.hypNew = undefined; }
    handleNewKey(event) { if (event.key === 'Escape') { this.hypNew = undefined; } }
    get hypNewBlocker() {
        if (!this.hypNew) { return null; }
        if (!(this.hypNew.title || '').trim()) { return 'Say what the possible cause is'; }
        if (!this.hypNew.category) { return 'Choose a category'; }
        return null;
    }
    get cantAddNew() { return this.saving || !!this.hypNewBlocker; }
    async handleNewSave() {
        if (this.cantAddNew) { return; }
        const f = this.hypNew;
        this.saving = true;
        this.error = undefined;
        try {
            const n = await addHypothesis({ recordId: this.recordId, payload: JSON.stringify({ title: f.title.trim(), category: f.category, sourceName: 'Added by You' }) });
            this.hypNew = undefined;
            await this.load();
            this.notice = 'Added as H' + n + ' on ' + f.category + '.';
        } catch (e) {
            this.error = this.msg(e, 'The hypothesis was not saved.');
        } finally {
            this.saving = false;
            this.sendState();
        }
    }

    // ================================================================ Root Causes
    get rootRows() {
        const codes = this.v.codes || [];
        return this.roots.map((r, i) => ({
            ...r, idx: i, isNew: !r.hypId && !r.whyId && !r.saved,
            roleOpts: ['Primary', 'Contributing'].map((x) => ({ label: x, pressed: String(r.role === x), cls: 'cq-chip xs' })),
            catOpts: this.v.categories.map((c) => ({ value: c, label: c, sel: c === r.category })),
            codeOpts: [{ value: '', label: 'Choose a code', sel: !r.codeId }].concat(codes.filter((c) => !r.category || c.category === r.category)
                .map((c) => ({ value: c.id, label: c.name + (c.sub ? ' (' + c.sub + ')' : ''), sel: c.id === r.codeId }))),
            savedHref: r.id ? this.href(r.id) : null
        }));
    }
    get hasRoots() { return this.roots.length > 0; }
    editRoot(i, k, val) {
        this.roots = this.roots.map((r, j) => (j === i ? { ...r, [k]: val } : r));
        this.rootsDirty = true;
        this.notice = undefined;
        this.sendState();
    }
    handleRootRole(event) { this.editRoot(Number(event.currentTarget.dataset.i), 'role', event.currentTarget.dataset.v); }
    handleRootCat(event) {
        const i = Number(event.currentTarget.dataset.i);
        const cat = event.target.value;
        const r = this.roots[i];
        const code = (this.v.codes || []).find((c) => c.id === r.codeId);
        this.roots = this.roots.map((x, j) => (j === i ? { ...x, category: cat, codeId: code && code.category === cat ? x.codeId : null } : x));
        this.rootsDirty = true;
        this.sendState();
    }
    handleRootCode(event) { this.editRoot(Number(event.currentTarget.dataset.i), 'codeId', event.target.value || null); }
    handleRootField(event) { this.editRoot(Number(event.currentTarget.dataset.i), event.currentTarget.dataset.f, event.target.value); }
    handleRootVerified(event) { this.editRoot(Number(event.currentTarget.dataset.i), 'verified', event.target.checked); }
    handleRootAdd() {
        this.roots = [...this.roots, { key: 'n:' + this.key(), text: '', source: 'Added here', role: this.roots.some((r) => r.role === 'Primary') ? 'Contributing' : 'Primary',
            category: null, codeId: null, evidence: '', verified: false, saved: false }];
        this.rootsDirty = true;
        this.sendState();
    }
    handleRootRemove(event) {
        const i = Number(event.currentTarget.dataset.i);
        this.roots = this.roots.filter((r, j) => j !== i);
        this.rootsDirty = true;
        this.sendState();
    }
    get rootBlocker() {
        if (!this.v) { return null; }
        if (!this.roots.length) { return 'Confirm a hypothesis first'; }
        if (this.roots.some((r) => !(r.text || '').trim())) { return 'Describe every root cause'; }
        if (this.roots.some((r) => !r.category)) { return 'Choose a category for every root cause'; }
        if (this.roots.some((r) => !r.codeId)) { return 'Choose a CQ cause code for every root cause'; }
        if (!this.roots.some((r) => r.role === 'Primary')) { return 'Mark at least one root cause Primary'; }
        return null;
    }
    // What Stands Out went from every tab (Lou, 27 Nov); the Open warning stays beside the save note
    get rootOpenNote() {
        const open = this.v.openHyps || [];
        return open.length ? open.join(', ') + (open.length === 1 ? ' is' : ' are') + ' still Open: settle ' + (open.length === 1 ? 'it' : 'them') + ' before you save.' : null;
    }
    get noRoots() { return !this.roots.length; }
    count(n, one, many) { const w = ['No', 'One', 'Two', 'Three', 'Four', 'Five'][n] || String(n); return w + ' ' + (n === 1 ? one : many); }
    get savedCount() { return this.roots.filter((r) => r.saved).length; }
    // Save Root Causes sits in the tab's bar, beside + Add Root Cause (it moved out of the workspace footer, Lou 27 Nov)
    get cantSaveRoots() { return this.saving || !!this.rootBlocker || !this.rootsDirty; }
    get saveRootsLabel() { return this.saving ? 'Saving…' : 'Save Root Causes'; }
    handleSaveRoots() { this.saveRoots(); }
    @api async saveRoots() {
        if (this.rootBlocker || this.saving) { return; }
        const rows = this.roots.map((r) => ({ key: r.key, id: r.id || null, hypId: r.hypId || null, whyId: r.whyId || null, text: (r.text || '').trim(), role: r.role,
            category: r.category, codeId: r.codeId, evidence: r.evidence || null, verified: !!r.verified }));
        this.rootsDirty = false;
        const ok = await this.run(() => saveRootCauses({ recordId: this.recordId, payload: JSON.stringify(rows) }),
            'Saved as ' + this.count(rows.length, 'CQ root cause', 'CQ root causes').toLowerCase() + ' on ' + this.v.investigationName + '.');
        if (ok) {
            this.roots = this.v.roots.map((r) => ({ ...r }));
            this.dispatchEvent(new CustomEvent('causechanged'));
        } else { this.rootsDirty = true; }
        this.sendState();
    }
}
