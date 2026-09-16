# 论文身份核实：作者、单位、中没中、发在哪

原则：**这部分最容易幻觉，必须查，不能凭印象答。** 查不到就直说查不到。

## 1. 状态词表（回答时必须用其中之一，不要含糊）

| 状态 | 含义 | 判定依据 |
|---|---|---|
| preprint | 只有预印本 | arXiv / bioRxiv 存在，无正式出版信息 |
| submitted | 作者声称已投稿 | 论文 comment 字段或作者主页自述 |
| under review | 审稿中 | OpenReview 有 submission，无决定 |
| accepted | 已录用未出版 | 会议官方接收列表 / OpenReview decision=Accept |
| published | 已正式出版 | DOI、会议 proceedings、期刊卷期 |

**不要因为出现在 arXiv 就默认已经正式发表。**

## 2. 核实渠道（按顺序试）

### arXiv API（最稳，无需鉴权）

```powershell
# 按 ID
Invoke-WebRequest "http://export.arxiv.org/api/query?id_list=1706.03762" -UseBasicParsing |
  Select-Object -Expand Content

# 按标题（注意 URL 编码）
Invoke-WebRequest "http://export.arxiv.org/api/query?search_query=ti:%22attention%20is%20all%20you%20need%22&max_results=5" -UseBasicParsing |
  Select-Object -Expand Content
```

重点看返回的这几个字段：

- `<published>` / `<updated>` — 首次上传和最后修改时间（updated 晚于 published 很多，通常说明改过好几版）；
- `<arxiv:comment>` — 常写 "Accepted at NeurIPS 2024" 之类，是**作者自述**，不是官方证据；
- `<arxiv:journal_ref>` — 有值基本可确认已正式发表；
- `<arxiv:primary_category>` — 领域。

### Crossref（查正式出版 / DOI）

```powershell
Invoke-WebRequest "https://api.crossref.org/works?query.bibliographic=<标题 URL 编码>&rows=3" -UseBasicParsing |
  Select-Object -Expand Content
```

看 `title`、`container-title`（会议或期刊名）、`type`、`issued`、`DOI`、`publisher`。匹配上标题才认。

### 其他（需要时用 firecrawl scrape 打开）

- **ACL Anthology**（`aclanthology.org`）— NLP 系会议的权威出处，能区分 main / Findings / demo / workshop；
- **OpenReview**（`openreview.net`）— 看 submission 与 decision，确认是否 under review / accepted；
- **PMLR / NeurIPS / ICLR 官方论文列表** — 确认是否在正式 proceedings；
- **DBLP**（`dblp.org`）— 看该工作的完整出版记录，顺带能看到作者其他论文；
- **会议官网接收列表** — 判定 accepted 的最终依据。

`scripts/paper-meta.ps1` 已经把 arXiv + Crossref 封装好，优先用它：

```powershell
./scripts/paper-meta.ps1 -ArxivId 1706.03762
./scripts/paper-meta.ps1 -Title "Attention Is All You Need"
```

## 3. 回答口径

- 有正式出版证据：给出会议 / 期刊、年份、DOI，并说明是在哪查到的。
- 只有预印本：**"目前只能确认公开预印本，无法确认已正式录用。"** 附上 arXiv 的 comment 字段（如果有），并注明那是作者自述。
- 会议档次问题（是否 CCF-A / 顶会）：可以给公认事实，但要提醒**目录有版本差异**（例如某年目录把某会议列入 A、另一版列入 B），不要把"所在会议级别"直接等同于"这篇论文质量"。

## 4. 单位与作者

需要时从 PDF 首页抽取（`source.txt` 开头就是），或 Crossref 的 `author.affiliation`。注意：一作单位 ≠ 所有作者单位；通讯作者通常是最后一位或标注星号的那位。
