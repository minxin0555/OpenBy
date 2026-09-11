# OpenBy

原生 macOS 文件打开分流工具：根据文件类型和所在文件夹，将文件交给指定应用。

例如，同样是 PDF，`~/Documents/文献/` 中的文件用 PDF Expert 打开，其他位置的文件用“预览”打开。

## 功能

- 按文件后缀或格式组管理打开方式。
- 按文件夹配置有序规则，支持包含子文件夹；第一条匹配规则生效。
- 未命中规则时使用该类型的回退应用。
- 停用时恢复原应用；若用户已手动修改默认应用，则尊重用户的选择。
- 菜单栏常驻，支持登录时启动；关闭设置窗口后仍可转发文件。
- 配置保存在本机，无网络请求或遥测。

## 构建与运行

需要 macOS 14 或更新版本，以及 Swift 6.0 或更新版本的工具链（可通过 Xcode 或 Command Line Tools 提供）。

在项目根目录执行：

```bash
# 构建当前架构的应用与 ZIP，不自动注册到 Launch Services
./scripts/build-app.sh --no-register

# 启动应用
open dist/OpenBy.app
```

输出为 `dist/OpenBy.app` 和 `dist/OpenBy-<版本号>.zip`。不带 `--no-register` 构建时，脚本还会注册应用到 Launch Services。构建通用版本可使用 `--universal`。

生成拖拽安装的 DMG（包含应用、Applications 快捷方式和安装说明）：

```bash
./scripts/build-dmg.sh             # 当前架构
./scripts/build-dmg.sh --universal # Intel + Apple Silicon
```

输出为 `dist/OpenBy-<版本号>-<架构>.dmg` 和对应的 `.sha256` 校验文件。

当前脚本使用 ad-hoc 签名，未进行 Developer ID 签名或公证。签名与分发步骤见[发布文档](docs/RELEASE.md)。

也可以打开 `OpenBy.xcodeproj`，选择 `OpenByApp` scheme。工程定义维护在 `project.yml` 中，修改后通过 `xcodegen generate` 重新生成工程。

## 使用

1. 打开设置，添加文件类型或格式组。
2. 添加位置规则，选择文件夹与目标应用，并设置其他位置使用的应用。
3. 点击“启用自动打开”，按系统提示确认默认打开方式的修改。
4. 在 Finder 中打开文件，OpenBy 按规则转交给目标应用。

停用某个类型时，使用“停用并恢复原应用”。配置位于 `~/Library/Application Support/OpenBy/config.json`。

## 验证

```bash
./scripts/run-tests.sh test       # 自定义 Swift 测试运行器
./scripts/run-tests.sh bench      # 路由性能基准
./scripts/check-window-layout.sh  # 原生窗口布局检查，需要 macOS 图形会话
```

本项目使用可执行测试运行器，测试入口为上述脚本。

## 目录

```text
Sources/
  OpenBy/               核心逻辑、系统接口、存储与 AppKit 界面
  OpenByApp/            应用入口
  OpenByTestRunner/     单元测试与测试运行器
Tests/WindowLayout/     窗口布局回归检查
Benchmarks/             性能基准
Resources/              应用元数据与正式图标
scripts/                构建、测试和图标生成脚本
docs/                   发布步骤、技术设计与优化记录
design/                 UI 概念稿、图标源文件与设计记录
OpenBy.xcodeproj/       可直接打开的共享 Xcode 工程
Package.swift           Swift Package Manager 定义
project.yml             XcodeGen 工程定义
```

`.build/`、`.build-xcode/`、`dist/` 和 Xcode 个人配置已忽略；发布 ZIP 可作为 GitHub Release 附件上传。

## 开发文档

- [构建、验证与发布](docs/RELEASE.md)
- [最初的技术设计](docs/开发文档.md)（历史方案，部分内容与当前实现不同）
- [性能诊断与优化计划](docs/性能诊断与优化计划.md)
- [UI 设计记录](design/UI美化方案.md)
- [图标源文件与生成方法](design/icons/README.md)
