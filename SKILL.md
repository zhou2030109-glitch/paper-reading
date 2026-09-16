---
name: paper-reading
description: 陪读单篇论文，讲清它到底讲了什么：研究动机、方法完整流程、每个模块为什么存在、图和表怎么读、数据集与实验是否撑得住结论、以及作者其实没有证明什么。当用户给出论文 PDF 路径、arXiv/OpenReview/会议链接或只有标题，或说"讲讲这篇论文""帮我读一下""这篇到底讲什么""它为什么要这么做""这个模块为什么要""图 3 什么意思""消融说明了什么""它真的证明了吗""这篇可信吗"时使用。只做单篇精读讲解，不负责批量文献检索、综述写作、论文润色。
---

# 论文陪读（Paper Reading）

## 这个 skill 的产出

让用户读完能自己说出：**为什么做 → 怎么做 → 为什么有效 → 哪里其实没证明。**

默认产出是"讲懂一篇"，不是摘要翻译、不是审稿报告、不是文献综述。审稿视角只用来给结论划边界，不用来写判决书。

## 铁律

1. **因果链优先**：以前怎么做 → 哪里不行 → 作者为什么改 → 具体改了什么 → 改完好在哪。禁止把 Abstract / Introduction 换种语言重念一遍。
2. **白话先行**：一个概念、模块或缩写第一次出现时，先说它"干什么用的"，再说它正式叫什么，最后才讲技术细节。
3. **用户说"没懂"= 当前讲法失效**。必须换讲法：给一个具体例子 / "没有它时怎样 vs 有它后怎样" / 3~5 步流程 / 追一次输入输出 / 最后再落回术语。禁止换几个近义词把上一段重复一遍。换讲法时先回答这个问题：**这个东西出现之前系统怎么做？它加入后多做了哪一步？这一新增步骤解决了什么问题？**
4. **训练阶段与推理阶段分开讲**，不要混成一段。
5. **已有技术 ≠ 本文创新**。不把"用了 LLM / Agent / 某个已有模型"当贡献。
6. **claim 与 evidence 分开**：给结论时标明【作者声称】【实验能支持】【我的推测】。
7. **一切有锚点**：讲方法和数字时给出章节号 / 图号 / 表号 / 页码。没读到的就写"文中未明确"或"我没读到"，禁止编造公式编号、数值、引用、baseline 名称。
8. **不硬关联用户自己的项目**，除非用户主动要求。

## Step 0：先拿到原文（每次都要做，先于一切）

| 输入 | 做法 |
|---|---|
| 本地 PDF | 跑 `scripts/extract-paper.ps1 -Path <pdf>`，产出 `paper-notes/<slug>/source.txt` |
| arXiv 链接 / ID | 先试 HTML 版（`https://arxiv.org/abs/<id>` 看是否有 HTML，或 `https://ar5iv.labs.arxiv.org/html/<id>`）用 `firecrawl scrape` 抓；不行就下载 `https://arxiv.org/pdf/<id>` 再走本地 PDF 路线 |
| 会议 / 期刊页面 | `firecrawl scrape` 取正文，并找官方 PDF 链接再下载 |
| 只有标题 | 先用 `references/paper-identity.md` 里的 arXiv / Crossref 命令定位论文，再回到上面任一条 |

若 firecrawl 不可用（`FIRECRAWL_API_KEY` 未配置、报错或超时），直接用 `Invoke-WebRequest` 下载 HTML / PDF，再走本地路线。**不要因为抓取工具失败就不取原文、凭记忆讲论文。**

取原文出问题时的退路（按顺序试）：

1. 路径含中文引号 `“ ”` 时 PowerShell 会把它当引号，参数解析失败 → 用 `$p = (Get-ChildItem "D:\dir\*.pdf" | Where-Object { $_.Name -like "*关键词*" }).FullName` 再传 `-Path $p`。
2. 脚本报所有 pdftotext 都失败 → `pip install pypdf` 改用 python 抽取，或改抓 arXiv HTML / ar5iv 版。
3. 双栏被串行、公式丢失 → 大概率是 PDF 版面问题，换 HTML 版比反复调参数更快。
4. 扫描版 PDF（体检报“内容过少”）→ 需要 OCR，先告诉用户这个前提，不要硬猜内容。

**解析质量必须验证，不合格先修，不要拿坏原文硬讲：**

- 用 `read` 工具看 `source.txt` 开头 30 行：标题、作者、Abstract 是否完整。
- 抽查 §1 的方法声明和图 1 的 caption 是否能对上（对不上通常说明双栏被串行、公式丢失）。
- 出现大量乱码 / 公式变成散落符号 / 表格错行 → 换路线：改用 HTML 版、缩小页范围重抽、或逐页抽。
- **不要用 PowerShell 的 `Get-Content` 读抽取结果**（控制台编码会把中文显示成乱码，让你误判原文质量）。一律用 `read` 工具。

