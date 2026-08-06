# OmniBar Freebuff 反代接入技术设计文档

> 状态：**规划中，待审阅**
> 目标版本：v3.0
> 调研对象：XxxXTeam/freebuff2api（FastAPI + httpx，AGPL-3.0）、Codebuff / Freebuff 上游 API、OmniBar 现有进程管理与 AI 接入基建
> 流程约定：**本文档审阅通过后再进入编码**。第 10 节「审阅决策点」需要拍板后才能开始对应编码。

---

## 0. TL;DR

- OmniBar **不实现反代**，而是**托管 freebuff2api 这个独立进程**（方案 A），把它当作"第二个网关"接入现有 AI 工作流：进程管理平移到 `FreebuffService`，Token 获取做成原生 OAuth 流程，AI 接入复用 `LiveConfig` 写器。
- 排除方案 B（Swift 原生移植 ~2000 行核心逻辑，上游 API 是移动靶心，必滞后）与方案 C（无 session 生命周期/身份注入/agent-run 记账的朴素反代必挂 403）。
- 运行时依赖 **`uv` + Python ≥3.13**（pyproject 硬性要求，`uv run` 可自动装 Python）；首启引导流程是本设计的最大不确定性。
- 关键权衡：Freebuff 与 Omniroute 对 Claude Code / Codex 是**互斥占用同一份 live 文件**，需做互斥与接管检测；是否要"链到 Omniroute 上游"取决于 Omniroute 添加 provider 的途径（决策点 10.3）。
- ⚠️ 许可：freebuff2api 是 **AGPL-3.0**，随 App 分发需合规（见 9.2）。

---

## 1. 背景与目标

### 1.1 背景

OmniBar 目前管理单个 Omniroute 网关（启停/监控/AI 接入）。freebuff2api 把 Codebuff Freebuff 的免费模型包装成 OpenAI 兼容 API（`/v1/models` + `/v1/chat/completions`），其价值全部集中在**绕过上游客户端校验的状态机**：session 生命周期、Buffy 身份提示注入、agent-run 记账、广告/streak 刷免费额度、多账号并发分配。

### 1.2 目标

在 OmniBar 内提供 **Freebuff 免费模型源**的完整闭环：

1. **进程托管**：一键启动/停止/重启 freebuff2api，状态进菜单栏与 Popover，崩溃自动重启。
2. **Token 获取**：原生 UI 完成 Codebuff OAuth 授权轮询，支持多账号（逗号分隔/列表管理）+ 在线验证。
3. **AI 接入**：新增「Freebuff 直连」卡片，一键把 Claude Code / Codex 指到 `http://localhost:{port}/v1`（复用 LiveConfig 写器、备份回滚、接管检测）。
4. **零回归**：现有 Omniroute 接入与全部测试保持全绿。

### 1.3 非目标

- 不重写反代逻辑；Swift 只做进程管理与配置编排。
- 不做基于 freebuff 的模型路由聚合（Combo 等）——那是 Omniroute 的活（见决策点 10.3 的"链上游"选项）。

---

## 2. freebuff2api 逆向解析（接入方视角）

### 2.1 本地 API（OmniBar 消费侧）

| Endpoint | 方法 | 用途 |
|---|---|---|
| `/healthz` | GET | 存活探针（可选本地 Bearer） |
| `/v1/models` | GET | 模型目录（按账号 `rateLimitsByModel` 过滤，含 always-available 基线模型） |
| `/v1/chat/completions` | POST | OpenAI 兼容聊天（流式/非流式） |

- 鉴权：`FREEBUFF_API_KEY` 为空 → 无鉴权；非空 → 需 `Authorization: Bearer <FREEBUFF_API_KEY>`。

### 2.2 上游 API（Token/反代实际交互）

