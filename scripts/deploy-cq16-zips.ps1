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
    powershell -ExecutionPolicy Bypass -File .\scripts\deploy-cq16-zips.ps1 -TargetOrg CQ16AI -List    # check the files only
    powershell -ExecutionPolicy Bypass -File .\scripts\deploy-cq16-zips.ps1 -TargetOrg CQ16AI          # steps 1-3, then stops
    (upload the five picklists it lists)
    powershell -ExecutionPolicy Bypass -File .\scripts\deploy-cq16-zips.ps1 -TargetOrg CQ16AI -From 4 -PicklistsDone
  Options: -Packages <folder> (default .\scripts\cq-packages), -Release CQSummer26, -WorkflowUser <username>,
           -Only "1,2,4" to rerun just the steps that failed (the summary prints the list), -From <number> to start later.
  - References to profiles the org does not have (a scratch org has no Standard Platform User) are taken out of CQ's
    app files first; they only say which record page that profile sees.

  For a new CQ release: new folder of ZIPs, -Release set to its prefix, and the list below checked against the manuals.
  See docs/cq16_install_notes.md and the CQ 16 Install Runbook.
#>
param(
    [Parameter(Mandatory = $true)][string]$TargetOrg,
    [string]$Packages = ".\scripts\cq-packages",
    [string]$Release = "CQSummer26",
    [string]$WorkflowUser,
    [int]$From = 1,
    [string]$Only,          # e.g. "1,2,4": deploy just these steps (to retry failures)
    [switch]$PicklistsDone, # the five picklists that must come first are uploaded: go past step 3
    [switch]$List
)
$onlySteps = @()
if ($Only) { $onlySteps = @($Only -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { [int]$_ }) }

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

