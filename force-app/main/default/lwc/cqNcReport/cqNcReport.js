import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { getEnclosingUtilityId, onUtilityClick, minimize } from 'lightning/platformUtilityBarApi';
import CqNcReportModal from 'c/cqNcReportModal';

/**
 * Opens Report a Nonconformance (c-cq-nc-report-modal). Three places, chosen with Lou 25 Nov 2026:
 *  - the utility bar (Quality Management, Field Actions): clicking the utility opens the popup straight away;
 *  - the Report a Nonconformance tab, which the New NC list button on the Nonconformance list opens: the popup opens
 *    on arrival and, when it closes, the person goes back to the Nonconformance list;
 *  - any page (app, home, record) as a button.
 */
export default class CqNcReport extends NavigationMixin(LightningElement) {
    @api buttonLabel = 'Report a Nonconformance';
    utilityId;
    onTab = false;
    opened = false;
    isOpening = false;

    @wire(CurrentPageReference)
    pageRef(ref) {
        this.onTab = !!ref && ref.type === 'standard__navItemPage';
        if (this.onTab && !this.opened) { this.opened = true; this.openModal(); }
    }

    connectedCallback() {
        // The utility bar API is missing when the utility is popped out into its own window (and off the utility bar),
        // so check it is there before calling it; the panel's own button still opens the popup.
        try {
            if (typeof getEnclosingUtilityId !== 'function') { return; }
            const p = getEnclosingUtilityId();
            if (!p || typeof p.then !== 'function') { return; }
            p.then((id) => {
                if (!id || typeof onUtilityClick !== 'function') { return; }
                this.utilityId = id;
                onUtilityClick({ utilityId: id, eventHandler: () => {
                    if (typeof minimize === 'function') { minimize({ utilityId: id }).catch(() => {}); }
                    this.openModal();
                } }).catch(() => {});
            }).catch(() => {});
        } catch (e) {
            // not in a utility bar
        }
    }

    get hint() { return this.onTab ? 'The Report a Nonconformance popup is closed.' : ''; }

    handleOpen() { this.openModal(); }

    async openModal() {
        if (this.isOpening) { return; }
        this.isOpening = true;
        let result;
        try {
            result = await CqNcReportModal.open({ size: 'small', description: 'Report a Nonconformance' });
        } finally {
            this.isOpening = false;
        }
        if (result && result.recordId) {
            this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: result.recordId, actionName: 'view' } });
        } else if (this.onTab) {
            this[NavigationMixin.Navigate]({ type: 'standard__objectPage', attributes: { objectApiName: 'compliancequest__SQX_Nonconformance__c', actionName: 'list' }, state: { filterName: 'Recent' } });
        }
    }
}
