@IsTest
private class CqIntakeChatClipTest {

    static Event_Question__c question() {
        Event_Question__c q = new Event_Question__c(Active__c = true, Required__c = true, Order__c = 1,
            Question__c = 'Where did this happen?', Answer_Type__c = 'Text', Role__c = 'Where Found',
            Audio_Wav_Base64__c = 'T0xE');
        insert q;
        return q;
    }

    static void attach(Id questionId, String fileName, Blob body) {
        ContentVersion v = new ContentVersion(Title = fileName, PathOnClient = fileName, VersionData = body);
        insert v;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :v.Id].ContentDocumentId;
        insert new ContentDocumentLink(LinkedEntityId = questionId, ContentDocumentId = docId, ShareType = 'V', Visibility = 'AllUsers');
    }

    @IsTest
    static void fieldClipIsUsedWhenNoFile() {
        Event_Question__c q = question();
        System.assertEquals('T0xE', CqIntakeChat.clipFor(q), 'with no file attached the stored field clip plays');
    }

    @IsTest
    static void attachedWavWinsOverTheField() {
        Event_Question__c q = question();
        Blob wav = Blob.valueOf('RIFF-new-clip');
        attach(q.Id, 'where.wav', wav);
        Test.startTest();
        String clip = CqIntakeChat.clipFor(q);
        Test.stopTest();
        System.assertEquals(EncodingUtil.base64Encode(wav), clip, 'the attached wav is the clip that plays');
    }

    @IsTest
    static void otherFilesAreIgnored() {
        Event_Question__c q = question();
        attach(q.Id, 'notes.txt', Blob.valueOf('not audio'));
        System.assertEquals('T0xE', CqIntakeChat.clipFor(q), 'only a wav file counts as a clip');
    }
}
