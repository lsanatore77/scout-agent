<#
  Deploys CQ's external packages (the metadata ZIPs from the Confluence manuals) into an org, in the manuals' order,
  after install-cq16.ps1 has installed the managed packages. Picklist ZIPs are not deployed here: CQ's manuals load them
  on the SQX_Post_Actions page, so the script lists them at the end, in order, for you to upload by hand.

  - ZIPs are found by name in the packages folder; a " (1)" or " (2)" your browser added is fine. If a name is there
    twice, the newest file is used.
  - A ZIP is skipped when its managed package is not installed in the org (for example if Supplier Central failed),
    and when the file is missing; both are listed at the end.
  - Platform Event Subscriber Config ZIPs: the Default Workflow User's username is written into each file first, as the
    manuals ask. By default that is the org's admin user (the one sf is logged in as); -WorkflowUser sets another.
  - Each ZIP is deployed with the manuals' test: RunSpecifiedTests compliancequest.SQX_Test_1931_ContentVersionPerm.

  Usage (PowerShell, from the repo folder):
    powershell -ExecutionPolicy Bypass -File .\scripts\deploy-cq16-zips.ps1 -TargetOrg CQ16AI -List     # check the files only
    powershell -ExecutionPolicy Bypass -File .\scripts\deploy-cq16-zips.ps1 -TargetOrg CQ16AI
  Options: -Packages <folder> (default .\scripts\cq-packages), -Release CQSummer26, -WorkflowUser <username>,
           -From <number> to start at a later step after fixing a failure.

  For a new CQ release: new folder of ZIPs, -Release set to its prefix, and the list below checked against the manuals.
  See docs/cq16_install_notes.md and the CQ 16 Install Runbook.
#>
param(
    [Parameter(Mandatory = $true)][string]$TargetOrg,
    [string]$Packages = ".\scripts\cq-packages",
    [string]$Release = "CQSummer26",
    [string]$WorkflowUser,
    [int]$From = 1,
    [switch]$List
)

$TEST = 'compliancequest.SQX_Test_1931_ContentVersionPerm'

# Managed package version ids (the same as install-cq16.ps1): a ZIP is deployed only when its package is installed
$pkg = @{
  CQ = '04tRn000000qxC5IAI'; DOCX = '04tRn000000rveTIAQ'; FORMS = '04tRn000000r08LIAQ'; RATINGS = '04tRn000000r0Q5IAI'
  AI = '04tRn000000r0MsIAI'; PROCESS = '04tRn000000r0I1IAI'; DESIGN = '04tRn000000r0BaIAI'; PLM = '04tRn000000r0GPIAY'
  EBR = '04tRn000000r0RhIAI'; LAB = '04tRn000000r0DBIAY'; MYCQ = '04tRn000000r0EnIAI'; EHS = '04tRn000000r0UvIAI'
  EHSAI = '04tRn000000r2ZxIAI'; SM = '04tRn000000r0BZIAY'; SC = '04tRn000000r0OTIAY'; SP = '04tRn000000r3B3IAI'
  REG = '04tRn000000r057IAA'; MRD = '04tRn000000r2WjIAI'
}

