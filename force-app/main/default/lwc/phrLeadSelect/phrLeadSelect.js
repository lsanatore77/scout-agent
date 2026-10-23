import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getCandidates from '@salesforce/apex/PhrLeadSelectController.getCandidates';

const TIERS = [
    { key: 'Top', label: 'Most Relevant' },
    { key: 'Next', label: 'Less Relevant' },
    { key: 'Set aside', label: 'Set Aside' }
];
const PAGE_SIZE = 5;
const DOT = { Red: '#ba0517', Yellow: '#dd7a01', Grey: '#939393' };

/**
 * Tick-box editor for the agent (lightning__AgentforceInput).
 * Shows every record found for the complaint, with everything worth reviewing ticked.
 * Every change sends the full state back with the valuechange event; the Submit
 * button is Agentforce's own and runs the add action with the last value sent.
 */
export default class PhrLeadSelect extends LightningElement {
    @api readOnly = false;

    _value = {};
    _loadedFor;
    rows = [];
    loading = false;
    error;
    manualId;
    complaintName;
    pageRecordId;
    pageByTier = {};

    @api
    get value() {
        return this._value;
    }
    set value(v) {
        this._value = v || {};
        this.load();
    }

    @wire(CurrentPageReference)
    pageRef(ref) {
        const id =
            ref && ((ref.attributes && ref.attributes.recordId) || (ref.state && (ref.state.recordId || ref.state.c__recordId)));
        if (id && id !== this.pageRecordId) {
            this.pageRecordId = id;
            this.load();
        }
    }

    connectedCallback() {
        this.load();
    }

    get recordId() {
        return (this._value && this._value.recordId) || this.pageRecordId || this.manualId || this.urlRecordId();
    }

    /** Last resort: the Id in the page address, e.g. /lightning/r/<object>/<id>/view */
    urlRecordId() {
        try {
            const m = window.location.pathname.match(/\/(?:lightning\/)?r\/[^/]+\/([a-zA-Z0-9]{15,18})(?:\/|$)/);
            return m ? m[1] : undefined;
        } catch (e) {
            return undefined;
        }
    }

    get needsId() {
        return !this.loading && !this.error && !this.hasRows && !this.recordId;
    }

    handleIdChange(event) {
        const v = (event.target.value || '').trim();
        if (v.length === 15 || v.length === 18) {
            this.manualId = v;
            this._loadedFor = undefined;
            this.load();
        }
    }

    load() {
        const rid = this.recordId;
        const lot = (this._value && this._value.lotNumber) || null;
        if (!rid || this._loadedFor === rid) {
            return;
        }
        this._loadedFor = rid;
        this.loading = true;
        this.error = undefined;
        getCandidates({ recordId: rid, lotNumber: lot })
            .then((res) => {
                if (!res.success) {
                    this.error = res.errorMessage || 'Could not load the records.';
                    this.rows = [];
                    return;
                }
                this.complaintName = res.complaintName;
                const chosen = this._value && this._value.selectedRecordIds;
                const restore = Array.isArray(chosen) && chosen.length > 0;
                this.rows = res.rows.map((r) => ({
                    ...r,
                    checked: r.alreadyAdded ? true : restore ? chosen.includes(r.id) : r.selected === true
                }));
                this.notify();
            })
            .catch((e) => {
                this.error = (e && e.body && e.body.message) || 'Could not load the records.';
                this._loadedFor = undefined;
            })
            .finally(() => {
                this.loading = false;
            });
    }

    get groups() {
        return TIERS.map((t) => {
            const all = this.rows
                .filter((r) => r.tier === t.key)
                .sort(byRelevance)
                .map((r) => ({
                    ...r,
                    key: r.id,
                    link: '/' + r.id,
                    locked: r.alreadyAdded || this.readOnly,
                    dotStyle: 'background:' + (DOT[r.colour] || '#c9c9c9'),
                    matchLabel: r.colour ? r.colour + (r.relevance == null ? '' : ' (' + r.relevance + ')') : '',
                    note: r.alreadyAdded ? 'Already on the PHR' : r.reason || ''
                }));
            const free = all.filter((i) => !i.alreadyAdded);
            // Every tier shows 5 at a time, most relevant first.
            const paging = pageOf(all, this.pageByTier[t.key] || 1);
            return {
                key: t.key,
                label: t.label + ' (' + all.length + ')',
                items: paging.items,
                pager: paging.pages.length > 1 ? paging : null,
                hasItems: all.length > 0,
                canToggle: free.length > 0 && !this.readOnly,
                allOn: free.length > 0 && free.every((i) => i.checked),
                toggleLabel: free.length > 0 && free.every((i) => i.checked) ? 'Clear' : 'Select all'
            };
        }).filter((g) => g.hasItems);
    }

    handlePage(event) {
        const to = event.currentTarget.dataset.page;
        const tier = event.currentTarget.dataset.tier;
        const current = this.pageByTier[tier] || 1;
        const pages = Math.max(1, Math.ceil(this.rows.filter((r) => r.tier === tier).length / PAGE_SIZE));
        const n = to === 'prev' ? current - 1 : to === 'next' ? current + 1 : Number(to);
        this.pageByTier = { ...this.pageByTier, [tier]: Math.min(Math.max(1, n), pages) };
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get counts() {
        const free = this.rows.filter((r) => !r.alreadyAdded);
        const on = free.filter((r) => r.checked).length;
        return on + ' of ' + free.length + ' selected to add';
    }

    handleTick(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        this.rows = this.rows.map((r) => (r.id === id && !r.alreadyAdded ? { ...r, checked } : r));
        this.notify();
    }

    handleToggleGroup(event) {
        const tier = event.target.dataset.tier;
        const group = this.groups.find((g) => g.key === tier);
        const turnOn = group ? !group.allOn : true;
        this.rows = this.rows.map((r) => (r.tier === tier && !r.alreadyAdded ? { ...r, checked: turnOn } : r));
        this.notify();
    }

    notify() {
        const free = this.rows.filter((r) => !r.alreadyAdded);
        const ids = free.filter((r) => r.checked).map((r) => r.id);
        const value = {
            recordId: this.recordId,
            lotNumber: (this._value && this._value.lotNumber) || null,
            selectedRecordIds: ids,
            noneSelected: ids.length === 0
        };
        this._value = value;
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { value } }));
    }
}

/** Highest relevance first; records without a score last. Keeps the original order for ties. */
function byRelevance(a, b) {
    const x = a.relevance == null ? -1 : a.relevance;
    const y = b.relevance == null ? -1 : b.relevance;
    return y - x;
}

/** One page of a list, plus the page links (numbers, Previous, Next). */
function pageOf(list, page) {
    const count = Math.max(1, Math.ceil(list.length / PAGE_SIZE));
    const current = Math.min(Math.max(1, page), count);
    const start = (current - 1) * PAGE_SIZE;
    return {
        items: list.slice(start, start + PAGE_SIZE),
        pages: Array.from({ length: count }, (_, i) => ({
            key: 'p' + (i + 1),
            num: String(i + 1),
            cls: i + 1 === current ? 'page current' : 'page',
            current: i + 1 === current
        })),
        hasPrev: current > 1,
        hasNext: current < count,
        range: start + 1 + '–' + Math.min(start + PAGE_SIZE, list.length) + ' of ' + list.length
    };
}
