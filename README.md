<div align="center">
  <img src="Wenku8Studio/AppResources/icon_raw.png" width="136" style="border-radius: 28px;" alt="Wenku8 Studio Icon"/>
  <h1>Wenku8 Studio</h1>
  <p><strong>轻小说文库（wenku8）macOS 原生 Liquid Glass 客户端 & 出版级 EPUB 拼装下载器</strong></p>

  <p>
    <a href="https://github.com/generalio/lightnovel-download/actions/workflows/ci.yml">
      <img src="https://github.com/generalio/lightnovel-download/actions/workflows/ci.yml/badge.svg" alt="CI"/>
    </a>
    <a href="https://github.com/generalio/lightnovel-download/releases">
      <img src="https://img.shields.io/github/v/release/generalio/lightnovel-download?style=flat-square&color=559DCD" alt="Release"/>
    </a>
    <img src="https://img.shields.io/badge/macOS-26%2B%20Liquid%20Glass-blue?style=flat-square&logo=apple" alt="macOS 26+"/>
    <img src="https://img.shields.io/badge/Swift-5.10%20%2F%20Xcode-orange?style=flat-square&logo=swift" alt="Swift"/>
    <img src="https://img.shields.io/badge/Python-3.11%2B%20CLI%20%26%20GUI-3776AB?style=flat-square&logo=python" alt="Python"/>
  </p>

  <p>
    <a href="#核心特性">核心特性</a> •
    <a href="#界面预览">界面预览</a> •
    <a href="#快速开始">快速开始</a> •
    <a href="#epub-拼装与自定义">EPUB 拼装</a> •
    <a href="#自动构建与发版">CI/CD 发版</a>
  </p>
</div>

---

## 简介

