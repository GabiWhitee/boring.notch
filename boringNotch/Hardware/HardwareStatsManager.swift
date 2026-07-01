//
//  HardwareStatsManager.swift
//  boringNotch
//
//  Extra hardware stats for the "Hardware" tab: uptime, Wi-Fi, per-core CPU,
//  and battery health / cycle count.
//

import Combine
import CoreWLAN
import Darwin
import Defaults
import Foundation
import IOKit

struct CoreLoad: Identifiable, Equatable {
    let id: Int
    let usage: Double
}

final class HardwareStatsManager: ObservableObject {
    static let shared = HardwareStatsManager()

    @Published private(set) var uptimeText: String = "—"
    @Published private(set) var wifiSSID: String?
    @Published private(set) var wifiRSSI: Int?
    @Published private(set) var perCoreUsage: [CoreLoad] = []
    @Published private(set) var batteryHealthPercent: Int?
    @Published private(set) var batteryCycleCount: Int?

    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var previousCoreTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)]?
    private var tickCount = 0

    private init() {
        Defaults.publisher(.enableHardwareTab)
            .sink { [weak self] change in
                if change.newValue { self?.start() } else { self?.stop() }
            }
            .store(in: &cancellables)

        if Defaults[.enableHardwareTab] { start() }
    }

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.sample() }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func sample() {
        let tick = tickCount
        tickCount &+= 1

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let uptime = self.readUptime()
            let cores = self.readPerCore()
            // Wi-Fi and battery detail change slowly — poll them less often.
            let wifi = (tick % 3 == 0) ? self.readWiFi() : nil
            let battery = (tick % 3 == 0) ? self.readBatteryDetail() : nil

            DispatchQueue.main.async {
                self.uptimeText = uptime
                if let cores = cores { self.perCoreUsage = cores }
                if let wifi = wifi {
                    self.wifiSSID = wifi.ssid
                    self.wifiRSSI = wifi.rssi
                }
                if let battery = battery {
                    self.batteryHealthPercent = battery.health
                    self.batteryCycleCount = battery.cycles
                }
            }
        }
    }

    // MARK: - Uptime

    private func readUptime() -> String {
        let seconds = Int(ProcessInfo.processInfo.systemUptime)
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    // MARK: - Wi-Fi

    private func readWiFi() -> (ssid: String?, rssi: Int?) {
        guard let interface = CWWiFiClient.shared().interface() else { return (nil, nil) }
        let rssi = interface.rssiValue()
        return (interface.ssid(), rssi == 0 ? nil : rssi)
    }

    /// Maps an RSSI (dBm) reading to 0...4 signal bars.
    static func wifiBars(for rssi: Int) -> Int {
        switch rssi {
        case (-50)...: return 4
        case (-60)..<(-50): return 3
        case (-70)..<(-60): return 2
        case (-80)..<(-70): return 1
        default: return 0
        }
    }

    // MARK: - Per-core CPU

    private func readPerCore() -> [CoreLoad]? {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0

        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCpus, &cpuInfo, &numCpuInfo
        )
        guard result == KERN_SUCCESS, let cpuInfo = cpuInfo else { return nil }
        defer {
            let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: UnsafeRawPointer(cpuInfo))), size)
        }

        let cpus = Int(numCpus)
        let stateMax = Int(CPU_STATE_MAX)
        var current: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
        current.reserveCapacity(cpus)
        for i in 0..<cpus {
            let base = i * stateMax
            current.append((
                user: UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_NICE)])
            ))
        }

        defer { previousCoreTicks = current }
        guard let prev = previousCoreTicks, prev.count == cpus else { return nil }

        var loads: [CoreLoad] = []
        loads.reserveCapacity(cpus)
        for i in 0..<cpus {
            let user = Double(current[i].user &- prev[i].user)
            let system = Double(current[i].system &- prev[i].system)
            let idle = Double(current[i].idle &- prev[i].idle)
            let nice = Double(current[i].nice &- prev[i].nice)
            let total = user + system + idle + nice
            let usage = total > 0 ? (user + system + nice) / total : 0
            loads.append(CoreLoad(id: i, usage: min(max(usage, 0), 1)))
        }
        return loads
    }

    // MARK: - Battery detail (IOKit)

    private func readBatteryDetail() -> (cycles: Int?, health: Int?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let cfProps = props?.takeRetainedValue()
        else {
            return (nil, nil)
        }
        let dict = cfProps as NSDictionary

        var cycles = dict["CycleCount"] as? Int
        var designCap = dict["DesignCapacity"] as? Int
        var maxCap = (dict["AppleRawMaxCapacity"] as? Int) ?? (dict["MaxCapacity"] as? Int)

        // Apple Silicon often nests these under "BatteryData".
        if let batteryData = dict["BatteryData"] as? [String: Any] {
            cycles = cycles ?? (batteryData["CycleCount"] as? Int)
            designCap = designCap ?? (batteryData["DesignCapacity"] as? Int)
            maxCap = maxCap ?? (batteryData["AppleRawMaxCapacity"] as? Int) ?? (batteryData["MaxCapacity"] as? Int)
        }

        var health: Int? = nil
        if let design = designCap, design > 0, let maximum = maxCap {
            health = Int((Double(maximum) / Double(design) * 100).rounded())
        }
        return (cycles, health)
    }
}