| Endpoint | 方法 | 说明 |
|---|---|---|
| `/api/auth/cli/code` | POST | body `{fingerprintId}` → `{loginUrl, fingerprintHash, expiresAt}` |
| `/api/auth/cli/status?fingerprintId&fingerprintHash&expiresAt` | GET | 轮询；`401`=待授权，成功返回 `{user:{authToken,...}}` |
| `/api/v1/freebuff/session` | GET | 当前 session + `rateLimitsByModel`（验证 Token 也用它） |
| `/api/v1/freebuff/session` | POST/DELETE | 创建/删除 session（`x-freebuff-model` / `x-freebuff-instance-id` 头） |
| `/api/v1/ads`、`/api/v1/ads/impression`、`zeroclick.dev/api/v2/impressions` | POST | 广告上报，刷免费 session 存活 |
| `/api/v1/agent-runs`(+`/steps`) | POST | START/STEP/FINISH 伪造 run 链 |
| `/api/v1/chat/completions` | POST | 真正的流式聊天（`ai-sdk` UA） |

关键对抗点（反代已内置，Swift 侧无需关心）：
- 身份提示：system 消息必须以 Buffy 身份开头，否则 403 `free_mode_cli_required`（`openai_compat.py:47`）。
- 区域限制：非 US 出口可能 409 `session_model_mismatch`（需走 US 代理，`FREEBUFF_PROXY_URL` 支持 http/socks5/socks5h）。
- session 单模型互斥：切模型需先 DELETE 旧 session，多账号用于并发隔离（`FREEBUFF_TOKEN` 逗号分隔）。

### 2.3 运行形态

```toml
[project]           # pyproject.toml
requires-python = ">=3.13"
dependencies = fastapi / httpx[socks] / python-dotenv / uvicorn[standard]
[project.scripts]
freebuff2api = "main:main"   # uvicorn.run("freebuff2api.app:app")
```

- 单进程 uvicorn，无 supervisor 链 → 进程管理比 omniroute 简单（无 launchd 冲突问题）。
- 配置全走环境变量（`config.py` 读 `.env` 与 env），非常适合由 OmniBar 注入。

---

## 3. 总体架构

```
┌────────────────────────── OmniBar (SwiftUI, 非沙盒) ──────────────────────────┐
│                                                                                │
│  Settings @AppStorage                                                          │
│   freebuffEnabled / port / tokens[] / localKey / proxy / autoStart / runtime   │
│                                                                                │
│  ┌──────────────┐   ┌─────────────────┐   ┌─────────────────────────────────┐ │
│  │FreebuffService│──▶│FreebuffAPIClient│   │FreebuffLinkManager              │ │
│  │ 进程托管/状态  │   │ /healthz /models │   │ 直连 AI 接入（互斥 + 接管检测） │ │
│  └──────┬───────┘   └─────────────────┘   └──────────────┬──────────────────┘ │
│         │ spawn 注入 env                                   │ 复用 LiveConfig    │
└─────────┼──────────────────────────────────────────────────┼─────────────────────┘
          ▼                                                   ▼
   freebuff2api 进程                           ~/.claude/settings.json
   (uv run --project <runtimeDir>)            ~/.codex/config.toml + auth.json
          │
          ▼ 上游 HTTPS
   www.codebuff.com / freebuff.com / zeroclick.dev
```

两种消费路径：
- **直连（v3.0 首发）**：Claude Code / Codex 直接指 `http://localhost:{port}/v1`，与 Omniroute 接入互斥。
- **链上游（可选，决策点 10.3）**：freebuff2api 作为 provider 挂进 Omniroute，由 Omniroute 统一路由、互不互斥。

---

## 4. 设置模型（AppSettings 扩展）

全部 `@AppStorage` + `didSet { notifyChange() }`（沿用现有防崩溃模式）：

