/**
 * PhrChecklistItem
 * One Product History Review checklist question with a suggested answer and what it is based on.
 */
@JsonAccess(serializable='always' deserializable='always')
global class PhrChecklistItem {
    @AuraEnabled global String questionNumber;
    @AuraEnabled global String question;
    @AuraEnabled global String suggestedAnswer;
    // The records or calculation the suggestion is based on, for example "NC-000084, NC-000085".
    @AuraEnabled global String basis;
    // Id of the checklist answer record (compliancequest__SQX_Product_History_Answer__c).
    @AuraEnabled global String answerId;
    // True when the data answers the question; false when the agent is not sure (nothing is saved for it).
    @AuraEnabled global Boolean sure;
    // suggested, unsure or saved.
    @AuraEnabled global String status;
}
