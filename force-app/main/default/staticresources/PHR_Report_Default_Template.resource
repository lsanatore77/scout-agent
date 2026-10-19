<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <style>
    @page {
      size: letter;
      margin: 0.55in 0.6in 0.75in 0.6in;
      @bottom-left { content: "{{footerNote}}"; font-family: Arial, Helvetica, sans-serif; font-size: 9px; color: #5a6778; }
      @bottom-right { content: "Page " counter(page) " of " counter(pages); font-family: Arial, Helvetica, sans-serif; font-size: 9px; color: #5a6778; }
    }
    body { font-family: Arial, Helvetica, sans-serif; font-size: 11px; color: #1a202c; }
    table { width: 100%; border-collapse: collapse; }
    .accent { border-top: 6px solid #0b3d6e; margin-bottom: 14px; }
    h1 { font-size: 22px; margin: 0; }
    .sub { font-size: 12px; margin-top: 5px; color: #2d3748; }
    .meta { font-size: 10px; color: #5a6778; line-height: 1.6; text-align: right; vertical-align: top; width: 190px; }
    h2 { font-size: 13px; color: #0b3d6e; margin: 0; border-bottom: 1px solid #0b3d6e; padding-bottom: 3px; margin-top: 20px; }
    .error { border: 1px solid #c53030; background: #fff5f5; color: #742a2a; padding: 8px 10px; margin-top: 14px; }
    .sig { margin-top: 8px; border: 1px solid #e6b3ae; background-color: #fdf1f0; }
    .sig td { padding: 10px 14px; vertical-align: middle; }
    .sig.r-medium { border-color: #f0d98a; background-color: #fff8e1; }
    .sig.r-low, .sig.r-none { border-color: #cbd5e0; background-color: #f7fafc; }
    .score { font-size: 28px; font-weight: bold; color: #b3261e; line-height: 1; }
    .r-medium .score { color: #8a6100; }
    .r-low .score, .r-none .score { color: #4a5568; }
    .rating { font-size: 10px; font-weight: bold; letter-spacing: 1px; text-transform: uppercase; }
    p.body { font-size: 11.5px; line-height: 1.6; margin: 8px 0 2px 0; }
    .note { font-size: 9px; color: #5a6778; margin-top: 4px; }
    .grid th { background-color: #edf2f7; color: #1a202c; text-align: left; padding: 5px 6px; font-size: 10px; border-bottom: 1px solid #b9c3d1; }
    .grid td { border-bottom: 1px solid #e2e8f0; padding: 5px 6px; font-size: 10px; vertical-align: top; }
    .chip { color: #ffffff; font-weight: bold; font-size: 9px; }
    .grid td.chipcell { border-bottom: none; padding: 2px 4px; text-align: center; font-size: 9px; font-weight: bold; vertical-align: middle; }
    .c-yellow td.chipcell { color: #1a202c; }
    .c-red { background-color: #c62828; }
    .c-yellow { background-color: #e0a100; color: #1a202c; }
    .c-grey { background-color: #8a94a3; }
    .c-none { background-color: #8a94a3; }
    .bar td { height: 10px; }
    .bar-done { background-color: #38a169; }
    .bar-rest { background-color: #2b6cb0; }
    .progress { margin-top: 8px; border: 1px solid #cbd5e0; background-color: #f7fafc; }
    .progress td { padding: 8px 12px; vertical-align: middle; }
    .big { font-size: 14px; font-weight: bold; }
    .badge-overdue { background-color: #fde8e8; color: #8a1c1c; font-size: 10px; font-weight: bold; padding: 3px 8px; }
    .pill { padding: 2px 7px; font-size: 9.5px; margin-right: 4px; }
    .st-draft { background-color: #edf2f7; color: #2d3748; }
    .st-open { background-color: #bee3f8; color: #1a365d; }
    .st-ready { background-color: #feebc8; color: #744210; }
    .st-sub { background-color: #e9d8fd; color: #44337a; }
    .st-done { background-color: #c6f6d5; color: #22543d; }
    .late { color: #8a1c1c; font-weight: bold; }
    .late-note { color: #8a1c1c; font-size: 9px; }
    .empty { color: #5a6778; font-style: italic; }
    .gap { margin-top: 8px; border: 1px solid #f0d98a; background-color: #fff8e1; padding: 8px 12px; font-size: 10.5px; }
    h3 { font-size: 11.5px; margin: 12px 0 6px 0; }
    .draftlabel { font-size: 10px; font-weight: bold; letter-spacing: 1px; text-transform: uppercase; color: #5a6778; margin-top: 14px; }
    .draft { margin-top: 4px; border-left: 3px solid #0b3d6e; padding-left: 10px; font-size: 11px; line-height: 1.5; }
    .draft h3 { font-size: 11.5px; margin: 8px 0 3px 0; color: #0b3d6e; }
    .draft p { margin: 3px 0; }
    .draft ul { margin: 3px 0 3px 16px; padding-left: 0; }
    .draft li { margin: 2px 0; }
  </style>
</head>
<body>
  <div class="accent"></div>
  {{errorBlock}}
  <table>
    <tr>
      <td style="vertical-align: top;">
        <h1>{{reportTitle}}</h1>
        <div class="sub">Complaint <strong>{{complaintName}}</strong>{{phrBlock}}{{partBlock}}{{lotBlock}}</div>
      </td>
      <td class="meta">Generated {{generatedAt}}<br/>Version {{versionLabel}}</td>
    </tr>
  </table>

  <h2>1. Overall significance</h2>
  <table class="sig r-{{ratingClass}}">
    <tr>
      <td style="width: 90px;"><div class="score">{{overallScore}}</div><div class="rating">{{overallRating}}</div></td>
      <td>{{reasonRows}}</td>
    </tr>
  </table>

  <h2>2. Summary</h2>
  <p class="body">{{summaryText}}</p>
  <div class="note">{{summaryWords}} words. Recommendations and gaps only; records are not named here.</div>

  <div class="draftlabel">Draft investigation summary</div>
  {{draftSummaryBlock}}

  <h2>3. Top records worth reviewing</h2>
  {{leadBlock}}

  <h2>4. Complaint steps and progress</h2>
  {{progressBlock}}

  {{investigationBlock}}

  <h2>Data gaps</h2>
  {{gapBlock}}
</body>
</html>
