<#
  Installs CQ 16 and its extensions into an org, in dependency order (the same set the dev sandbox runs).
  Skips any package already installed at that version, keeps going if one fails, and lists the failures at the end.

  Usage (PowerShell, from the repo folder):
    .\scripts\install-cq16.ps1 -TargetOrg CQ16AI
    .\scripts\install-cq16.ps1 -TargetOrg CQ16AI -InstallationKey <key>    # only if CQ gave you one

  The org needs, before ComplianceQuest installs: Enhanced Email on (Setup > Enhanced Email), and for the CQ.AI
  packages generative AI (scratch: config/cq16-ai-fresh-def.json has both). Not installed here, because a scratch
  org cannot get what they need: CQ.AI Data Cloud Extension (Data Cloud), CQ Embedded Analytics and CQ EHS Extension
  Analytics (CRM Analytics). Not installed either: our own and colleagues' packages (Triage Agent, Deployment Agent,
  Mobile Intake), so a snapshot of the org stays plain CQ.

  After it finishes, a snapshot for future scratch orgs:
    sf org create snapshot --source-org CQ16AI --name CQ16AISnap --description "CQ 16 + extensions + CQ.AI + generative AI" --target-dev-hub golden
#>
param(
    [Parameter(Mandatory = $true)][string]$TargetOrg,
    [string]$InstallationKey
)

# Order matters: each package comes after the ones it depends on.
$pkgs = [ordered]@{
  'ComplianceQuest'                       = '04tRn000000qxC5IAI'
  'ComplianceQuest User Interface'        = '04tRn000000qznNIAQ'
  'CQ Approval Extension'                 = '04tRn000000qzyfIAA'
  'CQ Process Extension'                  = '04tRn000000r0I1IAI'
  'CQ Design Extension'                   = '04tRn000000r0BaIAI'
  'CQ Forms Extension'                    = '04tRn000000r08LIAQ'
  'CQ Ratings Framework Extension'        = '04tRn000000r0Q5IAI'
  'CQ Supplier Management'                = '04tRn000000r0BZIAY'
  'CQ Supplier Performance Extension'     = '04tRn000000r3B3IAI'
  'CQ Supplier Central Extension'         = '04tRn000000r0OTIAY'
  'CQ Product Lifecycle Management Ext'   = '04tRn000000r0GPIAY'
  'CQ Electronic Batch Record Extension'  = '04tRn000000r0RhIAI'
  'CQ Laboratory Issues Extension'        = '04tRn000000r0DBIAY'
  'CQ Regulatory Reports Extension'       = '04tRn000000r057IAA'
  'CQ Management Review Dashboard Ext'    = '04tRn000000r2WjIAI'
  'CQ myCQ Extension'                     = '04tRn000000r0EnIAI'
  'CQ Document Extensions App'            = '04tRn000000rveTIAQ'
  'CQ Backup and Restore Extension'       = '04tRn000000qtwTIAQ'
  'CQ EHS Extension'                      = '04tRn000000r0UvIAI'
  'CQ EHS Extension Integration'          = '04tRn000000eQ5RIAU'
  'CQ.AI Extension'                       = '04tRn000000r0MsIAI'
  'CQ EHS Extension AI'                   = '04tRn000000r2ZxIAI'
}

# what is installed already (package version ids)
$have = @()
try {
    $json = sf package installed list --target-org $TargetOrg --json 2>$null | Out-String | ConvertFrom-Json
    $have = @($json.result | ForEach-Object { $_.SubscriberPackageVersionId })
} catch { Write-Host "Could not read the installed packages; installing all." -ForegroundColor Yellow }

$failed = @(); $done = @(); $skipped = @()
foreach ($name in $pkgs.Keys) {
    $id = $pkgs[$name]
    if ($have -contains $id) { $skipped += $name; Write-Host "Already installed: $name" -ForegroundColor DarkGray; continue }
    Write-Host "`n=== $name ($id) ===" -ForegroundColor Cyan
    $cmd = @('package', 'install', '--package', $id, '--target-org', $TargetOrg, '--wait', '60', '--no-prompt')
    if ($InstallationKey) { $cmd += @('--installation-key', $InstallationKey) }
    sf @cmd
    if ($LASTEXITCODE -eq 0) { $done += $name } else { $failed += $name }
}

Write-Host "`nInstalled: $($done.Count)   Already there: $($skipped.Count)   Failed: $($failed.Count)" -ForegroundColor Yellow
if ($failed.Count) { Write-Host ("Failed: " + ($failed -join ', ')) -ForegroundColor Red; Write-Host "Run the script again to retry just those (it skips what is installed)." }
