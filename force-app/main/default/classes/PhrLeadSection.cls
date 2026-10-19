/**
 * PhrLeadSection
 * One group of lead records (for example "Nonconformances") in the lead package.
 */
@JsonAccess(serializable='always' deserializable='always')
global class PhrLeadSection {
    @AuraEnabled global String title;
    // Note shown on the right of the heading, for example "linked to complaint on yes".
    @AuraEnabled global String headerNote;
    // Rows shown before "Show more" is used.
    @AuraEnabled global Integer shownCount;
    @AuraEnabled global List<PhrLeadRecord> rows = new List<PhrLeadRecord>();
}
