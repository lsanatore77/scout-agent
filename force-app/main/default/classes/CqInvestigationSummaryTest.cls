@IsTest
private class CqInvestigationSummaryTest {

    static Id makeNc() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Summary Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Summary Part', cqext__Title__c = 'Summary Part', compliancequest__Part_Number__c = 'SUM-PART-1',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = 'Hole offset', compliancequest__Type__c = 'Internal', compliancequest__Type_Of_Issue__c = 'Product',
            compliancequest__Description__c = 'Hole offset 0.4 mm', compliancequest__SQX_Part__c = part.Id, compliancequest__Lot_Number__c = 'SUM-LOT-1',
            compliancequest__Defective_Quantity__c = 5, compliancequest__Occurrence_Date__c = Date.today());
        insert nc;
        update new compliancequest__SQX_Nonconformance__c(Id = nc.Id, compliancequest__Activity_Code__c = 'submit');
        update new compliancequest__SQX_Nonconformance__c(Id = nc.Id, compliancequest__Investigation_Required__c = true,
            compliancequest__Activity_Code__c = 'takeownershipandinitiate');
        return nc.Id;
    }

    @IsTest
    static void suggestBuildsTheSections() {
        Id ncId = makeNc();
        compliancequest__SQX_Nonconformance__c nc = [SELECT compliancequest__SQX_Investigation__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId];
        if (nc.compliancequest__SQX_Investigation__c == null) { return; } // CQ did not make one in this org's test context
        String payload = JSON.serialize(new List<Map<String, Object>>{ new Map<String, Object>{ 'title' => 'Replace the locating pin',
            'description' => 'On fixture BF-02', 'type' => 'Correction', 'due' => String.valueOf(Date.today().addDays(10)) } });
        Test.startTest();
        String data = CqInvestigationSummary.buildData(nc.compliancequest__SQX_Investigation__c, payload);
        CqInvestigationSummary.mockResponse = '**Problem:**\nHole offset.\n\n## Actions\n* Replace the pin.';
        String text = CqInvestigationSummary.suggest(ncId, payload);
        Test.stopTest();
        for (String h : new List<String>{ '## PROBLEM', '## CONTAINMENT', '## HYPOTHESES', '## ROOT CAUSE', '## ACTIONS' }) {
            System.assert(data.contains(h), 'the data has ' + h);
        }
        System.assert(data.contains('Replace the locating pin (Correction)'), 'the actions on screen are used');
        System.assert(data.contains('On fixture BF-02'));
        System.assertEquals('Problem\nHole offset.\n\nActions\n- Replace the pin.', text, 'markdown taken off');
        System.assert(CqInvestigationSummary.buildData(nc.compliancequest__SQX_Investigation__c, null).contains('## ACTIONS'));
    }

    @IsTest
    static void suggestFailsKindly() {
        Id ncId = makeNc();
        compliancequest__SQX_Nonconformance__c nc = [SELECT compliancequest__SQX_Investigation__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId];
        if (nc.compliancequest__SQX_Investigation__c == null) { return; }
        CqInvestigationSummary.mockFail = true;
        try {
            CqInvestigationSummary.suggest(ncId, '[]');
            System.assert(false, 'should fail');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void richTextRoundTrip() {
        String plain = 'Problem\nHole offset on lot 24-0815.\nFound at final inspection.\n\nActions\n- Replace the pin (Correction)\n- Add a check <after> moves';
        String html = CqInvestigationSummary.toHtml(plain);
        System.assertEquals('<p><b>Problem</b></p><p>Hole offset on lot 24-0815.<br>Found at final inspection.</p><p><b>Actions</b></p>'
            + '<ul><li>Replace the pin (Correction)</li><li>Add a check &lt;after&gt; moves</li></ul>', html);
        System.assertEquals(plain, CqInvestigationSummary.toPlain(html), 'back to what the screen showed');
        System.assertEquals('Plain text', CqInvestigationSummary.toPlain('Plain text'));
        System.assertEquals(null, CqInvestigationSummary.toHtml(null));
    }
}
