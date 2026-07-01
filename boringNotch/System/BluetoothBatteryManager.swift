//
//  BluetoothBatteryManager.swift
//  boringNotch
//
//  Battery levels of connected Bluetooth devices (AirPods, mouse, keyboard).
//  Uses `system_profiler SPBluetoothDataType -json` and parses defensively,
//  since the exact JSON shape varies between macOS versions.
//

import Combine
import Defaults
import Foundation

struct BluetoothDevice: Identifiable, Equatable {
    let id = UUID()
    let name: String
    /// Single battery percentage for simple devices (mouse/keyboard).
    let main: Int?
    /// Split batteries for earbuds.
    let left: Int?
    let right: Int?
    let caseLevel: Int?

    static func == (lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool {
        lhs.name == rhs.name && lhs.main == rhs.main && lhs.left == rhs.left
            && lhs.right == rhs.right && lhs.caseLevel == rhs.caseLevel
    }

    /// A representative level for compact display (lowest known reading).
    var primaryLevel: Int? {
        let levels = [main, left, right].compactMap { $0 }
        return levels.min()
    }

    var symbol: String {
        if left != nil || right != nil { return "airpods" }
        return "keyboard.badge.ellipsis"
    }
}

final class BluetoothBatteryManager: ObservableObject {
    static let shared = BluetoothBatteryManager()

    @Published private(set) var devices: [BluetoothDevice] = []
    @Published private(set) var isLoading = false

    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private let refreshInterval: TimeInterval = 60

    private init() {
        Defaults.publisher(.systemShowBluetooth)
            .sink { [weak self] change in
                if change.newValue { self?.start() } else { self?.stop() }
            }
            .store(in: &cancellables)

        // Only poll when the System tab feature is on as well.
        Defaults.publisher(.enableSystemStats)
            .sink { [weak self] change in
                if change.newValue && Defaults[.systemShowBluetooth] {
                    self?.start()
                } else if !change.newValue {
                    self?.stop()
                }
            }
            .store(in: &cancellables)

        if Defaults[.enableSystemStats] && Defaults[.systemShowBluetooth] {
            start()
        }
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func refresh() {
        DispatchQueue.main.async { self.isLoading = true }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let parsed = self?.fetchDevices() ?? []
            DispatchQueue.main.async {
                self?.devices = parsed
                self?.isLoading = false
            }
        }
    }

    // MARK: - system_profiler

    private func fetchDevices() -> [BluetoothDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
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

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let bt = json["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }

        var results: [BluetoothDevice] = []
        for section in bt {
            guard let connected = section["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    guard let props = value as? [String: Any] else { continue }
                    let device = BluetoothDevice(
                        name: name,
                        main: percent(props["device_batteryLevelMain"]),
                        left: percent(props["device_batteryLevelLeft"]),
                        right: percent(props["device_batteryLevelRight"]),
                        caseLevel: percent(props["device_batteryLevelCase"])
                    )
                    // Only keep devices that report at least one battery reading.
                    if device.main != nil || device.left != nil || device.right != nil || device.caseLevel != nil {
                        results.append(device)
                    }
                }
            }
        }
        return results.sorted { $0.name < $1.name }
    }

    /// Parses values like "80%" (or 80) into an Int percentage.
    private func percent(_ raw: Any?) -> Int? {
        if let intValue = raw as? Int { return intValue }
        guard let string = raw as? String else { return nil }
        let digits = string.filter { $0.isNumber }
        return Int(digits)
    }
}
