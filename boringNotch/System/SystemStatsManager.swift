//
//  SystemStatsManager.swift
//  boringNotch
//
//  Live CPU / memory / network / disk indicators for the System tab.
//

import Combine
import Darwin
import Defaults
import Foundation

/// A single app/process grouped memory reading for the "top memory" list.
struct ProcessMemory: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let megabytes: Double

    var formatted: String {
        if megabytes >= 1024 {
            return String(format: "%.1f GB", megabytes / 1024)
        }
        return "\(Int(megabytes.rounded())) MB"
    }
}

final class SystemStatsManager: ObservableObject {
    static let shared = SystemStatsManager()

    /// 0...1 fraction of CPU in use.
    @Published private(set) var cpuUsage: Double = 0
    /// 0...1 fraction of physical memory in use.
    @Published private(set) var memoryUsage: Double = 0
    @Published private(set) var memoryUsedBytes: UInt64 = 0
    @Published private(set) var memoryTotalBytes: UInt64 = 0
    /// Bytes per second.
    @Published private(set) var networkDownBytesPerSec: Double = 0
    @Published private(set) var networkUpBytesPerSec: Double = 0
    @Published private(set) var diskFreeBytes: Int64 = 0
    @Published private(set) var diskTotalBytes: Int64 = 0
    /// Top memory-consuming apps, grouped (Chrome helpers collapse into "Google Chrome", etc.).
    @Published private(set) var topMemoryProcesses: [ProcessMemory] = []

    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private let sampleInterval: TimeInterval = 2

    private var previousCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var previousNet: (received: UInt64, sent: UInt64, time: Date)?
    /// `ps` is heavier than the Mach reads, so refresh the process list every few ticks.
    private var tickCount = 0

    private init() {
        Defaults.publisher(.enableSystemStats)
            .sink { [weak self] change in
                if change.newValue { self?.start() } else { self?.stop() }
            }
            .store(in: &cancellables)

        if Defaults[.enableSystemStats] { start() }
    }

    func start() {
        guard timer == nil else { return }
        sample() // immediate first read
        timer = Timer.publish(every: sampleInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.sample() }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func sample() {
        let currentTick = tickCount
        tickCount &+= 1

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let cpu = self.readCPUUsage()
            let mem = self.readMemory()
            let net = self.readNetworkSpeed()
            let disk = self.readDisk()
            // Refresh the process list on the first sample and then every ~6s.
            let topProcesses = (currentTick % 3 == 0) ? self.readTopMemoryProcesses() : nil

            DispatchQueue.main.async {
                if let cpu = cpu { self.cpuUsage = cpu }
                self.memoryUsage = mem.total > 0 ? Double(mem.used) / Double(mem.total) : 0
                self.memoryUsedBytes = mem.used
                self.memoryTotalBytes = mem.total
                self.networkDownBytesPerSec = net.down
                self.networkUpBytesPerSec = net.up
                self.diskFreeBytes = disk.free
                self.diskTotalBytes = disk.total
                if let topProcesses = topProcesses {
                    self.topMemoryProcesses = topProcesses
                }
            }
        }
    }

    // MARK: - Top memory processes

    private func readTopMemoryProcesses(limit: Int = 5) -> [ProcessMemory] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "rss=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var totals: [String: Double] = [:]
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let spaceIndex = line.firstIndex(of: " ") else { continue }
            guard let rssKB = Double(line[..<spaceIndex]) else { continue }
            let path = line[line.index(after: spaceIndex)...].trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }
            totals[appName(from: path), default: 0] += rssKB
        }

        return totals
            .map { ProcessMemory(name: $0.key, megabytes: $0.value / 1024) }
            .sorted { $0.megabytes > $1.megabytes }
            .prefix(limit)
            .map { $0 }
    }

    /// Turns an executable path into a friendly app name, grouping bundle helpers.
    private func appName(from path: String) -> String {
        if let appRange = path.range(of: ".app/") {
            let beforeApp = path[..<appRange.lowerBound]
            if let slash = beforeApp.lastIndex(of: "/") {
                return String(beforeApp[beforeApp.index(after: slash)...])
            }
            return String(beforeApp)
        }
        if let slash = path.lastIndex(of: "/") {
            return String(path[path.index(after: slash)...])
        }
        return path
    }

    // MARK: - CPU

    private func readCPUUsage() -> Double? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let user = info.cpu_ticks.0
        let system = info.cpu_ticks.1
        let idle = info.cpu_ticks.2
        let nice = info.cpu_ticks.3

        defer { previousCPUTicks = (user, system, idle, nice) }
        guard let prev = previousCPUTicks else { return nil }

        let userDiff = Double(user &- prev.user)
        let systemDiff = Double(system &- prev.system)
        let idleDiff = Double(idle &- prev.idle)
        let niceDiff = Double(nice &- prev.nice)
        let totalDiff = userDiff + systemDiff + idleDiff + niceDiff
        guard totalDiff > 0 else { return nil }
        return (userDiff + systemDiff + niceDiff) / totalDiff
    }

    // MARK: - Memory

    private func readMemory() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory

        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var info = vm_statistics64_data_t()
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, total) }

        let pageSize = UInt64(vm_page_size)
        let active = UInt64(info.active_count)
        let wired = UInt64(info.wire_count)
        let compressed = UInt64(info.compressor_page_count)
        let used = (active + wired + compressed) * pageSize
        return (min(used, total), total)
    }

    // MARK: - Network

    private func readNetworkSpeed() -> (down: Double, up: Double) {
        let counters = readNetworkCounters()
        let now = Date()
        defer { previousNet = (counters.received, counters.sent, now) }

        guard let prev = previousNet else { return (0, 0) }
        let elapsed = now.timeIntervalSince(prev.time)
        guard elapsed > 0 else { return (0, 0) }

        // Guard against counter wrap/reset (interface up/down).
        let downDelta = counters.received >= prev.received ? Double(counters.received - prev.received) : 0
        let upDelta = counters.sent >= prev.sent ? Double(counters.sent - prev.sent) : 0
        return (downDelta / elapsed, upDelta / elapsed)
    }

    private func readNetworkCounters() -> (received: UInt64, sent: UInt64) {
        var received: UInt64 = 0
        var sent: UInt64 = 0

        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return (0, 0) }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let addr = current.pointee
            if let sa = addr.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: addr.ifa_name)
                if !name.hasPrefix("lo"), let dataPtr = addr.ifa_data {
                    let data = dataPtr.assumingMemoryBound(to: if_data.self)
                    received += UInt64(data.pointee.ifi_ibytes)
                    sent += UInt64(data.pointee.ifi_obytes)
                }
            }
            ptr = addr.ifa_next
        }
        return (received, sent)
    }

    // MARK: - Disk

    private func readDisk() -> (free: Int64, total: Int64) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        ) else {
            return (0, 0)
        }
        let free = values.volumeAvailableCapacityForImportantUsage ?? 0
        let total = Int64(values.volumeTotalCapacity ?? 0)
        return (free, total)
    }

    // MARK: - Formatting helpers

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func formatSpeed(_ bytesPerSec: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(bytesPerSec)) + "/s"
    }
}