**Wenku8 Studio** 是一套面向 [轻小说文库（wenku8）](https://www.wenku8.cc) 的现代轻小说阅读、目录检索与 **EPUB 3.0 / 2.0 定制拼装工具**，同时提供：

1. **macOS 原生 SwiftUI 客户端（`Wenku8Studio`）**：采用 macOS 26+ 原生 **Liquid Glass（液态玻璃）** 视觉语言构建，零第三方依赖，支持全站发现与搜索、书架与历史管理、可视化分卷/章节勾选、内置沉浸阅读器（含插图大图灯箱预览）、书评楼层/楼中楼查看以及高度可定制的 EPUB 拼装工坊。
2. **跨平台 Python CLI & Fluent GUI**：保留轻量命令行工具（`lightnovel.py`）与 PyQt-Fluent-Widgets 桌面界面（`lightnovel_gui.py`），适合 Linux/Windows 及自动化批处理场景。

---

## 核心特性

### 1. 发现、检索与书架管理
- **双域名自动容灾**：默认优先请求 `https://www.wenku8.cc`，遇主站拦截或网络异常自动回退 `https://www.wenku8.net`。
- **多维度搜索与榜单**：默认加载「总点击榜」，支持最近更新、总推荐榜、月点击榜、完结专区、动画化作品，并支持按**书名 / 作者 / 书号**搜索；未登录触发全站权限时支持内置浏览器一键网页登录提取 Cookie（带格式自检与有效性测试）。
- **图文书架与浏览历史**：统一高颜值卡片展示异步封面、作者、文库分类、连载状态、字数、更新时间、Tags 与简介，整卡点击直达目录，右上角支持一键收藏与单条删除/清空。

### 2. 目录选章、书评楼中楼与内置阅读器
- **可视化分卷/章节勾选树**：拉取目录后自由勾选任意单卷或单个章节，支持全选、清空、反选、仅选含彩插卷、关键字过滤及范围快速勾选（如 `1-3`）。
- **macOS 原生检查器书评（`.inspector`）**：在书籍详情页直接滑出书评侧栏，点进帖子按 `1#` 主楼 + 楼层号 + **楼中楼嵌套引用**展示真实讨论。
- **沉浸式在线阅读器**：支持内置目录切换、素白/羊皮纸/护眼绿/夜间四套主题、黑体/楷体/宋体切换、字号/行距/段距/版心宽度调节、阅读进度记忆、方向键翻章及**插图大图灯箱预览（100%–400% 缩放、多图切换与保存）**。

### 3. 出版级 EPUB 拼装工坊
- **双规范兼容**：支持 **EPUB 3.0**（含 `nav.xhtml`、`cover-image`、`belongs-to-collection` 系列分组与 `toc.ncx` 回退）及 **EPUB 2.0**。
- **单卷 / 合集双模式**：支持每卷独立输出，或将多卷合并打包为单本带**二级嵌套目录**的全集 EPUB。
- **丰富元数据与扉页**：自动抓取并写入文库分类（`dc:publisher`）、作品 Tags（`dc:subject`）、简介（`dc:description`）、更新时间（`dc:date`），并可生成图文并茂的书籍简介扉页（`info.xhtml`）。
- **深度排版定制**：彩插独立分页/单页拼接、彩插置于正文前/后、正文重复插图自动去重、清理录入组声明行、自定义封面或追加本地彩页、外置共享 CSS 样式表（首行缩进/行高/段距）及文件名模板实时预览；严格按 EPUB 规范将 `mimetype` 以无压缩方式置于 ZIP 首字节。

---

## 界面预览

### macOS 原生客户端（Liquid Glass）

<div align="center">
  <img src="docs/screenshots/bookshelf.jpg" width="880" alt="书架与最近浏览"/>
  <br/><br/>
  <img src="docs/screenshots/book_card.jpg" width="440" alt="统一书籍卡片组件"/>
</div>

### 跨平台 Python Fluent GUI

<div align="center">
  <img src="resource/example1.png" width="420" alt="Python GUI 主界面"/>
  <img src="resource/example2.png" width="420" alt="Python GUI 下载示例"/>
</div>

---

## 快速开始

### 方式一：下载 GitHub Release 成品（macOS）

前往 [Releases 页面](https://github.com/generalio/lightnovel-download/releases) 下载最新 `Wenku8Studio-v*-macOS-arm64.dmg` 或 `.zip`，拖入「应用程序」即可运行（macOS 26+ Apple Silicon）。

> 若首次打开提示来自未签名开发者，可在系统「隐私与安全性」中允许打开，或执行：
> ```bash
> xattr -cr /Applications/Wenku8Studio.app
> ```

### 方式二：从源码使用 Xcode 构建 macOS 客户端

需要 macOS 26+、Xcode 26+（已验证 Xcode 27.2）与 `xcodegen`：

```bash
brew install xcodegen
./Wenku8Studio/build_app.sh
open Wenku8Studio.app
```

运行 Swift 单元测试：

```bash
cd Wenku8Studio
xcodegen generate
xcodebuild test -project Wenku8Studio.xcodeproj -scheme Wenku8Studio -destination 'platform=macOS'
```

### 方式三：运行 Python 命令行 / 跨平台 GUI

```bash
# 安装完整依赖（CLI + PyQt5 GUI）
pip install -r requirements.txt -i https://pypi.org/simple/

# 启动跨平台图形界面
python lightnovel_gui.py

# 或启动命令行交互模式
python lightnovel.py

# 非交互命令行下载（例如下载书号 3115 第 1~3 卷）
python lightnovel.py --no_input --book_no 3115 --volume_no 1-3 --out_dir ./out
```

仅使用命令行版本（Linux / 无头环境）只需安装核心依赖：

```bash
pip install requests beautifulsoup4 rich pillow -i https://pypi.org/simple/
```

---

## EPUB 拼装与自定义

在客户端「**设置 → EPUB 拼装**」中可一站式配置：

| 配置项 | 可选能力 |
| :--- | :--- |
| **规范版本** | EPUB 3.0（兼容 2.0）/ EPUB 2.0 |
| **导出策略** | 每卷独立 EPUB / 多卷合并单本合集（二级分卷目录） |
| **封面策略** | 优先本卷插图首图 / 强制书籍主页封面 / 导入本地自定义图片 |
| **彩插排版** | 每张彩插独立分页 / 单页连续拼装 / 忽略彩插页；支持正文前/后与额外追加本地图片 |
| **正文样式** | 段首缩进（em）、正文行高、段落间距滑块、清理头部录入组声明行 |
| **命名模板** | 支持 `{title}`、`{volume}`、`{index}`、`{author}`、`{id}` 变量与实时预览 |

---

## 自动构建与发版

仓库配置了完整的 GitHub Actions 工作流：

- **持续集成**（[ci.yml](.github/workflows/ci.yml)）：推送或 PR 至主分支时自动运行 Python 核心单元测试与 macOS Xcode 编译测试。
- **Tag 自动发版**（[release.yml](.github/workflows/release.yml)）：推送 `v*` 标签时自动执行测试、构建 `Wenku8Studio.app`、打包 `.dmg` / `.zip` 及 Python 脚本包，并发布至 GitHub Releases：

```bash
git tag v2.3.0
git push origin v2.3.0
```

---

## 目录结构

```text
lightnovel-download/
├── .github/workflows/          # GitHub Actions CI & Tag 自动发版工作流
├── Wenku8Studio/               # macOS 原生 SwiftUI 客户端（Liquid Glass）
│   ├── Sources/Wenku8Core/     # 网络抓取、GB18030 解析、Cookie 诊断、EPUB 组装引擎
│   ├── Sources/Wenku8Studio/   # SwiftUI 视图与状态管理（目录/阅读器/书架/发现/设置）
│   ├── Tests/Wenku8CoreTests/  # Swift XCTest 单元测试
│   ├── AppResources/           # 应用图标（Assets.xcassets / icon_raw.png）与 Info.plist
│   ├── project.yml             # XcodeGen 工程描述
│   └── build_app.sh            # 一键生成 .xcodeproj 并编译打包 .app
├── docs/screenshots/           # README 界面展示截图
├── Editer.py                   # Python 核心下载与 EPUB 打包类
├── utils.py                    # Python EPUB XHTML/OPF/NCX 模板与 XML 转义工具
├── lightnovel.py               # Python CLI 入口
├── lightnovel_gui.py           # Python PyQt-Fluent-Widgets GUI 入口
└── tests/test_core.py          # Python pytest 单元测试
```

---

## 免责声明

本项目仅供个人学习与离线阅读排版技术交流使用，请支持正版轻小说，勿用于商业用途或高频恶意爬取。