# The manuals upload these picklists BEFORE their extension's external package (its record types use their values), so
# the script stops after the core steps (1 to 3) until they are uploaded, then carries on with -PicklistsDone.
$picklistsFirst = @(
  'CQForms_Extension_Picklist_Package', 'CQProductLifecycleManagement_Extension_Picklist_Package',
  'CQElectronicBatchRecord_Extension_Picklist_Package', 'CQLaboratoryIssues_Extension_Picklist_Package',
  'CQEHS_Extension_Picklist_Package'
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

# Profiles in the org. CQ's files assign pages to profiles by their metadata name (Admin, Standard, StandardAul ...);
# an org without a profile's license (a scratch org has no Salesforce Platform licenses, so no Standard Platform User)
# rejects the whole file. References to missing profiles are taken out before deploying.
$orgProfiles = @()
try {
    $orgProfiles = @((sf data query --query "SELECT Name FROM Profile" --target-org $TargetOrg --json 2>$null | Out-String | ConvertFrom-Json).result.records | ForEach-Object { $_.Name })
} catch { }
$stdProfile = @{ 'Admin' = 'System Administrator'; 'Standard' = 'Standard User'; 'StandardAul' = 'Standard Platform User'
                 'ReadOnly' = 'Read Only'; 'ContractManager' = 'Contract Manager'; 'MarketingProfile' = 'Marketing User'
                 'SolutionManager' = 'Solution Manager'; 'ChatterFreeUser' = 'Chatter Free User' }
function Test-Profile([string]$metaName) {
    if ($orgProfiles.Count -eq 0) { return $true }   # could not read them: change nothing
    $name = if ($stdProfile.ContainsKey($metaName)) { $stdProfile[$metaName] } else { [Uri]::UnescapeDataString($metaName) }
    return ($orgProfiles -contains $name)
}
# Takes out <profileActionOverrides> for missing profiles from the app files, and profile files for missing profiles
function Remove-MissingProfiles([string]$dir) {
    $count = 0
    # app files come as Name.app or Name.app-meta.xml, depending on the ZIP
    foreach ($f in @(Get-ChildItem -Path $dir -Recurse -File | Where-Object { $_.Name -like '*.app' -or $_.Name -like '*.app-meta.xml' })) {
        $text = [IO.File]::ReadAllText($f.FullName)
        $names = @([regex]::Matches($text, '<profile>([^<]+)</profile>') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $new = $text
        foreach ($p in $names) {
            if (Test-Profile $p) { continue }
            $pat = '(?s)\s*<profileActionOverrides>((?!</profileActionOverrides>).)*<profile>' + [regex]::Escape($p) + '</profile>((?!</profileActionOverrides>).)*</profileActionOverrides>'
            $count += [regex]::Matches($new, $pat).Count
            $new = [regex]::Replace($new, $pat, '')
        }
        if ($new -ne $text) { [IO.File]::WriteAllText($f.FullName, $new) }
    }
    foreach ($f in @(Get-ChildItem -Path $dir -Recurse -File | Where-Object { $_.Name -like '*.profile' -or $_.Name -like '*.profile-meta.xml' })) {
        $pname = $f.Name -replace '\.profile(-meta\.xml)?$', ''
        if (-not (Test-Profile $pname)) { Remove-Item $f.FullName; $count++ }
    }
    # Permission set groups that include a Salesforce-licensed permission set (force__...) the org has no license for,
    # e.g. force__AnalyticsViewOnlyUser without the Analytics View Only Embedded App license: that one entry is taken out.
    foreach ($f in @(Get-ChildItem -Path $dir -Recurse -File -Filter *.permissionsetgroup*)) {
        $text = [IO.File]::ReadAllText($f.FullName)
        $new = $text
        foreach ($m in @([regex]::Matches($text, '<permissionSets>(force__[^<]+)</permissionSets>'))) {
            $ps = $m.Groups[1].Value
            if (-not $permSetsRead -or $orgPermSets -contains $ps) { continue }
            $new = [regex]::Replace($new, '\s*<permissionSets>' + [regex]::Escape($ps) + '</permissionSets>', '')
            $count++
        }
        if ($new -ne $text) { [IO.File]::WriteAllText($f.FullName, $new) }
    }
    return $count
}
$orgPermSets = @(); $permSetsRead = $false
try {
    $q = sf data query --query "SELECT Name FROM PermissionSet WHERE NamespacePrefix = 'force'" --target-org $TargetOrg --json 2>$null | Out-String | ConvertFrom-Json
    if ($q.status -eq 0) { $permSetsRead = $true; $orgPermSets = @($q.result.records | ForEach-Object { "force__" + $_.Name }) }
} catch { }

Write-Host "Org: $TargetOrg   Workflow user: $WorkflowUser   Packages: $Packages ($($zips.Count) ZIPs)" -ForegroundColor Cyan

# Copies of the picklist ZIPs in two folders, so the upload dialog shows only what to pick (names unchanged)
$firstDir = Join-Path $Packages '1 - upload first'; $afterDir = Join-Path $Packages '2 - upload after'
foreach ($d in @($firstDir, $afterDir)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }
# Some picklist ZIPs carry an app too (Supplier Performance's CQSPM app): the same clean-up as the external ZIPs is applied
# (references to profiles this org lacks are taken out), and the ZIP is rebuilt with the same name and folder layout.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$cleaned = @()
foreach ($p in $picklists) {
    $z = Find-Zip $p
    if (-not $z) { continue }
    $to = if ($picklistsFirst -contains $p) { $firstDir } else { $afterDir }
    $dest = Join-Path (Resolve-Path $to) $z.Name
    $tmp = Join-Path $env:TEMP ('cqp\' + [IO.Path]::GetRandomFileName())
    try {
        Expand-Archive -Path $z.FullName -DestinationPath $tmp -Force
        $gone = Remove-MissingProfiles $tmp
        if (Test-Path $dest) { Remove-Item $dest -Force }
        if ($gone -gt 0) {
            # built entry by entry: Windows PowerShell's ZipFile.CreateFromDirectory writes paths with backslashes,
            # and Salesforce then finds no package.xml. Entries need forward slashes, as in CQ's own ZIPs.
            $root = (Resolve-Path $tmp).Path.TrimEnd('\')
            $fs = [IO.File]::Open($dest, [IO.FileMode]::Create)
            $za = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($f in @(Get-ChildItem -Path $root -Recurse -File)) {
                    $rel = $f.FullName.Substring($root.Length + 1) -replace '\\', '/'
                    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($za, $f.FullName, $rel, [IO.Compression.CompressionLevel]::Optimal)
                }
            } finally { $za.Dispose(); $fs.Dispose() }
            $cleaned += "$($z.Name) ($gone)"
        } else {
            Copy-Item $z.FullName -Destination $dest -Force
        }
    } catch {
        Copy-Item $z.FullName -Destination $dest -Force
    } finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    }
}
Write-Host "Picklist ZIPs copied to '$firstDir' (5) and '$afterDir' (7)."
if ($cleaned.Count) { Write-Host "Cleaned for this org (references to missing profiles taken out): $($cleaned -join '; ')" }

$done = @(); $failed = @(); $missing = @(); $notInstalled = @(); $failedSteps = @()
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
    if ($onlySteps.Count -gt 0 -and $onlySteps -notcontains $n) { continue }
    if ($n -ge 4 -and -not $PicklistsDone -and -not $List -and $onlySteps.Count -eq 0) {
        Write-Host ""
        Write-Host "Stopping before step 4: upload these picklists first (Setup > Visualforce Pages > SQX_Post_Actions >" -ForegroundColor Yellow
        Write-Host "Preview > Picklist Update; Upload Files, Publish, wait for Succeeded), one at a time:" -ForegroundColor Yellow
        foreach ($p in $picklistsFirst) { $z = Find-Zip $p; if ($z) { Write-Host "  $($z.Name)" } else { Write-Host "  $p  (not in the folder)" -ForegroundColor Red } }
        Write-Host "Then run again with:  -From 4 -PicklistsDone" -ForegroundColor Yellow
        break
    }

    # unzip to a short folder, find the folder(s) holding package.xml
    $dir = Join-Path $work ("{0:D2}" -f $n)
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    try { Expand-Archive -Path $zip.FullName -DestinationPath $dir -Force }
    catch { $failed += "$($s.name): could not unzip ($($_.Exception.Message))"; Write-Host "$label  could not unzip" -ForegroundColor Red; continue }
    $roots = @(Get-ChildItem -Path $dir -Recurse -Filter package.xml -File | ForEach-Object { $_.DirectoryName })
    if ($roots.Count -eq 0) { $failed += "$($s.name): no package.xml inside"; Write-Host "$label  no package.xml inside" -ForegroundColor Red; continue }

    $gone = Remove-MissingProfiles $dir
    if ($gone -gt 0) { Write-Host "$label  took out $gone reference(s) to profiles or licensed permission sets this org does not have" }

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
    if ($ok) { $done += $s.name } else { $failed += "$($s.name) (step $n)"; $failedSteps += $n }
}

Write-Host ""
Write-Host "Deployed: $($done.Count)" -ForegroundColor Green
if ($notInstalled.Count) { Write-Host "Skipped, package not installed:" -ForegroundColor Yellow; $notInstalled | ForEach-Object { Write-Host "  $_" } }
if ($missing.Count) { Write-Host "Missing ZIPs:" -ForegroundColor Yellow; $missing | ForEach-Object { Write-Host "  $_" } }
if ($failed.Count) {
    Write-Host "Failed:" -ForegroundColor Red; $failed | ForEach-Object { Write-Host "  $_" }
    Write-Host "After fixing, rerun just these with:  -Only $($failedSteps -join ',')" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Picklists, all of them, before the snapshot (the five above go first, before steps 4 to 18)." -ForegroundColor Cyan
Write-Host "Setup > Visualforce Pages > SQX_Post_Actions > Preview > Picklist Update, in this order:" -ForegroundColor Cyan
$i = 0
foreach ($p in $picklists) {
    $zip = Find-Zip $p
    $i++
    if ($zip) { Write-Host ("  {0,2}. {1}" -f $i, $zip.Name) } else { Write-Host ("  {0,2}. {1}  (not in the folder)" -f $i, $p) -ForegroundColor Yellow }
}
if ($failed.Count) { exit 1 }