| 键 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `freebuffEnabled` | Bool | false | 总开关（进程是否随启动托管） |
| `freebuffPort` | Int | 8000 | 本地监听端口 |
| `freebuffTokens` | String | "" | 逗号分隔多账号 Bearer Token |
| `freebuffLocalAPIKey` | String | "" | 本地鉴权 key（空=无鉴权） |
| `freebuffProxyEnabled` | Bool | false | 是否走代理访问上游 |
| `freebuffProxyURL` | String | "" | `http://127.0.0.1:7890` / `socks5h://...` |
| `freebuffAutoStartOnLaunch` | Bool | true | 启动 OmniBar 自动拉起 |
| `freebuffAutoRestartOnCrash` | Bool | true | 崩溃自动重启 |
| `freebuffRuntimeDir` | String | `~/Library/Application Support/OmniBar/freebuff2api/` | 反代源码目录 |
| `freebuffRunMode` | String | "uv" | `uv` / `venv`（运行时引导，见 6.4） |
| `linkFreebuff` | Bool | false | 直连 AI 接入开关 |
| `linkFreebuffClaudeModel` / `linkFreebuffCodexModel` | String | "" | 直连默认模型 |

`freebuffTokens` 提供 computed `tokensArray` / `setTokensArray` 供 UI 列表编辑，持久化为逗号串（与上游 `FREEBUFF_TOKEN` 语义一致）。

---

## 5. 新增/修改文件清单

### 新增

```
Services/
  FreebuffService.swift          # 进程托管（仿 OmnirouteService）
  FreebuffAPIClient.swift        # /healthz /v1/models + upstream 验证
  FreebuffTokenManager.swift     # OAuth 授权轮询
  FreebuffRuntime.swift          # 运行时引导（uv 探测/同步）
  FreebuffLinkManager.swift      # 直连 AI 接入编排（复用 LiveConfig + BackupManager）
Models/
  FreebuffModel.swift            # GET /v1/models 的模型目录模型
Views/
  Settings/FreebuffSettings.swift
  Components/FreebuffSection.swift   # 状态卡 + Token 管理 + 直连卡（复用 AIIntegrationSection 卡片样式）
```

### 修改

```
Models/AppSettings.swift                       # 4 节设置项
App/AppDelegate.swift                          # 实例化 FreebuffService / TokenManager / LinkManager
Views/Settings/SettingsView.swift              # 新增「Freebuff」侧栏项
Views/Components/AIIntegrationSection.swift    # 或在独立 FreebuffSection 中复用 TargetCard
Services/LiveConfig/CodexLiveConfig.swift      # provider 名参数化（"omniroute"→可注入 "freebuff"）
Services/ProviderLinkManager.swift             # 互斥钩子（启用 freebuff 直连时关掉对应 omniroute 开关）
```

---

## 6. 详细设计

### 6.1 FreebuffService（进程托管）

`@MainActor final class FreebuffService: ObservableObject`，公开面与 `OmnirouteService` 对齐（状态/pid/port/uptime + start/stop/restart + 崩溃自启）：

```swift
enum FreebuffServiceStatus: Equatable { case unknown, stopped, running, error }

final class FreebuffService: ObservableObject {
    @Published private(set) var status: FreebuffServiceStatus
    @Published private(set) var pid: Int?
    @Published private(set) var version: String     // GET /healthz 解析（可选）
    @Published private(set) var availableModels: [FreebuffModel]   // GET /v1/models
    @Published private(set) var lastErrorMessage: String?

    func start() async -> Bool
    func stop() async -> Bool
    func restart() async -> Bool
    func refreshStatus() async
}
```

实现要点（全部复用 `OmnirouteService` 已验证的代码模式）：
- **存活探测**：`NWConnection(host: "127.0.0.1", port: UInt16(freebuffPort), .tcp)` 2s 超时（`checkProcessAlive`）。
- **PID 定位**：`lsof -i TCP:<port> -sTCP:LISTEN -t`（`findPID`）。
- **启动命令**（`startInternal`）：
  ```
  uv run --project '<runtimeDir>' freebuff2api
  ```
  - 环境变量注入：见 6.3 env 表；`FREEBUFF_HOST=127.0.0.1`（仅本地，**不要** `0.0.0.0`）。
  - `PATH` 补齐 `/opt/homebrew/bin:/usr/local/bin`（uv 通常装这里）；丢弃 stdout/stderr 防管道阻塞。
  - 轮询端口就绪，最多 15s。
