# OmniBar

> 轻量 macOS 菜单栏工具，管理本地的 Omniroute AI 网关，实时显示 Token 开销、服务状态、Provider 健康度，支持一键切换路由策略。

## 功能特性

- **菜单栏动态图标**：状态圆点（绿/红/黄）+ Token 开销文本（`$0.42` 或 `12.5K tok`）
- **右键菜单**：启动 / 停止 / 重启 / 打开 Dashboard / 偏好设置 / 退出
- **Popover 主面板**：四区块布局
  - 状态卡片（运行状态 / 运行时长 / 端口 / 版本号）
  - Provider 健康列表（✓ 健康 / ⏳ 冷却 / 🔒 锁定 / ✗ 离线）
  - Combo 路由策略选择器
  - 用量速览（今日 Token / 本月预算 / 预估节省）
- **偏好设置**：开机自启、菜单栏显示开关、端口、API Key、二进制路径、Dashboard URL、关于
- **全生命周期托管**：启动 OmniBar 自动拉起 Omniroute、崩溃自动重启（带重试上限）、退出时自动停止，均可在偏好设置中开关
- **Provider 操作**：在 Provider 详情卡片中测试连接、启用/停用、调整优先级、删除（二次确认）
- **版本更新**：自动检测 omniroute 新版本，菜单栏版本胶囊高亮提示，一键 `npm install -g omniroute@latest` 更新
- **开机自启**：基于 Service Management (`SMAppService.mainApp`)，回退到登录项脚本
- **优雅降级**：Omniroute 未运行时显示「服务未启动」，不崩溃
- **无滚动条 UI**：所有页面（Popover 列表 / 详情大卡片 / 设置页）统一隐藏滚动条，并强制 overlay 滚动条风格 + 关闭自动 content insets，确保隐藏后内容占满全宽、不会整体偏左

## 技术栈

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

## 构建

```bash
cd OmniBar
xcodebuild -project OmniBar.xcodeproj -scheme OmniBar -configuration Release -destination 'platform=macOS' build
```

产物位于 `~/Library/Developer/Xcode/DerivedData/OmniBar-*/Build/Products/Release/OmniBar.app`。

## 运行

直接在 Xcode 中按 ⌘R 运行，或双击编译产物 `OmniBar.app`。应用以 accessory 模式启动（不显示在 Dock 中），仅出现在菜单栏。

## 数据流

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

字段命名兼容 snake_case（`quota_remaining`、`is_active`、`today_tokens` 等），缺失字段会回退默认值，避免崩溃。

## 许可

MIT
