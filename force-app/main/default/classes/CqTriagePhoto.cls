/** Photo for Triage at a Glance: the newest image file attached to the record, and saving a new one. */
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

    /** Saves an image (base64, already resized in the browser) as a file on the record. Returns the version Id. */
    @AuraEnabled
    public static String savePhoto(Id recordId, String fileName, String base64Data) {
        if (recordId == null || String.isBlank(base64Data)) {
            throw new AuraHandledException('No photo to save.');
        }
        String name = String.isBlank(fileName) ? 'photo.jpg' : fileName;
        ContentVersion cv = new ContentVersion(
            Title = name, PathOnClient = name,
            VersionData = EncodingUtil.base64Decode(base64Data),
            FirstPublishLocationId = recordId);
        insert cv;
        return cv.Id;
    }
}
