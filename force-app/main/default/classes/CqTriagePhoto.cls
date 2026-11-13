/** Photo for Triage at a Glance: the newest image file attached to the record. */
public with sharing class CqTriagePhoto {
    @AuraEnabled
    public static String getPhotoVersionId(Id recordId) {
        if (recordId == null) { return null; }
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
              AND ContentDocument.FileType IN ('JPG', 'JPEG', 'PNG', 'GIF')
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 1
        ];
        return links.isEmpty() ? null : links[0].ContentDocument.LatestPublishedVersionId;
    }
}
