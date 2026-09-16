<#
.SYNOPSIS
  核实论文身份：arXiv 元数据（是否只是预印本、作者自述的录用信息）+ Crossref（正式出版 / DOI）。

.EXAMPLE
  ./paper-meta.ps1 -ArxivId 1706.03762
  ./paper-meta.ps1 -Title "Attention Is All You Need"
  ./paper-meta.ps1 -Doi "10.48550/arXiv.1706.03762"

.NOTES
  本文件必须以 UTF-8 with BOM 保存（Windows PowerShell 5.1 需要），否则中文会乱码并报语法错误。
  输出里的状态推测基于 arXiv 元数据；<arxiv:comment> 属于作者自述，不是官方录用证据。
#>
[CmdletBinding()]
param(
  [string]$ArxivId,
  [string]$Title,
  [string]$Doi
)

$ErrorActionPreference = 'Stop'
try { $OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

function Get-Web([string]$url, [int]$retry = 3) {
  for ($i = 1; $i -le $retry; $i++) {
    try { return (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30).Content }
    catch {
      if ($i -eq $retry) { throw }
      Start-Sleep -Seconds (3 * $i)
    }
  }
}

function Clean([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return '' }
  return (($s -replace '<[^>]+>', '') -replace '\s+', ' ').Trim()
}

function Or-None([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return '无' }
  return $s
}

if (-not ($ArxivId -or $Title -or $Doi)) { throw "至少给一个：-ArxivId / -Title / -Doi" }

# ---------------- arXiv ----------------
if ($ArxivId -or $Title) {
  if ($ArxivId) {
    $url = "http://export.arxiv.org/api/query?id_list=$ArxivId&max_results=5"
  }
  else {
    $url = "http://export.arxiv.org/api/query?search_query=ti:%22" + [uri]::EscapeDataString($Title) + "%22&max_results=5"
  }

  Write-Output "==== arXiv ===="
  Write-Output "query: $url"
  try {
    $c = Get-Web $url
    $entries = [regex]::Matches($c, '(?s)<entry>(.*?)</entry>')
    if ($entries.Count -eq 0) {
      Write-Output "arXiv 没有返回条目：可能标题匹配失败，或该工作未上 arXiv。"
    }
    foreach ($e in $entries) {
      $b = $e.Groups[1].Value
      $t    = Clean ([regex]::Match($b, '(?s)<title>(.*?)</title>').Groups[1].Value)
      $pub  = Clean ([regex]::Match($b, '(?s)<published>(.*?)</published>').Groups[1].Value)
      $upd  = Clean ([regex]::Match($b, '(?s)<updated>(.*?)</updated>').Groups[1].Value)
      $id   = Clean ([regex]::Match($b, '(?s)<id>(.*?)</id>').Groups[1].Value)
      $cat  = ([regex]::Match($b, 'primary_category[^>]*term="([^"]+)"').Groups[1].Value)
      $com  = Clean ([regex]::Match($b, '(?s)<arxiv:comment[^>]*>(.*?)</arxiv:comment>').Groups[1].Value)
      $jr   = Clean ([regex]::Match($b, '(?s)<arxiv:journal_ref[^>]*>(.*?)</arxiv:journal_ref>').Groups[1].Value)
      $doii = Clean ([regex]::Match($b, '(?s)<arxiv:doi[^>]*>(.*?)</arxiv:doi>').Groups[1].Value)
      $names = @([regex]::Matches($b, '<name>(.*?)</name>') | ForEach-Object { Clean $_.Groups[1].Value })
      if ($names.Count -le 6) { $auth = $names -join ', ' }
      else { $auth = ($names[0..4] -join ', ') + " 等 $($names.Count) 人" }

      if ($jr) { $status = "published - 有 journal_ref" }
      elseif ($doii) { $status = "published - 有 DOI" }
      elseif ($com -match '(?i)accept') { $status = "accepted - 作者自述，需官方列表确认" }
      elseif ($com -match '(?i)submit|under review|review') { $status = "submitted 或 under review - 作者自述" }
      else { $status = "preprint - arXiv 元数据无出版信息" }
      if ($upd -and $pub -and $upd -ne $pub) { $status += "；已多次修改" }

      Write-Output ""
      Write-Output "标题  : $t"
      Write-Output "id    : $id"
      Write-Output "作者  : $auth"
      Write-Output "发布  : $pub    最后修改: $upd"
      Write-Output "领域  : $cat"
      Write-Output "comment    : $(Or-None $com)"
      Write-Output "journal_ref: $(Or-None $jr)"
      Write-Output "arxiv DOI  : $(Or-None $doii)"
      Write-Output "状态推测   : $status"
    }
  }
  catch { Write-Output "arXiv 查询失败: $($_.Exception.Message)" }

  Write-Output ""
  Write-Output "注：comment 是作者自述，不等于官方录用。确认 accepted 请查会议官网接收列表 / OpenReview decision / ACL Anthology / PMLR。"
}

# ---------------- Crossref ----------------
if ($Title -or $Doi) {
  if ($Doi) {
    $url = "https://api.crossref.org/works/" + [uri]::EscapeDataString($Doi)
  }
  else {
    $url = "https://api.crossref.org/works?query.bibliographic=" + [uri]::EscapeDataString($Title) + "&rows=3&select=title,container-title,type,issued,DOI,publisher"
  }

  Write-Output ""
  Write-Output "==== Crossref　正式出版记录 ===="
  Write-Output "query: $url"
  try {
    $j = (Get-Web $url) | ConvertFrom-Json
    if ($j.message.items) { $items = $j.message.items } else { $items = @($j.message) }
    if ($Title) { $want = ($Title -replace '[^a-zA-Z0-9]', '').ToLower() } else { $want = $null }

    foreach ($it in ($items | Select-Object -First 3)) {
      $ti = ($it.title -join ' | ')
      $ct = ($it.'container-title' -join ' | ')
      $yr = $it.issued.'date-parts'[0][0]
      $match = '（未比对）'
      if ($want) {
        $got = ($ti -replace '[^a-zA-Z0-9]', '').ToLower()
        $ratio = 0.0
        if ($got.Length -gt 0 -and $want.Length -gt 0) {
          $ratio = [Math]::Min($got.Length, $want.Length) / [Math]::Max($got.Length, $want.Length)
        }
        if ($got -eq $want) { $match = '标题完全一致，可信' }
        elseif (($got.Contains($want) -or $want.Contains($got)) -and $ratio -ge 0.9) { $match = '标题高度相似，大概率同一篇' }
        elseif ($got.Contains($want) -or $want.Contains($got)) { $match = '标题只覆盖一部分，多半是另一篇工作，仅供参考' }
        else { $match = '标题不一致，与本篇无关' }
      }
      $ctShow = '无 container-title，可能只是预印本登记'
      if ($ct) { $ctShow = $ct }

      Write-Output ""
      Write-Output "标题  : $ti"
      Write-Output "出处  : $ctShow"
      Write-Output "类型  : $($it.type)    年份: $yr    出版方: $($it.publisher)"
      Write-Output "DOI   : $($it.DOI)"
      Write-Output "匹配  : $match"
    }
  }
  catch { Write-Output "Crossref 查询失败: $($_.Exception.Message)" }
}
