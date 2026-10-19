@JsonAccess(serializable='always' deserializable='always')
global class AssociatedItemsRecordInfo {
    @AuraEnabled global Id id;
    @AuraEnabled global String name;
    @AuraEnabled global String status;
    // Part Number of the Part (or, for Change Orders, the Product) the record is filed against.
    @AuraEnabled global String partNumber;
    @AuraEnabled global String createdDate;
    // Lot Number on the record itself (Nonconformances and Inspections only).
    @AuraEnabled global String lotNumber;
    // How the record was found: 'Part', 'Lot' or 'Part and Lot'. Blank when
    // the record came from an explicit ID list rather than auto-resolution.
    @AuraEnabled global String matchedBy;
}
