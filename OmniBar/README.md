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
- **开机自启**：基于 Service Management (`SMAppService.mainApp`)，回退到登录项脚本
- **优雅降级**：Omniroute 未运行时显示「服务未启动」，不崩溃

## 技术栈

- SwiftUI + AppKit (`NSStatusItem`)
- Network.framework（端口连通性检测）
- Service Management（开机自启）
- 最低 macOS 14.0 (Sonoma)
- 纯原生无第三方依赖

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
| `/api/combos`                  | GET    | Combo 路由策略列表    |
| `/api/combos/activate`         | POST   | 切换当前 Combo        |
| `/api/usage`                   | GET    | 用量统计              |
| `/api/version`                 | GET    | 服务版本              |

字段命名兼容 snake_case（`quota_remaining`、`is_active`、`today_tokens` 等），缺失字段会回退默认值，避免崩溃。

## 许可

MIT
