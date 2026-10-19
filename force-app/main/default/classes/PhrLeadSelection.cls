/**
 * PhrLeadSelection
 * The value the tick-box component (phrLeadSelect) hands back to the agent: which
 * complaint, and which records the user left ticked. This is the type the
 * phrLeadSelectionType Custom Lightning Type binds to (the editor override).
 */
@JsonAccess(serializable='always' deserializable='always')
global class PhrLeadSelection {
    @AuraEnabled @InvocableVariable(label='Complaint or PHR Id' description='The Complaint (or its Product History Review) open in the conversation.')
    global String recordId;

    @AuraEnabled @InvocableVariable(label='Lot Number Override' description='Optional. Search this lot instead of the Complaint\'s own lot.')
    global String lotNumber;

    @AuraEnabled @InvocableVariable(label='Selected Record Ids' description='Ids of the records the user left ticked.')
    global List<String> selectedRecordIds;

    // True when the user unticked everything, so an empty list is not read as "add all".
    @AuraEnabled @InvocableVariable(label='Nothing Selected' description='True when the user left nothing ticked.')
    global Boolean noneSelected;
}
