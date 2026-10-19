/**
 * PhrChecklistItem
 * One reviewer checklist question with an answer suggested from the lead records.
 */
@JsonAccess(serializable='always' deserializable='always')
global class PhrChecklistItem {
    @AuraEnabled global String questionNumber;
    @AuraEnabled global String question;
    @AuraEnabled global String suggestedAnswer;
    // The records the suggestion is based on, for example "NC-000084, NC-000085".
    @AuraEnabled global String basis;
}
