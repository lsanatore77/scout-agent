import { LightningElement, api } from 'lwc';

const CHIP = {
    Red: { cls: 'chip chip-red', label: 'All three criteria' },
    Yellow: { cls: 'chip chip-yellow', label: 'Two criteria' },
    Grey: { cls: 'chip chip-grey', label: 'One criterion' }
};
const RATING_CLASS = {
    High: 'rating rating-high',
    Medium: 'rating rating-medium',
    Low: 'rating rating-low'
};

/**
 * phrLeadPackage
 * Agentforce output renderer for PhrLeadPackageData: the records worth
 * reviewing for a complaint, grouped by type, with a colour chip for how many
 * criteria each met, plus the records that were set aside and why.
 * Null-safe: the template only reads getters.
 */
export default class PhrLeadPackage extends LightningElement {
    @api value;

    expanded = {};
    showAside = false;

    get _data() {
        return this.value || {};
    }

    get intro() {
        return this._data.intro;
    }

    get hasRating() {
        return !!this._data.overallRating && this._data.overallRating !== 'None';
    }

    get ratingText() {
        const score = this._data.overallScore;
        return this._data.overallRating + (score || score === 0 ? ' (' + score + ' of 100)' : '');
    }

    get ratingClass() {
        return RATING_CLASS[this._data.overallRating] || 'rating';
    }

    get sections() {
        const list = Array.isArray(this._data.sections) ? this._data.sections : [];
        return list
            .filter((s) => Array.isArray(s.rows) && s.rows.length > 0)
            .map((s, index) => {
                const shown = s.shownCount > 0 ? s.shownCount : 3;
                const isOpen = !!this.expanded[index];
                const total = s.rows.length;
                const rows = (isOpen ? s.rows : s.rows.slice(0, shown)).map((r) => this._row(r));
                return {
                    key: 'sec-' + index,
                    index: String(index),
                    heading: s.title + ' (' + total + ')',
                    headerNote:
                        s.headerNote || (total > shown && !isOpen ? 'showing top ' + shown : ''),
                    rows,
                    canToggle: total > shown,
                    toggleLabel: isOpen ? 'Show fewer' : 'Show more ' + String(s.title).toLowerCase()
                };
            });
    }

    get hasSections() {
        return this.sections.length > 0;
    }

    get setAsideRows() {
        const list = Array.isArray(this._data.setAside) ? this._data.setAside : [];
        return list.map((r) => this._row(r));
    }

    get setAsideCount() {
        return this.setAsideRows.length;
    }

    get hasSetAside() {
        return this.setAsideCount > 0;
    }

    get setAsideToggleLabel() {
        return this.showAside
            ? 'Hide the ' + this.setAsideCount + ' set aside'
            : 'Show the ' + this.setAsideCount + ' I set aside';
    }

    get errorText() {
        return this._data.success === false ? this._data.errorMessage || 'Something went wrong.' : '';
    }

    get hasError() {
        return !!this.errorText;
    }

    _row(r) {
        const chip = CHIP[r.colour] || CHIP.Grey;
        return {
            key: (r.id || r.name) + '-' + (r.recordType || ''),
            name: r.name,
            status: r.status,
            title: r.title || 'No title',
            note: r.note,
            reason: r.reason,
            chipClass: chip.cls,
            chipLabel: chip.label + (r.relevance || r.relevance === 0 ? ', ' + r.relevance + ' of 100' : '')
        };
    }

    handleToggleSection(event) {
        const index = event.currentTarget.dataset.index;
        this.expanded = { ...this.expanded, [index]: !this.expanded[index] };
    }

    handleToggleAside() {
        this.showAside = !this.showAside;
    }
}
