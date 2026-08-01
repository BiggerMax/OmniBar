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

    @Published private(set) var providers: [Provider] = []
    @Published private(set) var combos: [Combo] = []
    @Published private(set) var activeComboID: String? = nil
    @Published private(set) var usage: UsageStats = .init()

    @Published var isOperationInProgress: Bool = false
    @Published var lastErrorMessage: String? = nil
    /// 最近一次数据刷新是否因 API 鉴权失败（401）。用于 UI 给出明确提示与跳转。
    @Published private(set) var needsAuth: Bool = false

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

    nonisolated var settingsChanges: AnyPublisher<Void, Never> {
        settings.objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }

    init(settings: AppSettings = .shared) {
        self.settings = settings
        self.port = settings.omniroutePort
        self.api = OmnirouteAPIClient(settings: settings)
        observeSettings()
    }

    // MARK: - Settings

    private func observeSettings() {
        // 监听 settings 变化以刷新端口/连接信息
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            var previousPort = self.settings.omniroutePort
            for await _ in self.settings.objectWillChange.values {
                let newPort = self.settings.omniroutePort
                if newPort != previousPort {
                    previousPort = newPort
                    self.port = newPort
                    self.api.refreshSettings()
                    await self.refreshStatus()
                }
            }
        }
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
            needsAuth = false
            lastErrorMessage = nil
            return
        }

        status = .running
        pid = await findPID()

        // 并行获取 providers / combos / usage
        do {
            async let p = api.fetchProviders()
            async let c = api.fetchCombos()
            async let u = api.fetchUsageStats()

            let (providers, combos) = try await (p, c)
            self.providers = providers
            self.combos = combos
            // usage 获取失败不阻断主流程（部分网关可能未启用 analytics）
            if let stats = try? await u {
                self.usage = stats
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
        await perform(.start) { await self.startInternal() }
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
        await perform(.stop) { await self.stopInternal() }
    }

    private func stopInternal() async -> Bool {
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
