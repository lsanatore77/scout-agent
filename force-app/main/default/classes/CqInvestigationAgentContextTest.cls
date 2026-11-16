@IsTest
private class CqInvestigationAgentContextTest {

    static Map<String, Id> setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Agent Inv Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(Name = 'Agent Inv Part', cqext__Title__c = 'Agent Inv Part',
            compliancequest__Part_Number__c = 'AGI-PART-1', compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(compliancequest__NC_Title__c = 'Hub bond leak', compliancequest__Type__c = 'Internal',
            compliancequest__Type_Of_Issue__c = 'Product', compliancequest__Description_RT__c = '<p>Leak at the hub bond</p>', compliancequest__SQX_Part__c = part.Id,
            compliancequest__Lot_Number__c = 'AGI-LOT-1', compliancequest__Defective_Quantity__c = 4, compliancequest__Occurrence_Date__c = Date.today());
        insert nc;
        compliancequest__SQX_Investigation__c inv = new compliancequest__SQX_Investigation__c(compliancequest__SQX_Nonconformance__c = nc.Id);
        insert inv;
        Investigation_Hypothesis__c h1 = new Investigation_Hypothesis__c(Investigation__c = inv.Id, Number__c = 1, Title__c = 'Worn locating pin on fixture BF-02',
            Category__c = 'Machine', Status__c = 'Open', Source_Name__c = 'Added by You');
        insert h1;
        insert new Investigation_Evidence__c(Investigation__c = inv.Id, Hypothesis__c = h1.Id, Kind__c = 'Test', Test_Type__c = 'Measure or Inspect',
            Status__c = 'Done', Detail__c = 'Gauged the pin', Result__c = 'Pin 0.12 mm under nominal', Supports__c = 'For', Owner__c = UserInfo.getUserId(), Done_On__c = Date.today());
        return new Map<String, Id>{ 'nc' => nc.Id, 'inv' => inv.Id };
    }

    @IsTest
    static void investigationFacts() {
        Map<String, Id> ids = setup();
        Test.startTest();
        String facts = CqQualityAgentContext.factsFor(ids.get('inv'));
        Test.stopTest();
        System.assert(facts.contains('INVESTIGATION ['), facts);
        System.assert(facts.contains('STEP 2 WHAT CHANGED'), facts);
        System.assert(facts.contains('STEP 4 FIND THE CAUSE'), facts);
        System.assert(facts.contains('H1: Worn locating pin on fixture BF-02'), facts);
        System.assert(facts.contains('Pin 0.12 mm under nominal'), facts);
        System.assert(facts.contains('STEP 6 CONCLUSION'), facts);
    }

    @IsTest
    static void ncExtras() {
        Map<String, Id> ids = setup();
        List<String> l = new List<String>();
        Test.startTest();
        CqInvestigationAgentContext.ncExtras(l, ids.get('nc'));
        Test.stopTest();
        String facts = String.join(l, '\n');
        System.assert(facts.contains('HAPPENED BEFORE'), facts);
        System.assert(facts.contains('No earlier NC on the part had the same problem'), facts);
        System.assert(facts.contains('DISPOSITION'), facts);
    }
}
