@IsTest
private class PhrLeadAddActionTest {

    static final String LOT = 'LOT-REL-1';
    @TestSetup
    static void setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Relevance Family');
        insert fam;
        compliancequest__SQX_Part__c own = newPart('Relevance Product', 'REL-OWN', fam.Id);
        compliancequest__SQX_Part__c comp = newPart('Relevance Component', 'REL-COMP', fam.Id);
        compliancequest__SQX_Part__c other = newPart('Relevance Other Product', 'REL-OTHER', fam.Id);
        compliancequest__SQX_Part__c control = newPart('Relevance Control', 'REL-CONTROL', fam.Id);
        insert new List<compliancequest__SQX_Part__c>{ own, comp, other, control };

        // BOM: the product and another product both use the component.
        cqext__CQPLM_Assembly_Type__c asmType = new cqext__CQPLM_Assembly_Type__c(Name = 'BOM');
        insert asmType;
        cqext__CQPLM_Part_Revision__c ownRev = new cqext__CQPLM_Part_Revision__c(cqext__CQPLM_Part__c = own.Id);
        cqext__CQPLM_Part_Revision__c otherRev = new cqext__CQPLM_Part_Revision__c(cqext__CQPLM_Part__c = other.Id);
        insert new List<cqext__CQPLM_Part_Revision__c>{ ownRev, otherRev };
        // A flow may already create the assembly when a revision is inserted; add one only where it is missing.
        Map<Id, Id> asmByRev = new Map<Id, Id>();
        for (cqext__CQPLM_Assembly__c a : [
            SELECT Id, cqext__CQPLM_Part_Revision__c FROM cqext__CQPLM_Assembly__c
            WHERE cqext__CQPLM_Part_Revision__c IN :new Set<Id>{ ownRev.Id, otherRev.Id }
        ]) {
            asmByRev.put(a.cqext__CQPLM_Part_Revision__c, a.Id);
        }
        List<cqext__CQPLM_Assembly__c> newAsms = new List<cqext__CQPLM_Assembly__c>();
        for (Id revId : new List<Id>{ ownRev.Id, otherRev.Id }) {
            if (!asmByRev.containsKey(revId)) {
                newAsms.add(new cqext__CQPLM_Assembly__c(
                    cqext__CQPLM_Part_Revision__c = revId, cqext__CQPLM_Assembly_Type__c = asmType.Id));
            }
        }
        insert newAsms;
        for (cqext__CQPLM_Assembly__c a : newAsms) {
            asmByRev.put(a.cqext__CQPLM_Part_Revision__c, a.Id);
        }
        insert new List<cqext__CQPLM_Assembly_line_Item__c>{
            new cqext__CQPLM_Assembly_line_Item__c(cqext__CQPLM_Assembly__c = asmByRev.get(ownRev.Id),
                cqext__CQPLM_Part__c = comp.Id, cqext__Quantity__c = 1),
            new cqext__CQPLM_Assembly_line_Item__c(cqext__CQPLM_Assembly__c = asmByRev.get(otherRev.Id),
                cqext__CQPLM_Part__c = comp.Id, cqext__Quantity__c = 1)
        };

