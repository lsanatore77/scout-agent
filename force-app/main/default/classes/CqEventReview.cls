/**
 * Read model for the Event Review (reviewer) screen, per the v5 design: the problem on the left and
 * CQ.AI's suggestion (what it should become, open records on the same part, similar events) on the right.
 * Read only for now — the decision actions (Create NC / Complaint / Add to open record / Not a quality
 * issue) come next.
 */
public with sharing class CqEventReview {

    public class Ans { @AuraEnabled public String question; @AuraEnabled public String answer; @AuraEnabled public String role; }
    public class Rel {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String title;
        @AuraEnabled public String status; @AuraEnabled public String lot; @AuraEnabled public String note;
    }
    public class Suggestion {
        @AuraEnabled public String becomes;                 // 'New Nonconformance' | 'New Complaint'
        @AuraEnabled public List<String> reasons = new List<String>();
    }
    public class Review {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String title;
        @AuraEnabled public String problem; @AuraEnabled public String status; @AuraEnabled public Boolean urgent = false;
        @AuraEnabled public String partNumber; @AuraEnabled public String partName; @AuraEnabled public String lot;
        @AuraEnabled public Decimal units; @AuraEnabled public String whereFound; @AuraEnabled public String productAffected;
        @AuraEnabled public String injury; @AuraEnabled public String safety; @AuraEnabled public String reportedBy;
        @AuraEnabled public Datetime awareDate;
        @AuraEnabled public List<Ans> answers = new List<Ans>();
        @AuraEnabled public Suggestion suggestion = new Suggestion();
        @AuraEnabled public List<Rel> openOnPart = new List<Rel>();
        @AuraEnabled public List<Rel> similarEvents = new List<Rel>();
    }

    @AuraEnabled(cacheable=true)
    public static Review getReview(Id eventId) {
        if (eventId == null) { throw new AuraHandledException('No event to review.'); }
        List<Quality_Event__c> evs = [
            SELECT Id, Name, Title__c, Problem_Statement__c, Status__c, Urgent__c, Lot_Number__c, Units_Affected__c,
                   Where_Found__c, Product_Affected__c, Injury__c, Safety_Risk__c, Aware_Date__c,
                   Part__c, Part__r.compliancequest__Part_Number__c, Part__r.Name, Reported_By__r.Name,
                   (SELECT Question_Text__c, Answer__c, Role__c FROM Answers__r ORDER BY Order__c NULLS LAST)
            FROM Quality_Event__c WHERE Id = :eventId WITH USER_MODE
        ];
        if (evs.isEmpty()) { throw new AuraHandledException('That event is not available.'); }
        Quality_Event__c e = evs[0];

        Review r = new Review();
        r.id = e.Id; r.name = e.Name; r.title = e.Title__c; r.problem = e.Problem_Statement__c;
        r.status = e.Status__c; r.urgent = e.Urgent__c == true; r.lot = e.Lot_Number__c; r.units = e.Units_Affected__c;
        r.whereFound = e.Where_Found__c; r.productAffected = e.Product_Affected__c; r.injury = e.Injury__c;
        r.safety = e.Safety_Risk__c; r.awareDate = e.Aware_Date__c;
        r.reportedBy = e.Reported_By__r == null ? null : e.Reported_By__r.Name;
        if (e.Part__r != null) { r.partNumber = e.Part__r.compliancequest__Part_Number__c; r.partName = e.Part__r.Name; }
        for (Event_Answer__c a : e.Answers__r) {
            Ans x = new Ans(); x.question = a.Question_Text__c; x.answer = a.Answer__c; x.role = a.Role__c;
            r.answers.add(x);
        }

        r.suggestion = suggest(e);
        if (e.Part__c != null) {
            r.openOnPart = openNcs(e.Part__c, e.Lot_Number__c);
            r.similarEvents = similar(e.Part__c, e.Id);
        }
        return r;
    }

    static Suggestion suggest(Quality_Event__c e) {
        Suggestion s = new Suggestion();
        s.becomes = (e.Where_Found__c == 'At a Customer') ? 'New Complaint' : 'New Nonconformance';
        if (e.Where_Found__c != null) { s.reasons.add('Found ' + e.Where_Found__c.toLowerCase() + '.'); }
        if (e.Product_Affected__c == 'Yes') { s.reasons.add('A product was affected.'); }
        if (e.Safety_Risk__c == 'Yes') { s.reasons.add('Safety is at risk — triage starts High.'); }
        else if (e.Safety_Risk__c == 'Not Known') { s.reasons.add('Safety answered Not Sure — triage starts High.'); }
        if (e.Injury__c == 'Yes') { s.reasons.add('An injury was reported.'); }
        if (s.reasons.isEmpty()) { s.reasons.add('A quality event that needs a record.'); }
        return s;
    }

    static List<Rel> openNcs(Id partId, String lot) {
        List<Rel> out = new List<Rel>();
        for (compliancequest__SQX_Nonconformance__c n : [
            SELECT Name, compliancequest__NC_Title__c, compliancequest__Status__c, compliancequest__Lot_Number__c
            FROM compliancequest__SQX_Nonconformance__c
            WHERE compliancequest__SQX_Part__c = :partId AND compliancequest__Status__c != 'Closed'
            WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 5
        ]) {
            Rel rel = new Rel();
            rel.id = n.Id; rel.name = n.Name; rel.title = n.compliancequest__NC_Title__c;
            rel.status = n.compliancequest__Status__c; rel.lot = n.compliancequest__Lot_Number__c;
            Boolean sameLot = lot != null && n.compliancequest__Lot_Number__c == lot;
            rel.note = sameLot ? 'same part, same lot' : 'same part';
            out.add(rel);
        }
        return out;
    }

    static List<Rel> similar(Id partId, Id selfId) {
        List<Rel> out = new List<Rel>();
        for (Quality_Event__c e : [
            SELECT Name, Title__c, Status__c, Lot_Number__c FROM Quality_Event__c
            WHERE Part__c = :partId AND Id != :selfId AND Status__c != 'Closed'
            WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 5
        ]) {
            Rel rel = new Rel();
            rel.id = e.Id; rel.name = e.Name; rel.title = e.Title__c; rel.status = e.Status__c; rel.lot = e.Lot_Number__c;
            out.add(rel);
        }
        return out;
    }
}
