@IsTest
private class ComplaintLeadRankingTest {

    static PhrQmsPanelController.Row row(String name, Integer score) {
        PhrQmsPanelController.Row r = new PhrQmsPanelController.Row();
        r.name = name;
        r.relevance = score;
        return r;
    }

    @IsTest static void sortsHighestScoreFirstThenName() {
        List<PhrQmsPanelController.Row> sorted = ComplaintLeadRanking.sortByRelevance(new List<PhrQmsPanelController.Row>{
            row('NC-2', 50), row('CAPA-1', 80), row('NC-1', 50), row('INS-1', null) });
        Assert.areEqual('CAPA-1', sorted[0].name);
        Assert.areEqual('NC-1', sorted[1].name);
        Assert.areEqual('NC-2', sorted[2].name);
        Assert.areEqual('INS-1', sorted[3].name);
    }

    @IsTest static void unreadableComplaintGivesANoteNotAnError() {
        String text = ComplaintLeadRanking.buildText(UserInfo.getUserId());
        Assert.isTrue(text.startsWith('## MOST RELEVANT RECORDS'), text);
        Assert.isTrue(text.contains('could not be read') || text.contains('No records ranked'), text);
    }
}
