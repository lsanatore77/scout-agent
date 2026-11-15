@IsTest
private class CqQualityAgentContextTest {

    @IsTest
    static void noRecord() {
        CqQualityAgentContext.Request req = new CqQualityAgentContext.Request();
        List<CqQualityAgentContext.Response> out = CqQualityAgentContext.run(new List<CqQualityAgentContext.Request>{ req });
        System.assert(out[0].facts.contains('No record was given'), out[0].facts);
    }

    @IsTest
    static void otherObject() {
        String facts = CqQualityAgentContext.factsFor(UserInfo.getUserId());
        System.assert(facts.contains('only reads nonconformances'), facts);
    }

    @IsTest
    static void factsForAnNcInTriage() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Quality Agent Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Quality Agent Part', cqext__Title__c = 'Quality Agent Part', compliancequest__Part_Number__c = 'QA-AGENT-1',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        compliancequest__SQX_Nonconformance__c nc = nc('Seal open at packaging', part.Id);
        compliancequest__SQX_Nonconformance__c other = nc('Seal width low', part.Id);
        insert new List<compliancequest__SQX_Nonconformance__c>{ nc, other };
        nc.Triage_Draft__c = '{"v":1,"step":2,"maxStep":3,"acts":{"hold":true},"due":"2026-12-01","added":[],"data":"ask",'
            + '"asks":{"More photos":true},"askNote":"Need a close-up","sev":4,"lik":2,"picks":{},"extra":[]}';
        update nc;

        Test.startTest();
        String facts = CqQualityAgentContext.factsFor(nc.Id);
        Test.stopTest();

        System.assert(facts.contains('NONCONFORMANCE ['), facts);
        System.assert(facts.contains('Triage is in progress'), facts);
        System.assert(facts.contains('The step open now is Data Check'), facts);
        System.assert(facts.contains('Chosen in triage so far: Hold lot QA-LOT-1'), facts);
        System.assert(facts.contains('Request more information (More photos). Note: Need a close-up'), facts);
        System.assert(facts.contains('CQ.AI Suggests risk'), facts);
        System.assert(facts.contains('FIELD ACTION REVIEW'), facts);
        System.assert(facts.contains('(same lot)'), facts);
        System.assertEquals(1, [SELECT COUNT() FROM compliancequest__SQX_Nonconformance__c WHERE Id = :nc.Id AND Triage_Risk__c = null]);
    }

    static compliancequest__SQX_Nonconformance__c nc(String title, Id partId) {
        return new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = title, compliancequest__Type__c = 'Internal', compliancequest__Type_Of_Issue__c = 'Product',
            compliancequest__Description__c = title, compliancequest__SQX_Part__c = partId, compliancequest__Lot_Number__c = 'QA-LOT-1',
            compliancequest__Occurrence_Date__c = Date.today());
    }

    @IsTest
    static void relevantRecordsSameLotThenOpenThenNewest() {
        Datetime now = Datetime.now();
        Id fake = compliancequest__SQX_Nonconformance__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
        List<CqQualityAgentContext.Row> rows = new List<CqQualityAgentContext.Row>{
            new CqQualityAgentContext.Row(fake, 'A', null, 'Closed', 'L1', now, 'L1', 'compliancequest__SQX_Nonconformance__c'),
            new CqQualityAgentContext.Row(fake, 'B', null, 'Open', 'L2', now.addDays(-5), 'L1', 'compliancequest__SQX_Nonconformance__c'),
            new CqQualityAgentContext.Row(fake, 'C', null, 'Open', 'L2', now, 'L1', 'compliancequest__SQX_Nonconformance__c'),
            new CqQualityAgentContext.Row(fake, 'D', null, 'Draft', 'L1', now.addDays(-9), 'L1', 'compliancequest__SQX_Nonconformance__c')
        };
        List<String> l = new List<String>();
        CqQualityAgentContext.section(l, 'Other NCs', rows, 'L1');
        System.assert(l[0].startsWith('Other NCs: 4 (3 open, 2 on lot L1)'), l[0]);
        System.assert(l[1].startsWith('- [D]'), l[1]);
        System.assert(l[1].contains('(same lot)'), l[1]);
        System.assert(l[2].startsWith('- [A]'), l[2]);
        System.assert(l[3].startsWith('- [C]'), l[3]);
        System.assert(l[4].startsWith('- [B]'), l[4]);
    }
}
