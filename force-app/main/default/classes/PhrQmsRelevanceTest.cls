@IsTest
private class PhrQmsRelevanceTest {

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

    static PhrQmsPanelController.PanelData data() {
        Id complaintId = [SELECT Id FROM compliancequest__SQX_Complaint__c LIMIT 1].Id;
        PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(complaintId, null);
        System.assertEquals(true, d.success, 'error: ' + d.errorMessage);
        return d;
    }

    static PhrQmsPanelController.Row byName(List<PhrQmsPanelController.Row> rows, Id id) {
        for (PhrQmsPanelController.Row r : rows) {
            if (r.id == id) { return r; }
        }
        return null;
    }

    // ---------- Own part ----------

    @IsTest
    static void ownPart_symptomMatchIsRed_unrelatedIsYellow_andRedRanksFirst() {
        compliancequest__SQX_Nonconformance__c strong = newNc('Fluid leak at the seal of the valve', partId('REL-OWN'), null);
        compliancequest__SQX_Nonconformance__c weak = newNc('Label misprint on carton', partId('REL-OWN'), null);
        insert new List<compliancequest__SQX_Nonconformance__c>{ weak, strong };

        PhrQmsPanelController.PanelData d = data();
        System.assertEquals('v2', d.relevanceModel);
        PhrQmsPanelController.Row s = byName(d.nonconformances, strong.Id);
        PhrQmsPanelController.Row w = byName(d.nonconformances, weak.Id);
        System.assertNotEquals(null, s, 'symptom match is a lead');
        System.assertNotEquals(null, w, 'own part, open and recent is still a lead');
        System.assertEquals('Red', s.colour);
        System.assertEquals('Yellow', w.colour);
        System.assert(s.score > w.score, 'colour outranks');
        System.assertEquals(strong.Id, d.nonconformances[0].id, 'best first');
        System.assertEquals('Own part', s.relatedBy);
        System.assert(s.criteriaMet.contains('Symptom'));
        System.assert(!w.criteriaMet.contains('Symptom'));
    }

    @IsTest
    static void scoreWithinAColour_separatesStrongFromLoose() {
        compliancequest__SQX_Nonconformance__c strong = newNc('Fluid leak at the seal of the valve', partId('REL-OWN'), null);
        compliancequest__SQX_Nonconformance__c loose = newNc('Seal leak noted', partId('REL-OWN'), null);
        insert new List<compliancequest__SQX_Nonconformance__c>{ loose, strong };

        PhrQmsPanelController.PanelData d = data();
        PhrQmsPanelController.Row s = byName(d.nonconformances, strong.Id);
        PhrQmsPanelController.Row l = byName(d.nonconformances, loose.Id);
        System.assertEquals('Red', s.colour);
        System.assertEquals('Red', l.colour);
        System.assert(s.relevance > l.relevance, 'two reds differ by score');
        System.assert(s.relevance <= 100);
    }

    @IsTest
    static void lotMatch_isAlwaysALead_evenOnAnUnrelatedPart() {
        compliancequest__SQX_Nonconformance__c lotNc = newNc('Packaging issue', partId('REL-CONTROL'), LOT);
        insert lotNc;
        PhrQmsPanelController.PanelData d = data();
        PhrQmsPanelController.Row r = byName(d.nonconformances, lotNc.Id);
        System.assertNotEquals(null, r, 'a lot match is always a lead');
        System.assertEquals('Lot', r.matchedBy);
        System.assertEquals('Same lot', r.relatedBy);
        System.assertNotEquals('Grey', r.colour);
    }

    // ---------- Components and other products ----------

    @IsTest
    static void component_needsASymptom_otherwiseSetAsideWithAReason() {
        compliancequest__SQX_Nonconformance__c related = newNc('Seal leak fluid on component', partId('REL-COMP'), null);
        compliancequest__SQX_Nonconformance__c unrelated = newNc('Label misprint on carton', partId('REL-COMP'), null);
        insert new List<compliancequest__SQX_Nonconformance__c>{ related, unrelated };

        PhrQmsPanelController.PanelData d = data();
        PhrQmsPanelController.Row kept = byName(d.nonconformances, related.Id);
        System.assertNotEquals(null, kept);
        System.assertEquals('Component of the part', kept.relatedBy);
        System.assertEquals(null, byName(d.nonconformances, unrelated.Id), 'no symptom, not a lead');
        PhrQmsPanelController.Row aside = byName(d.setAside, unrelated.Id);
        System.assertNotEquals(null, aside);
        System.assertEquals('Set aside', aside.tier);
        System.assert(aside.reason.contains('symptom'), aside.reason);
    }

    @IsTest
    static void otherProductSharingAComponent_included_onlyWithASymptom_controlNeverLoaded() {
        compliancequest__SQX_Nonconformance__c related = newNc('Fluid leak at the seal', partId('REL-OTHER'), null);
        compliancequest__SQX_Nonconformance__c unrelated = newNc('Label misprint on carton', partId('REL-OTHER'), null);
        compliancequest__SQX_Nonconformance__c control = newNc('Fluid leak at the seal', partId('REL-CONTROL'), null);
        insert new List<compliancequest__SQX_Nonconformance__c>{ related, unrelated, control };

        PhrQmsPanelController.PanelData d = data();
        PhrQmsPanelController.Row kept = byName(d.nonconformances, related.Id);
        System.assertNotEquals(null, kept, 'same issue on a product sharing a component');
        System.assertEquals('Product sharing a component', kept.relatedBy);
        System.assertNotEquals(null, byName(d.setAside, unrelated.Id), 'unrelated issue on that product is set aside');
        System.assertEquals(null, byName(d.nonconformances, control.Id), 'product sharing nothing is never loaded');
        System.assertEquals(null, byName(d.setAside, control.Id));
    }

