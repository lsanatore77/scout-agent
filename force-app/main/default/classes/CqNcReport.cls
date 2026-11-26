/**
 * Report a Nonconformance: the two-step popup anyone can use to raise an NC directly, without intake.
 *
 * Step 1 checks for a possible duplicate while the person types: lot numbers written in the text are matched against
 * the lots on open NCs (no AI). Step 2 runs CQ.AI on Next: CQ's own Entity Extraction prompt with our field definitions
 * fills the record (title by the title rule, part, lot, quantity, failure, where found, type), and CQ's Paraphraser
 * suggests a clearer description. Nothing is saved before Create, which inserts the NC (plus its impacted part and lot
 * when both are known) and sends it straight to Triage and its queue (CqNcAutoTriage), with no Submit step.
 * Merge adds the report to the existing NC instead: a post on its feed and a task for its owner.
 *
 * Decided with Lou, 25 Nov 2026 (docs/backlog.md, "Report a Nonconformance").
 */
public with sharing class CqNcReport {
    public static final String SUBMIT = 'submit';
    public static final Integer TITLE_MAX = 80;
    static final List<String> OPEN_EXCLUDED = new List<String>{ 'Closed', 'Void', 'Complete' };
    static final List<String> TYPES = new List<String>{ 'Internal', 'Supplier', 'Customer' };

    // Canned model output for tests (prompt templates cannot run in tests).
    @TestVisible static String mockFill;
    @TestVisible static String mockWording;

    // The fields CQ.AI is asked for, in CQ's Entity Extraction prompt. TITLE follows the title rule (Lou, 25 Nov);
    // TYPE follows the type rule (Lou, 25 Nov).
    @TestVisible static final String ENTITIES = String.join(new List<String>{
        'TITLE (one line naming the item, what is wrong with it, and where it was found, for example: Balloon burst below rated pressure at final inspection. Under 80 characters, sentence case, no full stop. Leave out lot numbers, quantities, dates, part numbers and names of people. Use the words of the description)',
        'PART (the part number if one is written, otherwise the product or part name)',
        'LOT (the lot or batch number, only if one is written)',
        'UNITS AFFECTED (how many units were defective, as a number)',
        'DEFECT (what is wrong with the item, a few words; not the cause, and not how or where it was found)',
        'FOUND AT (the inspection, test or process step where it was found)',
        'TYPE (answer: Customer if it came from the field, a hospital, a patient, a procedure or a returned device; Supplier if it was found at incoming inspection on supplier material; otherwise Internal)'
    }, ', ');

    public class Dup {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String lot;
        @AuraEnabled public String stage;
    }

    public class Fill {
        @AuraEnabled public Boolean cqai = false;   // CQ.AI read it (false = the plain fallback read it)
        @AuraEnabled public String title;
        @AuraEnabled public Id partId;
        @AuraEnabled public String partNumber;
        @AuraEnabled public String partName;
        @AuraEnabled public String partTerm;        // CQ.AI's word for the part when no real part was found, to start the picker
        @AuraEnabled public String lot;
        @AuraEnabled public Boolean lotKnown = false; // the lot is a real lot record
        @AuraEnabled public Integer quantity;
        @AuraEnabled public String type;
        @AuraEnabled public String failure;
        @AuraEnabled public String foundAt;
    }

    public class Created {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String stage;
        @AuraEnabled public List<String> warnings = new List<String>();
    }

    /** What the popup sends on Create. suggested holds what CQ.AI filled in, so the note can show it beside what was saved. */
    public class Report {
        public String description;      // the description saved (the person's words or CQ.AI's wording)
        public String asReported;       // the person's own words
        public Boolean usedSuggestion;  // the person chose CQ.AI's wording
        public String title;
        public Id partId;
        public String lot;
        public Integer quantity;
        public String type;
        public String failure;
        public Map<String, String> suggested;
    }

    // ---------------------------------------------------------------- step 1 and 2: possible duplicates

    /** Open NCs whose lot is written in the text (or is the lot CQ.AI found). Up to three, newest first. */
    @AuraEnabled(cacheable=true)
    public static List<Dup> duplicates(String text, String lot) {
        Set<String> tokens = lotTokens(text);
        if (String.isNotBlank(lot)) { tokens.add(lot.trim().toUpperCase()); }
        List<Dup> out = new List<Dup>();
        if (tokens.isEmpty()) { return out; }
        Map<Id, String> lotOf = new Map<Id, String>();
        for (compliancequest__SQX_NC_Impacted_Product__c ip : [SELECT compliancequest__SQX_Nonconformance__c, compliancequest__Lot_Number__c
                FROM compliancequest__SQX_NC_Impacted_Product__c
                WHERE compliancequest__Lot_Number__c IN :tokens AND compliancequest__SQX_Nonconformance__r.compliancequest__Status__c NOT IN :OPEN_EXCLUDED
                WITH USER_MODE LIMIT 50]) {
            lotOf.put(ip.compliancequest__SQX_Nonconformance__c, ip.compliancequest__Lot_Number__c);
        }
        for (compliancequest__SQX_Nonconformance__c n : [SELECT Id, compliancequest__Lot_Number__c FROM compliancequest__SQX_Nonconformance__c
                WHERE compliancequest__Lot_Number__c IN :tokens AND compliancequest__Status__c NOT IN :OPEN_EXCLUDED WITH USER_MODE LIMIT 50]) {
            if (!lotOf.containsKey(n.Id)) { lotOf.put(n.Id, n.compliancequest__Lot_Number__c); }
        }
        if (lotOf.isEmpty()) { return out; }
        Map<String, String> stageLabel = new Map<String, String>();
        for (Schema.PicklistEntry e : compliancequest__SQX_Nonconformance__c.compliancequest__Record_Stage__c.getDescribe().getPicklistValues()) {
            stageLabel.put(e.getValue(), e.getLabel());
        }
        for (compliancequest__SQX_Nonconformance__c n : [SELECT Id, Name, compliancequest__NC_Title__c, compliancequest__Record_Stage__c
                FROM compliancequest__SQX_Nonconformance__c WHERE Id IN :lotOf.keySet() WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 3]) {
            Dup d = new Dup();
            d.id = n.Id; d.name = n.Name; d.title = n.compliancequest__NC_Title__c; d.lot = lotOf.get(n.Id);
            d.stage = stageLabel.containsKey(n.compliancequest__Record_Stage__c) ? stageLabel.get(n.compliancequest__Record_Stage__c) : n.compliancequest__Record_Stage__c;
            out.add(d);
        }
        return out;
    }

    /** Words that look like a lot number: letters and digits joined by dashes, with at least one digit (L26-0915, BL-25-0311). */
    @TestVisible
    static Set<String> lotTokens(String text) {
        Set<String> out = new Set<String>();
        if (String.isBlank(text)) { return out; }
        Matcher m = Pattern.compile('\\b[A-Za-z0-9]{1,12}(?:-[A-Za-z0-9]{1,12}){1,4}\\b').matcher(text);
        while (m.find()) {
            String t = m.group();
            if (t.length() >= 4 && t.length() <= 80 && Pattern.matches('.*[0-9].*', t)) { out.add(t.toUpperCase()); }
        }
        return out;
    }

    // ---------------------------------------------------------------- step 1: @ picks a lot or part

    public class Mention {
        @AuraEnabled public String kind;        // 'lot' or 'part'
        @AuraEnabled public String label;       // what goes in the text: the lot number, or the part number
        @AuraEnabled public String sub;         // the line under it: the lot's part, or the part's name
        @AuraEnabled public String lot;
        @AuraEnabled public Id partId;
        @AuraEnabled public String partNumber;
        @AuraEnabled public String partName;
    }

    /** What @ offers while the person types: up to five lots whose number starts with the term, and up to five active parts. */
    @AuraEnabled(cacheable=true)
    public static List<Mention> mentions(String term) {
        List<Mention> out = new List<Mention>();
        String t = term == null ? '' : term.trim();
        if (t.length() < 1 || t.length() > 40) { return out; }
        String safe = t.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
        String starts = safe + '%';
        String anywhere = '%' + safe + '%';
        List<compliancequest__SQX_Lot_Info__c> lots = [SELECT Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Lot_Info__c
            WHERE Name LIKE :starts WITH USER_MODE ORDER BY Name DESC LIMIT 5];
        Set<String> nums = new Set<String>();
        for (compliancequest__SQX_Lot_Info__c l : lots) { if (String.isNotBlank(l.compliancequest__Part_Number__c)) { nums.add(l.compliancequest__Part_Number__c); } }
        Map<String, compliancequest__SQX_Part__c> byNum = new Map<String, compliancequest__SQX_Part__c>();
        if (!nums.isEmpty()) {
            for (compliancequest__SQX_Part__c p : [SELECT Id, Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Part__c
                    WHERE compliancequest__Part_Number__c IN :nums WITH USER_MODE]) {
                byNum.put(p.compliancequest__Part_Number__c, p);
            }
        }
        for (compliancequest__SQX_Lot_Info__c l : lots) {
            Mention m = new Mention();
            m.kind = 'lot'; m.label = l.Name; m.lot = l.Name;
            compliancequest__SQX_Part__c p = byNum.get(l.compliancequest__Part_Number__c);
            if (p != null) { m.partId = p.Id; m.partNumber = p.compliancequest__Part_Number__c; m.partName = p.Name; }
            m.sub = p != null ? p.compliancequest__Part_Number__c + ' · ' + p.Name : l.compliancequest__Part_Number__c;
            out.add(m);
        }
        for (compliancequest__SQX_Part__c p : [SELECT Id, Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Part__c
                WHERE (compliancequest__Part_Number__c LIKE :anywhere OR Name LIKE :anywhere) AND compliancequest__Active__c = true
                WITH USER_MODE ORDER BY compliancequest__Part_Number__c LIMIT 5]) {
            Mention m = new Mention();
            m.kind = 'part'; m.label = String.isNotBlank(p.compliancequest__Part_Number__c) ? p.compliancequest__Part_Number__c : p.Name;
            m.sub = p.Name; m.partId = p.Id; m.partNumber = p.compliancequest__Part_Number__c; m.partName = p.Name;
            out.add(m);
        }
        return out;
    }

    // ---------------------------------------------------------------- step 2: CQ.AI fills in the record

    /** CQ.AI reads the description and fills the record. If CQ.AI cannot run, a plain read picks out the lot and the quantity. */
    @AuraEnabled
    public static Fill fillIn(String text) {
        if (String.isBlank(text)) { throw new AuraHandledException('Say what happened first.'); }
        Fill f = new Fill();
        Map<String, String> v = new Map<String, String>();
        try { v = parse(extract(text)); f.cqai = !v.isEmpty(); } catch (Exception e) { v = new Map<String, String>(); }
        if (v.isEmpty()) { v = plainRead(text); }

        f.type = typeOf(v.get('TYPE'));
        f.failure = clip(v.get('DEFECT'), 255);
        f.foundAt = v.get('FOUND AT');
        f.title = titleOf(v.get('TITLE'), f.foundAt);
        f.quantity = toInt(v.get('UNITS AFFECTED'));

        // lot, and the part from the lot's own record
        String lot = v.get('LOT');
        Set<String> tokens = lotTokens(text);
        if (String.isBlank(lot) && !tokens.isEmpty()) {
            List<compliancequest__SQX_Lot_Info__c> known = [SELECT Name FROM compliancequest__SQX_Lot_Info__c WHERE Name IN :tokens WITH USER_MODE LIMIT 1];
            if (!known.isEmpty()) { lot = known[0].Name; }
        }
        if (String.isNotBlank(lot)) {
            f.lot = lot.trim().left(80);
            compliancequest__SQX_Lot_Info__c li = lotRecord(f.lot);
            if (li != null) {
                f.lotKnown = true;
                f.lot = li.Name;
                setPart(f, partByNumber(li.compliancequest__Part_Number__c));
            }
        }
        // no part from the lot: a part number written in the text, else CQ.AI's word starts the picker
        String partRaw = v.get('PART');
        if (f.partId == null && String.isNotBlank(partRaw)) { setPart(f, partByNumber(partRaw)); }
        if (f.partId == null && !tokens.isEmpty()) {
            List<compliancequest__SQX_Part__c> p = [SELECT Id, Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Part__c
                WHERE compliancequest__Part_Number__c IN :tokens WITH USER_MODE LIMIT 1];
            if (!p.isEmpty()) { setPart(f, p[0]); }
        }
        if (f.partId == null && String.isNotBlank(partRaw)) { f.partTerm = partRaw.trim().left(40); }
        return f;
    }

    /** CQ.AI's clearer wording of the description (CQ's Paraphraser). Null when CQ.AI cannot run; the step then shows the person's words only. */
    @AuraEnabled
    public static String suggestDescription(String text) {
        if (String.isBlank(text)) { return null; }
        try {
            String s = wording(text);
            return String.isBlank(s) ? null : s.trim();
        } catch (Exception e) {
            return null;
        }
    }

    // ---------------------------------------------------------------- Create and Merge

    /** Inserts the NC (and its impacted part and lot), keeps what CQ.AI suggested beside it, then sends it to Triage and its queue. */
    @AuraEnabled
    public static Created create(String reportJson) {
        Report r = (Report) JSON.deserialize(reportJson, Report.class);
        if (r == null || String.isBlank(r.description)) { throw new AuraHandledException('Say what happened first.'); }
        Created c = new Created();
        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(
            compliancequest__Description__c = r.description.trim(),
            compliancequest__Description_RT__c = asHtml(r.description),
            compliancequest__NC_Title__c = String.isBlank(r.title) ? titleOf(null, null, r.description) : r.title.trim().left(255),
            compliancequest__Type__c = TYPES.contains(r.type) ? r.type : 'Internal',
            compliancequest__Type_Of_Issue__c = 'Product',
            compliancequest__SQX_Part__c = r.partId,
            compliancequest__Lot_Number__c = String.isBlank(r.lot) ? null : r.lot.trim().left(80),
            compliancequest__Defective_Quantity__c = r.quantity,
            compliancequest__Defect_Description__c = clip(r.failure, 255));
        // the move to Triage waits until the impacted part, the words as reported and the note are added (below)
        CqNcAutoTriage.deferred = true;
        try {
            insert as user nc;
        } catch (Exception e) {
            throw new AuraHandledException('The NC was not created: ' + CqSave.why(e));
        } finally {
            CqNcAutoTriage.deferred = false;
        }
        c.id = nc.Id;
        c.title = nc.compliancequest__NC_Title__c;

        // the impacted part and lot, which Triage's draft dispositions start from (unless CQ already added it from the NC's part and lot)
        if (r.partId != null && String.isNotBlank(r.lot)
                && [SELECT COUNT() FROM compliancequest__SQX_NC_Impacted_Product__c WHERE compliancequest__SQX_Nonconformance__c = :nc.Id WITH USER_MODE] == 0) {
            try {
                insert as user new compliancequest__SQX_NC_Impacted_Product__c(compliancequest__SQX_Nonconformance__c = nc.Id,
                    compliancequest__SQX_Impacted_Part__c = r.partId, compliancequest__Lot_Number__c = r.lot.trim().left(80),
                    compliancequest__Lot_Quantity__c = r.quantity);
            } catch (Exception e) {
                c.warnings.add('The impacted part and lot were not added: ' + CqSave.why(e));
            }
        }

        // the person's own words when CQ.AI's wording was used, and a note of what CQ.AI suggested beside what was saved
        try {
            if (r.usedSuggestion == true && String.isNotBlank(r.asReported)) {
                insert as user new compliancequest__SQX_Quick_NC__c(compliancequest__SQX_Nonconformance__c = nc.Id,
                    compliancequest__Title__c = 'As Reported', compliancequest__Description__c = r.asReported.trim());
            }
        } catch (Exception e) {
            c.warnings.add('The words as reported were not kept: ' + CqSave.why(e));
        }
        try {
            String note = suggestionNote(r);
            if (note != null) { addNote(nc.Id, 'CQ.AI at creation', note); }
        } catch (Exception e) {
            c.warnings.add('The note of CQ.AI\'s suggestions was not kept: ' + CqSave.why(e));
        }

        // straight to Triage and the queue, as every new NC does (CqNcAutoTriage)
        try {
            CqNcAutoTriage.send(new Set<Id>{ nc.Id }, true);
        } catch (Exception e) {
            c.warnings.add('It was not sent to Triage, so it stays in Draft: ' + CqSave.why(e));
        }

        compliancequest__SQX_Nonconformance__c saved = [SELECT Name, compliancequest__Record_Stage__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :nc.Id];
        c.name = saved.Name;
        c.stage = saved.compliancequest__Record_Stage__c;
        return c;
    }

    /** Adds the report to an existing NC instead of creating one: a post on its feed and, when a person owns it, a task for them. */
    @AuraEnabled
    public static Created addToExisting(Id ncId, String text, Integer quantity) {
        if (ncId == null || String.isBlank(text)) { throw new AuraHandledException('Nothing to add.'); }
        compliancequest__SQX_Nonconformance__c nc = [SELECT Id, Name, OwnerId, compliancequest__NC_Title__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId WITH USER_MODE];
        String who = UserInfo.getName();
        String body = 'Another report added by ' + who + ' in CQ.AI Report a Nonconformance'
            + (quantity == null ? '' : ' (defective quantity ' + quantity + ')') + ':\n\n' + text.trim();
        Created c = new Created();
        c.id = nc.Id; c.name = nc.Name; c.title = nc.compliancequest__NC_Title__c;
        try {
            insert as user new FeedItem(ParentId = nc.Id, Body = body.left(10000), Type = 'TextPost');
        } catch (Exception e) {
            // no feed on the NC: keep the report as a note instead
            try { addNote(nc.Id, 'Report added by ' + who, body); } catch (Exception e2) {
                throw new AuraHandledException('The report was not added: ' + CqSave.why(e2));
            }
        }
        if (String.valueOf(nc.OwnerId).startsWith('005') && nc.OwnerId != UserInfo.getUserId()) {
            try {
                insert as user new Task(OwnerId = nc.OwnerId, WhatId = nc.Id, Subject = ('Review a report added to ' + nc.Name).left(255),
                    Description = body.left(32000), Status = 'Not Started', Priority = 'Normal', ActivityDate = Date.today());
            } catch (Exception e) {
                c.warnings.add('The owner was not given a task: ' + CqSave.why(e));
            }
        }
        return c;
    }

    /** One file at a time onto the NC, after Create or Merge (the popup holds the files until a record exists). */
    @AuraEnabled
    public static void attachFile(Id recordId, String fileName, String base64) {
        if (recordId == null || String.isBlank(fileName) || String.isBlank(base64)) { return; }
        try {
            insert as user new ContentVersion(Title = fileName.left(255), PathOnClient = fileName.left(255),
                VersionData = EncodingUtil.base64Decode(base64), FirstPublishLocationId = recordId);
        } catch (Exception e) {
            throw new AuraHandledException(fileName + ' was not attached: ' + CqSave.why(e));
        }
    }

    // ---------------------------------------------------------------- helpers

    static void setPart(Fill f, compliancequest__SQX_Part__c p) {
        if (p == null) { return; }
        f.partId = p.Id; f.partNumber = p.compliancequest__Part_Number__c; f.partName = p.Name; f.partTerm = null;
    }

    static compliancequest__SQX_Lot_Info__c lotRecord(String lot) {
        if (String.isBlank(lot)) { return null; }
        List<compliancequest__SQX_Lot_Info__c> l = [SELECT Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Lot_Info__c
            WHERE Name = :lot.trim() WITH USER_MODE LIMIT 1];
        return l.isEmpty() ? null : l[0];
    }

    static compliancequest__SQX_Part__c partByNumber(String num) {
        if (String.isBlank(num)) { return null; }
        List<compliancequest__SQX_Part__c> p = [SELECT Id, Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Part__c
            WHERE compliancequest__Part_Number__c = :num.trim() WITH USER_MODE LIMIT 1];
        return p.isEmpty() ? null : p[0];
    }

    /** The title rule: item, defect, where found; under 80 characters; sentence case; no full stop. */
    @TestVisible
    static String titleOf(String t, String foundAt) { return titleOf(t, foundAt, null); }
    static String titleOf(String t, String foundAt, String description) {
        String s = String.isBlank(t) ? '' : t.normalizeSpace();
        if (s == '' && String.isNotBlank(description)) {
            s = description.normalizeSpace();
            Integer dot = s.indexOf('. ');
            if (dot > 0) { s = s.left(dot); }
        }
        s = s.removeEnd('.').trim();
        String place = String.isBlank(foundAt) ? '' : foundAt.normalizeSpace().removeEnd('.').trim();
        String low = s.toLowerCase();
        if (place != '' && !low.contains(place.toLowerCase()) && !low.contains(' at ') && !low.contains(' during ')
                && !low.contains(' found ') && (s.length() + 4 + place.length()) <= TITLE_MAX) {
            s = s + ' at ' + place.substring(0, 1).toLowerCase() + place.substring(1);
        }
        if (s.length() > TITLE_MAX) {
            s = s.left(TITLE_MAX);
            Integer sp = s.lastIndexOf(' ');
            if (sp > 40) { s = s.left(sp); }
        }
        return s == '' ? null : s.substring(0, 1).toUpperCase() + s.substring(1);
    }

    static String typeOf(String raw) {
        if (String.isBlank(raw)) { return 'Internal'; }
        for (String t : TYPES) { if (raw.toLowerCase().contains(t.toLowerCase())) { return t; } }
        return 'Internal';
    }

    static Integer toInt(String raw) {
        if (String.isBlank(raw)) { return null; }
        Matcher m = Pattern.compile('[0-9]+').matcher(raw);
        if (!m.find()) { return null; }
        try { Integer n = Integer.valueOf(m.group()); return n > 0 ? n : null; } catch (Exception e) { return null; }
    }

    static String clip(String s, Integer n) { return String.isBlank(s) ? null : s.trim().left(n); }

    static String asHtml(String s) {
        List<String> paras = new List<String>();
        for (String p : s.trim().split('\n\\s*\n')) { paras.add('<p>' + p.escapeHtml4().replace('\n', '<br>') + '</p>'); }
        return String.join(paras, '');
    }

    /** Without CQ.AI: the first lot-like word, and a number followed by units, pieces or the like. */
    @TestVisible
    static Map<String, String> plainRead(String text) {
        Map<String, String> out = new Map<String, String>();
        for (String t : lotTokens(text)) { out.put('LOT', t); break; }
        Matcher m = Pattern.compile('(?i)\\b([0-9]{1,6})\\s+(?:of\\s+[0-9]+\\s+)?(?:units?|pieces?|pcs|parts?|devices?|items?|catheters?|balloons?|housings?|pouches?)\\b').matcher(text);
        if (m.find()) { out.put('UNITS AFFECTED', m.group(1)); }
        return out;
    }

    static Map<String, String> parse(String raw) {
        Map<String, String> out = new Map<String, String>();
        if (String.isBlank(raw)) { return out; }
        Integer a = raw.indexOf('{');
        Integer b = raw.lastIndexOf('}');
        if (a < 0 || b < a) { return out; }
        Object top;
        try { top = JSON.deserializeUntyped(raw.substring(a, b + 1)); } catch (Exception e) { return out; }
        if (!(top instanceof Map<String, Object>)) { return out; }
        Map<String, Object> m = (Map<String, Object>) top;
        for (String k : m.keySet()) {
            Object v = m.get(k);
            Object val = v instanceof Map<String, Object> ? ((Map<String, Object>) v).get('value') : v;
            String s = val == null ? null : String.valueOf(val).trim();
            if (String.isBlank(s) || s == 'null') { continue; }
            String key = k.toUpperCase().trim();
            Integer p = key.indexOf('(');
            if (p > 0) { key = key.substring(0, p).trim(); }
            if (key.endsWith('TITLE')) { key = 'TITLE'; }   // the model sometimes answers NC TITLE
            out.put(key, s);
        }
        return out;
    }

    static String suggestionNote(Report r) {
        if (r.suggested == null || r.suggested.isEmpty()) { return null; }
        Map<String, String> saved = new Map<String, String>{
            'Title' => r.title, 'Lot' => r.lot, 'Defective Quantity' => r.quantity == null ? null : String.valueOf(r.quantity),
            'Type' => r.type, 'Failure' => r.failure };
        if (r.partId != null) {
            compliancequest__SQX_Part__c p = [SELECT compliancequest__Part_Number__c FROM compliancequest__SQX_Part__c WHERE Id = :r.partId WITH USER_MODE];
            saved.put('Part', p.compliancequest__Part_Number__c);
        }
        List<String> lines = new List<String>{ 'What CQ.AI suggested when the NC was reported, and what was saved.' };
        lines.add('Description: ' + (r.usedSuggestion == true ? 'CQ.AI\'s wording used (the words as reported are kept on the NC).' : 'the person\'s own words kept.'));
        for (String k : new List<String>{ 'Title', 'Part', 'Lot', 'Defective Quantity', 'Type', 'Failure' }) {
            String s = r.suggested.get(k);
            String v = saved.get(k);
            if (String.isBlank(s) && String.isBlank(v)) { continue; }
            String verdict = String.isBlank(s) ? 'added by the person' : (s == v ? 'accepted' : (String.isBlank(v) ? 'removed' : 'changed'));
            lines.add(k + ': ' + (String.isBlank(v) ? '(none)' : v) + ' [' + verdict + (verdict == 'changed' || verdict == 'removed' ? '; CQ.AI suggested ' + s : '') + ']');
        }
        return String.join(lines, '\n');
    }

    static void addNote(Id parentId, String title, String text) {
        ContentNote n = new ContentNote(Title = title.left(255),
            Content = Blob.valueOf('<p>' + text.escapeHtml4().replace('\n', '<br>') + '</p>'));
        insert as user n;
        insert as user new ContentDocumentLink(ContentDocumentId = n.Id, LinkedEntityId = parentId, ShareType = 'V');
    }

    // CQ's prompt templates (CQ.AI extension), called by name so this class installs in an org without generative AI.
    static String extract(String text) {
        if (Test.isRunningTest()) { return mockFill; }
        Invocable.Action a = Invocable.Action.createCustomAction('generatePromptResponse', 'cqext__CQSS_Entity_Extraction_Prompt');
        a.setInvocationParameter('Input:Description', text);
        a.setInvocationParameter('Input:Entities', ENTITIES);
        a.setInvocationParameter('Input:Date_Entities', String.valueOf(Date.today()));
        a.setInvocationParameter('Input:Reason_Required', 'false');
        Invocable.Action.Result res = a.invoke()[0];
        if (!res.isSuccess()) { throw new CalloutException(String.valueOf(res.getErrors())); }
        Object out = res.getOutputParameters().get('promptResponse');
        return out == null ? null : String.valueOf(out);
    }

    static String wording(String text) {
        if (Test.isRunningTest()) { return mockWording; }
        Invocable.Action a = Invocable.Action.createCustomAction('generatePromptResponse', 'cqext__CQSS_Paraphraser');
        a.setInvocationParameter('Input:Text_Description', text);
        Invocable.Action.Result res = a.invoke()[0];
        if (!res.isSuccess()) { throw new CalloutException(String.valueOf(res.getErrors())); }
        Object out = res.getOutputParameters().get('promptResponse');
        return out == null ? null : String.valueOf(out);
    }
}
