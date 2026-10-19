import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPanelData from '@salesforce/apex/PhrQmsPanelController.getPanelData';
import createRelatedRecords from '@salesforce/apex/PhrQmsPanelController.createRelatedRecords';

const PAGE_SIZE = 5;

const MATCH_LABELS = { 'Part and Lot': 'Part + Lot', Lot: 'Lot match' };

const SECTIONS = [
    { key: 'nonconformances', title: 'Nonconformances', numLabel: 'NC Number', note: 'Adds Related Product (NC lookup)', selectable: true },
    { key: 'capas', title: 'CAPAs', numLabel: 'CAPA Number', note: 'Adds Related Product (CAPA lookup)', selectable: true },
    { key: 'changeOrders', title: 'Change Orders', numLabel: 'CO Number', note: 'Adds Related Product (Change Order + number)', selectable: true },
    { key: 'inspections', title: 'Inspections', numLabel: 'Inspection Number', note: 'Adds Related Product (Inspection + number)', selectable: true },
    { key: 'investigations', title: 'Related Investigations', numLabel: 'Investigation', note: 'View only', selectable: false }
];

export default class PhrQmsRecordsPanel extends LightningElement {
    @api recordId;

    data;
    loading = false;
    saving = false;
    errorMessage;
    lotInput = '';
    searchedLot;
    selected = {};
    pages = {};
    _loadedFor;

    connectedCallback() {
        this.load();
    }

    renderedCallback() {
        if (this.recordId && this._loadedFor !== this.recordId && !this.loading) {
            this.load();
        }
    }

    load(lotOverride) {
        if (!this.recordId) {
            return;
        }
        this._loadedFor = this.recordId;
        this.loading = true;
        this.errorMessage = undefined;
        getPanelData({ recordId: this.recordId, lotOverride: lotOverride || null })
            .then((result) => {
                if (result.success) {
                    this.data = result;
                    if (!lotOverride) {
                        this.lotInput = result.lotNumber || '';
                    }
                    this.searchedLot = lotOverride || null;
                    this.selected = {};
                    this.pages = {};
                } else {
                    this.data = undefined;
                    this.errorMessage = result.errorMessage;
                }
            })
            .catch((error) => {
                this.data = undefined;
                this.errorMessage = this.reduceError(error);
            })
            .finally(() => {
                this.loading = false;
            });
    }

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return (error && error.message) || 'Unexpected error';
    }

    // ---------- derived state ----------

    get hasData() {
        return !!this.data;
    }

    get partLabel() {
        if (!this.data || !this.data.partName) {
            return 'No part on the Complaint';
        }
        return this.data.partName;
    }

    get componentNote() {
        const n = this.data ? this.data.componentPartCount : 0;
        return n > 0
            ? `Assembly line items included: ${n} component part${n === 1 ? '' : 's'}.`
            : 'No assembly component parts found.';
    }

    get noPhr() {
        return !!this.data && !this.data.phrId;
    }

    get selectedCount() {
        return SECTIONS.filter((s) => s.selectable).reduce(
            (n, s) => n + (this.selected[s.key] || []).length,
            0
        );
    }

    get createDisabled() {
        return this.saving || this.noPhr || this.selectedCount === 0;
    }

    get createLabel() {
        return this.selectedCount > 0
            ? `Create Related Records (${this.selectedCount})`
            : 'Create Related Records';
    }

    get sections() {
        if (!this.data) {
            return [];
        }
        return SECTIONS.map((s) => this.buildSection(s));
    }

    buildSection(s) {
        const rows = this.data[s.key] || [];
        const sel = this.selected[s.key] || [];
        const total = rows.length;
        const pageCount = Math.max(1, Math.ceil(total / PAGE_SIZE));
        const page = Math.min(this.pages[s.key] || 0, pageCount - 1);
        const start = page * PAGE_SIZE;
        const slice = rows.slice(start, start + PAGE_SIZE).map((r) => ({
            ...r,
            url: '/' + r.id,
            checked: sel.includes(r.id),
            statusText: r.status || '—',
            partText: r.partNumber || '—',
            createdText: r.createdDate ? new Date(r.createdDate).toLocaleDateString() : '—',
            rowClass: r.highlight ? 'row-highlight' : '',
            matchLabel: MATCH_LABELS[r.matchedBy] || null
        }));
        const newRows = rows.filter((r) => !r.alreadyAdded);
        const prevDisabled = page === 0;
        const nextDisabled = page >= pageCount - 1;
        return {
            ...s,
            countLabel: `${s.title} (${total})`,
            rows: slice,
            isEmpty: total === 0,
            showPager: total > PAGE_SIZE,
            rangeLabel: total === 0 ? '' : `Showing ${start + 1}-${Math.min(total, start + PAGE_SIZE)} of ${total}`,
            allSelected: newRows.length > 0 && sel.length === newRows.length,
            noneSelectable: newRows.length === 0,
            selectable: !!s.selectable,
            prevDisabled,
            nextDisabled,
            prevClass: prevDisabled ? 'pager-link pager-link-off' : 'pager-link',
            nextClass: nextDisabled ? 'pager-link pager-link-off' : 'pager-link'
        };
    }

    // ---------- handlers ----------

    handleLotChange(event) {
        this.lotInput = event.target.value;
    }

    handleLotKey(event) {
        if (event.key === 'Enter') {
            this.handleSearch();
        }
    }

    handleSearch() {
        const lot = (this.lotInput || '').trim();
        this.load(lot || null);
    }

    handleToggle(event) {
        const key = event.target.dataset.section;
        const id = event.target.dataset.id;
        const current = new Set(this.selected[key] || []);
        if (event.target.checked) {
            current.add(id);
        } else {
            current.delete(id);
        }
        this.selected = { ...this.selected, [key]: Array.from(current) };
    }

    handleToggleAll(event) {
        const key = event.target.dataset.section;
        const ids = event.target.checked
            ? (this.data[key] || []).filter((r) => !r.alreadyAdded).map((r) => r.id)
            : [];
        this.selected = { ...this.selected, [key]: ids };
    }

    handlePage(event) {
        event.preventDefault();
        const link = event.currentTarget;
        if (link.classList.contains('pager-link-off')) {
            return;
        }
        const key = link.dataset.section;
        const dir = link.dataset.dir === 'next' ? 1 : -1;
        this.pages = { ...this.pages, [key]: Math.max(0, (this.pages[key] || 0) + dir) };
    }

    handleCreate() {
        if (this.createDisabled) {
            return;
        }
        const pick = (key) => this.selected[key] || [];
        this.saving = true;
        // Investigations are view-only here: they are never sent.
        createRelatedRecords({
            recordId: this.recordId,
            ncIds: pick('nonconformances'),
            capaIds: pick('capas'),
            changeOrderIds: pick('changeOrders'),
            inspectionIds: pick('inspections'),
            investigationIds: []
        })
            .then((result) => {
                const created = result.relatedProductsCreated;
                const skipped = result.skipped;
                const message = result.success
                    ? `Added ${created} record${created === 1 ? '' : 's'} to the Product History Review` +
                      (skipped ? `; ${skipped} already present.` : '.')
                    : result.message;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: result.success ? 'Related records created' : 'Some records were not created',
                        message,
                        variant: result.success ? 'success' : 'warning'
                    })
                );
                this.load(this.searchedLot);
            })
            .catch((error) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Could not create records',
                        message: this.reduceError(error),
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.saving = false;
            });
    }
}
