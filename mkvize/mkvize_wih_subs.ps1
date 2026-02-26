<#
mkvize_with_subs.ps1

For each video:
- Remux to MKV with stream copy (NO quality loss).
- If a matching .srt exists, embed it as a subtitle track (still NO quality loss).

Matching:
- One subtitle per video, by normalized base filename.
- Supports "Episode 01.srt" and "Episode 01.en.srt" style names.
- Never applies all SRTs to all videos.

Requires: ffmpeg in PATH
  winget install Gyan.FFmpeg
#>

[CmdletBinding()]
param(
  [string]$VideoDir = ".",
  [string]$SubtitleDir = ".",
  [string]$OutputDir = "",

  [string[]]$VideoExts = @(".mkv",".mp4",".mov",".m4v",".avi",".webm",".ts"),

  [switch]$Recurse,
  [switch]$DryRun,
  [switch]$Overwrite,

  # Preferred subtitle language code for picking among multiple SRTs (e.g. en, fr, de)
  [string]$PreferLang = "en"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Require-Exe([string]$exe) {
  $cmd = Get-Command $exe -ErrorAction SilentlyContinue
  if (-not $cmd) { throw "Missing dependency: '$exe' not found in PATH." }
}

function Normalize-BaseName([string]$filename) {
  $n = [System.IO.Path]::GetFileNameWithoutExtension($filename).ToLowerInvariant()
  $n = ($n -replace "[\._]+"," " -replace "\s+"," ").Trim()
  return $n
}

function Strip-LangSuffix([string]$baseNoExt) {
  if ($baseNoExt -match "\.(en|eng|english|es|spa|fr|fre|de|ger|it|pt|br|ja|jp|jpn)$") {
    return ($baseNoExt -replace "\.(en|eng|english|es|spa|fr|fre|de|ger|it|pt|br|ja|jp|jpn)$","")
  }
  return $baseNoExt
}

function Pick-Subtitle($candidates, [string]$preferLang) {
  $rx = "\.$([Regex]::Escape($preferLang))\.srt$"
  $preferred = $candidates | Where-Object { $_.Name.ToLowerInvariant() -match $rx }
  if ($preferred) { return $preferred | Select-Object -First 1 }
  return ($candidates | Sort-Object { $_.Name.Length } | Select-Object -First 1)
}

function To-Iso639_2([string]$lang) {
  # Plex/Matroska language tags are commonly ISO 639-2/B or 639-2/T (3-letter).
  # We accept 2-letter inputs like "en" and map the common ones.
  $l = ($lang ?? "").Trim().ToLowerInvariant()
  if ([string]::IsNullOrWhiteSpace($l)) { return "eng" }

  $map = @{
    "en"="eng"; "eng"="eng"; "english"="eng";
    "es"="spa"; "spa"="spa"; "spanish"="spa";
    "fr"="fre"; "fre"="fre"; "fra"="fra"; "french"="fre";
    "de"="ger"; "ger"="ger"; "deu"="deu"; "german"="ger";
    "it"="ita"; "ita"="ita"; "italian"="ita";
    "pt"="por"; "por"="por"; "br"="por"; "portuguese"="por";
    "ja"="jpn"; "jp"="jpn"; "jpn"="jpn"; "japanese"="jpn";
  }

  if ($map.ContainsKey($l)) { return $map[$l] }

  # If user passes something else, keep it (best-effort).
  return $l
}

Require-Exe "ffmpeg"

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = Join-Path (Resolve-Path $VideoDir).Path "mkvized_out"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$resolvedVideoDir = (Resolve-Path $VideoDir).Path
$resolvedSubDir   = (Resolve-Path $SubtitleDir).Path
$resolvedOutDir   = (Resolve-Path $OutputDir).Path

Write-Host "VideoDir    : $resolvedVideoDir"
Write-Host "SubtitleDir : $resolvedSubDir"
Write-Host "OutputDir   : $resolvedOutDir"
Write-Host "Recurse     : $Recurse"
Write-Host "DryRun      : $DryRun"
Write-Host "Overwrite   : $Overwrite"
Write-Host "PreferLang  : $PreferLang"
Write-Host ""

# Index subtitles by normalized basename (FORCE ARRAY with @(...))
$subs = @(Get-ChildItem -Path $SubtitleDir -Filter *.srt -File -Recurse:$Recurse)
$subsByKey = @{}

foreach ($s in $subs) {
  $base = [System.IO.Path]::GetFileNameWithoutExtension($s.Name)
  $base = Strip-LangSuffix $base
  $key  = Normalize-BaseName ($base + ".x")
  if (-not $subsByKey.ContainsKey($key)) { $subsByKey[$key] = @() }
  $subsByKey[$key] += $s
}

# Collect videos (FORCE ARRAY with @(...)) and exclude OutputDir
$outExcludePrefix = $resolvedOutDir.TrimEnd('\') + '\*'
$videos = @(
  Get-ChildItem -Path $VideoDir -File -Recurse:$Recurse |
    Where-Object {
      $VideoExts -contains $_.Extension.ToLowerInvariant() -and
      $_.FullName -notlike $outExcludePrefix
    }
)

if ($videos.Count -eq 0) {
  Write-Warning "No videos found in '$VideoDir' with extensions: $($VideoExts -join ', ')"
  exit 0
}

$ffCommon = @("-hide_banner")
$ffCommon += ($(if ($Overwrite) { "-y" } else { "-n" }))

$ok = 0; $failed = 0

# Language tag for the embedded subtitle stream
$subLangTag = To-Iso639_2 $PreferLang

foreach ($v in $videos) {
  $key  = Normalize-BaseName $v.Name
  $base = [System.IO.Path]::GetFileNameWithoutExtension($v.Name)
  $outPath = Join-Path $OutputDir ($base + ".mkv")

  $hasSrt = $subsByKey.ContainsKey($key)
  $srt = $null
  if ($hasSrt) {
    $srt = Pick-Subtitle $subsByKey[$key] $PreferLang
  }

  if ($hasSrt) {
    # Remux + embed SRT in ONE pass.
    # IMPORTANT: Use per-stream codec copy to avoid ffmpeg's "multiple -c" warning.
    $args = $ffCommon + @(
      "-i", $v.FullName,
      "-i", $srt.FullName,
      "-map", "0",
      "-map", "1:0",
      "-c:v", "copy",
      "-c:a", "copy",
      "-c:s", "srt",
      "-map_metadata", "0",
      "-map_chapters", "0",
      "-metadata:s:s:0", "language=$subLangTag",
      "-metadata:s:s:0", "title=Subtitles",
      $outPath
    )

    Write-Host "MKVIZE+SUBS:"
    Write-Host "  VIDEO: $($v.Name)"
    Write-Host "    SRT: $($srt.Name)"
    Write-Host "    OUT: $outPath"
  } else {
    # Remux only (still stream copy).
    $args = $ffCommon + @(
      "-i", $v.FullName,
      "-map", "0",
      "-c:v", "copy",
      "-c:a", "copy",
      "-map_metadata", "0",
      "-map_chapters", "0",
      $outPath
    )

    Write-Host "MKVIZE (no matching SRT found):"
    Write-Host "  VIDEO: $($v.Name)"
    Write-Host "    OUT: $outPath"
  }

  if ($DryRun) {
    Write-Host "  (dry-run) ffmpeg $($args -join ' ')"
    Write-Host ""
    $ok++
    continue
  }

  & ffmpeg @args | Out-Host
  if ($LASTEXITCODE -ne 0) {
    Write-Error "ffmpeg failed for: $($v.Name) (exit $LASTEXITCODE)"
    $failed++
  } else {
    $ok++
  }

  Write-Host ""
}

Write-Host "Done. OK=$ok  Failed=$failed"
