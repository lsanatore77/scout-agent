/**
 * CqEventIntake: the Report a Problem screen (c-cq-event-intake), with its two tabs.
 *
 * Full Report: submitReport() makes a Quality Event (Waiting for Review) with the problem statement, title, part, lot and
 * units, plus one Event Answer per question. The questions come from Event Question (set per company). Questions with a
 * Role also fill the event's own fields (Where Found, Product Affected, Injury, Safety Risk), and any answer listed in a
 * question's Urgent When marks the event Urgent.
 *
 * Quick Log: quickLog() makes an NC marked Quick Log for one of the approved Quick Log Categories and closes it at once
 * with the category's disposition (Status and Stage Closed directly; agreed for quick logs, as CQ has no straight-to-closed
 * action). When the category's count in its window reaches the limit, CQ.AI opens a Trend event for review and links those
 * NCs to it.
 */
public with sharing class CqEventIntake {

    public static final String WAITING = 'Waiting for Review';

    public class Question {
        @AuraEnabled public Id id; @AuraEnabled public Integer order; @AuraEnabled public String question;
        @AuraEnabled public String answerType; @AuraEnabled public List<String> choices = new List<String>();
        @AuraEnabled public String role; @AuraEnabled public List<String> urgentWhen = new List<String>();
        @AuraEnabled public String help; @AuraEnabled public Boolean required = false;
    }
    public class Category {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String description;
        @AuraEnabled public String disposition; @AuraEnabled public Integer limitCount; @AuraEnabled public Integer days;
        @AuraEnabled public String scope; @AuraEnabled public String approvedBy; @AuraEnabled public Date approvedOn;
    }
    public class Setup {
        @AuraEnabled public List<Question> questions = new List<Question>();
        @AuraEnabled public List<Category> categories = new List<Category>();
        @AuraEnabled public String reporter;
    }
    public class Sent {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public Boolean urgent = false;
    }
    public class Trend {
        @AuraEnabled public Decimal total = 0; @AuraEnabled public Integer limitCount; @AuraEnabled public Integer days;
        @AuraEnabled public String scope; @AuraEnabled public String partNumber;
    }
    public class Logged {
        @AuraEnabled public Id ncId; @AuraEnabled public String ncName; @AuraEnabled public Trend trend;
        @AuraEnabled public Boolean triggered = false; @AuraEnabled public Id eventId; @AuraEnabled public String eventName;
        @AuraEnabled public Integer linked = 0;
    }

    // ---------------------------------------------------------------- setup
    @AuraEnabled
    public static Setup getSetup() {
        Setup s = new Setup();
        s.reporter = UserInfo.getName();
        for (Event_Question__c q : [SELECT Id, Order__c, Question__c, Answer_Type__c, Choices__c, Role__c, Urgent_When__c, Help_Text__c, Required__c
                FROM Event_Question__c WHERE Active__c = true ORDER BY Order__c NULLS LAST, Name]) {
            Question x = new Question();
            x.id = q.Id; x.order = q.Order__c == null ? null : q.Order__c.intValue(); x.question = q.Question__c;
            x.answerType = q.Answer_Type__c == null ? 'Text' : q.Answer_Type__c;
            x.choices = x.answerType == 'Yes or No' ? new List<String>{ 'Yes', 'No' } : split(q.Choices__c);
            x.role = q.Role__c == null || q.Role__c == 'None' ? null : q.Role__c;
            x.urgentWhen = split(q.Urgent_When__c); x.help = q.Help_Text__c; x.required = q.Required__c == true;
            s.questions.add(x);
        }
        for (Quick_Log_Category__c c : [SELECT Id, Name, Description__c, Disposition__c, Limit__c, Days__c, Scope__c, Approved_By__r.Name, Approved_On__c
                FROM Quick_Log_Category__c WHERE Active__c = true ORDER BY Name]) {
            s.categories.add(category(c));
        }
        return s;
    }

    // ---------------------------------------------------------------- Full Report
    @AuraEnabled
    public static Sent submitReport(String payload) {
        Map<String, Object> p = (Map<String, Object>) JSON.deserializeUntyped(payload);
        String title = str(p.get('title'));
        String problem = str(p.get('problem'));
        if (String.isBlank(problem)) { throw new AuraHandledException('Describe the problem.'); }
        if (String.isBlank(title)) { throw new AuraHandledException('Give it a title.'); }
        Map<Id, String> given = new Map<Id, String>();
        for (Object o : (List<Object>) (p.get('answers') == null ? new List<Object>() : p.get('answers'))) {
            Map<String, Object> a = (Map<String, Object>) o;
            if (a.get('questionId') != null && String.isNotBlank(str(a.get('answer')))) { given.put((Id) str(a.get('questionId')), str(a.get('answer')).trim()); }
        }
        List<Event_Question__c> qs = [SELECT Id, Order__c, Question__c, Role__c, Urgent_When__c, Required__c FROM Event_Question__c
            WHERE Active__c = true ORDER BY Order__c NULLS LAST, Name];
        for (Event_Question__c q : qs) {
            if (q.Required__c && !given.containsKey(q.Id)) { throw new AuraHandledException('Answer: ' + q.Question__c); }
        }

        Quality_Event__c ev = new Quality_Event__c(Title__c = title.left(255), Problem_Statement__c = problem, Event_Type__c = 'Report',
            Status__c = WAITING, Reported_By__c = UserInfo.getUserId(), Aware_Date__c = System.now(), Sent_On__c = Date.today(),
            Lot_Number__c = String.isBlank(str(p.get('lot'))) ? null : str(p.get('lot')).trim().left(80));
        if (String.isNotBlank(str(p.get('partId')))) { ev.Part__c = (Id) str(p.get('partId')); }
        if (String.isNotBlank(str(p.get('units')))) { ev.Units_Affected__c = Decimal.valueOf(str(p.get('units'))); }
        Boolean urgent = false;
        for (Event_Question__c q : qs) {
            String ans = given.get(q.Id);
            if (ans == null) { continue; }
            if (isIn(ans, split(q.Urgent_When__c))) { urgent = true; }
            if (q.Role__c == 'Where Found') { ev.Where_Found__c = pickWhere(ans); }
            else if (q.Role__c == 'Product Affected') { ev.Product_Affected__c = yesNo(ans, false); }
            else if (q.Role__c == 'Injury') { ev.Injury__c = yesNo(ans, true); }
            else if (q.Role__c == 'Safety Risk') { ev.Safety_Risk__c = yesNo(ans, true); }
        }
        ev.Urgent__c = urgent;
        insert ev;

        List<Event_Answer__c> rows = new List<Event_Answer__c>();
        for (Event_Question__c q : qs) {
            if (!given.containsKey(q.Id)) { continue; }
            rows.add(new Event_Answer__c(Quality_Event__c = ev.Id, Event_Question__c = q.Id, Question_Text__c = q.Question__c,
                Role__c = q.Role__c == null || q.Role__c == 'None' ? null : q.Role__c, Order__c = q.Order__c, Answer__c = given.get(q.Id).left(4000)));
        }
        if (!rows.isEmpty()) { insert rows; }
        Sent s = new Sent();
        s.id = ev.Id; s.name = [SELECT Name FROM Quality_Event__c WHERE Id = :ev.Id].Name; s.urgent = urgent;
        return s;
    }

    // ---------------------------------------------------------------- Quick Log
    @AuraEnabled
    public static Trend getTrend(Id categoryId, Id partId) {
        Quick_Log_Category__c c = loadCategory(categoryId);
        return trend(c, partId);
    }

    @AuraEnabled
    public static Logged quickLog(Id categoryId, Id partId, String lot, Integer quantity, String note) {
        if (categoryId == null) { throw new AuraHandledException('Pick what it was.'); }
        if (partId == null) { throw new AuraHandledException('Choose the part.'); }
        Integer qty = quantity == null || quantity < 1 ? 1 : quantity;
        Quick_Log_Category__c c = loadCategory(categoryId);
        compliancequest__SQX_Part__c part = [SELECT Id, Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Part__c WHERE Id = :partId];
        String what = qty + ' × ' + c.Name + (String.isBlank(c.Description__c) ? '' : ' (' + c.Description__c + ')') + ' on ' + part.compliancequest__Part_Number__c + '.';
        String body = '<p>' + what.escapeHtml4() + '</p>' + (String.isBlank(note) ? '' : '<p>' + note.trim().escapeHtml4() + '</p>')
            + '<p>Quick log, trend only. Disposition: ' + (c.Disposition__c == null ? 'none set' : c.Disposition__c).escapeHtml4() + '.</p>';
        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = (c.Name + ' (Quick Log)').left(255), compliancequest__Type__c = 'Internal',
            compliancequest__Type_Of_Issue__c = 'Product', compliancequest__Description_RT__c = body,
            compliancequest__SQX_Part__c = partId, compliancequest__Lot_Number__c = String.isBlank(lot) ? null : lot.trim().left(80),
            compliancequest__Defective_Quantity__c = qty, compliancequest__Occurrence_Date__c = Date.today(),
            Quick_Log__c = true, Quick_Log_Category__c = c.Id);
        Savepoint sp = Database.setSavepoint();
        Logged out = new Logged();
        try {
            insert nc;
            // closed at once with the category's disposition (agreed for quick logs: CQ has no straight-to-closed action)
            update new compliancequest__SQX_Nonconformance__c(Id = nc.Id, compliancequest__Status__c = 'Closed', compliancequest__Record_Stage__c = 'Closed',
                compliancequest__Close_Date__c = Date.today(),
                compliancequest__Closure_Comment__c = 'Quick log, trend only. Disposition: ' + (c.Disposition__c == null ? 'none set' : c.Disposition__c) + '.');
            out.ncId = nc.Id;
            out.ncName = [SELECT Name FROM compliancequest__SQX_Nonconformance__c WHERE Id = :nc.Id].Name;
            out.trend = trend(c, partId);
            if (c.Limit__c != null && out.trend.total >= c.Limit__c) { openTrendEvent(c, part, out); }
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException('The quick log was not saved: ' + e.getDmlMessage(0));
        }
        return out;
    }

    /** The quick logs counted toward the limit: this category, in the window, on this part (Same Part), not yet in a Trend event. */
    static List<compliancequest__SQX_Nonconformance__c> counted(Quick_Log_Category__c c, Id partId) {
        Datetime since = System.now().addDays(-(c.Days__c == null ? 30 : c.Days__c.intValue()));
        Boolean byPart = c.Scope__c != 'All Parts';
        if (byPart) {
            return [SELECT Id, Name, compliancequest__Defective_Quantity__c, compliancequest__Lot_Number__c, CreatedDate FROM compliancequest__SQX_Nonconformance__c
                WHERE Quick_Log__c = true AND Quick_Log_Category__c = :c.Id AND Trend_Event__c = null AND CreatedDate >= :since AND compliancequest__SQX_Part__c = :partId
                ORDER BY CreatedDate];
        }
        return [SELECT Id, Name, compliancequest__Defective_Quantity__c, compliancequest__Lot_Number__c, CreatedDate FROM compliancequest__SQX_Nonconformance__c
            WHERE Quick_Log__c = true AND Quick_Log_Category__c = :c.Id AND Trend_Event__c = null AND CreatedDate >= :since ORDER BY CreatedDate];
    }

    static Trend trend(Quick_Log_Category__c c, Id partId) {
        Trend t = new Trend();
        t.limitCount = c.Limit__c == null ? null : c.Limit__c.intValue();
        t.days = c.Days__c == null ? 30 : c.Days__c.intValue();
        t.scope = c.Scope__c == null ? 'Same Part' : c.Scope__c;
        if (partId != null) {
            for (compliancequest__SQX_Part__c p : [SELECT compliancequest__Part_Number__c FROM compliancequest__SQX_Part__c WHERE Id = :partId]) { t.partNumber = p.compliancequest__Part_Number__c; }
        }
        if (partId == null && t.scope != 'All Parts') { return t; }
        for (compliancequest__SQX_Nonconformance__c n : counted(c, partId)) { t.total += n.compliancequest__Defective_Quantity__c == null ? 1 : n.compliancequest__Defective_Quantity__c; }
        return t;
    }

    static void openTrendEvent(Quick_Log_Category__c c, compliancequest__SQX_Part__c part, Logged out) {
        List<compliancequest__SQX_Nonconformance__c> ncs = counted(c, part.Id);
        Boolean byPart = c.Scope__c != 'All Parts';
        String total = out.trend.total.stripTrailingZeros().toPlainString();
        String onPart = byPart ? ' on ' + part.compliancequest__Part_Number__c : '';
        List<String> lines = new List<String>();
        for (compliancequest__SQX_Nonconformance__c n : ncs) {
            lines.add(n.Name + ': ' + (n.compliancequest__Defective_Quantity__c == null ? '1' : n.compliancequest__Defective_Quantity__c.stripTrailingZeros().toPlainString())
                + (n.compliancequest__Lot_Number__c == null ? '' : ', lot ' + n.compliancequest__Lot_Number__c) + ', ' + n.CreatedDate.date().format());
        }
        Quality_Event__c ev = new Quality_Event__c(
            Title__c = (c.Name + ': ' + total + ' quick logs in ' + out.trend.days + ' days' + onPart).left(255),
            Problem_Statement__c = 'The ' + c.Name + ' quick-log count reached its limit of ' + c.Limit__c.intValue() + ' in ' + out.trend.days + ' days' + onPart
                + ' (' + total + ' logged). The quick logs behind the count:\n' + String.join(lines, '\n'),
            Event_Type__c = 'Trend', Status__c = WAITING, Quick_Log_Category__c = c.Id, Part__c = byPart ? part.Id : null,
            Units_Affected__c = out.trend.total, Reported_By__c = UserInfo.getUserId(), Aware_Date__c = System.now(), Sent_On__c = Date.today(),
            Where_Found__c = 'In Our Plant', Product_Affected__c = 'Yes');
        insert ev;
        for (compliancequest__SQX_Nonconformance__c n : ncs) { n.Trend_Event__c = ev.Id; }
        update ncs;
        out.triggered = true; out.eventId = ev.Id; out.linked = ncs.size();
        out.eventName = [SELECT Name FROM Quality_Event__c WHERE Id = :ev.Id].Name;
    }

    // ---------------------------------------------------------------- helpers
    static Quick_Log_Category__c loadCategory(Id categoryId) {
        List<Quick_Log_Category__c> cs = [SELECT Id, Name, Description__c, Disposition__c, Limit__c, Days__c, Scope__c, Active__c, Approved_By__r.Name, Approved_On__c
            FROM Quick_Log_Category__c WHERE Id = :categoryId];
        if (cs.isEmpty() || !cs[0].Active__c) { throw new AuraHandledException('That quick-log category is not available.'); }
        return cs[0];
    }
    static Category category(Quick_Log_Category__c c) {
        Category x = new Category();
        x.id = c.Id; x.name = c.Name; x.description = c.Description__c; x.disposition = c.Disposition__c;
        x.limitCount = c.Limit__c == null ? null : c.Limit__c.intValue(); x.days = c.Days__c == null ? 30 : c.Days__c.intValue();
        x.scope = c.Scope__c == null ? 'Same Part' : c.Scope__c; x.approvedBy = c.Approved_By__r == null ? null : c.Approved_By__r.Name;
        x.approvedOn = c.Approved_On__c;
        return x;
    }
    @TestVisible static List<String> split(String s) {
        List<String> out = new List<String>();
        if (String.isBlank(s)) { return out; }
        for (String x : s.split(';')) { if (String.isNotBlank(x)) { out.add(x.trim()); } }
        return out;
    }
    static Boolean isIn(String ans, List<String> list1) {
        for (String x : list1) { if (x.equalsIgnoreCase(ans)) { return true; } }
        return false;
    }
    @TestVisible static String pickWhere(String ans) {
        for (String v : new List<String>{ 'In Our Plant', 'At a Customer', 'At a Supplier', 'Not Known' }) { if (v.equalsIgnoreCase(ans)) { return v; } }
        String a = ans.toLowerCase();
        if (a.contains('plant')) { return 'In Our Plant'; }
        if (a.contains('customer') || a.contains('field')) { return 'At a Customer'; }
        if (a.contains('supplier')) { return 'At a Supplier'; }
        return 'Not Known';
    }
    @TestVisible static String yesNo(String ans, Boolean allowUnknown) {
        if (ans.equalsIgnoreCase('Yes')) { return 'Yes'; }
        if (ans.equalsIgnoreCase('No')) { return 'No'; }
        return allowUnknown ? 'Not Known' : null;
    }
    static String str(Object o) { return o == null ? null : String.valueOf(o); }
}
