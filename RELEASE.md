# OpenBy 发布清单

面向当前环境（macOS 26.5 Apple Silicon，仅 Command Line Tools + Swift 6.3.2，无完整 Xcode）的构建、验证与分发步骤。

## 1. 前置条件

- macOS 14 及以上（`Package.swift` 声明 `platforms: [.macOS(.v14)]`）。
- 安装 Command Line Tools：`xcode-select --install`（含 Swift 6.3+ 编译器与 SDK）。
- 本机无需 Xcode、无需 `xcodebuild`。

## 2. 本地构建

```bash
./scripts/build-app.sh            # 当前架构（arm64）
./scripts/build-app.sh --universal  # arm64 + x86_64 通用版（Rosetta 用户）
```

脚本流程：`swift build -c release` → 组装 `dist/OpenBy.app`（Info.plist + 二进制，包内可执行文件名保持 `OpenBy`）→ `plutil` 校验 → **ad-hoc 签名**（arm64 未签名不可运行）→ `lsregister -f` 注册（**漏掉则 Finder 不路由文件给 OpenBy**）。

产物：`dist/OpenBy.app`。

## 3. 自动验证

```bash
./scripts/run-tests.sh test     # 56 个单元测试（自定义 CLI 运行器，无 XCTest 依赖）
./scripts/run-tests.sh bench    # 10k 条规则路由基准
```

当前基准：1,000 条规则单文件路由 ≈ 0.066 ms；10,000 条 ≈ 0.51 ms（均 < 1 ms）。

## 4. 手动 E2E（GUI 接管部分需人工确认）

设置窗口三页：**文件类型 → 规则 → 诊断**。

1. **接管**：文件类型页添加 `pdf` → 选中该行点「设为默认」。macOS 26.4+ 可能弹系统确认框，点允许。状态列出现 ✓。
   - 命令核对：`mdls -name kMDItemContentType` 无效；用 `osascript` 或「显示简介」查看「打开方式」应为 OpenBy。
2. **分流**：建一个规则文件夹（如 `~/Documents/文献/`），规则页「添加规则」填文件夹、勾「包含所有子文件」、选目标应用（如 PDF Expert）。
3. **验证转发**：规则文件夹内放一个 PDF，文件夹外放一个 PDF，双击（或 `open`）两个文件，确认分别用目标应用和回退应用打开。
4. **试测**：规则页「测试文件…」选任意文件，可预览路由决策而不真正打开。
5. **停止接管**：文件类型页选中行点「停止接管」，确认「打开方式」恢复为接管前的应用。
   - 恢复逻辑**尊重用户手动选择**：若接管后用户已手动改成别的应用，OpenBy 不会越权覆盖。

自动化已覆盖的等价验证（本仓库开发期实测通过）：

| 用例 | 结果 |
|---|---|
| `open -a OpenBy.app 规则内.pdf` | 目标应用打开 |
| `open -a OpenBy.app 规则外.pdf` | 回退应用打开 |
| OpenBy 设为默认后 `open 规则外.pdf`（LS 直接分发） | 回退应用打开 |
| OpenBy 设为默认后 `open 规则内.pdf`（LS 直接分发） | 目标应用打开 |
| 混合批次（规则内+外各一）一次打开 | 两个应用各收到文件 |
| 接管：NSWorkspace/LS C API 设置默认并轮询验证 | 生效（0.5s 内） |
| 恢复：仅当当前默认仍是 OpenBy 时恢复 | 恢复成功，不越权 |
| 转发完成后进程 | 自动退出（exit 0） |

## 5. 发布（需要 Apple Developer ID 时）

> 目前 `build-app.sh` 使用 ad-hoc 签名（`codesign -s -`），仅适合本机/内部分发，无法通过 Gatekeeper 的公证校验。

有 Developer ID 后，正式发布步骤：

1. 用 Developer ID Application 证书签名并开启 Hardened Runtime：
   ```bash
   codesign --force --options runtime \
     --sign "Developer ID Application: 你的名字 (TEAMID)" \
     dist/OpenBy.app
   codesign --verify --strict --verbose=2 dist/OpenBy.app
   ```
2. 公证（Notarization）：
   ```bash
   ditto -c -k --keepParent dist/OpenBy.app dist/OpenBy.zip
   xcrun notarytool submit dist/OpenBy.zip --keychain-profile "OpenBy" --wait
   xcrun stapler staple dist/OpenBy.app
   spctl -a -vv dist/OpenBy.app   # 应输出 accepted
   ```
3. 制作 DMG（可选）：
   ```bash
   hdiutil create -volname OpenBy -srcfolder dist/OpenBy.app -ov -format UDZO dist/OpenBy.dmg
   ```
4. 发布前建议加一页「首次运行提示」：告知用户 OpenBy 会接管所选文件类型的默认打开方式，并给出停止接管的路径。

## 6. 隐私与已知限制（首版固定语义）

- 无网络、无遥测、无路径历史日志；错误信息中的用户目录缩略为 `~`（见 `OpenRequestCoordinator.redacted`）。
- 路径匹配为**字面路径** + 大小写不敏感 + NFC 规范化，**不解析符号链接**（见 `PathMatcher`）。
- 首版不含：URL/浏览器路由、脚本/正则、云同步、常驻菜单栏、文件内容识别、App Sandbox。
- 接管验证可能被系统确认框拦下：completion 后追加最多 ~3s 轮询重读（`AssociationService`），若仍失败请重试并在系统设置中确认。