# The external packages, in order. name = the file name after "extPkg_<Release>_"; needs = packages that must be installed;
# pesc = a Platform Event Subscriber Config package (the workflow username goes in first).
$steps = @(
  @{ name = 'Fresh_Installation';                                              needs = @('CQ') },
  @{ name = 'CQDocument_Extensions_Fresh_Installation';                         needs = @('CQ', 'DOCX') },
  @{ name = 'CQPlatformEventSubscriberConfigs_Fresh_Installation';              needs = @('CQ'); pesc = $true },
  @{ name = 'CQForms_Extension_Fresh_Installation';                             needs = @('FORMS') },
  @{ name = 'CQRatingsFramework_Extension_Fresh_Installation';                  needs = @('RATINGS') },
  @{ name = 'CQRatingsFramework_Extension_CQPlatformEventSubscriberConfigs_Fresh_Installation'; needs = @('RATINGS'); pesc = $true },
  @{ name = 'CQ.AI_Extension_Fresh_Installation_For_16.0.x';                    needs = @('AI') },
  @{ name = 'CQProcess_Extension_Fresh_Installation';                           needs = @('PROCESS') },
  @{ name = 'CQ.AI_Extension_Fresh_Installation_For_CQPE_16.0.x';               needs = @('AI', 'PROCESS') },
  @{ name = 'CQDesign_Extension_Fresh_Installation';                            needs = @('DESIGN') },
  @{ name = 'CQDesign_Extension_CQPlatformEventSubscriberConfigs_Package';      needs = @('DESIGN'); pesc = $true },
  @{ name = 'CQ.AI_Extension_Fresh_Installation_For_CQDE_16.0.x';               needs = @('AI', 'DESIGN') },
  @{ name = 'CQProductLifecycleManagement_Extension_Fresh_Installation';        needs = @('PLM') },
  @{ name = 'CQElectronicBatchRecord_Extension_Fresh_Installation';             needs = @('EBR') },
  @{ name = 'CQElectronicBatchRecord_Extension_CQPlatformEventSubscriberConfigs_Fresh_Installation'; needs = @('EBR'); pesc = $true },
  @{ name = 'CQLaboratoryIssues_Extension_Fresh_Installation';                  needs = @('LAB') },
  @{ name = 'CQmyCQ_Extension_Fresh_Installation';                              needs = @('MYCQ') },
  @{ name = 'CQEHS_Extension_Fresh_Installation';                               needs = @('EHS') },
  @{ name = 'CQmyCQ_Extension_Fresh_Installation_For_EHS';                      needs = @('EHS', 'MYCQ') },
  @{ name = 'CQEHS_Extension_AI_Object_Transformations_Package';                needs = @('EHSAI') },
  @{ name = 'CQSupplierManagement_Extension_Fresh_Installation';                needs = @('SM') },
  @{ name = 'CQSupplierManagement_Extension_CQPlatformEventSubscriberConfigs_Package'; needs = @('SM'); pesc = $true },
  @{ name = 'CQSupplierPerformance_Extension_Fresh_Installation';               needs = @('SP') },
  @{ name = 'CQSupplierCentral_Extension_Fresh_Installation';                   needs = @('SC') },
  @{ name = 'CQSupplierCentral_Extension_Fresh_Installation_For_CQSPFE';        needs = @('SC', 'SP', 'FORMS') },
  @{ name = 'CQRegulatoryReports_Extension_Fresh_Installation_For_16.0.x';      needs = @('REG') },
  @{ name = 'CQRegulatoryReports_Extension_ExclusivePackage_Fresh_Installation_For_16.0.x'; needs = @('REG') },
  @{ name = 'CQManagementReviewDashboard_Extension_Fresh_Installation';         needs = @('MRD') }
)

# Picklist ZIPs, uploaded by hand on SQX_Post_Actions > Picklist Update, in this order (Regulatory Reports: 1, then 2)
$picklists = @(
  'CQForms_Extension_Picklist_Package', 'CQRatingsFramework_Extension_Picklist_Package', 'CQProcess_Extension_Picklist_Package',
  'CQDesign_Extension_Picklist_Package', 'CQProductLifecycleManagement_Extension_Picklist_Package',
  'CQElectronicBatchRecord_Extension_Picklist_Package', 'CQLaboratoryIssues_Extension_Picklist_Package',
  'CQEHS_Extension_Picklist_Package', 'CQSupplierPerformance_Extension_Picklist_Package',
  'CQRegulatoryReports_Extension_Picklist_Package_1', 'CQRegulatoryReports_Extension_Picklist_Package_2',
  'CQManagementReviewDashboard_Extension_Picklist_Package'
)

if (-not (Test-Path $Packages)) { Write-Host "No packages folder at $Packages" -ForegroundColor Red; exit 1 }
$zips = @(Get-ChildItem -Path $Packages -Filter *.zip -File)

# The file for a name: "extPkg_<release>_<name>.zip". The release part is ignored (one folder per release), because CQ's
# own links are not consistent: "CQSummer26-" on the EBR picklist, "CQSumemer26_" on the Regulatory Reports exclusive
# package. A " (1)" your browser added is ignored too.
function Find-Zip([string]$name) {
    $want = $name.ToLowerInvariant()
    $hits = @($zips | Where-Object {
        $stem = ($_.BaseName -replace '\s*\(\d+\)\s*$', '').Trim()
        $stem = ($stem -replace '^extPkg_[^_-]+[_-]', '').ToLowerInvariant()
        $stem -eq $want
    } | Sort-Object LastWriteTime -Descending)
    if ($hits.Count -gt 0) { return $hits[0] } else { return $null }
}

