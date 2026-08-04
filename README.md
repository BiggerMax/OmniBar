# OmniBar — Omniroute macOS Menu Bar Manager

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![License](https://img.shields.io/badge/License-MIT-green)

**轻量级 macOS 菜单栏工具，智能管理你的 Omniroute AI 网关。**

OmniBar 是一个专为 AI 开发者设计的 macOS 菜单栏应用，帮助你实时监控和管理本地的 Omniroute AI 网关服务。通过直观的菜单栏图标和弹出面板，你可以随时掌握 Token 开销、服务状态和 Provider 健康度，无需打开浏览器或终端。

## ✨ 核心特性

### 🎯 实时监控
- **菜单栏动态图标**：状态圆点（🟢 运行中 / 🔴 错误 / 🟡 未知 / ⚪ 已停止）+ Token 开销文本（`$0.42` 或 `12.5K tok`）
- **一键启动/停止**：从菜单栏直接控制 Omniroute 服务
- **实时数据更新**：每 10-60 秒自动刷新 Provider、Combo 和用量数据

### 📊 Popover 主面板
- **状态卡片**：运行状态、运行时长、端口、版本号一目了然
- **Provider 健康列表**：直观显示所有 Provider 状态（✓ 健康 / ⏳ 冷却 / 🔒 锁定 / ✗ 离线）
- **Combo 路由策略选择器**：快速切换不同的路由策略（coding / cheap / fast 等）
- **用量速览**：今日 Token 消耗、本月预算、预估节省，配以迷你进度条

### ⚙️ 偏好设置
- **通用设置**：开机自启开关、菜单栏显示 Token 开关
- **连接配置**：Omniroute 端口（默认 20128）、API Key
- **高级选项**：Omniroute 二进制路径、Dashboard URL

### 🚀 全生命周期管理
- **自动拉起服务**：启动 OmniBar 自动启动 Omniroute（可配置）
- **崩溃自动重启**：服务异常退出时自动重启（带重试上限）
- **优雅退出**：退出时自动停止 Omniroute（可配置）
- **开机自启**：基于 Service Management，支持登录项回退

### 🎨 现代化 UI
- **原生 SwiftUI 界面**：流畅的动画和交互体验
- **无滚动条设计**：所有页面统一隐藏滚动条，界面更清爽
- **毛玻璃效果**：Popover 面板采用控制中心同款毛玻璃材质
- **深浅色模式适配**：自动跟随系统主题

## 📸 功能预览

### 菜单栏图标
```
🟢 [◁▷] 12.5K tok    ← 运行中，显示 Token 用量
🔴 [◁▷] $0.42         ← 运行中，显示费用
⚪ [◁▷]              ← 服务已停止
```

### Popover 面板布局
```
┌─────────────────────────────┐
│  ● 运行中  2h 15m  20128  v1.5  │  ← 状态卡片
├─────────────────────────────┤
│ ✓ Provider A    12ms       │
│ ⏳ Provider B    冷却中     │  ← Provider 列表
│ ✓ Provider C    8ms        │
├─────────────────────────────┤
│ Combo: coding ▼            │  ← 路由策略选择
├─────────────────────────────┤
│ 今日: 12.5K / 100K tok     │
│ ████████░░  预算剩余 87%    │  ← 用量速览
└─────────────────────────────┘
```

## 🛠️ 技术栈

- SwiftUI + AppKit (`NSStatusItem`)
- Network.framework（端口连通性检测）
- Service Management（开机自启）
- 最低 macOS 14.0 (Sonoma)
- 纯原生无第三方依赖
- `NSScrollView` 内省：通过 `NSViewRepresentable` 遍历窗口子树，强制隐藏滚动条（`DetailCards.swift` 中的 `introspectScrollView` + `NSScrollView.omnibarHideScrollbars`）

## 项目结构

```
OmniBar/
├── OmniBar.xcodeproj
└── OmniBar/
    ├── App/
    │   ├── OmniBarApp.swift          # SwiftUI @main 入口
    │   └── AppDelegate.swift         # NSStatusItem 生命周期管理
    ├── Models/
    │   ├── ServiceStatus.swift       # 状态枚举与展示
    │   ├── Provider.swift            # GET /api/providers
    │   ├── Combo.swift               # GET /api/combos
    │   ├── UsageStats.swift          # 用量聚合
    │   └── AppSettings.swift         # @AppStorage 持久化
    ├── Services/
    │   ├── OmnirouteService.swift     # 进程管理 + 主观察者
    │   ├── OmnirouteAPIClient.swift   # REST API 客户端
    │   ├── StatusItemManager.swift    # 菜单栏 / Popover / 右键菜单
    │   └── LaunchAtLogin.swift        # 开机自启
    ├── Views/
    │   ├── PopoverPanel.swift         # 主面板
    │   ├── Components/
    │   │   ├── StatusCard.swift
    │   │   ├── ProviderList.swift
    │   │   ├── ComboSelector.swift
    │   │   └── UsageSummary.swift
    │   └── Settings/
    │       ├── SettingsView.swift
    │       ├── GeneralSettings.swift
    │       ├── ConnectionSettings.swift
    │       └── AboutSettings.swift
    └── Resources/
        ├── Info.plist
        ├── OmniBar.entitlements
        └── Assets.xcassets
```

## 📦 安装

### 从源码构建

**环境要求**：
- macOS 14.0 (Sonoma) 或更高版本
- Xcode 15.0 或更高版本
- Swift 5.0+

**构建步骤**：
```bash
# 1. 克隆仓库
git clone https://github.com/BiggerMax/OmniBar.git
cd OmniBar

# 2. 打开项目
open OmniBar.xcodeproj

# 3. 在 Xcode 中按 Cmd + R 构建运行
```

**或使用命令行构建**：
```bash
cd OmniBar
xcodebuild -project OmniBar.xcodeproj -scheme OmniBar -configuration Release build
```

构建产物位于：
```
~/Library/Developer/Xcode/DerivedData/OmniBar-*/Build/Products/Release/OmniBar.app
```

### 安装到应用程序文件夹

将构建好的 `OmniBar.app` 拖到 `/Applications` 文件夹即可。

## 🚀 快速开始

1. **首次启动**：应用会自动检测 Omniroute 服务状态
2. **配置连接**：点击菜单栏图标 → 偏好设置 → 连接设置
3. **启动服务**：右键点击菜单栏图标 → 启动 Omniroute
4. **查看状态**：左键点击菜单栏图标查看详细信息

## 📖 使用指南

### 菜单栏操作

- **左键点击**：打开 Popover 主面板
- **右键点击**：显示操作菜单
  - 启动 / 停止 / 重启 Omniroute
  - 打开 Dashboard
  - 打开偏好设置
  - 退出应用

### 偏好设置

#### 通用
- ✅ 开机自启：登录 macOS 时自动启动
- ✅ 菜单栏显示 Token：在图标旁显示用量信息

#### 连接
- **端口**：Omniroute 监听端口（默认 20128）
- **API Key**：可选，用于访问受保护的 API 端点

1. 应用启动 → 读取 `AppSettings` → 通过 `NWConnection` 检查端口连通性
2. 服务运行 → 每 10-60s 轮询 `localhost:{port}` API
3. 获取 Provider / Combo / Usage → 更新 `@Published` → SwiftUI 自动刷新
4. 菜单栏 Token 文本每秒更新
5. 用户操作（启动 / 停止 / 切换 Combo）→ `Process` / `POST /api/combos/activate` → 刷新状态

## Omniroute API 约定

| Endpoint                       | Method | 描述                  |
| ------------------------------ | ------ | --------------------- |
| `/api/providers`               | GET    | Provider 列表与健康度 |
| `/api/providers/{id}`          | PATCH  | 启用/停用、调整优先级 |
| `/api/providers/{id}`          | DELETE | 删除连接            |
| `/api/providers/{id}/test`     | POST   | 重新测试连接健康度  |
| `/api/system/version`          | GET    | 当前/最新版本与可更新状态 |
| `/api/combos`                  | GET    | Combo 路由策略列表    |
| `/api/combos/activate`         | POST   | 切换当前 Combo        |
| `/api/usage`                   | GET    | 用量统计              |
| `/api/version`                 | GET    | 服务版本              |

字段命名兼容 snake_case（`quota_remaining`、`is_active`、`today_tokens` 等），缺失字段会自动回退到默认值，确保稳定性。

## 🤝 贡献

欢迎贡献！请遵循以下步骤：

1. **Fork 本仓库**
2. **创建功能分支**：`git checkout -b feature/AmazingFeature`
3. **提交更改**：`git commit -m 'Add some AmazingFeature'`
4. **推送到分支**：`git push origin feature/AmazingFeature`
5. **开启 Pull Request**

### 开发规范

- 遵循 Swift API Design Guidelines
- 保持代码简洁，添加必要的注释
- 确保在 macOS 14.0+ 上正常运行
- 提交信息使用清晰的描述

## 📜 更新日志

### v1.5
- **背景跟随系统深浅色**：移除强制深色外观，Popover 面板与设置窗口随系统主题自动在浅色霜感与深色玻璃间切换
- **全新交互 / 动效系统**：统一弹簧与缓动时钟，卡片/行悬停上浮辉光、按压缩放、路由切换弹性过渡、数字滚动与进度条平滑动画
- **隧道开关状态颜色**：运行时绿色、切换中黄色、待开启时强调蓝
- **PORT / PID / UPTIME 居中**：指标水平 + 垂直居中显示
- **减少页面跳转回弹**：路由过渡改用高阻尼、近无回弹的柔和动画
- **Provider / Combo 详情**：悬停箭头滑动高亮，进入动效更顺滑

### v1.0
- 首个正式版本：菜单栏监控、一键启停、Provider / Combo 管理、用量速览、暗色玻璃化 UI



本项目采用 **MIT 协议**开源。详见 [LICENSE](LICENSE) 文件。

## 🙏 致谢

- 基于 [Omniroute](https://github.com/omniroute/omniroute) 项目设计
- UI 灵感来自 macOS 控制中心
- 图标设计遵循 Apple Human Interface Guidelines

## 📧 联系方式

- **Issues**：[GitHub Issues](https://github.com/BiggerMax/OmniBar/issues)
- **Discussions**：[GitHub Discussions](https://github.com/BiggerMax/OmniBar/discussions)

## 🌟 支持项目

如果这个项目对你有帮助，请给我们一个 ⭐️ Star！

---

**Made with ❤️ for the AI community**
