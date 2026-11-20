@IsTest
private class CqIntakeChatClipTest {

    @TestSetup
    static void setup() { CqIntakeTestData.grantAccess(); }

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
    static void clipMethodReturnsTheClipForAQuestion() {
        Event_Question__c q = question();
        System.assertEquals('T0xE', CqIntakeChat.clip(q.Id), 'the device can fetch one question\'s clip');
    }

    @IsTest
    static void deviceLoadedAudioIsNotSentWithTheQuestion() {
        Event_Question__c q = question();
        CqEventExtract.mockJson = '{"DEFECT":{"value":"cracked hub"}}';
        String state = JSON.serialize(new Map<String, Object>{ 'description' => 'cracked hub', 'answers' => new List<Object>(), 'noAudio' => true });
        Test.startTest();
        CqIntakeChat.Turn t = CqIntakeChat.respond(state);
        Test.stopTest();
        System.assertEquals(q.Id, t.askQuestionId);
        System.assertEquals(null, t.askAudio, 'the clip is left out when the device loads clips itself');
        System.assertEquals(1, t.clipQuestionIds.size(), 'the device is told which questions have clips to load');
    }

    @IsTest
    static void unchangedDescriptionReusesTheLastRead() {
        question();
        CqEventExtract.mockJson = '{"DEFECT":{"value":"cracked hub"}}';
        String d = 'cracked hub on the line';
        CqIntakeChat.Turn first = CqIntakeChat.respond(JSON.serialize(new Map<String, Object>{ 'description' => d, 'answers' => new List<Object>() }));
        System.assert(String.isNotBlank(first.exJson), 'the read is handed back to the device');

        // A second read would now say something different, so the result shows which path ran.
        CqEventExtract.mockJson = '{"DEFECT":{"value":"bent pin"}}';
        Test.startTest();
        CqIntakeChat.Turn same = CqIntakeChat.respond(JSON.serialize(new Map<String, Object>{
            'description' => d, 'answers' => new List<Object>(), 'exJson' => first.exJson, 'exFor' => d }));
        CqIntakeChat.Turn changed = CqIntakeChat.respond(JSON.serialize(new Map<String, Object>{
            'description' => d + ' and a bent pin', 'answers' => new List<Object>(), 'exJson' => first.exJson, 'exFor' => d }));
        CqIntakeChat.Turn garbled = CqIntakeChat.respond(JSON.serialize(new Map<String, Object>{
            'description' => d, 'answers' => new List<Object>(), 'exJson' => 'not json', 'exFor' => d }));
        Test.stopTest();

        System.assert(defect(same) == 'cracked hub', 'same description: the earlier read is reused');
        System.assert(defect(changed) == 'bent pin', 'new words: the description is read again');
        System.assert(defect(garbled) == 'bent pin', 'an unreadable hand-back is ignored and the description is read again');
    }

    static String defect(CqIntakeChat.Turn t) {
        for (CqIntakeChat.Field f : t.understood) { if (f.key == 'defect') { return f.value; } }
        return null;
    }

    @IsTest
    static void otherFilesAreIgnored() {
        Event_Question__c q = question();
        attach(q.Id, 'notes.txt', Blob.valueOf('not audio'));
        System.assertEquals('T0xE', CqIntakeChat.clipFor(q), 'only a wav file counts as a clip');
    }
}
