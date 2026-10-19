import { LightningElement, api } from 'lwc';

/**
 * phrMissingData
 * Agentforce output renderer for PhrMissingDataResult: the reviewer's
 * missing-data check, one line per check, warnings first.
 */
export default class PhrMissingData extends LightningElement {
    @api value;

    get _data() {
        return this.value || {};
    }

    get intro() {
        return this._data.intro;
    }

    get checks() {
        const list = Array.isArray(this._data.checks) ? this._data.checks : [];
        const rows = list.map((c, index) => {
            const ok = c.status === 'ok';
            return {
                key: 'chk-' + index,
                order: ok ? 1 : 0,
                index,
                label: c.label,
                detail: c.detail,
                iconName: ok ? 'utility:success' : 'utility:warning',
                iconVariant: ok ? 'success' : 'warning',
                altText: ok ? 'OK' : 'Needs attention'
            };
        });
        // Warnings first, original order kept inside each group.
        return rows.sort((a, b) => a.order - b.order || a.index - b.index);
    }

    get hasChecks() {
        return this.checks.length > 0;
    }

    get countLabel() {
        return this.checks.length + (this.checks.length === 1 ? ' check' : ' checks');
    }

    get errorText() {
        return this._data.success === false ? this._data.errorMessage || 'Something went wrong.' : '';
    }

    get hasError() {
        return !!this.errorText;
    }
}
