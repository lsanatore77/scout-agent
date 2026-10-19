/**
 * AssociatedItemsPartInfo
 * -------------------------
 * Top-level, @AuraEnabled data class for the associatedItemsReport LWC's
 * Custom Lightning Type payload. Must be top-level (not nested), global,
 * and @JsonAccess-serializable per Salesforce's Apex-based Custom
 * Lightning Type requirements -- the @InvocableVariable-based action
 * schema and this rendering payload are two separate contracts.
 */
@JsonAccess(serializable='always' deserializable='always')
global class AssociatedItemsPartInfo {
    @AuraEnabled global Id id;
    @AuraEnabled global String name;
    @AuraEnabled global String partNumber;
    @AuraEnabled global String partType;
    @AuraEnabled global String partFamily;
    @AuraEnabled global Boolean hasNC;
}
