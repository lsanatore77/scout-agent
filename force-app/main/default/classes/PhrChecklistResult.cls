/**
 * PhrChecklistResult
 * Output of the checklist suggestions (and of saving them). Bound to the phrChecklistType renderer.
 */
@JsonAccess(serializable='always' deserializable='always')
global class PhrChecklistResult {
    @AuraEnabled global String intro;
    @AuraEnabled global String checklistName;
    @AuraEnabled global List<PhrChecklistItem> items = new List<PhrChecklistItem>();
    @AuraEnabled global Boolean success;
    @AuraEnabled global String errorMessage;
    // Name of the Product History Review, for example PHR-000004.
    @AuraEnabled global String phrName;
    @AuraEnabled global Integer sureCount;
    @AuraEnabled global Integer unsureCount;
    @AuraEnabled global Integer savedCount;
    // True when this result is from saving the answers.
    @AuraEnabled global Boolean saved;
    // The questions the agent is not sure about, one per line, for the agent to name in its reply.
    @AuraEnabled global String unsureQuestions;
}
