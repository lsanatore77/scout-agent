import { LightningElement, api } from 'lwc';

// Collapsible sections, in display order. Must match the data-section values
// on the section header buttons in the template.
const SECTION_KEYS = [
    'part',
    'assembly',
    'lineItems',
    'nonconformances',
    'capas',
    'changeOrders',
    'inspections',
    'investigations'
];

// Records shown per page in each table.
const PAGE_SIZE = 5;

// The count charts' bar runs 0 to this value; larger counts pin at the right edge.
const CHART_MAX = 15;

/**
 * associatedItemsReport
 * Agentforce output renderer for AssociatedItemsReportAction.Response.
 * Bound to the Custom Lightning Type c__associatedItemsReportType
 * (lightning__AgentforceOutput target). Agentforce passes the Response
 * object directly as `value`.
 *
 * Layout is sized for the narrow Agentforce panel: the template never reads
 * `value.*` directly (all access goes through null-safe getters), and the
 * tables use a compact column set so they fit without horizontal scrolling.
 */
export default class AssociatedItemsReport extends LightningElement {
    @api value;

    // ---------- Collapsible sections ----------

    // Every section starts expanded. Reassigned (never mutated) on toggle so
    // the template re-renders.
    openSections = Object.fromEntries(SECTION_KEYS.map((key) => [key, true]));

    /**
     * Per-section render state for the template, keyed by the button's
     * data-section value: { className, expanded ('true'/'false' for
     * aria-expanded), isOpen }. Collapsed sections don't render their
     * content at all, so each datatable re-measures its auto column widths
     * when reopened instead of keeping widths taken while hidden.
     */
    get ui() {
        const ui = {};
        SECTION_KEYS.forEach((key, index) => {
            const isOpen = this.openSections[key];
            ui[key] = {
                className:
                    'slds-section' +
                    (isOpen ? ' slds-is-open' : '') +
                    (index > 0 ? ' slds-m-top_medium' : ''),
                expanded: String(isOpen),
                isOpen
            };
        });
        return ui;
    }

    // ---------- Pagination (PAGE_SIZE rows per table) ----------

    // Zero-based current page per table; keys match SECTION_KEYS.
    pageIndex = {
        lineItems: 0,
        nonconformances: 0,
        capas: 0,
        changeOrders: 0,
        inspections: 0,
        investigations: 0
    };

    handlePage(event) {
        event.preventDefault();
        if (event.currentTarget.classList.contains('pager-link-off')) {
            return;
        }
        const { section, dir } = event.currentTarget.dataset;
        this.pageIndex = { ...this.pageIndex, [section]: this.pageIndex[section] + Number(dir) };
    }

    /**
     * One page of a table: { rows, showPager, rangeLabel, pageLabel,
     * prevDisabled, nextDisabled, prevClass, nextClass, prevTab, nextTab }. The page index is clamped, so a report
     * that gets shorter never leaves the table on an empty page.
     */
    _pageOf(key, list) {
        const total = list.length;
        const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
        const page = Math.min(Math.max(this.pageIndex[key], 0), pages - 1);
        const start = page * PAGE_SIZE;
        const end = Math.min(start + PAGE_SIZE, total);
        return {
            rows: list.slice(start, end),
            showPager: total > PAGE_SIZE,
            rangeLabel: 'Showing ' + (start + 1) + '\u2013' + end + ' of ' + total,
            pageLabel: 'Page ' + (page + 1) + ' of ' + pages,
            prevDisabled: page === 0,
            nextDisabled: page >= pages - 1,
            prevClass: 'pager-link' + (page === 0 ? ' pager-link-off' : ''),
            nextClass: 'pager-link' + (page >= pages - 1 ? ' pager-link-off' : ''),
            prevTab: page === 0 ? '-1' : '0',
            nextTab: page >= pages - 1 ? '-1' : '0'
        };
    }

    get lineItemsPage() {
        return this._pageOf('lineItems', this.assemblyLineItems);
    }

    get nonconformancesPage() {
        return this._pageOf('nonconformances', this.nonconformances);
    }

    get capasPage() {
        return this._pageOf('capas', this.capas);
    }

    get changeOrdersPage() {
        return this._pageOf('changeOrders', this.changeOrders);
    }

    get inspectionsPage() {
        return this._pageOf('inspections', this.inspections);
    }

    get investigationsPage() {
        return this._pageOf('investigations', this.investigations);
    }

    handleToggle(event) {
        const key = event.currentTarget.dataset.section;
        this.openSections = { ...this.openSections, [key]: !this.openSections[key] };
    }

    handleExpandAll() {
        this._setAllSections(true);
    }

    handleCollapseAll() {
        this._setAllSections(false);
    }

    _setAllSections(isOpen) {
        this.openSections = Object.fromEntries(SECTION_KEYS.map((key) => [key, isOpen]));
    }

    // ---------- Column definitions ----------

    // Lot Match is shown only when the Complaint has a Lot Number.
    get lineItemColumns() {
        const cols = [
            { label: 'Assembly', fieldName: 'assemblyName', wrapText: true },
            { label: 'Part', fieldName: 'partName', wrapText: true },
            { label: 'Part Number', fieldName: 'partNumber', wrapText: true }
        ];
        if (this.hasLotNumber) {
            cols.push({ label: 'Lot Match', fieldName: 'lotMatch', wrapText: true });
        }
        return cols;
    }

