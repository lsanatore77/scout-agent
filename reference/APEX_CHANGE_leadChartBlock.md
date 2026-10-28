# Apex addition for the report chart (not deployed)

The v2 template has a `{{leadChartBlock}}` placeholder beside the top-records table. Until the
renderer knows that placeholder it is removed, so the table takes the full width and the template
works as it is today. This change makes the renderer fill it.

## PhrReportRenderer.cls

### 1. In `buildValues`, after `v.put('leadBlock', leadBlock(d));`

```apex
v.put('leadChartBlock', leadChartBlock(d));
```

and add `'leadChartBlock'` to the list that is blanked when `!d.hasComplaint`.

### 2. New methods (anywhere in the class)

```apex
/** Small bar chart beside the top-records table: records by match colour, and how many are still open. */
private static String leadChartBlock(PhrReportData d) {
    if (d.leadRows.isEmpty()) { return ''; }
    Map<String, Integer> byColour = new Map<String, Integer>{ 'Red' => 0, 'Yellow' => 0, 'Grey' => 0 };
    Integer open = 0;
    for (PhrReportData.LeadRow r : d.leadRows) {
        String c = String.isBlank(r.colour) ? 'Grey' : r.colour;
        if (!byColour.containsKey(c)) { byColour.put(c, 0); }
        byColour.put(c, byColour.get(c) + 1);
        if (!isClosed(r.status)) { open++; }
    }
    Integer total = d.leadRows.size();
    String s = '<table class="chart"><tr><td class="pad"><div class="chartlabel">Top records by match</div>';
    for (String c : new List<String>{ 'Red', 'Yellow', 'Grey' }) {
        s += chartBar(c, 'c-' + c.toLowerCase(), byColour.get(c), total);
    }
    s += '<div class="total">' + d.totalLeads + '</div><div class="totallabel">records worth reviewing</div>';
    s += '<div class="chartlabel" style="margin-top: 10px;">Still open (of top ' + total + ')</div>';
    s += '<table class="row"><tr><td><table class="bar"><tr>'
        + (open > 0 ? '<td class="bar-done" style="width: ' + pct(open, total) + '%;"></td>' : '')
        + '<td class="rest"></td></tr></table></td><td class="n">' + open + '</td></tr></table>';
    return s + '</td></tr></table>';
}

private static String chartBar(String label, String cls, Integer n, Integer total) {
    Integer p = pct(n, total);
    return '<table class="row"><tr><td class="lbl">' + esc(label) + '</td><td><table class="bar"><tr>'
        + (p > 0 ? '<td class="' + cls + '" style="width: ' + p + '%;"></td>' : '')
        + '<td class="rest"></td></tr></table></td><td class="n">' + n + '</td></tr></table>';
}

private static Integer pct(Integer n, Integer total) {
    return total == 0 ? 0 : Integer.valueOf(Math.round(n * 100.0 / total));
}

private static Boolean isClosed(String status) {
    if (String.isBlank(status)) { return false; }
    String s = status.toLowerCase();
    return s.contains('closed') || s.contains('complete') || s.contains('cancel') || s.contains('void');
}
```

Notes
- The colour counts are of the **top rows shown** (`d.leadRows`), because only those carry a
  colour; the big number is `d.totalLeads`, every record found. The chart labels say so.
- No new data is queried; everything comes from `PhrReportData` as it is.
- The chart uses only the CSS classes already in the v2 template (`chart`, `row`, `bar`, `lbl`,
  `n`, `rest`, `total`, `totallabel`, `chartlabel`, and the `c-red` / `c-yellow` / `c-grey` /
  `bar-done` colours). With the old template, the chart block is simply not referenced.

## PhrReportCoverageTest.cls

Add one test so the new code is covered:

```apex
@IsTest static void chartCountsTheTopRecords() {
    PhrReportData d = fullData();   // 2 red rows, both Open
    String out = PhrReportRenderer.fill(
        '<html xmlns="http://www.w3.org/1999/xhtml"><body>{{leadChartBlock}}</body></html>', d, false);
    System.assert(out.contains('Top records by match'), out);
    System.assert(out.contains('class="n">2</td>'), 'two red rows: ' + out);
    System.assert(out.contains('<div class="total">12</div>'), out);
}
```