- **停止**：freebuff2api 是单进程，`findPID()` 后 SIGTERM → 3s 未退 SIGKILL（无 supervisor 链，比 omniroute 简单）。
- **崩溃自启**：`wasRunning + autoRestartOnCrash + retryLimit` 模式平移动。
- **首启引导**：`startInternal` 前调用 `FreebuffRuntime.ensure()`（见 6.4），失败给出可操作的错误提示。

### 6.2 FreebuffAPIClient

```swift
final class FreebuffAPIClient {
    init(port: Int, localKey: String?)                       // baseURL = http://127.0.0.1:port
    func fetchModels() async throws -> [FreebuffModel]        // GET /v1/models
    func health() async throws -> Bool                        // GET /healthz
    // upstream 侧（Token 验证，不经过本地反代）
    static func verifyUpstreamToken(_ token: String) async -> (ok: Bool, info: String)
    static func requestAuthCode() async throws -> AuthCode    // POST /api/auth/cli/code
}
```

- `verifyUpstreamToken`：`GET https://www.codebuff.com/api/v1/freebuff/session`，`Authorization: Bearer <token>`，200/2xx 即有效（对齐 `tool/get_token.py:87`）。
- 超时、错误映射复用 `OmnirouteAPIClient` 的 `OmnirouteAPIError` 模式（`unauthorized / endpointUnavailable / network`）。

### 6.3 子进程环境变量注入

| 环境变量 | 来源 | 值 |
|---|---|---|
| `FREEBUFF_TOKEN` | settings.freebuffTokens | 逗号分隔原文 |
| `FREEBUFF_API_KEY` | settings.freebuffLocalAPIKey | 空则不注入 |
| `FREEBUFF_HOST` | 固定 | `127.0.0.1` |
| `FREEBUFF_PORT` | settings.freebuffPort | Int |
| `FREEBUFF_PROXY_ENABLED` / `FREEBUFF_PROXY_URL` | settings | 按 proxy 开关 |
| `FREEBUFF_DEBUG` | 固定 | `false`（用户需日志时再开） |
| `FREEBUFF_LOG_LEVEL` | 固定 | `INFO` |
| `FREEBUFF_LOG_COLOR` | 固定 | `false`（非 TTY） |
| `FREEBUFF_SESSION_ID` / `FREEBUFF_CLIENT_ID` | 留空 | 由上游自行生成 |

> 注意：freebuff2api `config.py` 也读 `.env`；子进程 cwd 若落在 runtimeDir 会读到用户手改的 `.env`。**启动命令显式 `--project` + 不设 cwd 到 runtimeDir，或设置前清空 `FREEBUFF_*` 冲突项**，保证 env 注入优先级（env > .env > default）。这是实现细节里的一个坑，编码时单独验证。

### 6.4 FreebuffRuntime（运行时引导）

目标：`uv run --project <dir> freebuff2api` 在首启时可用。分四步，每步失败给中文提示：

1. **源码就绪**：`runtimeDir` 存在且含 `pyproject.toml` → 通过。否则尝试：
   - 内置 Bundle：若打包时已内嵌（见决策点 10.1）则解压；
   - 否则 `git clone --depth 1 https://github.com/XxxXTeam/freebuff2api <runtimeDir>`。
2. **uv 探测**：`which -a uv`（补 PATH 后）。缺失 → 尝试 `brew install uv` 失败则提示用户安装并给出命令（决策点 10.2：是否自动装）。
3. **依赖同步**：`uv sync --project <runtimeDir>`（`uv run` 首启也会自动 sync，这里提前跑以便给出进度）。
   - `requires-python >=3.13`：`uv run` 会自动下载对应 Python，无需用户干预（uv 的卖点）。
4. **可执行校验**：`uv run --project <runtimeDir> freebuff2api --help` 退出码 0。

缓存/幂等：`ensure()` 加 `inProgress` 锁 + 结果缓存（同一次启动会话内不重复 clone/sync）；进程启动失败不破坏源码。

