# CQ Mobile Intake: set up a test org in one command.
#
#   .\setup-intake-test.ps1
#   .\setup-intake-test.ps1 -Alias intake-test -DevHub golden
#
# Run from the packages\cq-mobile-intake folder. Steps (each stops the script if it fails):
#   1. scratch org from the CQ16BaseSnap snapshot (skipped if an org with that alias already exists)
#   2. deploy the intake and run its tests
#   3. assign the CQ Mobile Intake User and Admin permission sets
#   4. add the default questions, their read-aloud clips and quick-log categories (scripts\seed-questions.apex)
#   5. open Report an Event
# Safe to run again: steps 2 to 4 update what is there instead of duplicating it.

param(
    [string]$Alias = 'intake-test',
    [string]$DevHub = 'golden',
    [int]$Days = 7
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Step([string]$title, [scriptblock]$run) {
    Write-Host ''
    Write-Host "== $title" -ForegroundColor Cyan
    & $run
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Stopped: '$title' failed (see above). Fix it and run the script again." -ForegroundColor Red
        exit 1
    }
}

# 1. scratch org (skipped when the alias already works)
sf org display --target-org $Alias --json *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host "== Scratch org '$Alias' already exists: using it" -ForegroundColor Cyan
} else {
    Step "Create scratch org '$Alias' from CQ16BaseSnap (about 5 minutes)" {
        sf org create scratch --definition-file config\cq16-snapshot-def.json --alias $Alias --duration-days $Days --target-dev-hub $DevHub --no-namespace --wait 30
    }
}

# 2. deploy and test
Step 'Deploy the intake and run its tests' {
    sf project deploy start --source-dir force-app --target-org $Alias --test-level RunLocalTests --wait 30
}

# 3. access
Step 'Assign permission sets' {
    sf org assign permset --name CQ_Mobile_Intake_User --name CQ_Mobile_Intake_Admin --target-org $Alias
}

# 4. setup data: the default questions, their clips (from the package) and quick-log categories
Step 'Add the default questions' {
    sf apex run --file scripts\seed-questions.apex --target-org $Alias
}

# 5. open it
Step 'Open Report an Event' {
    sf org open --target-org $Alias --path /lightning/n/Report_an_Event
}

Write-Host ''
Write-Host 'Done. In the scratch org, add Mobile Intake to Case > Case Origin if you want it in reports and list views.' -ForegroundColor Green
