/**
 * PhrMissingCheck
 * One line of the missing-data check. Status is warn (needs attention) or ok.
 */
@JsonAccess(serializable='always' deserializable='always')
global class PhrMissingCheck {
    @AuraEnabled global String label;
    @AuraEnabled global String detail;
    @AuraEnabled global String status;
}
