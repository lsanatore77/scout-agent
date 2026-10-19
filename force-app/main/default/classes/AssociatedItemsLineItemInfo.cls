@JsonAccess(serializable='always' deserializable='always')
global class AssociatedItemsLineItemInfo {
    @AuraEnabled global Id id;
    @AuraEnabled global String assemblyName;
    @AuraEnabled global String partName;
    @AuraEnabled global String partNumber;
    // The component Part this line item points at.
    @AuraEnabled global Id partId;
    // Lot match for this component: how many Nonconformances and Inspections
    // carry the Complaint's Lot Number and are filed against this component Part.
    // lotMatch is blank when the Complaint has no Lot Number, otherwise
    // 'None' or text such as 'Lot · 1 NC, 2 inspections'.
    @AuraEnabled global String lotMatch;
    @AuraEnabled global Integer lotNcCount;
    @AuraEnabled global Integer lotInspectionCount;
}