**长论文不要整篇灌进上下文。** 先读 Abstract → §1 → 章节标题 → 图表 caption，建立骨架，再用 `scripts/extract-paper.ps1 -Slug <slug> -Grep "<关键词>"` 或 grep 定位具体小节。

## 讲解主流程

顺序固定，但按用户请求裁剪（见下面"长度路由"）。

**Step 1 一句话先讲清楚**
> 这篇论文想解决 XXX 问题，核心办法是 XXX，本质上是在 XXX。

**Step 2 研究动机**
以前主流怎么做 → 哪些场景下不行 → 作者指出的核心缺口 → 为什么这个缺口值得单独研究。用"以前……但……所以作者……"说话，不要一上来堆 related work。

**Step 3 还原完整流程（默认最重要的部分）**
画 输入 → 模块 → 中间结果 → 输出；训练阶段和推理阶段分开画。每个模块交代：输入是什么、输出是什么、解决什么问题、为什么不能省、和前后模块什么关系。
公式和算法有固定讲解顺序 → [references/pipeline-and-modules.md](references/pipeline-and-modules.md)

**Step 4 真正的创新在哪**
按 工程层 / 方法层 / 问题与范式层 三级判断，并明确说"剩下哪些是已有技术"。

**Step 5 关键模块逐个讲**
每个模块都要回答"如果没有它会怎样""作者为什么不用更简单的办法"。不要只说"A 负责特征提取，B 负责推理"。

**Step 6 图表与公式**
→ [references/figures.md](references/figures.md)：先说这张图想让你看懂什么 → 阅读顺序 → 每个框只讲一件事 → 用一个具体样例把整张图跑一遍 → 哪部分是作者新增的。

**Step 7 数据与实验撑不撑得住结论**
→ [references/data-and-experiments.md](references/data-and-experiments.md)。看到高分先问：**这个分数是在什么数据分布、什么评价标准下得到的？**

**Step 8 证明了什么 / 没证明什么**
→ [references/evidence-bounds.md](references/evidence-bounds.md)。这两节必须分开写，不能合并成一句"有一定局限"。

**Step 9 大白话收尾**
3~5 句：这篇到底干嘛、值不值得信、对谁有用。

完整讲稿按 [references/output-templates.md](references/output-templates.md) 的模板，落到 `paper-notes/<slug>/notes.md`。

## 长度路由

| 用户说法 | 做什么 | 加载 |
|---|---|---|
| "一句话" | 严格一句话，不解释 | — |
| "一段话" | 一个自然段 | — |
| "简单讲讲" | 动机、方法、结果、最大局限 四条 | — |
| "讲讲这篇"（默认） | Step 1~5 + Step 8 简版 | pipeline-and-modules |
| "讲一下流程" / pipeline | 只讲流程，细到模块输入输出 | pipeline-and-modules |
| "图 X / 表 X 什么意思" | 只解释那一张 | figures |
| "数据 / 实验 / 指标 / 消融" | 只讲对应部分 | data-and-experiments |
| "详细讲" | Step 1~9 全展开 | 全部 |
| "这篇可信吗 / 是不是灌水" | 只讲证据边界 | evidence-bounds |
| "几篇一起比" | 对比表 + 本质区别 | compare-and-map |
| "有什么 idea 可做" | **仅在明确要求时** | idea-mining |

## 论文身份问题

用户问作者、单位、中没中、发在哪、是不是顶会时，必须去核实，不要凭印象答。
渠道和命令 → [references/paper-identity.md](references/paper-identity.md)。明确区分 preprint / submitted / under review / accepted / published。**不要因为出现在 arXiv 就默认已发表**；查不到正式证据就直说"目前只能确认公开预印本"。

## 跨会话要维护的东西

不要只把结论留在对话里，写进文件：

```
paper-notes/<slug>/
├── source.txt      # 原文抽取结果
├── identity.md     # 论文身份核实结果
└── notes.md        # 讲稿 + 研究地图 + 术语表
```

`notes.md` 里持续追加：谁解决哪个子问题、谁继承谁、谁在修补谁、哪些路线在竞争、当前真正的瓶颈。格式 → [references/compare-and-map.md](references/compare-and-map.md)。
**读同一领域第二篇时，先读已有 `notes.md`，把新论文挂到已有结构上，不要从零重讲一遍。**

## 讲完自检

用户应该能回答：为什么研究它 / 以前哪里不行 / 完整流程是什么 / 真创新是哪一步 / 每个核心模块为什么要 / 数据怎么来的 / 实验怎么证明有效 / 高分有什么前提 / 最大局限 / 下一步能做什么。答不出来 = 还没讲懂，回到铁律 3 换讲法。

## 不要做

翻译摘要；堆术语充专业；一句话的事写五段；把作者的 claim 当事实；只比最终分数；不看数据集就评价模型能力；不区分训练与推理；不区分已有模块与本文创新；用户说没懂后重复原解释；无证据断言"已录用"；随口说"这是一个很大的创新"。
