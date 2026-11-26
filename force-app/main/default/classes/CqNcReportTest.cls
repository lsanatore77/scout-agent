@IsTest
private class CqNcReportTest {
    static compliancequest__SQX_Part__c makePart() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Report Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Report Balloon Catheter', cqext__Title__c = 'Report Balloon Catheter', compliancequest__Part_Number__c = 'RPT-1000',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        insert new compliancequest__SQX_Lot_Info__c(Name = 'RL26-0915', compliancequest__Part_Number__c = 'RPT-1000');
        return part;
    }

    static Id openNcOnLot(compliancequest__SQX_Part__c part, String lot) {
        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = 'Balloon burst below rated pressure', compliancequest__Type__c = 'Internal',
            compliancequest__Type_Of_Issue__c = 'Product', compliancequest__Description__c = 'Burst test failure',
            compliancequest__SQX_Part__c = part.Id, compliancequest__Lot_Number__c = lot);
        insert nc;
        return nc.Id;
    }

    static final String STORY = 'At final inspection on line 3, 12 balloon catheters from lot RL26-0915 failed the burst pressure test. '
        + 'They burst at 14 atm; the spec is 16 atm minimum.';

    @IsTest
    static void lotLikeWordsAreFoundInTheText() {
        Set<String> t = CqNcReport.lotTokens('Lot L26-0915 and BL-25-0311 failed; line-3 and spec 16 are not lots.');
        System.assert(t.contains('L26-0915'), 'a lot number is found');
        System.assert(t.contains('BL-25-0311'), 'a lot with two dashes is found');
        System.assert(!t.contains('16'), 'a plain number is not a lot');
        System.assertEquals(0, CqNcReport.lotTokens(null).size(), 'no text, no lots');
    }

    @IsTest
    static void atOffersLotsWithTheirPartAndParts() {
        compliancequest__SQX_Part__c part = makePart();
        Test.startTest();
        List<CqNcReport.Mention> byLot = CqNcReport.mentions('RL26');
        List<CqNcReport.Mention> byPart = CqNcReport.mentions('RPT');
        List<CqNcReport.Mention> none = CqNcReport.mentions(' ');
        List<CqNcReport.Mention> wild = CqNcReport.mentions('%');
        Test.stopTest();
        System.assertEquals(1, byLot.size(), 'the lot, and no part, starts with RL26');
        System.assertEquals('lot', byLot[0].kind);
        System.assertEquals('RL26-0915', byLot[0].label);
        System.assertEquals(part.Id, byLot[0].partId, 'a lot brings its part');
        System.assertEquals(1, byPart.size(), 'the part matches by number');
        System.assertEquals('part', byPart[0].kind);
        System.assertEquals('RPT-1000', byPart[0].label);
        System.assertEquals(0, none.size(), 'nothing typed, nothing offered');
        System.assertEquals(0, wild.size(), 'a % is searched as a character, not a wildcard');
    }

    @IsTest
    static void partsStartingWithTheTermComeFirst() {
        compliancequest__SQX_Part__c part = makePart();
        compliancequest__SQX_Part__c other = new compliancequest__SQX_Part__c(Name = 'Spare RPT holder', cqext__Title__c = 'Spare RPT holder',
            compliancequest__Part_Number__c = 'AA-RPT-9', compliancequest__Part_Family__c = part.compliancequest__Part_Family__c,
            compliancequest__Part_Type__c = 'Finished Product', compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert other;
        List<CqNcReport.Mention> r = CqNcReport.mentions('RPT');
        System.assertEquals(2, r.size());
        System.assertEquals('RPT-1000', r[0].label, 'starts with RPT, so first, though AA-RPT-9 sorts earlier');
        System.assertEquals('AA-RPT-9', r[1].label);
    }

    @IsTest
    static void anOpenNcOnTheSameLotIsAPossibleDuplicate() {
        compliancequest__SQX_Part__c part = makePart();
        Id existing = openNcOnLot(part, 'RL26-0915');
        Test.startTest();
        List<CqNcReport.Dup> d = CqNcReport.duplicates(STORY, null);
        List<CqNcReport.Dup> none = CqNcReport.duplicates('A seal channel on 4 pouches, no lot written.', null);
        List<CqNcReport.Dup> fromLot = CqNcReport.duplicates('No lot written here.', 'RL26-0915');
        Test.stopTest();
        System.assertEquals(1, d.size(), 'the open NC on the lot written in the text is offered');
        System.assertEquals(existing, d[0].id);
        System.assertEquals('RL26-0915', d[0].lot);
        System.assertEquals(0, none.size(), 'no lot written, no duplicate');
        System.assertEquals(1, fromLot.size(), 'the lot CQ.AI found also finds it');
    }

    @IsTest
    static void cqaiFillsTheRecordAndThePartComesFromTheLot() {
        makePart();
        CqNcReport.mockFill = '{"TITLE": {"value": "Balloon burst below rated pressure"}, "PART": {"value": "balloon catheters"}, '
            + '"LOT": {"value": "RL26-0915"}, "UNITS AFFECTED": {"value": 12}, "DEFECT": {"value": "Burst below rated pressure"}, '
            + '"FOUND AT": {"value": "Final inspection"}, "TYPE": {"value": "Internal"}}';
        Test.startTest();
        CqNcReport.Fill f = CqNcReport.fillIn(STORY);
        Test.stopTest();
        System.assert(f.cqai, 'CQ.AI read it');
        System.assertEquals('Balloon burst below rated pressure at final inspection', f.title, 'where it was found is added by the title rule');
        System.assertEquals('RL26-0915', f.lot);
        System.assert(f.lotKnown, 'the lot is a real lot record');
        System.assertEquals('RPT-1000', f.partNumber, 'the part comes from the lot record, not from CQ.AI\'s word');
        System.assertEquals(null, f.partTerm, 'no picker needed');
        System.assertEquals(12, f.quantity);
        System.assertEquals('Internal', f.type);
        System.assertEquals('Burst below rated pressure', f.failure);
    }

    @IsTest
    static void withNoLotThePickerStartsFromCqaisWord() {
        makePart();
        CqNcReport.mockFill = '{"TITLE": {"value": "Balloon burst below rated pressure at lot release testing."}, "PART": {"value": "balloons"}, '
            + '"UNITS AFFECTED": {"value": "2"}, "TYPE": {"value": "Customer"}}';
        CqNcReport.Fill f = CqNcReport.fillIn('Two of 20 balloons burst at 15 atm during release testing.');
        System.assertEquals(null, f.partId, 'no lot, no guessed part');
        System.assertEquals('balloons', f.partTerm, 'CQ.AI\'s word starts the picker');
        System.assertEquals('Balloon burst below rated pressure at lot release testing', f.title, 'no full stop');
        System.assertEquals('Customer', f.type);
        System.assertEquals(2, f.quantity);
    }

    @IsTest
    static void withoutCqaiAPlainReadStillFindsTheLotAndQuantity() {
        makePart();
        CqNcReport.mockFill = null;
        CqNcReport.Fill f = CqNcReport.fillIn(STORY);
        System.assert(!f.cqai, 'CQ.AI did not run');
        System.assertEquals('RL26-0915', f.lot);
        System.assertEquals('RPT-1000', f.partNumber, 'the lot still gives the part');
        System.assertEquals(12, f.quantity);
        System.assertEquals('Internal', f.type, 'Internal unless CQ.AI says otherwise');
    }

    @IsTest
    static void titleRuleKeepsTitlesShortAndInSentenceCase() {
        System.assertEquals('Seal channel in pouch at packaging visual', CqNcReport.titleOf('seal channel in pouch.', 'Packaging visual'));
        System.assertEquals('Burst during testing', CqNcReport.titleOf('Burst during testing', 'Lot release'), 'a title that already says where is left alone');
        String longT = CqNcReport.titleOf('Balloon protector requires excessive force to remove from the folded balloon after sterilisation cycle', null);
        System.assert(longT.length() <= CqNcReport.TITLE_MAX, 'cut to the limit');
        System.assertEquals(null, CqNcReport.titleOf(null, null));
    }

    @IsTest
    static void cqaisWordingIsSuggestedOrNothing() {
        CqNcReport.mockWording = '  A clearer description.  ';
        System.assertEquals('A clearer description.', CqNcReport.suggestDescription('what I wrote'));
        CqNcReport.mockWording = null;
        System.assertEquals(null, CqNcReport.suggestDescription('what I wrote'), 'no wording when CQ.AI cannot run');
        System.assertEquals(null, CqNcReport.suggestDescription(''));
    }

    @IsTest
    static void createSavesTheNcWithItsLotAndKeepsWhatCqaiSuggested() {
        compliancequest__SQX_Part__c part = makePart();
        CqNcReport.Report r = new CqNcReport.Report();
        r.description = 'CQ.AI wording of the burst test failure.';
        r.asReported = STORY;
        r.usedSuggestion = true;
        r.title = 'Balloon burst below rated pressure at final inspection';
        r.partId = part.Id; r.lot = 'RL26-0915'; r.quantity = 12; r.type = 'Internal'; r.failure = 'Burst below rated pressure';
        r.suggested = new Map<String, String>{ 'Title' => r.title, 'Part' => 'RPT-1000', 'Lot' => 'RL26-0915',
            'Defective Quantity' => '10', 'Type' => 'Internal', 'Failure' => 'Burst below rated pressure' };
        Test.startTest();
        CqNcReport.Created c = CqNcReport.create(JSON.serialize(r));
        Test.stopTest();
        compliancequest__SQX_Nonconformance__c nc = [SELECT compliancequest__NC_Title__c, compliancequest__Description__c, compliancequest__SQX_Part__c,
            compliancequest__Lot_Number__c, compliancequest__Defective_Quantity__c, compliancequest__Defect_Description__c, compliancequest__Type__c
            FROM compliancequest__SQX_Nonconformance__c WHERE Id = :c.id];
        System.assertEquals(r.title, nc.compliancequest__NC_Title__c);
        System.assertEquals(r.description, nc.compliancequest__Description__c, 'the chosen wording is saved');
        System.assertEquals(part.Id, nc.compliancequest__SQX_Part__c);
        System.assertEquals('RL26-0915', nc.compliancequest__Lot_Number__c);
        System.assertEquals(12, nc.compliancequest__Defective_Quantity__c);
        System.assertEquals('Burst below rated pressure', nc.compliancequest__Defect_Description__c);
        System.assertEquals(1, [SELECT COUNT() FROM compliancequest__SQX_NC_Impacted_Product__c WHERE compliancequest__SQX_Nonconformance__c = :c.id],
            'one impacted part and lot');
        System.assertEquals(1, [SELECT COUNT() FROM compliancequest__SQX_Quick_NC__c WHERE compliancequest__SQX_Nonconformance__c = :c.id
            AND compliancequest__Title__c = 'As Reported'], 'the words as reported are kept');
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :c.id], 'the note of CQ.AI\'s suggestions');
        System.assertNotEquals(null, c.name);
    }

    @IsTest
    static void createNeedsADescription() {
        Boolean refused = false;
        try { CqNcReport.create(JSON.serialize(new CqNcReport.Report())); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'no description, no NC');
    }

    @IsTest
    static void mergeAddsTheReportToTheExistingNc() {
        compliancequest__SQX_Part__c part = makePart();
        Id existing = openNcOnLot(part, 'RL26-0915');
        Test.startTest();
        CqNcReport.Created c = CqNcReport.addToExisting(existing, STORY, 12);
        Test.stopTest();
        System.assertEquals(existing, c.id);
        Integer posts = [SELECT COUNT() FROM FeedItem WHERE ParentId = :existing AND Type = 'TextPost'];
        Integer notes = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :existing];
        System.assertEquals(1, posts + notes, 'the report is on the NC as a post (or a note)');
        System.assertEquals(0, [SELECT COUNT() FROM compliancequest__SQX_Nonconformance__c WHERE Id != :existing AND compliancequest__Lot_Number__c = 'RL26-0915'],
            'no new NC');
    }

    @IsTest
    static void aFileIsAttachedToTheNc() {
        compliancequest__SQX_Part__c part = makePart();
        Id existing = openNcOnLot(part, 'RL26-0915');
        CqNcReport.attachFile(existing, 'photo.txt', EncodingUtil.base64Encode(Blob.valueOf('picture')));
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :existing]);
    }
}
