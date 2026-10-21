@IsTest
private class SummaryRichTextTest {

    @IsTest
    static void markdownBoldItalicAndParagraphs() {
        String html = SummaryRichText.fromAgent('Intro **bold** and *italic*.\n\nSecond line\nwrapped');
        Assert.areEqual('<p>Intro <strong>bold</strong> and <em>italic</em>.</p><p>Second line<br/>wrapped</p>', html);
    }

    @IsTest
    static void markdownBulletsAndNumbers() {
        String html = SummaryRichText.fromAgent('- one\n- two\n\n1. first\n2. second');
        Assert.areEqual('<ul><li>one</li><li>two</li></ul><ol><li>first</li><li>second</li></ol>', html);
    }

    @IsTest
    static void markdownNestedBullets() {
        String html = SummaryRichText.fromAgent('- a\n  - b\n- c');
        Assert.areEqual('<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>', html);
    }

    @IsTest
    static void markdownHeadingsRulesAndLinks() {
        String html = SummaryRichText.fromAgent('# Title\n---\nSee [site](https://example.com) and [bad](javascript:alert(1))');
        Assert.isTrue(html.startsWith('<h2><strong>Title</strong></h2><hr/>'), html);
        Assert.isTrue(html.contains('<a href="https://example.com">site</a>'), html);
        Assert.isFalse(html.contains('<a href="javascript'), html);
    }

    @IsTest
    static void markdownEscapesRawAngleBrackets() {
        String html = SummaryRichText.fromAgent('Torque < 5 & > 2');
        Assert.areEqual('<p>Torque &lt; 5 &amp; &gt; 2</p>', html);
    }

    @IsTest
    static void htmlIsKeptButSanitized() {
        String html = SummaryRichText.fromAgent(
            '<p onclick="x()">Hi <b>there</b></p><script>alert(1)</script><ul><li>a</li></ul><img src=x><a href="javascript:x">l</a><!-- c -->');
        Assert.areEqual('<p>Hi <b>there</b></p><ul><li>a</li></ul><a>l</a>', html);
    }

    @IsTest
    static void blankReturnsEmpty() {
        Assert.areEqual('', SummaryRichText.fromAgent(null));
        Assert.areEqual('', SummaryRichText.fromAgent('   '));
    }

    @IsTest
    static void longTextIsCutAtBlockBoundary() {
        List<String> items = new List<String>();
        for (Integer i = 0; i < 3000; i++) { items.add('- item number ' + i); }
        String html = SummaryRichText.fromAgent(String.join(items, '\n'));
        Assert.isTrue(html.length() <= SummaryRichText.MAX_LENGTH, 'length ' + html.length());
        Assert.isTrue(html.endsWith(SummaryRichText.TRUNCATION_NOTE));

        List<String> paras = new List<String>();
        for (Integer i = 0; i < 3000; i++) { paras.add('Paragraph number ' + i + ' with **bold** text'); }
        String html2 = SummaryRichText.fromAgent(String.join(paras, '\n\n'));
        Assert.isTrue(html2.length() <= SummaryRichText.MAX_LENGTH);
        Assert.isTrue(html2.contains('</p>' + SummaryRichText.TRUNCATION_NOTE));
    }

    @IsTest
    static void smallLimitFallsBackToPlainText() {
        String html = SummaryRichText.fromAgent('One very long single paragraph that cannot fit anywhere at all, so it has to be cut down to the limit.', 100);
        Assert.isTrue(html.length() <= 100, html);
        Assert.isTrue(html.endsWith(SummaryRichText.TRUNCATION_NOTE));
    }

    @IsTest
    static void flattenedTextGetsHeadingsAndBulletsBack() {
        String flat = 'Associated Items The primary part is Automobile (AUT-1000). Counts by part: Spark Plug: Nonconformances 7 (Draft 5, Open 2). '
            + 'Most relevant records: NC-000055 | Open | Automobile; CAPA-000029 | Open | Automobile. '
            + 'Product History Review PHR-000002 is in *Draft* status. '
            + 'Trends, gaps and next steps  - Trend: many open NCs.  - Gap: answers missing. This is an AI-generated draft that requires review.';
        String html = SummaryRichText.fromAgent(flat);
        Assert.isTrue(html.startsWith('<h3><strong>Associated Items</strong></h3>'), html);
        Assert.isTrue(html.contains('<h3><strong>Product History Review</strong></h3>'), html);
        Assert.isTrue(html.contains('<h3><strong>Trends, gaps and next steps</strong></h3>'), html);
        Assert.isTrue(html.contains('<ul><li>NC-000055 | Open | Automobile</li><li>CAPA-000029 | Open | Automobile.</li></ul>'), html);
        Assert.isTrue(html.contains('<ul><li>Trend: many open NCs.</li><li>Gap: answers missing.</li></ul>'), html);
        Assert.isTrue(html.endsWith('<p>This is an AI-generated draft that requires review.</p>'), html);
    }

    @IsTest
    static void textWithLineBreaksIsNotRearranged() {
        String text = 'Associated Items are fine here, and this line is long enough to pass the length check for restoring breaks, so keep it as is.\nNext line';
        Assert.areEqual(text, SummaryRichText.restoreLineBreaks(text));
    }

    @IsTest
    static void partlyFlattenedTextKeepsStructure() {
        String text = 'Complaint Overview\nThe primary complaint COM-0000000002 reports an engine misfire, open and in progress. Most relevant to the reported problem:\n\n'
            + '* NC-000042 | Draft | Automobile | Engine misfire.\n\nMost relevant associated records: - NC-000042 | Draft | Automobile. - NC-000041 | Draft | Spark Plug.\n\n'
            + 'Trends, gaps and next steps\n\n* Trend: Spark Plug has multiple NCs. - Trend: Engine Block shows open items. - Gaps: several answers missing.\n\n'
            + 'Product History Review\nPHR-000000 Status: Draft. - Recommended next steps: execute INS-0000000000.\nThis is an AI-generated draft that requires investigator review.';
        String html = SummaryRichText.fromAgent(text);
        Assert.isTrue(html.startsWith('<h3><strong>Complaint Overview</strong></h3><p>The primary complaint'), html);
        Assert.isTrue(html.contains('<h3><strong>Trends, gaps and next steps</strong></h3>'), html);
        Assert.isTrue(html.contains('<h3><strong>Product History Review</strong></h3><p>PHR-000000 Status: Draft.</p>'), html);
        Assert.isTrue(html.contains('<li>NC-000041 | Draft | Spark Plug.</li>'), html);
        Assert.isTrue(html.contains('<li>Trend: Spark Plug has multiple NCs.</li><li>Trend: Engine Block shows open items.</li><li>Gaps: several answers missing.</li>'), html);
        Assert.isTrue(html.contains('<li>Recommended next steps: execute INS-0000000000.</li>'), html);
        Assert.isTrue(html.endsWith('<p>This is an AI-generated draft that requires investigator review.</p>'), html);
    }

    @IsTest
    static void relativeAndAnchorLinksAreKept() {
        String html = SummaryRichText.fromAgent('See [NC-000042](/a0Bhm000001AbCdEAK) and <a href=\'/a0Chm000002XyZaEAL\'>CAPA-000016</a> and [bad](//evil.com).');
        Assert.isTrue(html.contains('<a href="/a0Bhm000001AbCdEAK">NC-000042</a>'), html);
        Assert.isTrue(html.contains('<a href="/a0Chm000002XyZaEAL">CAPA-000016</a>'), html);
        Assert.isFalse(html.contains('evil.com"'), html);
    }
}
