@IsTest
private class PhrQmsPanelControllerTest {

    // This class tests the original ranking, kept as the fallback.
    // PhrQmsRelevanceTest covers the relevance model.
    static {
        PhrQmsRelevanceSettings.useNewModel = false;
    }

    @TestSetup
    static void setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'PHR Panel Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'PHR Panel Part',
            cqext__Title__c = 'PHR Panel Part',
            compliancequest__Part_Number__c = 'TST-PHR-001',
            compliancequest__Part_Family__c = fam.Id,
            compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true,
            cqext__Part_Definition__c = 'Individual');
        insert part;
        compliancequest__SQX_Part__c other = new compliancequest__SQX_Part__c(
            Name = 'PHR Panel Other Part',
            cqext__Title__c = 'PHR Panel Other Part',
            compliancequest__Part_Number__c = 'TST-PHR-002',
            compliancequest__Part_Family__c = fam.Id,
            compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true,
            cqext__Part_Definition__c = 'Individual');
        insert other;

        compliancequest__SQX_Complaint__c complaint = new compliancequest__SQX_Complaint__c(
            compliancequest__Complaint_Title__c = 'PHR panel test complaint',
            compliancequest__Description__c = 'PHR panel test complaint description',
            compliancequest__SQX_Part__c = part.Id,
            compliancequest__Country_of_Origin__c = 'US',
            compliancequest__Aware_Date__c = Date.today(),
            compliancequest__Occurrence_Date__c = Date.today(),
            compliancequest__Reported_Date__c = Date.today(),
            compliancequest__Lot_Number__c = ' Lot-PHR-1 ');
        insert complaint;

        insert new compliancequest__SQX_Product_History_Review__c(
            compliancequest__SQX_Complaint__c = complaint.Id,
            compliancequest__Completed_By__c = 'Test Reviewer');

        insert new List<compliancequest__SQX_Nonconformance__c>{
            newNc('Part match NC', part.Id, null),
            newNc('Lot match NC', other.Id, 'LOT-PHR-1')
        };
    }

    static compliancequest__SQX_Nonconformance__c newNc(String title, Id partId, String lot) {
        return new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = title,
            compliancequest__Type__c = 'Internal',
            compliancequest__Type_Of_Issue__c = 'Product',
            compliancequest__Description__c = title + ' description',
            compliancequest__SQX_Part__c = partId,
            compliancequest__Lot_Number__c = lot,
            compliancequest__Occurrence_Date__c = Date.today());
    }

    static compliancequest__SQX_Product_History_Review__c phr() {
        return [SELECT Id FROM compliancequest__SQX_Product_History_Review__c LIMIT 1];
    }

    static compliancequest__SQX_Complaint__c complaint() {
        return [SELECT Id FROM compliancequest__SQX_Complaint__c LIMIT 1];
    }

    @IsTest
    static void panelData_fromPhr_findsPartAndLotMatches() {
        Test.startTest();
        PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(phr().Id, null);
        Test.stopTest();

        System.assertEquals(true, d.success, 'error: ' + d.errorMessage);
        System.assertEquals('TST-PHR-001', d.partNumber);
        System.assertEquals('Lot-PHR-1', d.lotNumber, 'lot is trimmed');
        System.assertEquals(2, d.nonconformances.size(), 'part match plus case-insensitive lot match');
        Set<String> matches = new Set<String>();
        for (PhrQmsPanelController.Row r : d.nonconformances) {
            matches.add(r.matchedBy);
            System.assertEquals(false, r.alreadyAdded);
        }
        System.assert(matches.contains('Part'), 'part-matched NC present');
        System.assert(matches.contains('Lot'), 'lot-matched NC present');
    }

    @IsTest
    static void panelData_fromComplaint_resolvesPhr() {
        PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(complaint().Id, null);
        System.assertEquals(true, d.success, 'error: ' + d.errorMessage);
        System.assertEquals(phr().Id, d.phrId);
        System.assertEquals(complaint().Id, d.complaintId);
    }

    @IsTest
    static void panelData_lotOverride_replacesComplaintLot() {
        PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(phr().Id, 'NO-SUCH-LOT');
        System.assertEquals(true, d.success, 'error: ' + d.errorMessage);
        System.assertEquals('NO-SUCH-LOT', d.lotNumber);
        System.assertEquals(1, d.nonconformances.size(), 'only the part match remains');
        System.assertEquals('Part', d.nonconformances[0].matchedBy);
    }

    @IsTest
    static void panelData_unsupportedRecord_returnsError() {
        PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(UserInfo.getUserId(), null);
        System.assertEquals(false, d.success);
        System.assertNotEquals(null, d.errorMessage);
        PhrQmsPanelController.PanelData none = PhrQmsPanelController.getPanelData(null, null);
        System.assertEquals(false, none.success);
    }

    @IsTest
    static void createRelatedRecords_addsRowsOnceAndFlagsThem() {
        PhrQmsPanelController.PanelData before = PhrQmsPanelController.getPanelData(phr().Id, null);
        List<Id> ncIds = new List<Id>();
        for (PhrQmsPanelController.Row r : before.nonconformances) {
            ncIds.add(r.id);
        }

        Test.startTest();
        PhrQmsPanelController.CreateResult first = PhrQmsPanelController.createRelatedRecords(
            phr().Id, ncIds, null, null, null, null);
        PhrQmsPanelController.CreateResult second = PhrQmsPanelController.createRelatedRecords(
            phr().Id, ncIds, null, null, null, null);
        Test.stopTest();

        System.assertEquals(true, first.success, 'first: ' + first.message);
        System.assertEquals(2, first.relatedProductsCreated);
        System.assertEquals(0, second.relatedProductsCreated, 'duplicates are not created');
        System.assertEquals(2, second.skipped);
        System.assertEquals(2, [SELECT COUNT() FROM compliancequest__SQX_Related_Product__c
            WHERE compliancequest__SQX_Product_History_Review__c = :phr().Id]);

        PhrQmsPanelController.PanelData after = PhrQmsPanelController.getPanelData(phr().Id, null);
        for (PhrQmsPanelController.Row r : after.nonconformances) {
            System.assertEquals(true, r.alreadyAdded, 'rows now flagged as added');
        }
    }

    @IsTest
    static void createRelatedRecords_withoutPhr_returnsError() {
        delete [SELECT Id FROM compliancequest__SQX_Product_History_Review__c];
        List<Id> ncIds = new List<Id>{ [SELECT Id FROM compliancequest__SQX_Nonconformance__c LIMIT 1].Id };
        PhrQmsPanelController.CreateResult r = PhrQmsPanelController.createRelatedRecords(
            complaint().Id, ncIds, null, null, null, null);
        System.assertEquals(false, r.success);
        System.assert(r.message.contains('no Product History Review'), r.message);
    }

    @IsTest
    static void createRelatedRecords_emptySelection_isNoOp() {
        PhrQmsPanelController.CreateResult r = PhrQmsPanelController.createRelatedRecords(
            phr().Id, null, null, null, null, null);
        System.assertEquals(true, r.success, r.message);
        System.assertEquals(0, r.relatedProductsCreated);
        System.assertEquals(0, r.linkedInvestigationsCreated);
    }

    @IsTest
    static void action_previewThenApply() {
        PhrQmsRelatedRecordsAction.Request req = new PhrQmsRelatedRecordsAction.Request();
        req.recordId = complaint().Id;

        PhrQmsRelatedRecordsAction.Response preview =
            PhrQmsRelatedRecordsAction.run(new List<PhrQmsRelatedRecordsAction.Request>{ req })[0];
        System.assertEquals(true, preview.success, preview.summary);
        System.assertEquals(false, preview.applied);
        System.assert(preview.summary.contains('Preview only'), preview.summary);
        System.assertEquals(0, [SELECT COUNT() FROM compliancequest__SQX_Related_Product__c], 'preview writes nothing');

        req.mode = 'apply';
        PhrQmsRelatedRecordsAction.Response applied =
            PhrQmsRelatedRecordsAction.run(new List<PhrQmsRelatedRecordsAction.Request>{ req })[0];
        System.assertEquals(true, applied.success, applied.summary);
        System.assertEquals(true, applied.applied);
        System.assertEquals(2, [SELECT COUNT() FROM compliancequest__SQX_Related_Product__c]);
    }

    @IsTest
    static void action_badRecord_reportsFailureWithoutThrowing() {
        PhrQmsRelatedRecordsAction.Request req = new PhrQmsRelatedRecordsAction.Request();
        req.recordId = UserInfo.getUserId();
        PhrQmsRelatedRecordsAction.Response res =
            PhrQmsRelatedRecordsAction.run(new List<PhrQmsRelatedRecordsAction.Request>{ req })[0];
        System.assertEquals(false, res.success);
        System.assertNotEquals(null, res.summary);
    }

    @IsTest
    static void ranking_partAndLotOutranksLotOutranksPart_andFlagsNewRows() {
        compliancequest__SQX_Part__c part = [SELECT Id FROM compliancequest__SQX_Part__c
            WHERE compliancequest__Part_Number__c = 'TST-PHR-001' LIMIT 1];
        insert newNc('Part and Lot NC', part.Id, 'lot-phr-1');

        PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(phr().Id, null);
        System.assertEquals(true, d.success, 'error: ' + d.errorMessage);
        System.assertEquals(3, d.nonconformances.size());
        System.assertEquals('Part and Lot', d.nonconformances[0].matchedBy, 'combo match first');
        System.assertEquals('Lot', d.nonconformances[1].matchedBy);
        System.assertEquals('Part', d.nonconformances[2].matchedBy);
        for (PhrQmsPanelController.Row r : d.nonconformances) {
            System.assertEquals(true, r.isNew, 'created just now');
            System.assertNotEquals(null, r.createdDate);
        }
        System.assertEquals(true, d.nonconformances[0].highlight);
        System.assert(d.nonconformances[0].score > d.nonconformances[1].score);
        System.assert(d.nonconformances[1].score > d.nonconformances[2].score);
    }

    @IsTest
    static void ranking_scoreAndSortRules() {
        // Match type outweighs recency and status.
        System.assert(PhrQmsPanelController.score('Part and Lot', false, 'Closed')
            > PhrQmsPanelController.score('Lot', true, 'Open'));
        System.assert(PhrQmsPanelController.score('Lot', false, 'Closed')
            > PhrQmsPanelController.score('Part', true, 'Open'));
        // Within a tier, recent and open rows score higher.
        System.assert(PhrQmsPanelController.score('Part', true, 'Open')
            > PhrQmsPanelController.score('Part', false, 'Open'));
        System.assert(PhrQmsPanelController.score('Part', false, 'Open')
            > PhrQmsPanelController.score('Part', false, 'Closed'));
        System.assertEquals(0, PhrQmsPanelController.score(null, false, 'Closed'));
        System.assertEquals(true, PhrQmsPanelController.isOpenStatus(null));
        System.assertEquals(true, PhrQmsPanelController.isOpenStatus('Draft'));
        System.assertEquals(false, PhrQmsPanelController.isOpenStatus(' Closed '));

        // Same score: newest first; old rows are not "new"; highlight is capped.
        List<PhrQmsPanelController.Row> rows = new List<PhrQmsPanelController.Row>();
        for (Integer i = 0; i < 5; i++) {
            PhrQmsPanelController.Row r = new PhrQmsPanelController.Row();
            r.name = 'R' + i;
            r.matchedBy = 'Part';
            r.status = 'Open';
            r.createdDate = Datetime.now().addDays(-(PhrQmsPanelController.NEW_WINDOW_DAYS + 10 + i));
            rows.add(r);
        }
        rows[4].createdDate = Datetime.now().addDays(-1);
        PhrQmsPanelController.rank(rows);
        System.assertEquals('R4', rows[0].name, 'recent row sorts first');
        System.assertEquals(true, rows[0].isNew);
        System.assertEquals(false, rows[1].isNew);
        System.assertEquals('R0', rows[1].name, 'then newest of the older rows');
        System.assertEquals(true, rows[0].highlight);
        System.assertEquals(false, rows[1].highlight, 'part-only and not new is not highlighted');
    }

    @IsTest
    static void helpers_behaveAsDocumented() {
        System.assertEquals('Part', PhrQmsPanelController.matchedBy(true, false));
        System.assertEquals('Lot', PhrQmsPanelController.matchedBy(false, true));
        System.assertEquals('Part and Lot', PhrQmsPanelController.matchedBy(true, true));
        System.assertEquals(null, PhrQmsPanelController.matchedBy(false, false));

        System.assertEquals(true, PhrQmsPanelController.lotHit(new Set<String>{ 'ABC-1' }, ' abc-1 '));
        System.assertEquals(false, PhrQmsPanelController.lotHit(new Set<String>{ 'ABC-1' }, 'ABC-2'));
        System.assertEquals(false, PhrQmsPanelController.lotHit(new Set<String>{ 'ABC-1' }, null));

        System.assertEquals('change order|co-1', PhrQmsPanelController.refKey('Change Order', 'CO-1'));

        Id complaintId = '001000000000001AAA';
        System.assertEquals(true, PhrQmsPanelController.isOwnInvestigation(complaintId, complaintId, null));
        System.assertEquals(true, PhrQmsPanelController.isOwnInvestigation(complaintId, null, '001000000000001'));
        System.assertEquals(false, PhrQmsPanelController.isOwnInvestigation(complaintId, null, null));
        System.assertEquals(false, PhrQmsPanelController.isOwnInvestigation(null, complaintId, null));
    }
}
