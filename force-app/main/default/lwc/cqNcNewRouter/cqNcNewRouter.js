import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import cqScreens from '@salesforce/customPermission/CQAI_CQ_Standard_NC_Screens';

/**
 * Behind the Nonconformance New button (the cqNcNewOverride Aura wrapper). Everyone gets CQ.AI Report a Nonconformance
 * (its tab opens the popup and goes back to the NC list when it closes). People with the CQ Standard NC Screens
 * permission (Enterprise tier) get CQ's own NC wizard, as before. Decided with Lou 25 Nov 2026.
 * The page is replaced, not added to, so Back does not land here again.
 */
export default class CqNcNewRouter extends NavigationMixin(LightningElement) {
    connectedCallback() {
        const ref = cqScreens
            ? { type: 'standard__component', attributes: { componentName: 'compliancequest__SQX_Nonconformance_Wizard' } }
            : { type: 'standard__navItemPage', attributes: { apiName: 'Report_a_Nonconformance' }, state: { c__open: String(Date.now()) } };
        this[NavigationMixin.Navigate](ref, true);
    }
}
