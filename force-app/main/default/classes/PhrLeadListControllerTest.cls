@IsTest
private class PhrLeadListControllerTest {

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

    static Id phrId() {
        return [SELECT Id FROM compliancequest__SQX_Product_History_Review__c LIMIT 1].Id;
    }

    /** Stores every lead, adding only the first NC; returns the Ids of both NCs. */
    static List<Id> storeLeadsAddingOne() {
        compliancequest__SQX_Nonconformance__c a = newNc('Fluid leak at the seal of the valve', partId('REL-OWN'), null);
        compliancequest__SQX_Nonconformance__c b = newNc('Label misprint on carton', partId('REL-OWN'), null);
        insert new List<compliancequest__SQX_Nonconformance__c>{ a, b };
        PhrLeadAddAction.Request req = new PhrLeadAddAction.Request();
        req.recordId = [SELECT Id FROM compliancequest__SQX_Complaint__c LIMIT 1].Id;
        req.selectedRecordIds = new List<String>{ String.valueOf(a.Id) };
        PhrLeadAddAction.Response r = PhrLeadAddAction.run(new List<PhrLeadAddAction.Request>{ req })[0];
        System.assertEquals(true, r.success, r.summary);
        return new List<Id>{ a.Id, b.Id };
    }

    @IsTest
    static void getLeadsReturnsEveryStoredLeadWithItsAddedState() {
        List<Id> ncs = storeLeadsAddingOne();
        List<PhrLeadListController.LeadRow> rows = PhrLeadListController.getLeads(phrId());
        System.assertEquals(2, rows.size());
        Integer added = 0;
        for (PhrLeadListController.LeadRow r : rows) {
            if (r.added) { added++; System.assertEquals('Added', r.addedLabel); }
            else { System.assertEquals('Not added', r.addedLabel); }
            System.assert(String.isNotBlank(r.recordNumber));
            System.assertEquals('/' + r.recordId, r.link);
        }
        System.assertEquals(1, added);
    }

    @IsTest
    static void addLeadsAddsANotAddedLeadOnce() {
        List<Id> ncs = storeLeadsAddingOne();
        Id notAdded = [SELECT Id FROM PHR_Lead__c WHERE Added__c = false LIMIT 1].Id;
        Integer before = [SELECT COUNT() FROM compliancequest__SQX_Related_Product__c];
        PhrLeadListController.AddResult res = PhrLeadListController.addLeads(phrId(), new List<Id>{ notAdded });
        System.assertEquals(true, res.success, res.message);
        System.assertEquals(1, res.added);
        System.assertEquals(before + 1, [SELECT COUNT() FROM compliancequest__SQX_Related_Product__c]);
        System.assertEquals(true, [SELECT Added__c FROM PHR_Lead__c WHERE Id = :notAdded].Added__c);

        // Asking again adds nothing more.
        PhrLeadListController.AddResult again = PhrLeadListController.addLeads(phrId(), new List<Id>{ notAdded });
        System.assertEquals(0, again.added);
        System.assertEquals(before + 1, [SELECT COUNT() FROM compliancequest__SQX_Related_Product__c]);
    }

    @IsTest
    static void addLeadsWithNothingSelectedReturnsAMessage() {
        PhrLeadListController.AddResult res = PhrLeadListController.addLeads(phrId(), new List<Id>());
        System.assertEquals(false, res.success);
        System.assert(String.isNotBlank(res.message));
    }

    @IsTest
    static void investigationLeadsFollowTheLinkedComplaint() {
        storeLeadsAddingOne();
        List<compliancequest__SQX_Linked_Investigation__c> links = [
            SELECT compliancequest__SQX_Investigation__c FROM compliancequest__SQX_Linked_Investigation__c
            WHERE compliancequest__SQX_Complaint__c IN (
                SELECT compliancequest__SQX_Complaint__c FROM compliancequest__SQX_Product_History_Review__c WHERE Id = :phrId())
            LIMIT 1
        ];
        if (!links.isEmpty()) {
            List<PhrLeadListController.LeadRow> rows = PhrLeadListController.getLeadsForInvestigation(links[0].compliancequest__SQX_Investigation__c);
            System.assertEquals(2, rows.size());
            System.assert(String.isNotBlank(rows[0].phrName));
        }
    }

    @IsTest
    static void investigationWithNoLinkedComplaintHasNoLeads() {
        String prefix = compliancequest__SQX_Investigation__c.SObjectType.getDescribe().getKeyPrefix();
        Id none = Id.valueOf(prefix + '000000000001');
        System.assertEquals(0, PhrLeadListController.getLeadsForInvestigation(none).size());
    }
}
