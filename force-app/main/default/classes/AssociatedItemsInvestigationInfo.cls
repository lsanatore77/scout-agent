/**
 * AssociatedItemsInvestigationInfo
 * ----------------------------------
 * One Investigation related to the Complaint's Part or Lot Number, for the
 * Related Investigations section. Investigations started from the Complaint
 * itself are not included.
 */
@JsonAccess(serializable='always' deserializable='always')
global class AssociatedItemsInvestigationInfo {
    @AuraEnabled global Id id;
    @AuraEnabled global String name;
    // Number of the record the Investigation was started from (a Complaint, NC, etc.).
    @AuraEnabled global String sourceName;
    // Part Number of the Part the Investigation is filed against.
    @AuraEnabled global String partNumber;
    @AuraEnabled global String status;
    // 'Part', 'Lot' or 'Part and Lot'.
    @AuraEnabled global String matchedBy;
    @AuraEnabled global String createdDate;
}
