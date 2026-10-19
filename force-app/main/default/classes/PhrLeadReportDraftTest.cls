@IsTest
private class PhrLeadReportDraftTest {
    @IsTest
    static void cleanForPdfFixesEntitiesAndBreaks() {
        String r = PhrLeadReportController.cleanForPdf('<p>a&nbsp;b<br></p>');
        System.assertEquals('<p>a&#160;b<br/></p>', r);
    }
}
