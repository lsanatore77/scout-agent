import { LightningElement, api } from 'lwc';
import getLeads from '@salesforce/apex/PhrLeadListController.getLeads';
import getLeadsForInvestigation from '@salesforce/apex/PhrLeadListController.getLeadsForInvestigation';

/**
 * phrLeadLists: the three tier lists (Top, Next, Set aside) of the records that
 * were added to a Product History Review. Records that were found but not added
 * are hidden unless "Show not added" is switched on; they are added from the agent
 * (run "show package" again and tick them).
 */
const DOT = {
    Red: { cls: 'dot dot-red', label: 'Red: all three criteria' },
    Yellow: { cls: 'dot dot-yellow', label: 'Yellow: two criteria' },
    Grey: { cls: 'dot dot-grey', label: 'Grey: one criterion' }
};
// Top and Next lists show how each record is related instead of its title; Set aside keeps the title.
// The Match column is a colored dot (hover for the colour and score).
const LEAD_HEADERS = ['Record', 'Type', 'Status', 'Match', 'Related by'];
const SET_ASIDE_HEADERS = ['Record', 'Type', 'Title', 'Status', 'Match', 'Why set aside'];
const ADDED_HEADER = 'Added';
const PHR_HEADER = 'PHR';
const INVESTIGATION_OBJECT = 'compliancequest__SQX_Investigation__c';
const TIERS = [
    { key: 'Top', title: 'Most Relevant', empty: 'No most relevant records were added.' },
    { key: 'Next', title: 'Less Relevant', empty: 'No less relevant records were added.' },
    { key: 'Set aside', title: 'Set Aside', empty: 'No set aside records were added.' }
];

export default class PhrLeadLists extends LightningElement {
    @api recordId;
    @api objectApiName;
    rows = [];
    loading = true;
    showNotAdded = false;
    error;

    connectedCallback() {
        this.load();
    }

    load() {
        this.loading = true;
        this.error = undefined;
        const request = this.isInvestigation
            ? getLeadsForInvestigation({ investigationId: this.recordId })
            : getLeads({ phrId: this.recordId });
        request
            .then((data) => {
                this.rows = data || [];
            })
            .catch((e) => {
                this.error = e && e.body && e.body.message ? e.body.message : 'Could not load the leads.';
            })
            .finally(() => {
                this.loading = false;
            });
    }

    get isInvestigation() {
        return this.objectApiName === INVESTIGATION_OBJECT;
    }

    /** The PHR column only appears when the leads come from more than one Product History Review. */
    get showPhr() {
        return new Set(this.rows.map((r) => r.phrName)).size > 1;
    }

    get emptyMessage() {
        return this.isInvestigation
            ? 'No records have been added to a Product History Review linked to this investigation yet.'
            : 'No records have been added to this Product History Review yet.';
    }

    get hasError() {
        return !!this.error;
    }

    get hasAny() {
        return this.rows.length > 0;
    }

    get addedRows() {
        return this.rows.filter((r) => r.added);
    }

    get visibleRows() {
        return this.showNotAdded ? this.rows : this.addedRows;
    }

    get notAddedCount() {
        return this.rows.length - this.addedRows.length;
    }

    get hasNotAdded() {
        return this.notAddedCount > 0;
    }

    get notAddedNote() {
        const n = this.notAddedCount;
        return (
            n +
            (n === 1 ? ' more record was' : ' more records were') +
            (this.showNotAdded ? ' found but not added (shown below).' : ' found but not added.') +
            (this.isInvestigation ? ' They can be added from the complaint in the agent.' : ' Ask the agent to "show package" to add them.')
        );
    }

    get tiers() {
        return TIERS.map((t) => {
            const rows = this.visibleRows.filter((r) => r.tier === t.key);
            const asideTier = t.key === 'Set aside';
            const headers = (asideTier ? SET_ASIDE_HEADERS : LEAD_HEADERS)
                .concat(this.showPhr ? [PHR_HEADER] : [])
                .concat(this.showNotAdded ? [ADDED_HEADER] : []);
            return {
                key: t.key,
                heading: t.title + ' (' + rows.length + ')',
                empty: t.empty,
                rows: rows.map((r) => this.decorate(r, asideTier)),
                headers: headers.map((h) => ({ key: h, label: h })),
                hasRows: rows.length > 0
            };
        });
    }

    decorate(r, asideTier) {
        const d = DOT[r.colour];
        return {
            ...r,
            asideTier,
            hasDot: !!d,
            dotClass: d ? d.cls : '',
            dotLabel: d ? d.label + (r.relevance == null ? '' : ' (' + r.relevance + ')') : '',
            showAdded: this.showNotAdded,
            showPhr: this.showPhr
        };
    }

    handleShowNotAdded(event) {
        this.showNotAdded = event.target.checked;
    }

    handleRefresh() {
        this.load();
    }
}
