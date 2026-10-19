/**
 * PhrChecklistResult
 * Output of the checklist suggestions. Bound to the phrChecklistType renderer.
 */
@JsonAccess(serializable='always' deserializable='always')
global class PhrChecklistResult {
    @AuraEnabled global String intro;
    @AuraEnabled global String checklistName;
    @AuraEnabled global List<PhrChecklistItem> items = new List<PhrChecklistItem>();
    @AuraEnabled global Boolean success;
    @AuraEnabled global String errorMessage;
}
