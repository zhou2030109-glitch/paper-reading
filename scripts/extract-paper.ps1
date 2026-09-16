<#
.SYNOPSIS
  论文 PDF -> 纯文本，落到 paper-notes/<slug>/source.txt，并顺手做解析质量体检 + 生成骨架（章节/图表清单）。

.EXAMPLE
  ./extract-paper.ps1 -Path "D:\papers\attention.pdf"
  ./extract-paper.ps1 -Path paper.pdf -Slug attention -Pages "1-4"
  ./extract-paper.ps1 -Slug attention -Grep "ablation"      # 在已抽取文本里检索

.NOTES
  本文件必须以 UTF-8 with BOM 保存（Windows PowerShell 5.1 需要），否则中文会乱码并报语法错误。
  抽取结果一律用 read 工具查看，不要用 Get-Content（控制台编码会显示成乱码）。
  优先用 Git 自带 poppler 的 pdftotext；MiKTeX 自带的那个在提权环境下会拒绝运行。
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Path,
  [string]$Slug,
  [string]$Pages,                                   # "1-4" 或 "7"
  [string]$Grep,                                    # 检索模式：在 source.txt 里找关键词
  [string]$OutDir = "paper-notes",
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
try { $OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}

function Get-Slug([string]$name) {
  $s = [IO.Path]::GetFileNameWithoutExtension($name).ToLowerInvariant()
  $s = $s -replace '[^a-z0-9]+', '-'
  $s = $s.Trim('-')
  if ($s.Length -gt 40) { $s = $s.Substring(0, 40).Trim('-') }
  if ([string]::IsNullOrWhiteSpace($s)) { $s = 'paper' }
  return $s
}

# ---------- 检索模式 ----------
if ($Grep) {
  $files = @()
  if ($Slug) {
    $cand = Join-Path $OutDir "$Slug\source.txt"
    if (Test-Path $cand) { $files = @($cand) } else { throw "找不到 $cand" }
  }
  else {
    $files = @(Get-ChildItem -Path $OutDir -Recurse -Filter 'source.txt' -ErrorAction SilentlyContinue | ForEach-Object FullName)
    if ($files.Count -eq 0) { throw "在 $OutDir 下没有找到任何 source.txt，先跑一次抽取" }
  }
  foreach ($f in $files) {
    Write-Output "=== $f ==="
    $hits = Select-String -Path $f -Pattern $Grep -Context 6, 6 -Encoding UTF8
    if (-not $hits) { Write-Output "(无匹配)"; continue }
    foreach ($h in ($hits | Select-Object -First 8)) {
      Write-Output ("--- line {0} ---" -f $h.LineNumber)
      $h.Context.PreContext | ForEach-Object { Write-Output "  $_" }
      Write-Output (">>" + $h.Line)
      $h.Context.PostContext | ForEach-Object { Write-Output "  $_" }
    }
  }
  return
}

# ---------- 抽取模式 ----------
if (-not $Path) { throw "需要 -Path <pdf>（或用 -Slug + -Grep 进入检索模式）" }
if (-not (Test-Path -LiteralPath $Path)) { throw "文件不存在: $Path" }
$pdf = (Resolve-Path -LiteralPath $Path).Path
if (-not $Slug) { $Slug = Get-Slug $pdf }

$dir = Join-Path $OutDir $Slug
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$txt      = Join-Path $dir 'source.txt'
$headFile = Join-Path $dir 'source.head.txt'
$outline  = Join-Path $dir 'outline.txt'

# pdftotext 候选：先 PATH，再 Git poppler，最后 MiKTeX（提权环境下会拒绝运行）
$cands = New-Object System.Collections.Generic.List[string]
$onPath = (Get-Command pdftotext -ErrorAction SilentlyContinue).Source
if ($onPath) { $cands.Add($onPath) }
foreach ($p in @(
    "$env:ProgramFiles\Git\mingw64\bin\pdftotext.exe",
    "${env:ProgramFiles(x86)}\Git\mingw64\bin\pdftotext.exe",
    "$env:LOCALAPPDATA\Programs\Git\mingw64\bin\pdftotext.exe",
    "$env:LOCALAPPDATA\Programs\MiKTeX\miktex\bin\x64\pdftotext.exe",
    "$env:ProgramFiles\MiKTeX\miktex\bin\x64\pdftotext.exe"
  )) {
  if ((Test-Path $p) -and ($cands -notcontains $p)) { $cands.Add($p) }
}
if ($cands.Count -eq 0) {
  throw "找不到任何 pdftotext。退路：pip install pypdf 后用 python 抽取，或改抓 arXiv HTML/ar5iv 版。"
}

