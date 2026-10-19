@IsTest
private class SummaryHtmlRepairTest {

    static final String SAMPLE =
        '<p><strong>Complaint Overview</strong> Complaint COM-0000000006 concerns a hub that separated from the shaft. It is in Draft status.\n\n</p>'
        + '<p><strong>Associated Items</strong> The primary part has 1 Nonconformance (Draft). The five most relevant records are: '
        + 'NC-000072 (Draft, &quot;Balloon burst&quot;), NC-000076 (Draft, &quot;Field return&quot;), CAPA-000006 (Draft, &quot;Wall thickness&quot;), '
        + 'and INS-0000000019 (Open, &quot;No title&quot;, inspection result: Fail).\n\n</p>'
        + '<p><strong>Analysis and Next Steps</strong> The trend shows *recurring quality actions* on related parts. This is an AI-generated draft that requires investigator review.</p>';

    @IsTest static void titlesBecomeHeadings() {
        String html = SummaryRichText.fromAgent(SummaryHtmlRepair.repair(SAMPLE));
        Assert.isTrue(html.startsWith('<h3><strong>Complaint Overview</strong></h3><p>Complaint <strong>COM-0000000006</strong>'), html);
        Assert.isTrue(html.contains('<p><br/></p><h3><strong>Associated Items</strong></h3>'), html);
        Assert.isTrue(html.contains('<p><br/></p><h3><strong>Analysis and Next Steps</strong></h3>'), html);
    }

    @IsTest static void associatedItemsSectionIsBulletedWithNestedRecords() {
        String html = SummaryRichText.fromAgent(SummaryHtmlRepair.repair(SAMPLE));
        Assert.isTrue(html.contains('<h3><strong>Associated Items</strong></h3><ul><li>The primary part has 1 Nonconformance (Draft).</li><li>The five most relevant records are:<ul><li><strong>NC-000072</strong>'), html);
        Assert.isTrue(html.contains('inspection result: Fail)</li></ul></li></ul>'), html);
    }

    @IsTest static void associatedItemsWithoutRecordListStillBecomesBullets() {
        String s = '<p><strong>Associated Items</strong> The part has 2 Nonconformances (Draft). It has 1 Change Order (Open). No other items were found for this complaint at this time.</p>';
        String out = SummaryHtmlRepair.repair(s);
        Assert.isTrue(out.contains('<ul><li>The part has 2 Nonconformances (Draft).</li><li>It has 1 Change Order (Open).</li>'), out);
    }

    @IsTest static void recordListBecomesBullets() {
        String html = SummaryRichText.fromAgent(SummaryHtmlRepair.repair(SAMPLE));
        Assert.isTrue(html.contains('<ul><li><strong>NC-000072</strong> (Draft, &quot;Balloon burst&quot;)</li><li><strong>NC-000076</strong>'), html);
        Assert.isTrue(html.contains('<li><strong>CAPA-000006</strong> (Draft, &quot;Wall thickness&quot;)</li><li><strong>INS-0000000019</strong> (Open'), html);
        Assert.isFalse(html.contains('<li>and '), html);
    }

    @IsTest static void italicAndDisclaimerAreFixed() {
        String html = SummaryRichText.fromAgent(SummaryHtmlRepair.repair(SAMPLE));
        Assert.isTrue(html.contains('<em>recurring quality actions</em>'), html);
        Assert.isFalse(html.contains('*recurring'), html);
        Assert.isTrue(html.endsWith('<p>This is an AI-generated draft that requires investigator review.</p>'), html);
        Assert.isFalse(html.contains('<p></p>'), html);
    }

    @IsTest static void recordNumbersAreBoldedOnlyOnce() {
        String s = '<p>The records NC-000072 and <strong>CAPA-000006</strong> and the part PTCA-1000 are in this long enough sentence so that the repair does not skip it because of its length.</p>';
        String out = SummaryHtmlRepair.repair(s);
        Assert.isTrue(out.contains('<strong>NC-000072</strong>'), out);
        Assert.isTrue(out.contains('<strong>CAPA-000006</strong>') && !out.contains('<strong><strong>'), out);
        Assert.isFalse(out.contains('<strong>PTCA-1000</strong>'), out);
    }

    @IsTest static void plainTextAndShortTextAreLeftAlone() {
        String plain = 'Complaint Overview\nThe primary complaint reports an engine misfire, open and in progress, and this line is long enough to pass the length check.';
        Assert.areEqual(plain, SummaryHtmlRepair.repair(plain));
        Assert.areEqual('<p>short</p>', SummaryHtmlRepair.repair('<p>short</p>'));
        Assert.areEqual(null, SummaryHtmlRepair.repair(null));
    }

    @IsTest static void singleRecordInParenthesesIsNotListed() {
        String s = '<p>The change order (CHG-000001, Draft) is on the same part as the complaint and is described by its title in the data we were given here.</p>';
        Assert.areEqual(s, SummaryHtmlRepair.recordListsToBullets(s));
    }
}