        compliancequest__SQX_Complaint__c complaint = new compliancequest__SQX_Complaint__c(
            compliancequest__Complaint_Title__c = 'Valve leaks fluid at the seal',
            compliancequest__Description__c = 'Fluid leak observed at the seal during use',
            compliancequest__SQX_Part__c = own.Id,
            compliancequest__Country_of_Origin__c = 'US',
            compliancequest__Aware_Date__c = Date.today(),
            compliancequest__Occurrence_Date__c = Date.today(),
            compliancequest__Reported_Date__c = Date.today(),
            compliancequest__Lot_Number__c = LOT);
        insert complaint;
        insert new compliancequest__SQX_Product_History_Review__c(
            compliancequest__SQX_Complaint__c = complaint.Id,
            compliancequest__Completed_By__c = 'Test Reviewer');
    }

    static compliancequest__SQX_Part__c newPart(String name, String partNo, Id familyId) {
        return new compliancequest__SQX_Part__c(
            Name = name, cqext__Title__c = name, compliancequest__Part_Number__c = partNo,
            compliancequest__Part_Family__c = familyId, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
    }

    static compliancequest__SQX_Nonconformance__c newNc(String title, Id partId, String lot) {
        return new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = title,
            compliancequest__Type__c = 'Internal',
            compliancequest__Type_Of_Issue__c = 'Product',
            compliancequest__Description__c = title,
            compliancequest__SQX_Part__c = partId,
            compliancequest__Lot_Number__c = lot,
            compliancequest__Occurrence_Date__c = Date.today());
    }

    static Id partId(String partNo) {
        return [SELECT Id FROM compliancequest__SQX_Part__c WHERE compliancequest__Part_Number__c = :partNo LIMIT 1].Id;
    }

    static PhrLeadAddAction.Response run(List<String> selected) {
        PhrLeadAddAction.Request req = new PhrLeadAddAction.Request();
        req.recordId = [SELECT Id FROM compliancequest__SQX_Complaint__c LIMIT 1].Id;
        req.selectedRecordIds = selected;
        List<PhrLeadAddAction.Response> out = PhrLeadAddAction.run(new List<PhrLeadAddAction.Request>{ req });
        System.assertEquals(1, out.size());
        return out[0];
    }

    static Map<String, PHR_Lead__c> leadsById() {
        Map<String, PHR_Lead__c> m = new Map<String, PHR_Lead__c>();
        for (PHR_Lead__c l : [SELECT Record_Id__c, Added__c, Tier__c, Colour__c, Record_Title__c, Record_Type__c FROM PHR_Lead__c]) {
            m.put(l.Record_Id__c, l);
        }
        return m;
    }

    static Integer relatedProducts() {
        return [SELECT COUNT() FROM compliancequest__SQX_Related_Product__c];
    }

    @IsTest
    static void blankSelectionAddsEveryLeadAndStoresThemAll() {
        compliancequest__SQX_Nonconformance__c a = newNc('Fluid leak at the seal of the valve', partId('REL-OWN'), null);
        compliancequest__SQX_Nonconformance__c b = newNc('Label misprint on carton', partId('REL-OWN'), null);
        insert new List<compliancequest__SQX_Nonconformance__c>{ a, b };
        PhrLeadAddAction.Response r = run(null);
        System.assertEquals(true, r.success, '' + r.summary);
        System.assertEquals(2, r.recordsAdded);
        System.assertEquals(2, relatedProducts());
        Map<String, PHR_Lead__c> m = leadsById();
        System.assertEquals(2, m.size());
        System.assertEquals(true, m.get(String.valueOf(a.Id)).Added__c);
        System.assertEquals(true, m.get(String.valueOf(b.Id)).Added__c);
        System.assertEquals('Red', m.get(String.valueOf(a.Id)).Colour__c);
        System.assertEquals('Fluid leak at the seal of the valve', m.get(String.valueOf(a.Id)).Record_Title__c);
        System.assertEquals('Nonconformance', m.get(String.valueOf(a.Id)).Record_Type__c);
        System.assertNotEquals(null, m.get(String.valueOf(a.Id)).Tier__c);
    }

    @IsTest
    static void unticked_isStoredNotAdded_andCanBeAddedLaterWithoutDuplicates() {
        compliancequest__SQX_Nonconformance__c a = newNc('Fluid leak at the seal of the valve', partId('REL-OWN'), null);
        compliancequest__SQX_Nonconformance__c b = newNc('Label misprint on carton', partId('REL-OWN'), null);
        insert new List<compliancequest__SQX_Nonconformance__c>{ a, b };

        PhrLeadAddAction.Response r1 = run(new List<String>{ String.valueOf(a.Id) });
        System.assertEquals(true, r1.success, '' + r1.summary);
        System.assertEquals(1, r1.recordsAdded);
        System.assertEquals(1, relatedProducts());
        Map<String, PHR_Lead__c> m = leadsById();
        System.assertEquals(2, m.size(), 'both stored');
        System.assertEquals(true, m.get(String.valueOf(a.Id)).Added__c);
        System.assertEquals(false, m.get(String.valueOf(b.Id)).Added__c);

        PhrLeadAddAction.Response r2 = run(new List<String>{ String.valueOf(b.Id) });
        System.assertEquals(true, r2.success, '' + r2.summary);
        System.assertEquals(2, relatedProducts());
        m = leadsById();
        System.assertEquals(2, m.size(), 'no duplicate lead rows');
        System.assertEquals(true, m.get(String.valueOf(a.Id)).Added__c, 'stays added');
        System.assertEquals(true, m.get(String.valueOf(b.Id)).Added__c);
    }

    @IsTest
    static void junkIdsAreIgnored() {
        compliancequest__SQX_Nonconformance__c a = newNc('Fluid leak at the seal of the valve', partId('REL-OWN'), null);
        insert a;
        PhrLeadAddAction.Response r = run(new List<String>{ 'not-an-id', '', String.valueOf(partId('REL-OWN')) });
        System.assertEquals(true, r.success, '' + r.summary);
        System.assertEquals(0, r.recordsAdded);
        System.assertEquals(0, relatedProducts());
        System.assertEquals(1, leadsById().size(), 'the lead is still stored');
    }

    @IsTest
    static void badRecordIdReturnsAnErrorNotAnException() {
        PhrLeadAddAction.Request req = new PhrLeadAddAction.Request();
        req.recordId = [SELECT Id FROM compliancequest__SQX_Part__c LIMIT 1].Id;
        PhrLeadAddAction.Response r = PhrLeadAddAction.run(new List<PhrLeadAddAction.Request>{ req })[0];
        System.assertEquals(false, r.success);
        System.assert(String.isNotBlank(r.summary));
    }
}
