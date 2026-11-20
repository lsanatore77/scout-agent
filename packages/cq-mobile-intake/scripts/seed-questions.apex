// CQ Mobile Intake: default setup data. Run once after installing or deploying the package:
//
//   sf apex run --file scripts\seed-questions.apex --target-org <alias>
//
// Creates the 9 default Event Questions (with roles, urgent answers, help text and the Case field each answer goes
// to), attaches each question's read-aloud clip from the package (static resources CQ_Intake_Clip_01..09), and adds
// the default Quick Log Categories. Safe to run again: a question or category that already exists (same text / name)
// is left as it is, and a clip is attached only to a question that has no file yet.

// Question text, Order, Answer Type, Choices, Role, Urgent When, Help Text, Required, Case Field, clip
List<List<Object>> defaults = new List<List<Object>>{
    new List<Object>{ 'Where did this happen?', 1.0, 'Choice', 'In Our Plant;At a Supplier;At a Customer', 'Where Found', null, null, true, 'Where_Found__c', '01' },
    new List<Object>{ 'Which customer?', 1.1, 'Text', null, 'Customer', null, 'The customer who reported it, so a complaint can name them.', false, 'Customer_Reported__c', '02' },
    new List<Object>{ 'Which supplier?', 1.2, 'Text', null, 'Supplier', null, 'The supplier the part came from.', false, 'Supplier_Reported__c', '03' },
    new List<Object>{ 'Do you have a lot or batch number?', 1.5, 'Text', null, 'Lot Or Part', null, 'If you have it, the product links automatically. If not, tell me which product it was.', false, null, '04' },
    new List<Object>{ 'Did this affect a product?', 2.0, 'Yes or No', null, 'Product Affected', null, null, true, 'Product_Affected__c', '05' },
    new List<Object>{ 'Was anyone injured?', 3.0, 'Yes or No', null, 'Injury', 'Yes', 'If yes, get help first and follow your site\'s injury procedure.', true, 'Injury_Reported__c', '06' },
    new List<Object>{ 'Could anyone get hurt, or is product safety at risk?', 4.0, 'Choice', 'No;Yes;Not Sure', 'Safety Risk', 'Yes;Not Sure', null, true, 'Safety_Risk_Reported__c', '07' },
    new List<Object>{ 'Which test or inspection found it?', 5.0, 'Text', null, 'None', null, 'Optional.', false, 'Found_By__c', '08' },
    new List<Object>{ 'Who was hurt?', 5.0, 'Text', null, 'Injured Person', null, 'The name of the person who was injured, so a Safety Event can be raised.', false, 'Injured_Person__c', '09' }
};

// ---- questions
Map<String, Event_Question__c> byText = new Map<String, Event_Question__c>();
for (Event_Question__c q : [SELECT Id, Question__c FROM Event_Question__c]) { byText.put(q.Question__c, q); }
List<Event_Question__c> newQs = new List<Event_Question__c>();
for (List<Object> d : defaults) {
    String text = (String) d[0];
    if (byText.containsKey(text)) { continue; }
    Event_Question__c q = new Event_Question__c(Question__c = text, Order__c = (Decimal) d[1], Answer_Type__c = (String) d[2],
        Choices__c = (String) d[3], Role__c = (String) d[4], Urgent_When__c = (String) d[5], Help_Text__c = (String) d[6],
        Required__c = (Boolean) d[7], Case_Field__c = (String) d[8], Audio_Source_Text__c = text, Active__c = true);
    newQs.add(q);
    byText.put(text, q);
}
insert newQs;
System.debug(String.format('Questions added: {0}, already there: {1}', new List<Object>{ newQs.size(), defaults.size() - newQs.size() }));

// ---- clips: from the package's static resources, onto questions that have no file yet
Set<Id> qIds = new Set<Id>();
for (Event_Question__c q : byText.values()) { qIds.add(q.Id); }
Set<Id> hasFile = new Set<Id>();
for (ContentDocumentLink l : [SELECT LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId IN :qIds]) { hasFile.add(l.LinkedEntityId); }
Map<String, StaticResource> clips = new Map<String, StaticResource>();
for (StaticResource r : [SELECT Name, Body FROM StaticResource WHERE Name LIKE 'CQ_Intake_Clip_%']) { clips.put(r.Name.right(2), r); }
List<ContentVersion> files = new List<ContentVersion>();
for (List<Object> d : defaults) {
    Event_Question__c q = byText.get((String) d[0]);
    StaticResource r = clips.get((String) d[9]);
    if (q == null || hasFile.contains(q.Id) || r == null) { continue; }
    files.add(new ContentVersion(Title = String.format('Clip {0}: {1}', new List<Object>{ d[9], d[0] }), PathOnClient = String.format('clip_{0}.wav', new List<Object>{ d[9] }), VersionData = r.Body,
        FirstPublishLocationId = q.Id));
}
insert files;
System.debug(String.format('Clips attached: {0}{1}', new List<Object>{ files.size(), clips.isEmpty() ? ' (no CQ_Intake_Clip_ static resources found)' : '' }));

// ---- quick-log categories (used by the desktop quick log)
Set<String> haveCat = new Set<String>();
for (Quick_Log_Category__c c : [SELECT Name FROM Quick_Log_Category__c]) { haveCat.add(c.Name); }
List<Quick_Log_Category__c> cats = new List<Quick_Log_Category__c>();
for (Quick_Log_Category__c c : new List<Quick_Log_Category__c>{
        new Quick_Log_Category__c(Name = 'Broken Screw', Description__c = 'Fastener snapped at assembly', Disposition__c = 'Scrap the screw, replace', Limit__c = 10, Days__c = 30, Scope__c = 'Same Part', Active__c = true),
        new Quick_Log_Category__c(Name = 'Cosmetic Scratch', Description__c = 'Non-functional surface', Disposition__c = 'Use as is (cosmetic class C)', Limit__c = 15, Days__c = 30, Scope__c = 'Same Part', Active__c = true),
        new Quick_Log_Category__c(Name = 'Label Smudge', Description__c = 'Reprinted at the line', Disposition__c = 'Reprint label', Limit__c = 10, Days__c = 30, Scope__c = 'All Parts', Active__c = true),
        new Quick_Log_Category__c(Name = 'Damaged Carton', Description__c = 'Repacked, product OK', Disposition__c = 'Repack', Limit__c = 12, Days__c = 30, Scope__c = 'All Parts', Active__c = true) }) {
    if (!haveCat.contains(c.Name)) { cats.add(c); }
}
insert cats;
System.debug(String.format('Quick Log Categories added: {0}', new List<Object>{ cats.size() }));