if ((Test-Path $txt) -and -not $Force) {
  Write-Output "已存在（跳过抽取）: $txt"
}
else {
  $args2 = @('-layout', '-enc', 'UTF-8')
  if ($Pages) {
    $parts = $Pages.Split('-')
    if ($parts.Count -ge 1 -and $parts[0]) { $args2 += @('-f', $parts[0].Trim()) }
    if ($parts.Count -ge 2 -and $parts[1]) { $args2 += @('-l', $parts[1].Trim()) }
  }
  $args2 += @($pdf, $txt)

  $ok = $false
  $notes = New-Object System.Collections.Generic.List[string]
  foreach ($exe in $cands) {
    if (Test-Path $txt) { Remove-Item $txt -Force -ErrorAction SilentlyContinue }
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $msg = (& $exe @args2 2>&1 | Out-String).Trim()
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    $bytes = 0
    if (Test-Path $txt) { $bytes = (Get-Item $txt).Length }
    if ($bytes -gt 1000) {
      Write-Output "已抽取: $txt   by $exe"
      if ($msg) { $notes.Add($msg) }
      $ok = $true
      break
    }
    $why = '输出为空'
    if ($msg) {
      if ($msg -match '(?i)elevated') { $why = '该 pdftotext 拒绝在提权环境运行' }
      elseif ($msg -match '(?i)password|encrypted') { $why = 'PDF 有加密/口令' }
      else { $why = $msg }
    }
    Write-Output ("跳过 $exe : $why")
  }
  if (-not $ok) {
    throw "所有候选 pdftotext 都失败。退路：pip install pypdf（或 pdfminer.six）改用 python 抽取；或改抓 arXiv HTML/ar5iv 版。"
  }
}

$text = Get-Content -LiteralPath $txt -Raw -Encoding UTF8
if (-not $text) { throw "抽取结果为空" }

$lines       = $text -split "`n"
$lineCount   = $lines.Count
$nonWs       = ($text -replace '\s', '').Length
$pages       = ([regex]::Matches($text, "\f")).Count + 1
$repl        = ([regex]::Matches($text, [char]0xFFFD)).Count
$noSpaceLong = ($lines | Where-Object { $_.Length -gt 60 -and $_ -notmatch '\s' }).Count
$veryLong    = ($lines | Where-Object { $_.Length -gt 200 }).Count
$hasAbstract = [bool]($text -match '(?im)^\s*(abstract|摘要)\b')
$figCount    = ([regex]::Matches($text, '(?im)^\s*(figure|fig\.|图)\s*\d+')).Count
$tabCount    = ([regex]::Matches($text, '(?im)^\s*(table|表)\s*\d+')).Count
$hasRefs     = [bool]($text -match '(?im)^\s*(references|参考文献)\b')

$warn = New-Object System.Collections.Generic.List[string]
if ($nonWs -lt 2000) { $warn.Add("内容过少（$nonWs 字符）：可能是扫描版 PDF，需要 OCR；或页范围给错了") }
if ($repl -gt 0) { $warn.Add("含 $repl 个替换字符(U+FFFD)，有编码丢失") }
if ($noSpaceLong -gt [Math]::Max(3, $lineCount * 0.2)) { $warn.Add("大量长行无空格（$noSpaceLong 行）：疑似 CID 字体映射失败，正文不可信") }
if ($veryLong -gt [Math]::Max(3, $lineCount * 0.15)) { $warn.Add("大量超长行（$veryLong 行）：疑似双栏被串行，建议改用 arXiv HTML 版或 ar5iv") }
if (-not $hasAbstract) { $warn.Add("没找到 Abstract/摘要，可能没抽到正文首页") }
if (-not $hasRefs) { $warn.Add("没找到 References/参考文献，可能抽取不完整") }

Write-Output ""
Write-Output "---- 体检 ----"
Write-Output ("页数 ~{0} | 行数 {1} | 非空白字符 {2} | Figure {3} | Table {4}" -f $pages, $lineCount, $nonWs, $figCount, $tabCount)
if ($warn.Count -eq 0) { Write-Output "verdict: PASS" }
else { Write-Output "verdict: WARN"; $warn | ForEach-Object { Write-Output "  - $_" } }

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($headFile, (($lines | Select-Object -First 40) -join "`n"), $utf8NoBom)

$skel = New-Object System.Collections.Generic.List[string]
$skel.Add('# 骨架（L 后的数字是 source.txt 行号，可配合 read 的 offset 使用）')
$skel.Add('')
$skel.Add('## 章节标题候选')
for ($i = 0; $i -lt $lineCount; $i++) {
  $l = $lines[$i].Trim()
  $m = [regex]::Match($l, '^(\d+(?:\.\d+){0,2})\.?\s+(.*)$')
  if (-not $m.Success) { continue }
  $rest = $m.Groups[2].Value.Trim()
  # 排除表格行（数字后跟的是一堆数字/空格）
  if ($rest -notmatch '^[A-Za-z\u4e00-\u9fff]') { continue }
  if ($rest -match '\s{3,}') { continue }
  if ($rest.Length -lt 3 -or $rest.Length -gt 60) { continue }
  $skel.Add(("  L{0}: {1}   {2}" -f ($i + 1), $m.Groups[1].Value, $rest))
  if ($skel.Count -gt 60) { break }
}
$skel.Add('')
$skel.Add('## 图表 caption 候选')
$n = 0
for ($i = 0; $i -lt $lineCount; $i++) {
  $l = $lines[$i].Trim()
  if ($l -match '^(Figure|Fig\.|Table|Algorithm|图|表)\s*\d+' -and $l.Length -lt 220) {
    $skel.Add(("  L{0}: {1}" -f ($i + 1), $l)); $n++
    if ($n -ge 40) { break }
  }
}
[IO.File]::WriteAllText($outline, ($skel -join "`r`n"), $utf8NoBom)

Write-Output ""
Write-Output "---- 下一步 ----"
Write-Output "1) 用 read 工具看 $headFile"
Write-Output "2) 用 read 工具看 $outline 建立骨架"
Write-Output "3) 需要细节时: ./extract-paper.ps1 -Slug $Slug -Grep `"关键词`""
Write-Output "4) verdict 为 WARN 时先换 arXiv HTML/ar5iv 版或缩小页范围重抽，别拿坏原文硬讲"
