# Apex addition for the report chart (not deployed)

The v2 template has a `{{leadChartBlock}}` placeholder in the "Match breakdown" card beside
"1. Overall significance". Until the renderer knows that placeholder it is removed, so the card
renders empty but the rest of the template works as it is today. This change makes the renderer
fill it.

## PhrReportRenderer.cls

### 1. In `buildValues`, after `v.put('leadBlock', leadBlock(d));`

```apex
v.put('leadChartBlock', leadChartBlock(d));
```

and add `'leadChartBlock'` to the list that is blanked when `!d.hasComplaint`.

### 2. New methods (anywhere in the class)

```apex
/** Small bar chart beside the significance card: top records by match colour, and how many are still open. */
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
    String s = '<table class="chart"><tr><td>';
    for (String c : new List<String>{ 'Red', 'Yellow', 'Grey' }) {
        s += chartBar(c, 'lbl-' + c.toLowerCase(), 'c-' + c.toLowerCase(), byColour.get(c), total);
    }
    s += '<div class="divider"></div>';
    s += chartBar('Still open', 'lbl-open', 'bar-done', open, total);
    s += '<div class="chartnote">' + d.totalLeads + ' records worth reviewing; the top ' + total
        + ' are listed in section 3.</div>';
    return s + '</td></tr></table>';
}

/** One chart row: coloured label, proportional bar, count on the right. */
private static String chartBar(String label, String labelCls, String barCls, Integer n, Integer total) {
    Integer p = pct(n, total);
    return '<table class="row"><tr><td class="lbl ' + labelCls + '">' + esc(label) + '</td><td><table class="bar"><tr>'
        + (p > 0 ? '<td class="' + barCls + '" style="width: ' + p + '%;"></td>' : '')
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
- The colour counts and the "Still open" count are of the **top rows shown** (`d.leadRows`),
  because only those carry a colour; `d.totalLeads` (every record found) goes in the note under
  the chart. The note says so.
- No new data is queried; everything comes from `PhrReportData` as it is.
- The chart uses only CSS classes already in the v2 template: `chart`, `row`, `bar`, `rest`,
  `lbl`, `lbl-red` / `lbl-yellow` / `lbl-grey` / `lbl-open`, `n`, `divider`, `chartnote`, and the
  `c-red` / `c-yellow` / `c-grey` / `bar-done` colours. With the old template the chart block is
  simply not referenced.

## PhrReportCoverageTest.cls

Add one test so the new code is covered:

```apex
@IsTest static void chartCountsTheTopRecords() {
    PhrReportData d = fullData();   // 2 red rows, both Open
    String out = PhrReportRenderer.fill(
        '<html xmlns="http://www.w3.org/1999/xhtml"><body>{{leadChartBlock}}</body></html>', d, false);
    System.assert(out.contains('class="lbl lbl-red">Red</td>'), out);
    System.assert(out.contains('class="n">2</td>'), 'two red rows: ' + out);
    System.assert(out.contains('12 records worth reviewing'), out);
}
```
