# CQ.AI intake - generate the 9 read-aloud prompt clips using the built-in Windows voice.
# HOW TO RUN: open PowerShell, paste this whole block, press Enter.
# It writes clips.json in your current folder. Then upload that file to Salesforce (Files tab).

Add-Type -AssemblyName System.Speech

# The 9 prompts (key = the exact question text CQ.AI asks)
$prompts = @(
  'Where did this happen?'
  'Which customer?'
  'Which supplier?'
  'Do you have a lot or batch number?'
  'Did this affect a product?'
  'Was anyone injured?'
  'Could anyone get hurt, or is product safety at risk?'
  'Which test or inspection found it?'
  'Who was hurt?'
)

$rate = 8000   # 8 kHz keeps each clip small enough for the Salesforce text field

# Build a canonical PCM WAV (44-byte header + samples) around raw PCM bytes.
function New-WavBytes([byte[]]$pcm, [int]$rate) {
  $ms = New-Object System.IO.MemoryStream
  $bw = New-Object System.IO.BinaryWriter($ms)
  $bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
  $bw.Write([int](36 + $pcm.Length))
  $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVE'))
  $bw.Write([Text.Encoding]::ASCII.GetBytes('fmt '))
  $bw.Write([int]16)       # fmt chunk size
  $bw.Write([int16]1)      # PCM
  $bw.Write([int16]1)      # mono
  $bw.Write([int]$rate)
  $bw.Write([int]($rate * 2))   # byte rate (rate * channels * bytesPerSample)
  $bw.Write([int16]2)      # block align
  $bw.Write([int16]16)     # bits per sample
  $bw.Write([Text.Encoding]::ASCII.GetBytes('data'))
  $bw.Write([int]$pcm.Length)
  $bw.Write($pcm)
  $bw.Flush()
  $out = $ms.ToArray()
  $bw.Dispose(); $ms.Dispose()
  return ,$out
}

$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
# OPTIONAL: pick a specific installed voice, e.g. a female US voice:
#   $synth.SelectVoice('Microsoft Zira Desktop')
# List what you have with:  $synth.GetInstalledVoices() | % { $_.VoiceInfo.Name }

$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(
  $rate,
  [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
  [System.Speech.AudioFormat.AudioChannel]::Mono)

$result = [ordered]@{}
Write-Host ""
foreach ($text in $prompts) {
  $ms = New-Object System.IO.MemoryStream
  $synth.SetOutputToAudioStream($ms, $fmt)
  $synth.Speak($text)
  $synth.SetOutputToNull()
  $pcm = $ms.ToArray()
  $ms.Dispose()
  $wav = New-WavBytes $pcm $rate
  $b64 = [Convert]::ToBase64String($wav)
  $result[$text] = $b64
  $ms_dur = [int]($pcm.Length / ($rate * 2) * 1000)
  $warn = if ($b64.Length -gt 131000) { '  <-- TOO BIG for the field!' } else { '' }
  Write-Host ("  {0,-54} {1,5} ms   {2,7} b64 chars{3}" -f $text, $ms_dur, $b64.Length, $warn)
}
$synth.Dispose()

$path = Join-Path (Get-Location) 'clips.json'
($result | ConvertTo-Json) | Set-Content -Path $path -Encoding ascii
Write-Host ""
Write-Host "Saved: $path"
Write-Host "Next: upload clips.json to Salesforce (Files tab -> Upload), then tell Claude."
