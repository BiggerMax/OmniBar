//
//  OmnirouteService.swift
//  OmniBar
//
//  Omniroute 进程管理 + 监听服务（主观察者，承担 ViewModel 角色）
//

import Foundation
import SwiftUI
import Combine
import Network

/// 服务操作类型
enum ServiceOperation: String, Equatable {
    case start, stop, restart
}

/// 操作结果，用于按钮上的瞬时成功/失败反馈
struct OperationResult: Equatable {
    let operation: ServiceOperation
    let success: Bool
    /// 每次结果都带唯一 id，保证连续两次相同结果也能触发动画
    let id = UUID()

    static func == (lhs: OperationResult, rhs: OperationResult) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class OmnirouteService: ObservableObject {
    @Published private(set) var status: ServiceStatus = .unknown
    @Published private(set) var pid: Int? = nil
    @Published private(set) var port: Int
    @Published private(set) var version: String = "—"
    @Published private(set) var uptime: TimeInterval = 0
    @Published private(set) var startedAt: Date? = nil

    // MARK: 版本与更新
    /// 当前 omniroute 版本（GET /api/system/version -> current）
    @Published private(set) var systemVersion: String = "—"
    /// 远程最新版本
    @Published private(set) var latestVersion: String = "—"
    /// 是否存在可更新版本
    @Published private(set) var updateAvailable: Bool = false
    @Published private(set) var isCheckingUpdate: Bool = false
    @Published private(set) var isUpdating: Bool = false
    /// 最近一次更新/检查的提示信息
    @Published private(set) var updateMessage: String? = nil

    // MARK: Provider 操作
    /// 是否有 provider 操作（测试/启用/优先级/删除）进行中
    @Published private(set) var providerOperationInProgress: Bool = false
    /// 最近一次 provider 操作的提示信息
    @Published private(set) var providerOperationMessage: String? = nil

    @Published private(set) var providers: [Provider] = []
    @Published private(set) var combos: [Combo] = []
    @Published private(set) var activeComboID: String? = nil
    /// 网关可路由模型列表（GET /v1/models），供「AI 接入」模型选择
    @Published private(set) var gatewayModels: [GatewayModel] = []
    @Published private(set) var usage: UsageStats = .init()
    /// 最近一次真实模型调用（GET /api/usage/call-logs），用于「当前调用」展示
    @Published private(set) var latestCall: CallLog? = nil

    // MARK: 提示词压缩（网关为数据源，刷新时读取、用户改动时写回）
    /// 是否启用提示词压缩（GET /api/settings/compression -> enabled）
    @Published private(set) var compressionEnabled: Bool = false
    /// 压缩模式：off / lite / standard / aggressive / ultra
    @Published private(set) var compressionMode: String = "off"

    @Published var isOperationInProgress: Bool = false
    @Published var lastErrorMessage: String? = nil
    /// 最近一次数据刷新是否因 API 鉴权失败（401）。用于 UI 给出明确提示与跳转。
    @Published private(set) var needsAuth: Bool = false

    // MARK: Cloudflare Tunnel（cloudflared 命名隧道，代理 /v1 到公网）
    /// 隧道进程是否在运行
    @Published private(set) var tunnelRunning: Bool = false
    /// 隧道公网地址（来自设置，仅展示）
    @Published var tunnelPublicURL: String {
        didSet { settings.tunnelPublicURL = tunnelPublicURL }
    }
    /// 隧道启停操作是否进行中
    @Published private(set) var tunnelOperationInProgress: Bool = false
    /// 隧道最近一次操作的提示信息
    @Published private(set) var tunnelMessage: String? = nil
    /// 由本 App 拉起的 cloudflared 进程
    private var tunnelTask: Process?

    /// 当前正在执行的操作（用于 UI 精确定位到具体按钮做加载动画）
    @Published private(set) var runningOperation: ServiceOperation? = nil
    /// 最近一次操作的结果（成功/失败），用于按钮上的瞬时反馈动画
    @Published private(set) var lastOperationResult: OperationResult? = nil

    private let api: OmnirouteAPIClient
    private let settings: AppSettings
    private var pollTask: Task<Void, Never>?
    private var uptimeTimer: Timer?
    /// 由本 App 拉起的 omniroute 进程（用于退出时清理引用）
    private var launchedTask: Process?

    // MARK: - 生命周期托管状态
    /// 上次轮询是否处于运行状态（用于识别“运行中→意外停止”的崩溃）
    private var wasRunning = false
    /// 连续自动重启计数，配合 restartRetryLimit 防止无限重启循环
    private var consecutiveCrashCount = 0
    /// 用户手动停止后抑制自动重启（直到再次手动启动）
    private var suppressAutoRestart = false
    /// 防止并发触发自动重启
    private var autoRestartInFlight = false

    nonisolated var settingsChanges: AnyPublisher<Void, Never> {
        settings.objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }

    /// 设置变化订阅的持有者（Combine sink 需强引用，否则订阅立即释放）
    private var settingsCancellables: Set<AnyCancellable> = []
    /// 上一次观测到的端口，用于识别端口变更
    private var previousPort: Int

    init(settings: AppSettings = .shared) {
        self.settings = settings
        self.port = settings.omniroutePort
        self.previousPort = settings.omniroutePort
        self.tunnelPublicURL = settings.tunnelPublicURL
        self.api = OmnirouteAPIClient(settings: settings)
        observeSettings()
    }

    // MARK: - Settings

    private func observeSettings() {
        // 监听 settings 变化以刷新端口/连接信息。
        // 注意：不能用 for-await（AsyncPublisher）订阅 objectWillChange——SwiftUI 的
        // UserDefaultObserver 会在视图更新期间（如设置页 Toggle 切换 @AppStorage）
        // 同步发布变更，AsyncPublisher 同步接收会触发
        // “Publishing changes from within view updates”断言崩溃。
        // 必须改用 receive(on:) 异步跳转到主队列后再处理，彻底避开视图更新周期。
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let newPort = self.settings.omniroutePort
                if newPort != self.previousPort {
                    self.previousPort = newPort
                    self.port = newPort
                    self.api.refreshSettings()
                    Task { await self.refreshStatus() }
                }
            }
            .store(in: &settingsCancellables)
    }
    // MARK: - Lifecycle

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                await self.refreshStatus()
                try? await Task.sleep(nanoseconds: UInt64(max(5, min(60, self.settings.pollIntervalSeconds))) * 1_000_000_000)
            }
        }
        startUptimeTimer()
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        uptimeTimer?.invalidate()
        uptimeTimer = nil
    }

    private func startUptimeTimer() {
        uptimeTimer?.invalidate()
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if let started = self.startedAt, self.status == .running {
                    self.uptime = Date().timeIntervalSince(started)
                }
            }
        }
    }

    // MARK: - Refresh

    func refreshStatus() async {
        // 检查进程是否存活
        let isAlive = await checkProcessAlive()
        if !isAlive {
            status = .stopped
            pid = nil
            startedAt = nil
            uptime = 0
            providers = []
            combos = []
            latestCall = nil
            needsAuth = false
            lastErrorMessage = nil

            // 崩溃自动重启：之前在运行、未手动停止、且在重试上限内
            let shouldRestart = wasRunning
                && settings.autoRestartOnCrash
                && !suppressAutoRestart
                && !autoRestartInFlight
                && consecutiveCrashCount < settings.restartRetryLimit
            if shouldRestart {
                autoRestartInFlight = true
                consecutiveCrashCount += 1
                lastErrorMessage = "omniroute 意外停止，正在自动重启 (\(consecutiveCrashCount)/\(settings.restartRetryLimit))…"
                _ = await startInternal()
                autoRestartInFlight = false
                // 恢复健康则清除提示；恢复失败会由下一轮继续尝试（直到重试上限）
                if status == .running {
                    lastErrorMessage = nil
                }
            }
            return
        }

        // 健康：重置崩溃计数，标记正在运行
        consecutiveCrashCount = 0
        wasRunning = true
        status = .running
        pid = await findPID()
        refreshTunnelStatus()

        // 并行获取 providers / combos / usage / system version
        do {
            async let p = api.fetchProviders()
            async let c = api.fetchCombos()
            async let u = api.fetchUsageStats()
            async let v = api.fetchSystemVersion()
            async let calls = api.fetchRecentCalls(limit: 10)
            async let m = api.fetchModels()

            let (providers, combos) = try await (p, c)
            self.providers = providers
            self.combos = combos
            // 网关模型列表：失败不阻断（旧版网关或无 /v1/models 时保持为空）
            if let models = try? await m {
                self.gatewayModels = models
            }
            // usage 获取失败不阻断主流程（部分网关可能未启用 analytics）
            if let stats = try? await u {
                self.usage = stats
            }
            // 最近调用：失败不阻断，仅保留上次值
            if let logs = try? await calls {
                self.latestCall = logs.first(where: { !$0.isTestCall })
            }
            // 版本信息：失败不阻断，仅保持上次值
            if let ver = try? await v {
                if let cur = ver.current, !cur.isEmpty { self.systemVersion = cur }
                if let lat = ver.latest, !lat.isEmpty { self.latestVersion = lat }
                self.updateAvailable = ver.updateAvailable ?? false
                // 同步顶部状态卡片的 version 显示为真实版本
                if !self.systemVersion.isEmpty, self.systemVersion != "—" {
                    self.version = self.systemVersion
                }
            }
            // 读取服务端当前激活的 combo（部分版本不回写，则回退到列表首项）
            if let active = try? await api.fetchActiveCombo(),
               let matched = combos.first(where: { $0.id == active || $0.name == active }) {
                self.activeComboID = matched.id
            } else {
                self.activeComboID = combos.first?.id
            }
            self.needsAuth = false
            self.lastErrorMessage = nil
            if startedAt == nil {
                startedAt = Date()
            }
            // 读取提示词压缩配置（旧版网关若无此端点则静默忽略，保留默认值）
            if let cs = try? await api.fetchCompressionSettings() {
                self.compressionEnabled = cs.enabled
                self.compressionMode = cs.defaultMode
            }
        } catch OmnirouteAPIError.unauthorized {
            self.needsAuth = true
            self.lastErrorMessage = "API 鉴权失败：请在偏好设置 → 连接 中填写正确的 API Key"
            self.providers = []
            self.combos = []
        } catch OmnirouteAPIError.endpointUnavailable {
            self.needsAuth = false
            self.lastErrorMessage = "网关暂不支持数据接口（/api/providers 或 /api/combos 不可用）"
            self.providers = []
            self.combos = []
        } catch {
            self.needsAuth = false
            self.lastErrorMessage = "数据获取失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Process Management

    /// 统一包装：维护 runningOperation / isOperationInProgress / lastOperationResult
    /// 保证按钮动画有稳定的状态来源，且成功反馈至少可见 (最短展示时长)
    private func perform(_ operation: ServiceOperation,
                         _ body: () async -> Bool) async -> Bool {
        guard runningOperation == nil else { return false }
        runningOperation = operation
        isOperationInProgress = true
        lastOperationResult = nil

        let startTime = Date()
        let ok = await body()

        // 操作过快时略作停留，避免加载动画一闪而过造成"没反应"的错觉
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed < 0.45 {
            try? await Task.sleep(nanoseconds: UInt64((0.45 - elapsed) * 1_000_000_000))
        }

        runningOperation = nil
        isOperationInProgress = false
        lastOperationResult = OperationResult(operation: operation, success: ok)

        // 1.6 秒后自动清除结果标记，让按钮回到常态
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard let self else { return }
            if self.runningOperation == nil {
                self.lastOperationResult = nil
            }
        }
        return ok
    }

    func start() async -> Bool {
        // 手动启动：解除抑制，允许后续崩溃自动重启
        suppressAutoRestart = false
        return await perform(.start) { await self.startInternal() }
    }

    /// 启动时自动拉起：若已启用 autoStartOnLaunch 且服务未运行，则以托管方式启动
    func startIfNeeded() async {
        guard settings.autoStartOnLaunch else { return }
        if await checkProcessAlive() {
            wasRunning = true
            return
        }
        suppressAutoRestart = false
        await startInternal()
    }

    private func startInternal() async -> Bool {
        // 已在运行则直接返回
        if await checkProcessAlive() {
            await refreshStatus()
            return status == .running
        }

        let binary = settings.omnirouteBinaryPath
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            lastErrorMessage = "启动失败：找不到可执行文件 \(binary)，请在偏好设置 → 连接 中修正二进制路径"
            status = .error
            return false
        }

        // 若存在 launchd LaunchAgent（com.omniroute.autostart），优先 bootstrap 让 launchd 托管。
        // 这样启动后由 launchd 守护，且与「停止时 bootout」对称，避免手动拉起进程与 launchd 冲突。
        if Self.bootstrapOmnirouteLaunchAgent() {
            // 等待 launchd 拉起，端口就绪即成功
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if await checkProcessAlive() {
                    await refreshStatus()
                    lastErrorMessage = nil
                    return status == .running
                }
            }
            // launchd 拉起失败，落到手动启动
        }

        do {
            let task = Process()
            // omniroute 是 node shim，必须经由 shell 继承完整 PATH，否则找不到 node
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            let cmd = "exec \(shellQuote(binary)) serve --no-open --port \(settings.omniroutePort)"
            task.arguments = ["-lc", cmd]

            var env = ProcessInfo.processInfo.environment
            let extraPaths = [
                "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                NSHomeDirectory() + "/.workbuddy/binaries/node/versions/22.22.2/bin"
            ]
            env["PATH"] = (extraPaths + [env["PATH"] ?? ""]).joined(separator: ":")
            task.environment = env

            // 必须丢弃输出，否则 pipe 缓冲区写满会让子进程阻塞
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            task.standardInput = FileHandle.nullDevice

            try task.run()
            launchedTask = task

            // 轮询等待端口就绪，最多 15 秒
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if await checkProcessAlive() {
                    await refreshStatus()
                    lastErrorMessage = nil
                    return status == .running
                }
            }

            lastErrorMessage = "启动超时：端口 \(settings.omniroutePort) 在 15 秒内未就绪"
            status = .error
            return false
        } catch {
            lastErrorMessage = "启动失败: \(error.localizedDescription)"
            status = .error
            return false
        }
    }

    /// shell 参数安全转义
    private nonisolated func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func stop() async -> Bool {
        // 手动停止：抑制崩溃自动重启，用户明确要关闭
        suppressAutoRestart = true
        wasRunning = false
        let ok = await perform(.stop) { await self.stopInternal() }
        if ok {
            consecutiveCrashCount = 0
        }
        return ok
    }

    /// 退出 OmniBar 时的完整清理：停止轮询，并（按配置 stopOnQuit）停止 omniroute。
    /// 供 applicationShouldTerminate 使用，返回后通常已同步完毕，App 可安全退出。
    func shutdown() async {
        suppressAutoRestart = true
        wasRunning = false
        stopPolling()
        if settings.stopOnQuit {
            _ = await stopInternal()
        }
    }

    private func stopInternal() async -> Bool {
        // 关键：omniroute 可能被 launchd LaunchAgent（com.omniroute.autostart）托管，
        // 直接杀进程会被 launchd 立即拉起（KeepAlive=true）。必须先卸载 LaunchAgent。
        let agentUnloaded = Self.unloadOmnirouteLaunchAgent()

        guard let currentPID = await findPID() else {
            status = .stopped
            pid = nil
            startedAt = nil
            uptime = 0
            return true
        }
        // 收集整条进程链：[监听端口的 server, supervisor(node wrapper), ...]
        // omniroute 自带 crash recovery：supervisor 会在 server 挂掉后自动拉起新的。
        // 因此必须【倒序】先杀 supervisor，再杀 server，否则 supervisor 会立刻重新拉起。
        let targets = collectProcessChain(from: currentPID).reversed().map { $0 }

        // 第一步：发 SIGTERM 优雅停止（supervisor 优先）
        for p in targets { _ = runKill(pid: p, signal: "TERM") }
        // 等待最多 3 秒，每 0.5s 检查一次端口
        for _ in 0..<6 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let alive = await checkProcessAlive()
            if !alive {
                launchedTask = nil
                await refreshStatus()
                return status == .stopped
            }
        }
        // 第二步：SIGTERM 没生效，用 SIGKILL 强杀整条链（依然 supervisor 优先）
        for p in targets { _ = runKill(pid: p, signal: "KILL") }
        launchedTask = nil
        try? await Task.sleep(nanoseconds: 800_000_000)

        // 第三步：supervisor 可能在被杀前已拉起新 server，这里兜底清理残留
        if await checkProcessAlive() {
            for _ in 0..<3 {
                guard let leftover = await findPID() else { break }
                for p in collectProcessChain(from: leftover).reversed() {
                    _ = runKill(pid: p, signal: "KILL")
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
                if await !checkProcessAlive() { break }
            }
        }
        await refreshStatus()
        // refreshStatus 通过 TCP 探测，若端口已关闭则判定为 stopped
        if status == .running {
            // 兜底：直接标记为 stopped，避免 UI 误显示
            status = .stopped
            pid = nil
            startedAt = nil
            uptime = 0
        }
        // LaunchAgent 已成功卸载但进程还在（理论上极罕见），再补一轮
        if status == .running, agentUnloaded {
            status = .stopped
            pid = nil
            startedAt = nil
            uptime = 0
        }
        return status == .stopped
    }

    func restart() async -> Bool {
        await perform(.restart) { await self.restartInternal() }
    }

    private func restartInternal() async -> Bool {
        // 优先路径：omniroute 自带 crash recovery（supervisor + --max-restarts）。
        // 只杀 server 子进程，supervisor 会自动拉起新实例——这是最快且最稳的重启方式，
        // 无需我们自己启动，也不会与 recovery 机制打架。
        if let currentPID = await findPID(),
           let supervisor = supervisorPID(of: currentPID) {
            _ = runKill(pid: currentPID, signal: "TERM")

            // 等待 supervisor 拉起新 server：先确认旧的消失，再确认新的就绪
            var recovered = false
            for _ in 0..<24 {  // 最多 12 秒
                try? await Task.sleep(nanoseconds: 500_000_000)
                if await checkProcessAlive(),
                   let newPID = await findPID(),
                   newPID != currentPID,
                   supervisorPID(of: newPID) == supervisor {
                    recovered = true
                    break
                }
            }

            if recovered {
                await refreshStatus()
                lastErrorMessage = nil
                return status == .running
            }
            // recovery 未生效（可能超过 --max-restarts 上限），落到完整重启流程
        }

        // 兜底路径：完整停止后重新启动
        // 注意：调用 internal 版本，避免重复进入 perform() 被并发守卫拦截
        _ = await stopInternal()
        for _ in 0..<10 {
            if await !checkProcessAlive() { break }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        if await checkProcessAlive() {
            lastErrorMessage = "重启失败：端口 \(settings.omniroutePort) 仍被占用，请手动检查残留进程"
            return false
        }
        return await startInternal()
    }

    /// 查找 supervisor（omniroute 的 node wrapper 父进程）
    /// 返回 nil 表示该进程不是由 supervisor 管理的（无 crash recovery）
    private nonisolated func supervisorPID(of pid: Int) -> Int? {
        guard let (ppid, command) = parentInfo(of: pid) else { return nil }
        let lower = command.lowercased()
        guard lower.contains("omniroute") || lower.contains("node") else { return nil }
        return ppid
    }

    /// 同步调用 /bin/kill 发送信号
    @discardableResult
    private nonisolated func runKill(pid: Int, signal: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/kill")
        task.arguments = ["-\(signal)", "\(pid)"]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 从监听端口的 PID 向上收集父进程链，命中 omniroute/node 的一并纳入
    /// 目的：omniroute 是 node shim，实际监听端口的是子进程，只杀它父进程会残留
    private nonisolated func collectProcessChain(from pid: Int) -> [Int] {
        var result: [Int] = [pid]
        var current = pid
        for _ in 0..<4 {
            guard let info = parentInfo(of: current) else { break }
            let (ppid, command) = info
            guard ppid > 1 else { break }
            // 只有父进程确实是 omniroute/node 相关才纳入，避免误杀 launchd/终端
            let lower = command.lowercased()
            guard lower.contains("omniroute") || lower.contains("node") else { break }
            result.append(ppid)
            current = ppid
        }
        // 先杀子后杀父
        return result
    }

    /// 返回 (ppid, 父进程命令行)
    private nonisolated func parentInfo(of pid: Int) -> (Int, String)? {
        guard let ppidText = runCapture("/bin/ps", ["-o", "ppid=", "-p", "\(pid)"]),
              let ppid = Int(ppidText.trimmingCharacters(in: .whitespacesAndNewlines)),
              ppid > 1 else { return nil }
        let command = runCapture("/bin/ps", ["-o", "command=", "-p", "\(ppid)"]) ?? ""
        return (ppid, command)
    }

    /// 同步执行命令并捕获 stdout
    private nonisolated func runCapture(_ path: String, _ args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// omniroute 可能被第三方 LaunchAgent（com.omniroute.autostart）托管（KeepAlive=true），
    /// 直接杀进程会被 launchd 立即拉起。停止前必须卸载该 LaunchAgent。
    /// - Returns: 是否存在并已卸载
    private static func unloadOmnirouteLaunchAgent() -> Bool {
        let label = "com.omniroute.autostart"
        let uid = getuid()
        // 检查是否已注册
        let check = runSync("/bin/launchctl", ["print", "gui/\(uid)/\(label)"])
        guard let check, !check.isEmpty else { return false }
        // 卸载（bootout 对已注册服务返回 0；未注册返回非 0，忽略即可）
        _ = runSync("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
        return true
    }

    /// 启动时若 LaunchAgent 存在，尝试 bootstrap 让 launchd 接管（KeepAlive 自动守护），
    /// 与系统自启机制一致，避免 OmniBar 手动拉起与 launchd 托管冲突。
    private static func bootstrapOmnirouteLaunchAgent() -> Bool {
        let label = "com.omniroute.autostart"
        let uid = getuid()
        let plistPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/LaunchAgents/com.omniroute.autostart.plist")
        guard FileManager.default.fileExists(atPath: plistPath) else { return false }
        // 已注册则无需重复
        if let check = runSync("/bin/launchctl", ["print", "gui/\(uid)/\(label)"]), !check.isEmpty {
            return true
        }
        // bootstrap 成功才返回 true（失败返回非 0 输出为空）
        let out = runSync("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistPath])
        return out != nil
    }

    /// 同步执行命令（忽略输出，返回退出码是否为 0）
    @discardableResult
    private static func runSync(_ path: String, _ args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - Cloudflare Tunnel

    /// 刷新隧道运行状态（轮询时调用）。启动时同时将公网地址写回设置。
    func refreshTunnelStatus() {
        tunnelRunning = isCloudflaredRunning()
    }

    /// 检测 cloudflared 是否正以「目标配置文件 + 隧道名」在运行
    private func isCloudflaredRunning() -> Bool {
        let bin = settings.cloudflaredBinaryPath
        let cfg = settings.cloudflaredConfigPath
        guard !bin.isEmpty, !cfg.isEmpty else { return false }
        let output = runCapture("/bin/ps", ["-axo", "command="]) ?? ""
        return output
            .split(separator: "\n")
            .contains { line in
                let l = line.lowercased()
                return l.contains("cloudflared")
                    && l.contains("tunnel")
                    && l.contains("run")
                    && l.contains(cfg.lowercased())
            }
    }

    /// 启用/停用 Cloudflare Tunnel。
    /// - Parameters:
    ///   - enabled: true 启动隧道，false 停止隧道
    /// - Returns: 是否成功
    @discardableResult
    func setTunnel(enabled: Bool) async -> Bool {
        guard !tunnelOperationInProgress else { return false }
        tunnelOperationInProgress = true
        defer { tunnelOperationInProgress = false }
        if enabled {
            return await startTunnel()
        } else {
            return await stopTunnel()
        }
    }

    private func startTunnel() async -> Bool {
        let bin = settings.cloudflaredBinaryPath
        let cfg = settings.cloudflaredConfigPath
        let name = settings.cloudflaredTunnelName
        guard FileManager.default.isExecutableFile(atPath: bin) else {
            tunnelMessage = "启动失败：找不到 cloudflared（\(bin)），请在偏好设置 → 连接 中修正路径"
            return false
        }
        guard FileManager.default.fileExists(atPath: cfg) else {
            tunnelMessage = "启动失败：找不到隧道配置 \(cfg)"
            return false
        }
        if isCloudflaredRunning() {
            tunnelMessage = "隧道已在运行"
            tunnelRunning = true
            return true
        }

        do {
            let task = Process()
            // cloudflared 是 go 二进制，可直接执行；经 shell 继承 PATH
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            let cmd = "exec \(shellQuote(bin)) tunnel --config \(shellQuote(cfg)) run \(shellQuote(name))"
            task.arguments = ["-lc", cmd]

            var env = ProcessInfo.processInfo.environment
            let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            env["PATH"] = (extraPaths + [env["PATH"] ?? ""]).joined(separator: ":")
            task.environment = env
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            task.standardInput = FileHandle.nullDevice

            try task.run()
            tunnelTask = task

            // 轮询等待隧道就绪（最多 12 秒）
            for _ in 0..<24 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if isCloudflaredRunning() {
                    tunnelRunning = true
                    tunnelMessage = "隧道已启用（\(settings.tunnelPublicURL)）"
                    return true
                }
            }
            tunnelMessage = "启动超时：cloudflared 在 12 秒内未就绪，请检查配置与网络"
            return false
        } catch {
            tunnelMessage = "启动失败：\(error.localizedDescription)"
            return false
        }
    }

    private func stopTunnel() async -> Bool {
        let cfg = settings.cloudflaredConfigPath
        // 找到匹配该配置的 cloudflared 进程并终止
        let output = runCapture("/bin/ps", ["-axo", "pid=,command="]) ?? ""
        var killed = false
        for line in output.split(separator: "\n") {
            let l = line.lowercased()
            guard l.contains("cloudflared"), l.contains("tunnel"), l.contains(cfg.lowercased()) else { continue }
            guard let pid = Int(line.split(separator: " ").first ?? "") else { continue }
            _ = runKill(pid: pid, signal: "TERM")
            killed = true
        }
        // 等 2 秒确认退出；未退出则强杀
        if killed {
            for _ in 0..<4 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !isCloudflaredRunning() { break }
            }
            if isCloudflaredRunning() {
                let again = runCapture("/bin/ps", ["-axo", "pid=,command="]) ?? ""
                for line in again.split(separator: "\n") {
                    let l = line.lowercased()
                    guard l.contains("cloudflared"), l.contains("tunnel"), l.contains(cfg.lowercased()) else { continue }
                    guard let pid = Int(line.split(separator: " ").first ?? "") else { continue }
                    _ = runKill(pid: pid, signal: "KILL")
                }
            }
        }
        tunnelTask = nil
        try? await Task.sleep(nanoseconds: 300_000_000)
        tunnelRunning = isCloudflaredRunning()
        if !tunnelRunning {
            tunnelMessage = "隧道已停用"
            return true
        }
        tunnelMessage = "停止失败：隧道进程仍在运行"
        return false
    }

    /// 清除最近一次隧道操作的提示信息。
    func clearTunnelMessage() {
        tunnelMessage = nil
    }

    // MARK: - Prompt Compression

    /// 设置提示词压缩（总开关 + 模式），写回网关后同步本地状态。
    /// - Parameters:
    ///   - enabled: 是否启用压缩
    ///   - mode: 压缩模式（off/lite/standard/aggressive/ultra）
    /// - Returns: 是否成功
    @discardableResult
    func setCompression(enabled: Bool, mode: String) async -> Bool {
        do {
            let cs = try await api.setCompressionSettings(enabled: enabled, defaultMode: mode)
            self.compressionEnabled = cs.enabled
            self.compressionMode = cs.defaultMode
            self.needsAuth = false
            self.lastErrorMessage = nil
            return true
        } catch OmnirouteAPIError.unauthorized {
            self.needsAuth = true
            self.lastErrorMessage = "API 鉴权失败：请在偏好设置 → 连接 中填写正确的 API Key"
            return false
        } catch OmnirouteAPIError.endpointUnavailable {
            self.lastErrorMessage = "当前网关版本不支持提示词压缩（/api/settings/compression 不可用）"
            return false
        } catch {
            self.lastErrorMessage = "设置提示词压缩失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Combo Switching

    func switchCombo(to id: String) async -> Bool {
        guard let combo = combos.first(where: { $0.id == id }) else { return false }
        do {
            // 用 name 或 id 均可；服务端按 name/id 匹配
            let success = try await api.setActiveCombo(nameOrId: combo.name)
            if success {
                activeComboID = id
            }
            return success
        } catch OmnirouteAPIError.unauthorized {
            self.needsAuth = true
            self.lastErrorMessage = "API 鉴权失败：请在偏好设置 → 连接 中填写正确的 API Key"
            return false
        } catch OmnirouteAPIError.endpointUnavailable {
            self.lastErrorMessage = "当前网关未提供切换 Combo 的接口，请通过 Dashboard 操作"
            return false
        } catch {
            self.lastErrorMessage = "切换失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Provider Operations

    /// 重新测试单个 Provider 连接（触发健康度检测），成功后刷新本地列表。
    func testProvider(_ provider: Provider) async -> Bool {
        guard !providerOperationInProgress else { return false }
        providerOperationInProgress = true
        defer { providerOperationInProgress = false }
        do {
            let result = try await api.testProvider(id: provider.id)
            if result.valid == true {
                providerOperationMessage = "「\(provider.displayName)」测试通过"
            } else if let err = result.error, !err.isEmpty {
                providerOperationMessage = "「\(provider.displayName)」测试失败：\(err)"
            } else {
                providerOperationMessage = "「\(provider.displayName)」测试未通过"
            }
            await refreshStatus()
            return result.valid ?? false
        } catch OmnirouteAPIError.unauthorized {
            self.needsAuth = true
            providerOperationMessage = "API 鉴权失败：请在偏好设置 → 连接 中填写正确的 API Key"
            return false
        } catch OmnirouteAPIError.endpointUnavailable {
            providerOperationMessage = "网关未提供测试接口（/api/providers/{id}/test 不可用）"
            return false
        } catch {
            providerOperationMessage = "测试失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 启用/停用单个 Provider 连接。
    func setProviderActive(_ provider: Provider, active: Bool) async -> Bool {
        guard !providerOperationInProgress else { return false }
        providerOperationInProgress = true
        defer { providerOperationInProgress = false }
        do {
            try await api.updateProvider(id: provider.id, isActive: active)
            providerOperationMessage = "「\(provider.displayName)」已\(active ? "启用" : "停用")"
            await refreshStatus()
            return true
        } catch OmnirouteAPIError.unauthorized {
            self.needsAuth = true
            providerOperationMessage = "API 鉴权失败：请在偏好设置 → 连接 中填写正确的 API Key"
            return false
        } catch OmnirouteAPIError.endpointUnavailable {
            providerOperationMessage = "网关未提供更新接口（PATCH /api/providers/{id} 不可用）"
            return false
        } catch {
            providerOperationMessage = "\(active ? "启用" : "停用")失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 调整单个 Provider 连接的优先级。
    func setProviderPriority(_ provider: Provider, priority: Int) async -> Bool {
        guard !providerOperationInProgress else { return false }
        providerOperationInProgress = true
        defer { providerOperationInProgress = false }
        do {
            try await api.updateProvider(id: provider.id, priority: priority)
            providerOperationMessage = "「\(provider.displayName)」优先级设为 \(priority)"
            await refreshStatus()
            return true
        } catch OmnirouteAPIError.unauthorized {
            self.needsAuth = true
            providerOperationMessage = "API 鉴权失败：请在偏好设置 → 连接 中填写正确的 API Key"
            return false
        } catch OmnirouteAPIError.endpointUnavailable {
            providerOperationMessage = "网关未提供更新接口（PATCH /api/providers/{id} 不可用）"
            return false
        } catch {
            providerOperationMessage = "优先级调整失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 删除单个 Provider 连接。
    func deleteProvider(_ provider: Provider) async -> Bool {
        guard !providerOperationInProgress else { return false }
        providerOperationInProgress = true
        defer { providerOperationInProgress = false }
        do {
            try await api.deleteProvider(id: provider.id)
            providerOperationMessage = "「\(provider.displayName)」已删除"
            await refreshStatus()
            return true
        } catch OmnirouteAPIError.unauthorized {
            self.needsAuth = true
            providerOperationMessage = "API 鉴权失败：请在偏好设置 → 连接 中填写正确的 API Key"
            return false
        } catch OmnirouteAPIError.endpointUnavailable {
            providerOperationMessage = "网关未提供删除接口（DELETE /api/providers/{id} 不可用）"
            return false
        } catch {
            providerOperationMessage = "删除失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 批量删除多个 Provider 连接。逐项调用删除接口，统计成功/失败数量。
    func deleteProviders(_ providers: [Provider]) async -> Int {
        guard !providerOperationInProgress, !providers.isEmpty else { return 0 }
        providerOperationInProgress = true
        defer { providerOperationInProgress = false }

        var success = 0
        for provider in providers {
            do {
                try await api.deleteProvider(id: provider.id)
                success += 1
            } catch OmnirouteAPIError.unauthorized {
                self.needsAuth = true
                providerOperationMessage = "API 鉴权失败：请在偏好设置 → 连接 中填写正确的 API Key"
                break
            } catch OmnirouteAPIError.endpointUnavailable {
                providerOperationMessage = "网关未提供删除接口（DELETE /api/providers/{id} 不可用）"
                break
            } catch {
                // 单条失败不中断，继续删剩余项；最后汇总提示
            }
        }
        providerOperationMessage = "已删除 \(success)/\(providers.count) 个连接"
        await refreshStatus()
        return success
    }

    /// 清除最近一次 provider 操作的提示信息（UI 主动消费后调用）。
    func clearProviderOperationMessage() {
        providerOperationMessage = nil
    }

    // MARK: - Version & Update

    /// 主动检查更新（即时拉取 /api/system/version）。与轮询合并刷新，UI 可手动触发。
    func checkForUpdate() async {
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }
        do {
            let ver = try await api.fetchSystemVersion()
            if let cur = ver.current, !cur.isEmpty { self.systemVersion = cur }
            if let lat = ver.latest, !lat.isEmpty { self.latestVersion = lat }
            self.updateAvailable = ver.updateAvailable ?? false
            if !self.systemVersion.isEmpty, self.systemVersion != "—" {
                self.version = self.systemVersion
            }
            if self.updateAvailable {
                updateMessage = "发现新版本 \(self.latestVersion)（当前 \(self.systemVersion)）"
            } else {
                updateMessage = "已是最新版本 \(self.systemVersion)"
            }
        } catch OmnirouteAPIError.unauthorized {
            self.needsAuth = true
            updateMessage = "检查更新失败：API 鉴权失败"
        } catch OmnirouteAPIError.endpointUnavailable {
            updateMessage = "网关未提供版本接口（/api/system/version 不可用）"
        } catch {
            updateMessage = "检查更新失败：\(error.localizedDescription)"
        }
    }

    /// 执行 omniroute 更新。
    /// omniroute 通过 npm 全局安装，更新走 `npm install -g omniroute@latest`。
    /// 更新完成后提示用户重启服务以应用新版本（不自动重启，避免打断在途请求）。
    @discardableResult
    func performUpdate() async -> Bool {
        guard !isUpdating else { return false }
        isUpdating = true
        updateMessage = "正在更新 omniroute…"
        defer { isUpdating = false }
        let ok = await Self.runNpmInstallLatest()
        if ok {
            updateMessage = "更新完成，请重启 Omniroute 服务以应用新版本"
            await checkForUpdate()
        } else {
            updateMessage = "更新失败：npm install -g omniroute@latest 执行未成功，请查看终端日志"
        }
        return ok
    }

    /// 清除最近一次更新操作的提示信息。
    func clearUpdateMessage() {
        updateMessage = nil
    }

    /// 同步执行 npm install -g omniroute@latest（off-main，避免阻塞 UI）。
    private static nonisolated func runNpmInstallLatest() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/zsh")
                task.arguments = ["-lc", "npm install -g omniroute@latest"]
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                task.standardInput = FileHandle.nullDevice
                do {
                    try task.run()
                    task.waitUntilExit()
                    continuation.resume(returning: task.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Process Detection

    private func checkProcessAlive() async -> Bool {
        let port = settings.omniroutePort
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            var resumed = false
            let lock = NSLock()
            let resume: (Bool) -> Void = { value in
                lock.lock()
                if !resumed { resumed = true; continuation.resume(returning: value) }
                lock.unlock()
            }
            let conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(integerLiteral: UInt16(port)), using: .tcp)
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resume(true)
                case .failed, .cancelled:
                    resume(false)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .utility))
            // 超时保险：2s
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                resume(false)
                conn.cancel()
            }
        }
    }

    private func findPID() async -> Int? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                task.arguments = ["-i", "TCP:\(self.settings.omniroutePort)", "-sTCP:LISTEN", "-t"]
                let pipe = Pipe()
                task.standardOutput = pipe
                do {
                    try task.run()
                    task.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let pid = Int(output.components(separatedBy: "\n").first ?? "")
                    continuation.resume(returning: pid)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
