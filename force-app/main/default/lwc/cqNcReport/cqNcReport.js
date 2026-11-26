import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { getEnclosingUtilityId, onUtilityClick, minimize } from 'lightning/platformUtilityBarApi';
import CqNcReportModal from 'c/cqNcReportModal';

const TAB = 'Report_a_Nonconformance';
// Shared by every copy on the page (the tab and the utility bar): only one popup at a time.
let popupOpen = false;

/**
 * Opens Report a Nonconformance (c-cq-nc-report-modal). Three places, chosen with Lou 25 Nov 2026:
 *  - the utility bar (Quality Management, Field Actions): clicking the utility opens the popup straight away;
 *  - the Report a Nonconformance tab, which the New NC list button on the Nonconformance list opens: the popup opens
 *    on arrival and, when it closes, the person goes back to the Nonconformance list;
 *  - any page (app, home, record) as a button.
 */
export default class CqNcReport extends NavigationMixin(LightningElement) {
    @api buttonLabel = 'Report a Nonconformance';
    @api inUtilityBar = false;   // set in the utility bar pages: that copy never opens the popup on its own
    utilityId;
    onTab = false;
    opened = false;
    isOpening = false;
    isOpen = false;   // the popup is up: the tab behind it shows nothing
    lastKey;

    // Resolves to the utility's id when this copy sits in the utility bar, else null. The utility bar copy also sees the
    // page reference, so only the tab's own copy may open the popup on arrival (else it opened twice). Made on first use:
    // the page reference can arrive before connectedCallback runs.
    utilityPromise;
    get utilityCheck() {
        if (!this.utilityPromise) {
            let p = null;
            try {
                if (typeof getEnclosingUtilityId === 'function') { p = getEnclosingUtilityId(); }
            } catch (e) { p = null; }
            this.utilityPromise = p && typeof p.then === 'function' ? p.then((id) => id || null).catch(() => null) : Promise.resolve(null);
        }
        return this.utilityPromise;
    }

    @wire(CurrentPageReference)
    pageRef(ref) {
        const here = !!ref && ref.type === 'standard__navItemPage' && ref.attributes && ref.attributes.apiName === TAB;
        // Lightning keeps the tab alive after it is left, so each arrival must open the popup again: the New button sends a
        // fresh c__open value every time, and leaving the tab (or closing the popup) resets it for a plain arrival.
        const key = here && ref.state ? ref.state.c__open || '' : '';
        this.utilityCheck.then((id) => {
            if (!here) { this.opened = false; }
            this.onTab = here && !id && !this.inUtilityBar;
            if (this.onTab && (!this.opened || key !== this.lastKey)) {
                this.opened = true;
                this.lastKey = key;
                this.openModal();
            }
        });
    }

    connectedCallback() {
        // The utility bar API is missing when the utility is popped out into its own window (and off the utility bar),
        // so check it is there before calling it; the panel's own button still opens the popup.
        try {
            this.utilityCheck.then((id) => {
                if (!id || typeof onUtilityClick !== 'function') { return; }
                this.utilityId = id;
                onUtilityClick({ utilityId: id, eventHandler: () => {
                    if (typeof minimize === 'function') { minimize({ utilityId: id }).catch(() => {}); }
                    this.openModal();
                } }).catch(() => {});
            });
        } catch (e) {
            // not in a utility bar
        }
    }

    get showBar() { return !this.isOpen; }
    get hint() { return this.onTab ? 'The Report a Nonconformance popup is closed.' : ''; }

    handleOpen() { this.openModal(); }

    async openModal() {
        if (this.isOpening || popupOpen) { return; }
        popupOpen = true;
        this.isOpening = true;
        this.isOpen = true;
        let result;
        try {
            result = await CqNcReportModal.open({ size: 'small', description: 'Report a Nonconformance' });
        } finally {
            popupOpen = false;
            this.isOpening = false;
            this.isOpen = false;
        }
        if (result && result.recordId) {
            this.opened = false;
            this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: result.recordId, actionName: 'view' } });
        } else if (this.onTab) {
            this.opened = false;
            this[NavigationMixin.Navigate]({ type: 'standard__objectPage', attributes: { objectApiName: 'compliancequest__SQX_Nonconformance__c', actionName: 'list' }, state: { filterName: 'Recent' } });
        }
    }
}
