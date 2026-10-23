@IsTest
private class PhrDescriptionCheckTest {

    static compliancequest__SQX_Complaint__c complaint(String description) {
        return new compliancequest__SQX_Complaint__c(compliancequest__Description__c = description);
    }

    static PhrDescriptionCheck.Finding find(List<PhrDescriptionCheck.Finding> fs, String label) {
        for (PhrDescriptionCheck.Finding f : fs) { if (f.label == label) { return f; } }
        return null;
    }

    @IsTest static void detailsInTheDescriptionThatAreMissingAreReported() {
        List<PhrDescriptionCheck.Finding> fs = PhrDescriptionCheck.check(complaint(
            'Hub separated on Oct 3, 2026. Lot number: LT-2291. Catalog # BR-450. 3 units affected. The patient was injured.'));
        Assert.isTrue(find(fs, 'Description: lot or serial').detail.contains('LT-2291'));
        Assert.isTrue(find(fs, 'Description: part').detail.contains('BR-450'));
        Assert.isTrue(find(fs, 'Description: date').detail.contains('Oct 3, 2026'));
        Assert.isTrue(find(fs, 'Description: quantity').detail.contains('3 units'));
        Assert.isTrue(find(fs, 'Description: patient or injury').detail.contains('"patient"'));
        for (PhrDescriptionCheck.Finding f : fs) { Assert.isTrue(f.isGap, f.label); }
    }

    @IsTest static void differentValuesAreFlaggedAndMatchingOnesAreNot() {
        compliancequest__SQX_Complaint__c c = complaint('Serial no. SN00123 failed; model X200-3; 2 devices returned.');
        c.compliancequest__Lot_Number__c = 'SN-00999';
        c.compliancequest__Model_Name__c = 'x200 3';
        c.compliancequest__Complaint_Quantity__c = 5;
        c.compliancequest__Occurrence_Date__c = Date.today();
        List<PhrDescriptionCheck.Finding> fs = PhrDescriptionCheck.check(c);
        Assert.isTrue(find(fs, 'Description: lot or serial').detail.contains('SN-00999'));
        Assert.isNull(find(fs, 'Description: part'), 'The model number matches');
        Assert.isTrue(find(fs, 'Description: quantity').detail.contains('is 5'));
    }

    @IsTest static void nothingMissingGivesOneOkLine() {
        compliancequest__SQX_Complaint__c c = complaint('Customer reports the hub was loose. It may be a lot of trouble.');
        List<PhrDescriptionCheck.Finding> fs = PhrDescriptionCheck.check(c);
        Assert.areEqual(1, fs.size());
        Assert.isFalse(fs[0].isGap);
    }

    @IsTest static void blankDescriptionIsAGap() {
        List<PhrDescriptionCheck.Finding> fs = PhrDescriptionCheck.check(complaint(null));
        Assert.areEqual(1, fs.size());
        Assert.isTrue(fs[0].isGap);
    }

    @IsTest static void codesCompareLoosely() {
        Assert.isTrue(PhrDescriptionCheck.same('lt-2291', 'LT2291'));
        Assert.isFalse(PhrDescriptionCheck.same('LT-2291', null));
        Assert.isFalse(PhrDescriptionCheck.same('A1', 'B2'));
        Assert.areEqual('LT-2291', PhrDescriptionCheck.firstGroup(
            Pattern.compile('(?i)lot\\s+([A-Z0-9-]+)'), 'lot LT-2291'));
    }
}
