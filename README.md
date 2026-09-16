# paper-reading

给 AI coding agent 用的**论文精读陪读** skill。目标只有一个：让你读完一篇论文后，能自己说清 **为什么做 → 怎么做 → 为什么有效 → 哪里其实没证明**。

不是摘要翻译，不是文献综述，也不是审稿机器人。审稿视角只用来给结论划边界。

## 安装

复制整个目录到 agent 的 skill 目录即可（目录名不影响加载，`SKILL.md` 的 `name` 才是标识）：

```bash
# 全局（任何项目都能用）
cp -r paper-reading ~/.agents/skills/

# 项目级
cp -r paper-reading <你的仓库>/.agents/skills/
```

Windows 上全局目录是 `C:\Users\<你>\.agents\skills\`。

## 结构

```
paper-reading/
├── SKILL.md                          定位 + 8 条铁律 + 9 步流程 + 长度路由表
├── references/
│   ├── pipeline-and-modules.md       流程画法、模块六问、公式/算法讲解顺序、创新三层
│   ├── figures.md                    图表读法（含"这张图不能说明什么"）
│   ├── data-and-experiments.md       数据来源/标注/划分/指标四问/公平性/消融
│   ├── evidence-bounds.md            claim 与 evidence 分离、平均分掩盖、强假设清单
│   ├── paper-identity.md             录用状态核实渠道（arXiv / Crossref / OpenReview）
│   ├── output-templates.md           完整模板 + 各长度档裁剪 + 换讲法示例
│   ├── compare-and-map.md            多论文对比表 + 研究地图 + notes.md 结构
│   └── idea-mining.md                找选题（默认不加载，仅在明确要求时）
└── scripts/
    ├── extract-paper.ps1             PDF → 文本 + 解析质量体检 + 骨架 + 关键词检索
    └── paper-meta.ps1                arXiv / Crossref 身份核实
```

`SKILL.md` 只放路由和铁律，细节按需加载——单篇快读只吃 9KB，深度审查才拉 references。

## 用法

```
帮我读一下 D:\papers\xxx.pdf      → 默认 9 步讲解
讲讲这篇的流程                     → 只讲 pipeline
图 3 什么意思                      → 只解释那张图
这篇可信吗                         → 只讲证据边界
/skill:paper-reading <path>       → 强制加载
```

## 脚本

```powershell
# PDF → 文本，顺带体检解析质量 + 生成章节/图表骨架
./scripts/extract-paper.ps1 -Path "D:\papers\attention.pdf"
./scripts/extract-paper.ps1 -Path paper.pdf -Slug attention -Pages "1-4"
./scripts/extract-paper.ps1 -Slug attention -Grep "ablation"

# 论文身份核实（是否只是预印本、有没有正式发表记录）
./scripts/paper-meta.ps1 -ArxivId 1706.03762
./scripts/paper-meta.ps1 -Title "Attention Is All You Need"
```

产物落在 `paper-notes/<slug>/`：`source.txt`、`source.head.txt`、`outline.txt`、`notes.md`。

## 依赖与坑

- Windows PowerShell 5.1+。
- 需要 `pdftotext`（Git for Windows 自带 poppler，或 poppler / MiKTeX）。脚本会逐个实测候选：
  **MiKTeX 自带的那个在提权环境下会报 `security risk: running with elevated privileges` 而拒绝运行**，Git 自带的可正常用。
- `scripts/*.ps1` 必须保持 **UTF-8 with BOM**，否则 PowerShell 5.1 会按 GBK 解析中文并直接语法报错。
- 抽取结果请用编辑器/`read` 工具查看，不要用 PowerShell 的 `Get-Content`——控制台编码会把中文显示成乱码，让你误判解析质量。
- 路径含中文引号 `“ ”` 时 PowerShell 会把它们当成引号导致参数解析失败，用 `Get-ChildItem | Where-Object | .FullName` 传入。