    investigationColumns = [
        { label: 'Name', fieldName: 'name', wrapText: true },
        { label: 'Part Number', fieldName: 'partNumber', wrapText: true },
        { label: 'Source', fieldName: 'sourceName', wrapText: true },
        { label: 'Status', fieldName: 'status', wrapText: true },
        { label: 'Created', fieldName: 'createdDate', wrapText: true }
    ];

    // Shared by Nonconformances, CAPAs, Change Orders and Inspections.
    recordColumns = [
        { label: 'Name', fieldName: 'name', wrapText: true },
        { label: 'Part Number', fieldName: 'partNumber', wrapText: true },
        { label: 'Status', fieldName: 'status', wrapText: true },
        { label: 'Created', fieldName: 'createdDate', wrapText: true }
    ];

    // ---------- Null-safe accessors used by the template ----------

    get _report() {
        return this.value || {};
    }

    get generatedAt() {
        return this._report.generatedAt;
    }

    get cardTitle() {
        return this._report.reportTitle || 'Associated Items Summary Report';
    }

    get hasPrimaryPart() {
        return !!this._report.hasPrimaryPart && !!this._report.primaryPart;
    }

    get primaryPart() {
        return this._report.primaryPart || {};
    }

    get assemblies() {
        return this._list(this._report.assemblies);
    }

    get assemblyLineItems() {
        return this._list(this._report.assemblyLineItems);
    }

    get nonconformances() {
        return this._list(this._report.nonconformances);
    }

    get capas() {
        return this._list(this._report.capas);
    }

    get changeOrders() {
        return this._list(this._report.changeOrders);
    }

    get inspections() {
        return this._list(this._report.inspections);
    }

    get investigations() {
        return this._list(this._report.investigations);
    }

    // ---------- Filters (Lot / date range badges) ----------

    get hasLotNumber() {
        return !!this._report.lotNumber;
    }

    get lotLabel() {
        return this.hasLotNumber ? 'Lot: ' + this._report.lotNumber : '';
    }

    get hasDateRange() {
        return !!this._report.dateRangeLabel;
    }

    get dateRangeBadge() {
        return this.hasDateRange ? 'Created: ' + this._report.dateRangeLabel : '';
    }

    get hasFilters() {
        return this.hasLotNumber || this.hasDateRange;
    }

    // ---------- Nonconformance / CAPA count charts ----------

    /**
     * Two charts shown under Primary Part. Status by count:
     *   over 10          -> red, alert icon, "Bad trend"
     *   over 5 up to 10  -> yellow
     *   5 or fewer       -> green
     */
    get countCharts() {
        return [
            this._buildCountChart('nc', 'Nonconformance Count', this.nonconformancesCount),
            this._buildCountChart('capa', 'CAPA Count', this.capasCount)
        ];
    }

    _buildCountChart(key, title, count) {
        let level;
        let statusText;
        let iconName;
        let iconVariant;
        if (count > 10) {
            level = 'red';
            statusText = 'Bad trend: more than 10';
            iconName = 'utility:error';
            iconVariant = 'error';
        } else if (count > 5) {
            level = 'yellow';
            statusText = 'Watch: 6 to 10';
            iconName = 'utility:warning';
            iconVariant = 'warning';
        } else {
            level = 'green';
            statusText = 'On target: 5 or fewer';
            iconName = 'utility:success';
            iconVariant = 'success';
        }
        const pct = Math.min(count, CHART_MAX) / CHART_MAX * 100;
        return {
            key,
            title,
            count,
            statusText,
            iconName,
            iconVariant,
            numberClass: 'count-number count-' + level,
            badgeClass: 'count-badge badge-' + level,
            pinStyle: 'left: calc(' + pct + '% - 1px)',
            ariaLabel: title + ': ' + count + '. ' + statusText
        };
    }

    // ---------- Primary Part NC badge ----------

    get hasNcLabel() {
        return this.primaryPart.hasNC ? 'Has Nonconformance' : 'No Nonconformance';
    }

    get hasNcVariant() {
        return this.primaryPart.hasNC ? 'warning' : 'success';
    }

    // ---------- Section counts / visibility ----------

    get hasAssemblies() {
        return this.assemblies.length > 0;
    }

    get hasAssemblyLineItems() {
        return this.assemblyLineItems.length > 0;
    }

    get assemblyLineItemsCount() {
        return this.assemblyLineItems.length;
    }

    get hasNonconformances() {
        return this.nonconformances.length > 0;
    }

    get nonconformancesCount() {
        return this.nonconformances.length;
    }

    get hasCapas() {
        return this.capas.length > 0;
    }

    get capasCount() {
        return this.capas.length;
    }

    get hasChangeOrders() {
        return this.changeOrders.length > 0;
    }

    get changeOrdersCount() {
        return this.changeOrders.length;
    }

    get hasInspections() {
        return this.inspections.length > 0;
    }

    get inspectionsCount() {
        return this.inspections.length;
    }

    get hasInvestigations() {
        return this.investigations.length > 0;
    }

    get investigationsCount() {
        return this.investigations.length;
    }

    // ---------- Helpers ----------

    _list(list) {
        return Array.isArray(list) ? list : [];
    }
}
