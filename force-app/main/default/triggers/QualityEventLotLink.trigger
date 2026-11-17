/**
 * When a Quality Event is created with a lot but no part, link the part from the lot (the way CQ does on
 * its own records) and complete a shorthand lot to its full number. Runs before insert so the values save
 * with the record. Only fills a blank part — never overrides a part someone chose.
 */
trigger QualityEventLotLink on Quality_Event__c (before insert) {
    List<Quality_Event__c> need = new List<Quality_Event__c>();
    List<String> lots = new List<String>();
    for (Quality_Event__c e : Trigger.new) {
        if (e.Part__c == null && String.isNotBlank(e.Lot_Number__c)) {
            need.add(e);
            lots.add(e.Lot_Number__c);
        }
    }
    if (need.isEmpty()) { return; }

    List<CqEventLotLink.LotMatch> matches = CqEventLotLink.resolveAll(lots);
    for (Integer i = 0; i < need.size(); i++) {
        CqEventLotLink.LotMatch m = matches[i];
        if (m != null && m.partId != null) {
            need[i].Part__c = m.partId;
            if (String.isNotBlank(m.lotName)) { need[i].Lot_Number__c = m.lotName; }
        }
    }
}
