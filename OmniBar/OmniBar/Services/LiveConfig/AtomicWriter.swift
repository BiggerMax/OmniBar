//
//  AtomicWriter.swift
//  OmniBar
//
//  原子写盘与文件快照（备份 / 回滚）工具。
//  写 live 配置文件时使用「同目录临时文件 + rename」，避免写一半损坏用户配置。
//

import Foundation

/// 原子写盘：临时文件写入同目录后再 rename，确保对目标文件始终是完整替换。
enum AtomicWriter {

    /// 原子写入 Data。会确保父目录存在。
    static func write(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // 临时文件必须与目标同目录，rename 才保证在同一文件系统内原子生效
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).omnitmp")
        try data.write(to: tmp, options: .atomic)
        _ = try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: tmp, to: url)
    }

    static func writeText(_ text: String, to url: URL) throws {
        try write(Data(text.utf8), to: url)
    }

    static func readText(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    static func writeJSON(_ obj: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try write(data, to: url)
    }

    static func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return obj
    }
}

/// 快照管理：在「接入」前把 live 文件原样复制到备份目录，供关闭时回滚。
/// 备份路径可注入（测试用临时目录），默认 ~/Library/Application Support/OmniBar/backups。
struct BackupManager {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
            self.directory = base.appendingPathComponent("OmniBar/backups", isDirectory: true)
        }
    }

    /// 备份文件名：`<marker>-<basename>`，如 `omnibar:claudeCode-settings.json`。
    func backupURL(for liveURL: URL, marker: String) -> URL {
        let name = liveURL.lastPathComponent
        return directory.appendingPathComponent("\(marker)-\(name)")
    }

    /// 是否已有该目标的备份（= 接入前该 live 文件真实存在过）。
    func hasBackup(liveURL: URL, marker: String) -> Bool {
        FileManager.default.fileExists(atPath: backupURL(for: liveURL, marker: marker).path)
    }

    /// 若目标已存在于备份目录则返回；否则把 liveURL 原样复制一份。
    /// - Returns: 备份 URL（存在与否）
    @discardableResult
    func ensureBackup(of liveURL: URL, marker: String) -> URL {
        let backup = backupURL(for: liveURL, marker: marker)
        if FileManager.default.fileExists(atPath: backup.path) {
            return backup
        }
        // 只有 live 文件真实存在才备份（不存在 = 首次接入，回滚时删除即可）
        if FileManager.default.fileExists(atPath: liveURL.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: liveURL, to: backup)
        }
        return backup
    }

    /// 还原 live 文件：以备份覆盖；live 原本不存在则删除。返回原始 urls 供清理。
    @discardableResult
    func restore(liveURL: URL, marker: String) -> Bool {
        let backup = backupURL(for: liveURL, marker: marker)
        let hadOriginal = FileManager.default.fileExists(atPath: backup.path)
        if hadOriginal {
            // 先删当前再还原，确保不残留
            try? FileManager.default.removeItem(at: liveURL)
            return (try? FileManager.default.copyItem(at: backup, to: liveURL)) != nil
        } else {
            // 接入前没有该文件，还原 = 删除
            try? FileManager.default.removeItem(at: liveURL)
            return true
        }
    }

    /// 清理该目标的备份（成功回滚后调用）。
    func cleanup(liveURL: URL, marker: String) {
        let backup = backupURL(for: liveURL, marker: marker)
        try? FileManager.default.removeItem(at: backup)
    }
}