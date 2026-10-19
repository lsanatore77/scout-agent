@IsTest
private class PhrLeadPackageActionTest {

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

    static PhrLeadPackageData run() {
        PhrLeadPackageAction.Request req = new PhrLeadPackageAction.Request();
        req.recordId = [SELECT Id FROM compliancequest__SQX_Complaint__c LIMIT 1].Id;
        List<PhrLeadPackageAction.ActionResponse> out = PhrLeadPackageAction.run(
            new List<PhrLeadPackageAction.Request>{ req });
        System.assertEquals(1, out.size());
        return out[0].leadPackage;
    }

    @IsTest
    static void returnsRankedSectionsWithTitlesColourAndRating() {
        insert new List<compliancequest__SQX_Nonconformance__c>{
            newNc('Fluid leak at the seal of the valve', partId('REL-OWN'), null),
            newNc('Label misprint on carton', partId('REL-OWN'), null)
        };
        Test.startTest();
        PhrLeadPackageData p = run();
        Test.stopTest();
        System.assertEquals(true, p.success, '' + p.errorMessage);
        System.assertEquals(1, p.sections.size());
        PhrLeadSection s = p.sections[0];
        System.assertEquals('Nonconformances', s.title);
        System.assertEquals(2, s.rows.size());
        System.assertEquals('Red', s.rows[0].colour);
        System.assertEquals('Fluid leak at the seal of the valve', s.rows[0].title);
        System.assertNotEquals(null, s.rows[0].name);
        System.assertNotEquals('None', p.overallRating);
        System.assertNotEquals(null, p.overallScore);
        System.assert(String.isNotBlank(p.intro));
    }

    @IsTest
    static void lotMatchRaisesTheOverallScore() {
        insert newNc('Fluid leak at the seal of the valve', partId('REL-OWN'), LOT);
        PhrLeadPackageData p = run();
        System.assertEquals(true, p.success, '' + p.errorMessage);
        System.assert(p.overallScore >= 40, 'lot match plus a strong lead is at least Medium: ' + p.overallScore);
    }

    @IsTest
    static void ratingBands() {
        System.assertEquals('None', PhrLeadPackageAction.rating(0));
        System.assertEquals('Low', PhrLeadPackageAction.rating(39));
        System.assertEquals('Medium', PhrLeadPackageAction.rating(40));
        System.assertEquals('Medium', PhrLeadPackageAction.rating(59));
        System.assertEquals('High', PhrLeadPackageAction.rating(60));
        System.assertEquals(0, PhrLeadPackageAction.overallScore(new List<PhrQmsPanelController.Row>()));
    }

    @IsTest
    static void badRecordIdReturnsAnErrorNotAnException() {
        PhrLeadPackageAction.Request req = new PhrLeadPackageAction.Request();
        req.recordId = [SELECT Id FROM compliancequest__SQX_Part__c LIMIT 1].Id;
        PhrLeadPackageData p = PhrLeadPackageAction.run(new List<PhrLeadPackageAction.Request>{ req })[0].leadPackage;
        System.assertEquals(false, p.success);
        System.assert(String.isNotBlank(p.errorMessage));
    }
}