### 6.5 FreebuffTokenManager（OAuth 授权轮询）

对齐 `tool/get_token.py` / `tool/web`，纯 URLSession 实现：

```
用户点「登录授权」
 └─ POST https://www.codebuff.com/api/auth/cli/code
     body {"fingerprintId":"fb-<8B hex>"}
     头  User-Agent: Bun/1.3.11, Content-Type: application/json
     → {loginUrl, fingerprintHash, expiresAt}
 └─ NSWorkspace.shared.open(loginUrl)      # 浏览器完成 GitHub 授权
 └─ 轮询 GET /api/auth/cli/status?fingerprintId&fingerprintHash&expiresAt
     每 2s，最长 5min；HTTP 401 = 待授权继续，2xx 且 user.authToken 存在 = 成功
 └─ 验证：verifyUpstreamToken(authToken)
 └─ 写入 settings.freebuffTokens（追加/替换，UI 提供列表管理）
```

- 指纹 `fb-<secrets.token_hex(8)>` → Swift 用 `UUID` 派生 `Data.random(count:8).hexString`。
- UI 形态：设置页内嵌 Sheet，含「打开授权页」「等待中…（剩余 N 秒）」「成功，Token 已添加」三态；可取消。
- 轮询期间 app 最小化不受影响（URLSession 后台继续）；失败/超时有重试入口。

### 6.6 FreebuffLinkManager（直连 AI 接入）

复用现有 `ProviderLinkManager` 的安全层（`BackupManager` + 原子写 + 接管检测），但**独立实例**，避免改动已验证的 omniroute 路径：

```
final class FreebuffLinkManager: ObservableObject {
    // 与 ProviderLinkManager 同构：enable/disable/toggle/takeoverStatus/isExternallyModified
    var baseURL: String { "http://127.0.0.1:\(settings.freebuffPort)/v1" }
}
```

- **写 Claude Code**：`ClaudeCodeLiveConfig.enable(baseURL: freebuffBaseURL, apiKey: settings.freebuffLocalAPIKey, model: linkFreebuffClaudeModel)` —— 写器本身已参数化，无需改。
- **写 Codex**：`CodexLiveConfig.enable(homeURL:..., baseURL: freebuffBaseURL, model:..., apiKey: localKey)` + 用 `freebuffAPIClient.fetchModels()` 建 `omnibar-model-catalog.json`。
- **互斥规则**（决策点 10.4 细节）：Claude Code / Codex 的 live 文件同一时刻只能指一个网关。启用 freebuff 直连时，若对应 omniroute 开关（`linkClaudeCode`/`linkCodex`）已开 → 先关它（走其 disable 回滚）；反之亦然。UI 提示「已接管，原网关连接已断开」。
- **冲突检测**：复用 takeover 逻辑——`ANTHROPIC_BASE_URL` 指向非本网关/非本端口即提示第三方托管。

### 6.7 UI 设计

**设置页「Freebuff」分区**（仿 ConnectionSettings 卡片式）：
- 状态行：运行中/已停止/错误 + 端口 + PID + 启动/停止/重启按钮（复用 `StatusCard` 视觉）。
- Token 管理：多账号列表（增/删/验证/一键授权），每个 token 显示验证状态与邮箱（如上游返回）。
- 代理：开关 + URL 输入（`socks5h://` 提示）。
- 运行时：`runtimeDir` 只读展示 + 「重新同步」按钮（触发 `FreebuffRuntime.ensure(force: true)`）。
- 模型预览：`GET /v1/models` 列表（失败时显示健康/错误原因）。

**AI 接入新增「Freebuff 免费模型源」卡片**（与 Claude Code / Codex 卡并列）：
- 开关 → `linkFreebuff`；模型下拉 → freebuff 模型目录（provider 分组复用 `GroupedModelPicker`）。
- 关闭时显示与 omniroute 卡的互斥提示。

**Popover**：主面板加一行 Freebuff 状态（可选，v3.0 首版可在设置页内完成，Popover 只加状态圆点）。

