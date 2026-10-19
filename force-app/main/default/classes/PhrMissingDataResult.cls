/**
 * PhrMissingDataResult
 * Output of the missing-data check. Bound to the phrMissingDataType renderer.
 */
@JsonAccess(serializable='always' deserializable='always')
global class PhrMissingDataResult {
    @AuraEnabled global String intro;
    @AuraEnabled global List<PhrMissingCheck> checks = new List<PhrMissingCheck>();
    @AuraEnabled global Boolean success;
    @AuraEnabled global String errorMessage;
}
