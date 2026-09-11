# OpenBy 发布清单

以下命令均在项目根目录执行。

当前发布版本为 **1.1.0**，构建号 **3**。

生成 DMG：`./scripts/build-dmg.sh`；通用版本：`./scripts/build-dmg.sh --universal`。
脚本重新构建应用，生成包含 Applications 快捷方式和安装说明的压缩只读镜像，校验镜像并输出 SHA-256 文件；不会注册应用或修改默认打开方式。

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

脚本流程：`swift build -c release` → 在本地临时目录组装并签名，输出 `dist/OpenBy.app` 和发布 ZIP（Info.plist + 二进制，包内可执行文件名保持 `OpenBy`）→ `plutil` 校验 → **ad-hoc 签名**（arm64 未签名不可运行）→ `lsregister -f` 注册（**漏掉则 Finder 不路由文件给 OpenBy**）。

产物：`dist/OpenBy.app`。

## 3. 自动验证

```bash
./scripts/run-tests.sh test     # 单元测试（自定义 CLI 运行器，无 XCTest 依赖）
./scripts/run-tests.sh bench    # 10k 条规则路由基准
```

当前基准：1,000 条规则单文件路由 ≈ 0.066 ms；10,000 条 ≈ 0.51 ms（均 < 1 ms）。

## 4. 手动 E2E（GUI 接管部分需人工确认）

设置窗口采用“左侧文件类型 + 右侧完整设置”的单窗口布局。

1. **添加类型或格式组**：点击「添加文件类型…」，选择图片、视频、音频或文档预设，也可直接输入后缀或添加示例文件。修改组名和后缀列表后点击「添加」；后缀支持逗号、空格分隔。格式冲突应提示修改，不覆盖已有组。
2. **分流**：选中左侧 `.PDF 文件` → 点击「添加位置规则…」→ 选择规则文件夹（如 `~/Documents/文献/`）和目标应用（如 PDF Expert）。
3. **启用**：点击「启用自动打开」。macOS 26.4+ 可能弹系统确认框，点允许；状态应变为绿色“已启用自动打开”。
   - 命令核对：`mdls -name kMDItemContentType` 无效；用 `osascript` 或「显示简介」查看「打开方式」应为 OpenBy。
4. **验证转发**：规则文件夹内放一个 PDF，文件夹外放一个 PDF，双击（或 `open`）两个文件，确认分别用目标应用和“其他位置”应用打开。
5. **停用**：点击「停用并恢复原应用」，确认「打开方式」恢复为启用前的应用。
   - 恢复逻辑**尊重用户手动选择**：若接管后用户已手动改成别的应用，OpenBy 不会越权覆盖。

格式组补充检查：选择图片预设，删掉 `png` 并加入 `avif` 后保存；确认左侧只有一个组，组内格式共用位置规则和“其他位置”应用。通过「更多 → 编辑格式组…」可再次增删后缀。启用只成功一部分时应显示「部分启用」，支持「启用剩余格式」和整组停用；移除已启用的格式前须恢复其原应用。`jpg/jpeg` 等别名可能共用 macOS 系统关联，但 OpenBy 路由只匹配组中明确列出的后缀。

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
| 转发完成后进程（1.1） | 后台常驻，同 PID 接收后续文件；菜单栏可主动退出 |

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
- 首版不含：URL/浏览器路由、脚本/正则、云同步、文件内容识别、App Sandbox。
- 接管验证可能被系统确认框拦下：completion 后追加最多 ~3s 轮询重读（`AssociationService`），若仍失败请重试并在系统设置中确认。


## 1.1 响应速度优化

- 后台常驻，不占 Dock；关闭设置窗口仍能转发文件，菜单栏提供设置、退出和登录时启动。
- 所有文件类型共用后台路由队列。不同目标独立执行，同目标有序；30 秒超时释放状态，迟到回调不会影响新请求。
- 类型与应用定位采用有界缓存，配置更改立即更新后续请求；在途请求保留原 fallback。
- 应用后备路径必须与 bundle ID 匹配。打开失败会使目标缓存失效，下一次请求重新定位；超时不会自动重复打开。
- 构建：`./scripts/build-app.sh`；只打包不注册：`./scripts/build-app.sh --no-register`。
- 回归：`swift run -c release OpenByTestRunner`。
- 性能：`swift run -c release OpenByBenchmark --rules 1000 --iterations 2000 --pipeline`。该模式使用真实应用定位和假打开，绝不把结果当成文档已显示。

升级时先退出旧 OpenBy，再启动新版 `dist/OpenBy.app`。脚本同时生成 `dist/OpenBy-1.1.zip`，压缩包排除 Finder 扩展属性，适合复制到稳定的本地应用目录后使用。登录项由菜单栏设置启用，构建和测试不会自动注册登录项。

发布人工检查：通过 Finder 打开配置范围内与范围外的测试文件；间隔 10 秒以上重复，确认 PID 不变；关闭设置后仍能路由；在系统允许后单独验证实际注销/登录启动。