    // ---------- Tiers ----------

    @IsTest
    static void tiers_topFiveThenNext_acrossAllLeads() {
        List<compliancequest__SQX_Nonconformance__c> ncs = new List<compliancequest__SQX_Nonconformance__c>();
        for (Integer i = 1; i <= 7; i++) {
            ncs.add(newNc('Fluid leak at the seal of the valve ' + i, partId('REL-OWN'), null));
        }
        insert ncs;
        PhrQmsPanelController.PanelData d = data();
        Integer top = 0;
        Integer next = 0;
        for (PhrQmsPanelController.Row r : d.nonconformances) {
            if (r.tier == 'Top') { top++; System.assertEquals(true, r.highlight); }
            if (r.tier == 'Next') { next++; System.assertEquals(false, r.highlight); }
        }
        System.assertEquals(PhrQmsRelevanceSettings.TOP_LEADS, top);
        System.assertEquals(2, next);
    }

    // ---------- Change orders ----------

    static compliancequest__SQX_Change_Order__c newCo(String title, Id productId) {
        return new compliancequest__SQX_Change_Order__c(
            compliancequest__Title__c = title,
            compliancequest__Description__c = title,
            compliancequest__Justification__c = title,
            compliancequest__SQX_Product__c = productId,
            compliancequest__Change_Category__c = 'Compliance',
            compliancequest__Priority__c = 'Normal',
            compliancequest__Target_Completion_Date__c = Date.today().addDays(5));
    }

    @IsTest
    static void changeOrder_documentOnly_isSetAside_partDesignIsBoostedAndALead() {
        compliancequest__SQX_Change_Order__c doc = newCo('Update work instruction', partId('REL-OWN'));
        compliancequest__SQX_Change_Order__c pd = newCo('Revise valve seal design', partId('REL-OWN'));
        compliancequest__SQX_Change_Order__c unk = newCo('Revise valve housing', partId('REL-OWN'));
        insert new List<compliancequest__SQX_Change_Order__c>{ doc, pd, unk };
        PhrQmsRelevance.changeClassOverride.put(doc.Id, PhrQmsRelevance.CLASS_DOCUMENT);
        PhrQmsRelevance.changeClassOverride.put(pd.Id, PhrQmsRelevance.CLASS_PART_DESIGN);

        PhrQmsPanelController.PanelData d = data();
        PhrQmsPanelController.Row docRow = byName(d.setAside, doc.Id);
        System.assertNotEquals(null, docRow, 'document change only is set aside');
        System.assertEquals('Document change only', docRow.reason);
        System.assertEquals(null, byName(d.changeOrders, doc.Id));

        PhrQmsPanelController.Row pdRow = byName(d.changeOrders, pd.Id);
        PhrQmsPanelController.Row unkRow = byName(d.changeOrders, unk.Id);
        System.assertNotEquals(null, pdRow, 'part or design change is a lead');
        System.assert(pdRow.changeType.startsWith('Part or design change'), pdRow.changeType);
        System.assertNotEquals(null, unkRow, 'unclassified keeps reduced weight');
        System.assert(pdRow.relevance > unkRow.relevance, 'part and design changes are prioritised');
    }

    // ---------- Fallback ----------

    @IsTest
    static void switchOff_usesTheOriginalRanking() {
        compliancequest__SQX_Nonconformance__c nc = newNc('Label misprint on carton', partId('REL-OWN'), null);
        compliancequest__SQX_Nonconformance__c unrelatedComp = newNc('Label misprint on carton', partId('REL-COMP'), null);
        insert new List<compliancequest__SQX_Nonconformance__c>{ nc, unrelatedComp };

        PhrQmsRelevanceSettings.useNewModel = false;
        PhrQmsPanelController.PanelData d = data();
        System.assertEquals(null, d.relevanceModel);
        System.assertEquals(0, d.setAside.size());
        System.assertNotEquals(null, byName(d.nonconformances, unrelatedComp.Id), 'original ranking lists every part match');
        System.assertEquals(null, byName(d.nonconformances, nc.Id).colour);
    }

    // ---------- Helpers ----------

    @IsTest
    static void tokensAndDice() {
        Set<String> a = PhrQmsRelevance.tokens('The valve leaks fluid at the seal. 123');
        System.assert(a.contains('valve'));
        System.assert(a.contains('leak'), 'simple plural handling');
        System.assert(!a.contains('the'));
        System.assert(!a.contains('123'));
        System.assertEquals(0.0, PhrQmsRelevance.dice(a, new Set<String>()));
        System.assertEquals(1.0, PhrQmsRelevance.dice(a, a));
        Set<String> b = PhrQmsRelevance.tokens('Label misprint');
        System.assertEquals(0.0, PhrQmsRelevance.dice(a, b));
    }

    @IsTest
    static void otherProducts_countsSharedComponents_excludesOwnAndControl() {
        Set<Id> comps = new Set<Id>{ partId('REL-COMP') };
        Map<Id, Integer> others = PhrQmsRelevance.otherProducts(partId('REL-OWN'), comps);
        System.assertEquals(1, others.size());
        System.assertEquals(1, others.get(partId('REL-OTHER')));
        System.assert(!others.containsKey(partId('REL-OWN')));
        System.assert(!others.containsKey(partId('REL-CONTROL')));
        System.assertEquals(0, PhrQmsRelevance.otherProducts(partId('REL-OWN'), new Set<Id>()).size());
    }
}
