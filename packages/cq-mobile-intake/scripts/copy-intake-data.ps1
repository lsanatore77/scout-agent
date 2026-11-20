# Copies the mobile intake setup data from one org to another, using your existing sf CLI logins:
#   - Event Questions (with Case Field, roles, urgent answers, help text)
#   - each question's read-aloud .wav clip (a file on the question)
#   - Quick Log Categories (Approved By is left blank: users differ between orgs)
#
#   .\scripts\copy-intake-data.ps1 -From dev -To intake-test
#
# Safe to run again: a question or category that already exists in the target (same text / name) is left alone,
# and a clip is added only to a question that has none. PowerShell only; no Node needed.

param(
    [Parameter(Mandatory = $true)][string]$From,
    [Parameter(Mandatory = $true)][string]$To
)
$ErrorActionPreference = 'Stop'
$Api = 'v66.0'

function Connect-Org([string]$alias) {
    $json = sf org display --target-org $alias --json | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Could not read the login for '$alias'. Is it in 'sf org list'?" }
    $r = ($json | ConvertFrom-Json).result
    return @{ Url = $r.instanceUrl; Token = $r.accessToken; Alias = $alias }
}
function Invoke-Sf($org, [string]$method, [string]$path, $body) {
    $h = @{ Authorization = "Bearer $($org.Token)" }
    try {
        if ($null -ne $body) {
            $json = $body | ConvertTo-Json -Depth 20 -Compress
            return Invoke-RestMethod -Method $method -Uri ($org.Url + $path) -Headers $h -ContentType 'application/json; charset=utf-8' `
                -Body ([Text.Encoding]::UTF8.GetBytes($json))
        }
        return Invoke-RestMethod -Method $method -Uri ($org.Url + $path) -Headers $h
    } catch {
        $detail = $_.ErrorDetails.Message
        if (-not $detail -and $_.Exception.Response) {
            try { $detail = (New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd() } catch { }
        }
        $short = if ($path.Length -gt 160) { $path.Substring(0, 160) + '...' } else { $path }
        Write-Host ''
        Write-Host "FAILED in '$($org.Alias)': $method $([uri]::UnescapeDataString($short))" -ForegroundColor Red
        Write-Host "Salesforce said: $detail" -ForegroundColor Red
        exit 1
    }
}
function Get-Records($org, [string]$soql) {
    $r = Invoke-Sf $org 'GET' "/services/data/$Api/query?q=$([uri]::EscapeDataString($soql))" $null
    $rows = @($r.records)
    while (-not $r.done) { $r = Invoke-Sf $org 'GET' $r.nextRecordsUrl $null; $rows += $r.records }
    return $rows
}
function Add-Records($org, [string]$type, $rows) {
    $ids = @()
    for ($i = 0; $i -lt $rows.Count; $i += 200) {
        $batch = @($rows[$i..([Math]::Min($i + 199, $rows.Count - 1))] | ForEach-Object {
            $rec = [ordered]@{ attributes = @{ type = $type } }
            foreach ($k in $_.Keys) { $rec[$k] = $_[$k] }
            $rec
        })
        $res = Invoke-Sf $org 'POST' "/services/data/$Api/composite/sobjects" @{ allOrNone = $true; records = $batch }
        foreach ($x in $res) { if (-not $x.success) { throw ($x.errors | ConvertTo-Json -Depth 5) }; $ids += $x.id }
    }
    return $ids
}
function Copy-Fields($row, [string[]]$fields) {
    $h = [ordered]@{}
    foreach ($f in $fields) { $v = $row.$f; if ($null -ne $v) { $h[$f] = $v } }
    return $h
}

$QFields = 'Order__c','Question__c','Answer_Type__c','Choices__c','Role__c','Urgent_When__c','Help_Text__c','Required__c','Active__c','Case_Field__c','Audio_Source_Text__c','Audio_Wav_Base64__c'
$CFields = 'Name','Description__c','Disposition__c','Limit__c','Days__c','Scope__c','Active__c','Approved_On__c'

$src = Connect-Org $From
$dst = Connect-Org $To
Write-Host "Copying intake setup from $($src.Url) to $($dst.Url)"

# Questions
$sq = Get-Records $src "SELECT Id, $($QFields -join ', ') FROM Event_Question__c ORDER BY Order__c"
$have = @{}
foreach ($r in (Get-Records $dst 'SELECT Id, Question__c FROM Event_Question__c')) { $have[$r.Question__c] = $r.Id }
$toAdd = @($sq | Where-Object { -not $have.ContainsKey($_.Question__c) })
if ($toAdd.Count -gt 0) {
    $newIds = Add-Records $dst 'Event_Question__c' @($toAdd | ForEach-Object { Copy-Fields $_ $QFields })
    for ($i = 0; $i -lt $toAdd.Count; $i++) { $have[$toAdd[$i].Question__c] = $newIds[$i] }
}
Write-Host "Questions: $($toAdd.Count) added, $($sq.Count - $toAdd.Count) already there"

# Clips: the newest .wav on each source question, added where the target question has no file
$clips = 0
foreach ($q in $sq) {
    $target = $have[$q.Question__c]
    if ((Get-Records $dst "SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = '$target'").Count -gt 0) { continue }
    $links = Get-Records $src "SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = '$($q.Id)'"
    if ($links.Count -eq 0) { continue }
    $docIds = ($links | ForEach-Object { "'$($_.ContentDocumentId)'" }) -join ','
    $v = Get-Records $src "SELECT Id, Title, PathOnClient FROM ContentVersion WHERE ContentDocumentId IN ($docIds) AND IsLatest = true AND FileExtension = 'wav' ORDER BY CreatedDate DESC LIMIT 1"
    if ($v.Count -eq 0) { continue }
    $tmp = [IO.Path]::GetTempFileName()
    try {
        Invoke-WebRequest -Uri "$($src.Url)/services/data/$Api/sobjects/ContentVersion/$($v[0].Id)/VersionData" `
            -Headers @{ Authorization = "Bearer $($src.Token)" } -OutFile $tmp -UseBasicParsing
        $data = [Convert]::ToBase64String([IO.File]::ReadAllBytes($tmp))
    } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
    $path = if ($v[0].PathOnClient) { $v[0].PathOnClient } else { "$($v[0].Title).wav" }
    Invoke-Sf $dst 'POST' "/services/data/$Api/sobjects/ContentVersion" @{
        Title = $v[0].Title; PathOnClient = $path; VersionData = $data; FirstPublishLocationId = $target } | Out-Null
    $clips++
    Write-Host "  clip: $($v[0].Title)"
}
Write-Host "Clips: $clips added"

# Quick Log Categories
$sc = Get-Records $src "SELECT $($CFields -join ', ') FROM Quick_Log_Category__c"
$tc = @{}
foreach ($r in (Get-Records $dst 'SELECT Name FROM Quick_Log_Category__c')) { $tc[$r.Name] = $true }
$cAdd = @($sc | Where-Object { -not $tc.ContainsKey($_.Name) })
if ($cAdd.Count -gt 0) { Add-Records $dst 'Quick_Log_Category__c' @($cAdd | ForEach-Object { Copy-Fields $_ $CFields }) | Out-Null }
Write-Host "Quick Log Categories: $($cAdd.Count) added, $($sc.Count - $cAdd.Count) already there"
Write-Host 'Done.' -ForegroundColor Green