# What is installed, and the workflow user
$installed = @()
try {
    $json = sf package installed list --target-org $TargetOrg --json 2>$null | Out-String | ConvertFrom-Json
    $installed = @($json.result | ForEach-Object { $_.SubscriberPackageVersionId })
} catch { Write-Host "Could not read the installed packages from $TargetOrg." -ForegroundColor Red; exit 1 }
if (-not $WorkflowUser) {
    try { $WorkflowUser = (sf org display --target-org $TargetOrg --json 2>$null | Out-String | ConvertFrom-Json).result.username } catch { }
}
if (-not $WorkflowUser) { Write-Host "Could not read the org's username; pass -WorkflowUser." -ForegroundColor Red; exit 1 }

Write-Host "Org: $TargetOrg   Workflow user: $WorkflowUser   Packages: $Packages ($($zips.Count) ZIPs)" -ForegroundColor Cyan

$done = @(); $failed = @(); $missing = @(); $notInstalled = @()
$work = Join-Path $env:TEMP 'cqz'   # short path: some ZIPs have long names inside
$n = 0
foreach ($s in $steps) {
    $n++
    $label = "{0,2}. {1}" -f $n, $s.name
    $zip = Find-Zip $s.name
    $need = @($s.needs | Where-Object { $installed -notcontains $pkg[$_] })
    if (-not $zip) { $missing += $s.name; Write-Host "$label  MISSING (no ZIP in the folder)" -ForegroundColor Yellow; continue }
    if ($need.Count -gt 0) { $notInstalled += "$($s.name) (needs $($need -join ', '))"; Write-Host "$label  skipped: $($need -join ', ') not installed" -ForegroundColor Yellow; continue }
    if ($List) { Write-Host "$label  ready: $($zip.Name)"; continue }
    if ($n -lt $From) { Write-Host "$label  skipped (-From $From)"; continue }

    # unzip to a short folder, find the folder(s) holding package.xml
    $dir = Join-Path $work ("{0:D2}" -f $n)
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    try { Expand-Archive -Path $zip.FullName -DestinationPath $dir -Force }
    catch { $failed += "$($s.name): could not unzip ($($_.Exception.Message))"; Write-Host "$label  could not unzip" -ForegroundColor Red; continue }
    $roots = @(Get-ChildItem -Path $dir -Recurse -Filter package.xml -File | ForEach-Object { $_.DirectoryName })
    if ($roots.Count -eq 0) { $failed += "$($s.name): no package.xml inside"; Write-Host "$label  no package.xml inside" -ForegroundColor Red; continue }

    # Platform Event Subscriber Configs: the Default Workflow User
    if ($s.pesc) {
        $files = @(Get-ChildItem -Path $dir -Recurse -File | Where-Object { $_.Name -like '*.platformEventSubscriberConfig*' })
        foreach ($f in $files) {
            $text = [IO.File]::ReadAllText($f.FullName)
            $new = [regex]::Replace($text, '<user>[^<]*</user>', "<user>$WorkflowUser</user>")
            [IO.File]::WriteAllText($f.FullName, $new)
        }
        Write-Host "$label  workflow user written into $($files.Count) file(s)"
    }

    $ok = $true
    foreach ($root in $roots) {
        Write-Host "$label  deploying $($zip.Name) ..." -ForegroundColor Cyan
        sf project deploy start --metadata-dir $root --target-org $TargetOrg --test-level RunSpecifiedTests --tests $TEST --wait 60
        if ($LASTEXITCODE -ne 0) { $ok = $false }
    }
    if ($ok) { $done += $s.name } else { $failed += "$($s.name) (step $n; fix, then rerun with -From $n)" }
}

Write-Host ""
Write-Host "Deployed: $($done.Count)" -ForegroundColor Green
if ($notInstalled.Count) { Write-Host "Skipped, package not installed:" -ForegroundColor Yellow; $notInstalled | ForEach-Object { Write-Host "  $_" } }
if ($missing.Count) { Write-Host "Missing ZIPs:" -ForegroundColor Yellow; $missing | ForEach-Object { Write-Host "  $_" } }
if ($failed.Count) { Write-Host "Failed:" -ForegroundColor Red; $failed | ForEach-Object { Write-Host "  $_" } }

Write-Host ""
Write-Host "By hand, Setup > Visualforce Pages > SQX_Post_Actions > Preview > Picklist Update, in this order:" -ForegroundColor Cyan
$i = 0
foreach ($p in $picklists) {
    $zip = Find-Zip $p
    $i++
    if ($zip) { Write-Host ("  {0,2}. {1}" -f $i, $zip.Name) } else { Write-Host ("  {0,2}. {1}  (not in the folder)" -f $i, $p) -ForegroundColor Yellow }
}
if ($failed.Count) { exit 1 }
