# 广海课表云 iOS 版（GdouSchedule iOS）

「广海课表云」的 iOS 版本，界面与功能来自同项目的网页版 [gdou-schedule-web](https://github.com/leolee80888/gdou-schedule-web)，用 `WKWebView` 把单文件课表包成原生 App：

- 内置空白课表页面（`Resources/Web/index.html`），首次打开点「导入」选课表 PDF 即可
- 课表 PDF **在手机本地解析**（`DecompressionStream`），不联网、不上传
- 数据存 `localStorage`（自定义 `gdou://` scheme 提供稳定 origin，杀进程不丢）
- 原生补齐了网页版在 iOS 上缺的能力：文件选择、`confirm` 弹窗、导出 JSON 的分享面板、高德导航跳转
- 纯源码项目，不提交 `.xcodeproj`（用 XcodeGen 生成），也不提交 IPA

## 构建

没有 Mac 也能出 IPA：仓库带 GitHub Actions 工作流（`.github/workflows/build-ipa.yml`），push 到 `main` 或手动 `workflow_dispatch` 就会在 `macos-14` 上编出**未签名 IPA**，在 Actions 页面的 Artifacts 里下载 `GdouSchedule-unsigned-ipa`。

有 Mac 本地构建：

```bash
brew install xcodegen
xcodegen generate
open GdouSchedule.xcodeproj   # 用 Xcode 选自己的开发者账号 Run / Archive
```

命令行出未签名包（与 CI 一致）：

```bash
xcodebuild -project GdouSchedule.xcodeproj -scheme GdouSchedule \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath build/GdouSchedule.xcarchive archive \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

mkdir -p Payload && cp -R build/GdouSchedule.xcarchive/Products/Applications/*.app Payload/
zip -qry GdouSchedule-unsigned.ipa Payload
```

## 安装到 iPhone

CI 产物是**未签名 IPA**，装到手机上必须自己签名（二选一）：

1. **Sideloadly / AltStore（Windows 可用，免费 Apple ID）**：连上 iPhone，把 IPA 拖进 Sideloadly，填 Apple ID，签名安装。免费账号签名 7 天过期，到期重签名一次。
2. **自己的开发者账号**：Xcode 打开项目，Bundle Identifier 改成 `com.<你的名字>.gdouschedule`，选 Team 后 Archive → Distribute → Ad Hoc / Development 导出签名 IPA。

> 首次打开若提示「未受信任的开发者」，去「设置 → 通用 → VPN 与设备管理」信任对应证书。

## 项目结构

```
project.yml                       XcodeGen 工程描述（Bundle ID / 版本 / Info.plist）
Sources/AppDelegate.swift         App 入口
Sources/WebViewController.swift   WKWebView 容器：文件选择、弹窗、下载分享、外链跳转
Sources/SchemeHandler.swift       gdou:// 自定义 scheme，把内置网页按 HTTP 方式喂给 WebView
Resources/Web/index.html          课表页面（与网页版空白版同源）
Resources/Assets.xcassets         AppIcon（1024，海蓝底 + 「课」）
tools/make_icon.py                图标生成脚本（Pillow）
```

## 与网页版的差异

| 能力 | 网页版 | iOS 版 |
| --- | --- | --- |
| 打开方式 | 双击 HTML | 桌面图标 |
| 选 PDF | `<input type="file">` | 原生文档选择器（`UIDocumentPickerViewController`） |
| `confirm` 确认框 | 浏览器原生 | 原生 `UIAlertController`（否则 iOS 上恒为 false） |
| 导出 JSON | 浏览器下载 | `WKDownload` + 系统分享面板存到「文件」 |
| 高德导航 | 新标签页 | 跳转高德 App / Safari |
| 数据持久化 | localStorage | localStorage（`gdou://app` origin） |

## 环境要求

- iOS 17.0+（`DecompressionStream` 需要 iOS 16.4 以上，保守取 17.0）
- 构建端：macOS + Xcode 15 / 16（CI 用 `macos-14`）

## 许可证

[MIT](LICENSE)