---

## 7. 生命周期与关键时序

### 7.1 首次启用

```
用户开 freebuffEnabled
 ├─ FreebuffRuntime.ensure()          # clone(或解包) → 探 uv → uv sync → 校验
 ├─ FreebuffService.start()           # uv run --project <dir> freebuff2api
 │    └─ 注入 env → 轮询端口(15s) → status=.running
 └─ 若 linkFreebuff 已开 → FreebuffLinkManager.enable(...)
```

### 7.2 Token 授权

见 6.5 时序。成功后 `settings.freebuffTokens` 变化 → `FreebuffService` 若在运行则提示「Token 已更新，请重启服务生效」（freebuff2api 启动时读 env，**运行中改 token 需重启**——文档明确此限制，避免用户困惑）。

### 7.3 退出清理

`applicationShouldTerminate`：`freebuffService.shutdown()`（按 `freebuffAutoStopOnQuit`，默认 true，与 omniroute 的 `stopOnQuit` 对齐）。

---

## 8. 错误处理与边界

| 场景 | 表现 |
|---|---|
| uv 未安装 | 引导提示安装命令，`start()` 返回 false + 中文文案 |
| `uv sync` 失败（网络/Python 下载） | 提示重试，不破坏已有源码；支持离线时手动 `uv sync` |
| 端口占用 | 提示占用方，提供改端口 |
| Token 无效/过期 | 模型预览与请求均 4xx → UI 红色「Token 失效」+ 一键重新授权 |
| 上游区域限制（409 session_model_mismatch） | 提示「需 US 出口，请配置代理」 |
| 运行中改 token/port | 提示重启生效（观测 `freebuffTokens`/`freebuffPort` 变化） |
| live 文件被外部改写 | 复用 `isExternallyModified` + 一键恢复 |
| 崩溃循环 | `consecutiveCrashCount` + `restartRetryLimit`（默认 3） |

---

## 9. 风险与合规

### 9.1 上游稳定性
- Freebuff/Codebuff 为闭源逆向（HAR 逆向、obfuscated UA），规则随时可能变（403 `free_mode_cli_required`、新模型、session 锁定）。
- **缓解**：反代逻辑完全由 freebuff2api 上游跟进；OmniBar 只做进程+配置层，解耦。升级 = 重新 `git pull` + 重启（提供「更新运行时」按钮：`git -C <runtimeDir> pull` + `uv sync`）。

### 9.2 许可（AGPL-3.0）⚠️
- freebuff2api 为 AGPL-3.0；OmniBar 为 MIT。
- 若随 App **打包分发**反代源码/二进制，构成"combined work"，需要以 AGPL 合规方式提供源码并说明许可证（可整体以 AGPL 分发该部分，或独立仓库）。
- **推荐缓解**：默认**首次使用时从 GitHub clone**（不内嵌分发，避开分发义务；用户机器上私有运行，AGPL 传染面最小）。内嵌 bundle 作为决策点 10.1 交给用户拍板。文档/UI 需标注来源与许可证。

### 9.3 安全
- freebuff2api 仅监听 `127.0.0.1`，不对外。
- `freebuffLocalAPIKey` 为空时本地无鉴权——仅本机可访问，可接受；默认建议生成随机 key（仿 `omnirouteAPIKey` 默认值逻辑）。
- Token 存 `@AppStorage`（UserDefaults 明文）——与现有 `omnirouteAPIKey` 一致；如需加强走 Keychain（决策点 10.5）。

### 9.4 免费额度的可持续性
- 依赖广告上报/streak 机制维持免费 session，属"薅羊毛"，有封号/额度策略调整风险。文档注明，不提供任何规避手段。

---

## 10. 审阅决策点

