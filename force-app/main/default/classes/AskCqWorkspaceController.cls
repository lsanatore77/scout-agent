/**
 * AskCqWorkspaceController
 * --------------------------
 * Backs the PHR workspace table (askCqRecordsDemo): the live relevance package for the
 * complaint of the Product History Review on screen, and adding the records the user switched on.
 *
 * Nothing new is calculated here. getPackage reuses PhrQmsPanelController.getPanelData (the same
 * relevance model the agent's Relevance Package action reads) and addSelected reuses
 * PhrLeadAddAction (the same add the agent's tick list used), so the workspace and Ask CQ see the
 * same records and the same scores.
 */
public with sharing class AskCqWorkspaceController {

    /** ✦ Suggested = red (met every criterion) and at least this many relevance points. */
    @TestVisible static Integer SUGGEST_MIN_POINTS = 80;

    public class Row {
        @AuraEnabled public String id;
        @AuraEnabled public String recordNumber;
        @AuraEnabled public String recordType;
        @AuraEnabled public String status;
        @AuraEnabled public String title;
        @AuraEnabled public String colour;
        @AuraEnabled public Integer relevance;
        @AuraEnabled public String criteriaMet;
        @AuraEnabled public String matchedBy;
        @AuraEnabled public String relatedBy;
        @AuraEnabled public String reason;
        @AuraEnabled public Boolean added;
        @AuraEnabled public Boolean suggested;   // red and 80+ points: pre-selected in the workspace
        @AuraEnabled public String link;
        @AuraEnabled public String partName;
        @AuraEnabled public String lotNumber;
        @AuraEnabled public String rootCause;
    }

    public class PackageData {
        @AuraEnabled public Boolean success = true;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String complaintName;
        @AuraEnabled public String partName;
        @AuraEnabled public String partNumber;
        @AuraEnabled public String lotNumber;
        @AuraEnabled public List<Row> rows = new List<Row>();
    }

    public class AddResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Integer recordsAdded;
        @AuraEnabled public String message;
    }

    /** The live package: nonconformances, CAPAs, change orders, inspections and investigations, best first inside each type. */
    @AuraEnabled
    public static PackageData getPackage(Id recordId) {
        PackageData p = new PackageData();
        try {
            PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(recordId, null);
            if (!d.success) {
                p.success = false;
                p.errorMessage = d.errorMessage;
                return p;
            }
            p.complaintName = d.complaintName;
            p.partName = d.partName;
            p.partNumber = d.partNumber;
            p.lotNumber = d.lotNumber;
            List<PhrQmsPanelController.Row> all = new List<PhrQmsPanelController.Row>();
            all.addAll(d.nonconformances);
            all.addAll(d.capas);
            all.addAll(d.changeOrders);
            all.addAll(d.inspections);
            all.addAll(d.investigations);
            Map<Id, String> titles = loadTitles(all);
            Map<Id, String> lots = loadLots(all);
            Map<Id, String> causes = loadRootCauses(all);
            for (PhrQmsPanelController.Row r : all) {
                Row w = toRow(r, titles);
                w.partName = r.partNumber;
                w.lotNumber = lots.get(r.id);
                w.rootCause = causes.get(r.id);
                p.rows.add(w);
            }
        } catch (Exception ex) {
            p.success = false;
            p.errorMessage = ex.getMessage();
        }
        return p;
    }

    /** Adds the switched-on records to the Product History Review and stores every record as a PHR Lead. */
    @AuraEnabled
    public static AddResult addSelected(Id recordId, List<String> selectedIds) {
        PhrLeadAddAction.Request req = new PhrLeadAddAction.Request();
        req.recordId = recordId;
        req.selectedRecordIds = (selectedIds == null || selectedIds.isEmpty()) ? new List<String>{ 'none' } : selectedIds;
        PhrLeadAddAction.Response res = PhrLeadAddAction.run(new List<PhrLeadAddAction.Request>{ req })[0];
        AddResult out = new AddResult();
        out.success = res.success == true;
        out.recordsAdded = res.recordsAdded;
        out.message = res.summary;
        if (!out.success) { throw new AuraHandledException(String.isBlank(res.summary) ? 'The records could not be added.' : res.summary); }
        return out;
    }

    // ---------- review steps ----------

    public class StepStatus {
        @AuraEnabled public String phrName;
        @AuraEnabled public String complaintId;
        @AuraEnabled public String complaintName;
        @AuraEnabled public String phrStatus;
        @AuraEnabled public String partName;
        @AuraEnabled public String lotNumber;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Integer pendingChecklist = 0;
        @AuraEnabled public Integer suggestedPending = 0;  // suggestions the user has not accepted yet
        @AuraEnabled public Integer recordsAdded = 0;      // Related Products on the PHR
        @AuraEnabled public Integer questionsTotal = 0;
        @AuraEnabled public Integer questionsAnswered = 0;
        @AuraEnabled public Boolean summarySaved = false;
        @AuraEnabled public String summaryHtml;
        @AuraEnabled public Integer reportCount = 0;
        @AuraEnabled public List<ReportFile> reports = new List<ReportFile>();
    }

    public class ReportFile {
        @AuraEnabled public String title;
        @AuraEnabled public String link;
        @AuraEnabled public Datetime modified;
        @AuraEnabled public Integer version;
    }

    public class Question {
        @AuraEnabled public String id;
        @AuraEnabled public String number_x;
        @AuraEnabled public String question;
        @AuraEnabled public String answer;
        @AuraEnabled public String notes;
        @AuraEnabled public Boolean answered;
        @AuraEnabled public List<String> options = new List<String>();   // allowed answers from the question's result type
        @AuraEnabled public Boolean suggested = false;                     // answered by the checklist agent and accepted
        @AuraEnabled public String suggestedAnswer;                        // what the checklist logic would answer (unanswered questions only)
        @AuraEnabled public String suggestedBasis;
    }

    /** Where each review step stands, read from the PHR itself. */
    @AuraEnabled
    public static StepStatus getStatus(Id phrId) {
        StepStatus st = new StepStatus();
        compliancequest__SQX_Product_History_Review__c phr = [
            SELECT Id, Name, compliancequest__Status__c, compliancequest__Product_History_Review_Summary__c,
                   compliancequest__SQX_Complaint__c, compliancequest__SQX_Complaint__r.Name,
                   compliancequest__SQX_Complaint__r.compliancequest__SQX_Part__r.Name,
                   compliancequest__SQX_Complaint__r.compliancequest__Lot_Number__c,
                   Owner.Name, compliancequest__Pending_PHR_Checklist_Count__c
            FROM compliancequest__SQX_Product_History_Review__c WHERE Id = :phrId LIMIT 1
        ];
        st.phrName = phr.Name;
        st.ownerName = phr.Owner.Name;
        st.pendingChecklist = phr.compliancequest__Pending_PHR_Checklist_Count__c == null ? 0 : Integer.valueOf(phr.compliancequest__Pending_PHR_Checklist_Count__c);
        if (phr.compliancequest__SQX_Complaint__r != null) {
            st.lotNumber = phr.compliancequest__SQX_Complaint__r.compliancequest__Lot_Number__c;
            if (phr.compliancequest__SQX_Complaint__r.compliancequest__SQX_Part__r != null) {
                st.partName = phr.compliancequest__SQX_Complaint__r.compliancequest__SQX_Part__r.Name;
            }
        }
        st.phrStatus = phr.compliancequest__Status__c;
        st.complaintId = phr.compliancequest__SQX_Complaint__c;
        st.complaintName = phr.compliancequest__SQX_Complaint__r == null ? null : phr.compliancequest__SQX_Complaint__r.Name;
        st.summarySaved = String.isNotBlank(phr.compliancequest__Product_History_Review_Summary__c);
        st.summaryHtml = phr.compliancequest__Product_History_Review_Summary__c;
        st.recordsAdded = [SELECT COUNT() FROM compliancequest__SQX_Related_Product__c WHERE compliancequest__SQX_Product_History_Review__c = :phrId];
        for (compliancequest__SQX_Product_History_Answer__c a : [
            SELECT compliancequest__Answer__c FROM compliancequest__SQX_Product_History_Answer__c
            WHERE compliancequest__SQX_Product_History_Review__c = :phrId
        ]) {
            st.questionsTotal++;
            if (String.isNotBlank(a.compliancequest__Answer__c)) { st.questionsAnswered++; }
        }
        if (st.complaintId != null) {
            List<String> titles = PhrReportSettings.phrTitles();
            for (ContentDocumentLink l : [
                SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.LatestPublishedVersionId,
                       ContentDocument.LastModifiedDate, ContentDocument.LatestPublishedVersion.VersionNumber
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :st.complaintId AND ContentDocument.Title IN :titles
                ORDER BY ContentDocument.LastModifiedDate DESC
            ]) {
                ReportFile f = new ReportFile();
                f.title = l.ContentDocument.Title;
                f.link = '/' + l.ContentDocumentId;
                f.modified = l.ContentDocument.LastModifiedDate;
                f.version = l.ContentDocument.LatestPublishedVersion == null ? null : Integer.valueOf(l.ContentDocument.LatestPublishedVersion.VersionNumber);
                st.reports.add(f);
            }
            st.reportCount = st.reports.size();
        }
        return st;
    }

    /** The checklist questions on the PHR with their current answers and the answers allowed for each. */
    @AuraEnabled
    public static List<Question> getChecklist(Id phrId) {
        List<compliancequest__SQX_Product_History_Answer__c> answers = [
            SELECT Id, compliancequest__Question_Number__c, compliancequest__Question__c, compliancequest__Answer__c,
                   compliancequest__Notes__c, compliancequest__Result_Type_Id__c
            FROM compliancequest__SQX_Product_History_Answer__c
            WHERE compliancequest__SQX_Product_History_Review__c = :phrId
            ORDER BY compliancequest__Question_Number__c, Name
        ];
        Map<String, List<String>> allowed = allowedValues(answers);
        Map<String, PhrChecklistItem> suggestions = suggestionsFor(phrId, answers);
        List<Question> out = new List<Question>();
        for (compliancequest__SQX_Product_History_Answer__c a : answers) {
            Question q = new Question();
            q.id = a.Id;
            q.number_x = a.compliancequest__Question_Number__c;
            q.question = a.compliancequest__Question__c;
            q.answer = a.compliancequest__Answer__c;
            q.answered = String.isNotBlank(a.compliancequest__Answer__c);
            q.suggested = q.answered && a.compliancequest__Notes__c != null && a.compliancequest__Notes__c.startsWith(PhrChecklistAction.CQ_MARK);
            q.notes = q.suggested ? a.compliancequest__Notes__c.substring(PhrChecklistAction.CQ_MARK.length()) : a.compliancequest__Notes__c;
            String key = a.compliancequest__Result_Type_Id__c;
            if (key != null && allowed.containsKey(key)) { q.options = allowed.get(key); }
            else if (key != null && allowed.containsKey(key.left(15))) { q.options = allowed.get(key.left(15)); }
            if (q.options.isEmpty()) { q.options = new List<String>{ 'Yes', 'No', 'N/A' }; }
            PhrChecklistItem sug = suggestions.get(a.Id);
            if (!q.answered && sug != null && sug.sure == true && String.isNotBlank(sug.suggestedAnswer)) {
                q.suggestedAnswer = sug.suggestedAnswer;
                q.suggestedBasis = sug.basis;
            }
            out.add(q);
        }
        return out;
    }

    /** The checklist logic's suggestions (no save), keyed by answer Id. Empty when every question is answered. */
    private static Map<String, PhrChecklistItem> suggestionsFor(Id phrId, List<compliancequest__SQX_Product_History_Answer__c> answers) {
        Map<String, PhrChecklistItem> out = new Map<String, PhrChecklistItem>();
        Boolean anyOpen = false;
        for (compliancequest__SQX_Product_History_Answer__c a : answers) { if (String.isBlank(a.compliancequest__Answer__c)) { anyOpen = true; } }
        if (!anyOpen) { return out; }
        try {
            PhrChecklistAction.Request req = new PhrChecklistAction.Request();
            req.recordId = phrId;
            req.saveAnswers = false;
            PhrChecklistResult res = PhrChecklistAction.run(new List<PhrChecklistAction.Request>{ req })[0].result;
            if (res != null && res.items != null) {
                for (PhrChecklistItem it : res.items) { if (it.answerId != null) { out.put(it.answerId, it); } }
            }
        } catch (Exception ex) {
            // suggestions are a convenience; the checklist still works without them
        }
        return out;
    }

    /** The user accepted a suggestion: save it with its evidence and the "suggested" stamp. */
    @AuraEnabled
    public static void acceptSuggestion(Id answerId, String answer, String basis) {
        update new compliancequest__SQX_Product_History_Answer__c(
            Id = answerId,
            compliancequest__Answer__c = answer,
            compliancequest__Answer_Value__c = answer,
            compliancequest__Notes__c = PhrChecklistAction.CQ_MARK + (basis == null ? '' : basis)
        );
    }

    /** Saves an answer picked by the user. A changed answer is the user's, so the "suggested" stamp comes off. */
    @AuraEnabled
    public static void saveAnswer(Id answerId, String answer) {
        compliancequest__SQX_Product_History_Answer__c a = [
            SELECT Id, compliancequest__Answer__c, compliancequest__Notes__c
            FROM compliancequest__SQX_Product_History_Answer__c WHERE Id = :answerId LIMIT 1
        ];
        Boolean changed = a.compliancequest__Answer__c != answer;
        a.compliancequest__Answer__c = answer;
        a.compliancequest__Answer_Value__c = answer;
        if (changed && a.compliancequest__Notes__c != null && a.compliancequest__Notes__c.startsWith(PhrChecklistAction.CQ_MARK)) {
            a.compliancequest__Notes__c = a.compliancequest__Notes__c.substring(PhrChecklistAction.CQ_MARK.length());
        }
        update a;
    }

    /** Same lookup the checklist agent uses: result type Id -> the answer values it allows. */
    private static Map<String, List<String>> allowedValues(List<compliancequest__SQX_Product_History_Answer__c> answers) {
        Set<Id> typeIds = new Set<Id>();
        for (compliancequest__SQX_Product_History_Answer__c a : answers) {
            try { if (String.isNotBlank(a.compliancequest__Result_Type_Id__c)) { typeIds.add((Id) a.compliancequest__Result_Type_Id__c); } } catch (Exception e) { continue; }
        }
        Map<String, List<String>> out = new Map<String, List<String>>();
        if (typeIds.isEmpty()) { return out; }
        for (compliancequest__SQX_Result_Type_Value__c v : [
            SELECT Name, compliancequest__SQX_Result_Type__c FROM compliancequest__SQX_Result_Type_Value__c
            WHERE compliancequest__SQX_Result_Type__c IN :typeIds ORDER BY Name
        ]) {
            for (String key : new List<String>{ String.valueOf(v.compliancequest__SQX_Result_Type__c),
                    String.valueOf(v.compliancequest__SQX_Result_Type__c).left(15) }) {
                if (!out.containsKey(key)) { out.put(key, new List<String>()); }
                out.get(key).add(v.Name);
            }
        }
        return out;
    }

    private static Row toRow(PhrQmsPanelController.Row r, Map<Id, String> titles) {
        Row w = new Row();
        w.id = r.id;
        w.recordNumber = r.name;
        w.recordType = r.recordType;
        w.status = r.status;
        w.title = titles.get(r.id);
        w.colour = r.colour;
        w.relevance = r.relevance;
        w.criteriaMet = r.criteriaMet;
        w.matchedBy = r.matchedBy;
        w.relatedBy = r.relatedBy;
        w.reason = r.reason;
        w.added = r.alreadyAdded == true;
        w.suggested = r.colour == 'Red' && r.relevance != null && r.relevance >= SUGGEST_MIN_POINTS;
        w.link = '/' + r.id;
        return w;
    }

    /** Lot numbers for NCs and inspections. */
    private static Map<Id, String> loadLots(List<PhrQmsPanelController.Row> rows) {
        Set<Id> nc = new Set<Id>();
        Set<Id> insp = new Set<Id>();
        for (PhrQmsPanelController.Row r : rows) {
            if (r.id == null) { continue; }
            String t = String.valueOf(r.id.getSobjectType());
            if (t == 'compliancequest__SQX_Nonconformance__c') { nc.add(r.id); }
            else if (t == 'compliancequest__SQX_Inspection__c') { insp.add(r.id); }
        }
        Map<Id, String> m = new Map<Id, String>();
        for (compliancequest__SQX_Nonconformance__c x : [SELECT Id, compliancequest__Lot_Number__c FROM compliancequest__SQX_Nonconformance__c WHERE Id IN :nc]) {
            m.put(x.Id, x.compliancequest__Lot_Number__c);
        }
        for (compliancequest__SQX_Inspection__c x : [SELECT Id, compliancequest__Lot_Number__c FROM compliancequest__SQX_Inspection__c WHERE Id IN :insp]) {
            m.put(x.Id, x.compliancequest__Lot_Number__c);
        }
        return m;
    }

    /**
     * Root cause per record, read from the Root Cause records of the record's investigation
     * (NC and CAPA through their investigation; an investigation row directly). Code name, else
     * category, else the first line of the description.
     */
    private static Map<Id, String> loadRootCauses(List<PhrQmsPanelController.Row> rows) {
        Set<Id> ids = new Set<Id>();
        for (PhrQmsPanelController.Row r : rows) { if (r.id != null) { ids.add(r.id); } }
        Map<Id, String> m = new Map<Id, String>();
        if (ids.isEmpty()) { return m; }
        for (compliancequest__SQX_Root_Cause__c rc : [
            SELECT compliancequest__SQX_Investigation__c,
                   compliancequest__SQX_Investigation__r.compliancequest__SQX_Nonconformance__c,
                   compliancequest__SQX_Investigation__r.compliancequest__SQX_CAPA__c,
                   compliancequest__Root_Cause_Code_Name__c, compliancequest__Root_Cause_Category_Name__c, compliancequest__Description__c
            FROM compliancequest__SQX_Root_Cause__c
            WHERE compliancequest__SQX_Investigation__c IN :ids
               OR compliancequest__SQX_Investigation__r.compliancequest__SQX_Nonconformance__c IN :ids
               OR compliancequest__SQX_Investigation__r.compliancequest__SQX_CAPA__c IN :ids
            ORDER BY CreatedDate
        ]) {
            String text = String.isNotBlank(rc.compliancequest__Root_Cause_Code_Name__c) ? rc.compliancequest__Root_Cause_Code_Name__c
                : String.isNotBlank(rc.compliancequest__Root_Cause_Category_Name__c) ? rc.compliancequest__Root_Cause_Category_Name__c
                : rc.compliancequest__Description__c;
            if (String.isBlank(text)) { continue; }
            text = text.stripHtmlTags().trim();
            if (text.length() > 90) { text = text.left(87) + '\u2026'; }
            for (Id key : new List<Id>{ rc.compliancequest__SQX_Investigation__c,
                    rc.compliancequest__SQX_Investigation__r.compliancequest__SQX_Nonconformance__c,
                    rc.compliancequest__SQX_Investigation__r.compliancequest__SQX_CAPA__c }) {
                if (key != null && ids.contains(key) && !m.containsKey(key)) { m.put(key, text); }
            }
        }
        return m;
    }

    /** Titles for NCs, CAPAs and change orders. Inspections and investigations have none. */
    private static Map<Id, String> loadTitles(List<PhrQmsPanelController.Row> rows) {
        Set<Id> nc = new Set<Id>();
        Set<Id> capa = new Set<Id>();
        Set<Id> co = new Set<Id>();
        for (PhrQmsPanelController.Row r : rows) {
            if (r.id == null) { continue; }
            String t = String.valueOf(r.id.getSobjectType());
            if (t == 'compliancequest__SQX_Nonconformance__c') { nc.add(r.id); }
            else if (t == 'compliancequest__SQX_CAPA__c') { capa.add(r.id); }
            else if (t == 'compliancequest__SQX_Change_Order__c') { co.add(r.id); }
        }
        Map<Id, String> m = new Map<Id, String>();
        for (compliancequest__SQX_Nonconformance__c x : [
            SELECT Id, compliancequest__NC_Title__c FROM compliancequest__SQX_Nonconformance__c WHERE Id IN :nc
        ]) { m.put(x.Id, x.compliancequest__NC_Title__c); }
        for (compliancequest__SQX_CAPA__c x : [
            SELECT Id, compliancequest__Title__c FROM compliancequest__SQX_CAPA__c WHERE Id IN :capa
        ]) { m.put(x.Id, x.compliancequest__Title__c); }
        for (compliancequest__SQX_Change_Order__c x : [
            SELECT Id, compliancequest__Title__c FROM compliancequest__SQX_Change_Order__c WHERE Id IN :co
        ]) { m.put(x.Id, x.compliancequest__Title__c); }
        return m;
    }
}