| # | 决策 | 选项 | 建议 |
|---|---|---|---|
| 10.1 | 运行时源码分发方式 | A) 首用 git clone（不内嵌） B) 内嵌 Bundle | **A**（AGPL 合规最简）；B 需法务确认 |
| 10.2 | uv 缺失时行为 | A) 提示手动安装 B) 自动 `brew install uv` | **A**（不擅自装软件）；提供一键复制命令 |
| 10.3 | 消费路径 | A) 仅直连 B) 追加「链到 Omniroute 上游」 | **先 A**；B 需确认 Omniroute 添加 provider 途径（API 无 create，只能改 config/dashboard）后单独立项 |
| 10.4 | 直连互斥策略 | A) freebuff 与 omniroute 互斥（关一个开另一个） B) 允许并存但提示 | **A**（live 文件同一时刻只能指一个网关，硬性约束） |
| 10.5 | Token 存储 | A) @AppStorage（现状一致） B) Keychain | **A**（与 omnirouteAPIKey 对齐，v3.0 不扩大安全面） |

---

## 11. 测试策略

### 单测（新增 `OmniBarTests/`）
- `FreebuffRuntimeTests`：runtimeDir 判定 / env 冲突消除 / uv 探测逻辑（注入 fake runner）。
- `FreebuffAPIClientTests`：`/v1/models` 解析、`/healthz`、错误映射（复用 `MockURLProtocol`）。
- `FreebuffTokenManagerTests`：code→poll→token 状态机（401 重试、超时、成功），fake URLSession。
- `FreebuffLinkManagerTests`：直连 enable/disable、与 omniroute 互斥、接管/外部改写检测（复用 `BackupManager` 测试夹具）。

### 集成冒烟（本机手动）
1. `uv sync` + 启动 → `curl /healthz`、`curl /v1/models`。
2. `curl /v1/chat/completions`（stream + non-stream）冒烟。
3. 开直连 → Claude Code 会话 `/status` 显示 `127.0.0.1:8000/v1`，Codex `/model` 列出 freebuff 模型。
4. 多账号并发：两个 token 同时请求不同模型不互相覆盖。
5. 崩溃自启 / 端口占用 / uv 缺失三条错误路径。

### 回归
- 现有 `OmnirouteAPIClientTests` / `LiveConfigTests` 全绿；omniroute 接入路径零改动验证。

---

## 12. 实施里程碑

| 里程碑 | 内容 | 验收 |
|---|---|---|
| M1 骨架 | `FreebuffRuntime` + `FreebuffService`（启动/停止/状态）+ env 注入 | 本机启动 freebuff2api，`/healthz` 绿 |
| M2 Token | `FreebuffTokenManager` + 设置页 Token 管理 + 验证 | 授权流程跑通，多账号落盘 |
| M3 直连 | `FreebuffLinkManager` + 卡片 + 互斥 + 接管检测 | Claude Code / Codex 指向 freebuff 可用 |
| M4 打磨 | 状态卡/错误文案/更新运行时/回归测试 | 全部测试绿，错误路径可操作 |
| M5（可选） | 链到 Omniroute 上游 | 决策点 10.3 通过后立项 |

---

## 13. 附录

### 13.1 上游依赖的 UA 指纹（Token 流程用，勿改）
- Token 请求：`User-Agent: Bun/1.3.11`、`Accept: application/json`。
- 反代内部（Swift 不碰）：`ai-sdk/...`（chat）、`Freebuff-CLI/0.0.105`（ads）等，见 freebuff2api `codebuff.py:20-26`。

### 13.2 模型目录映射
freebuff2api `models.py` 已把上游 `rateLimitsByModel` 映射到可对话模型 id（如 `crof/glm-5.2`→`z-ai/glm-5.2`），本地 `/v1/models` 返回的就是最终可用集合，Swift 直接消费即可，无需自建映射。

### 13.3 相关文件索引
- 反代：`freebuff2api/app.py`、`codebuff.py`、`openai_compat.py`、`config.py`、`models.py`
- Token 流程：`tool/get_token.py`、`tool/web/main.py`
- OmniBar 参照实现：`OmnirouteService.swift`（进程）、`ProviderLinkManager.swift` + `LiveConfig/*`（接入）、`OmnirouteAPIClient.swift`（API 模式）
