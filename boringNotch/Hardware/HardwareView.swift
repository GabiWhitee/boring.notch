//
//  HardwareView.swift
//  boringNotch
//
//  "Hardware" notch tab: battery detail, Wi-Fi, uptime, per-core CPU.
//

import Defaults
import SwiftUI

// MARK: - Notch tab

struct HardwareView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var hw = HardwareStatsManager.shared
    @ObservedObject private var battery = BatteryStatusViewModel.shared

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    batteryCard
                    Color.clear.frame(width: vm.closedNotchSize.width + 24)
                    wifiUptimeCard
                }
                coresCard
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .secondarySystemFill).opacity(0.3))
            )
    }

    // MARK: Battery

    private var batteryLevel: Int { Int(battery.levelBattery) }

    private var batteryColor: Color {
        if battery.isCharging || battery.isPluggedIn { return .green }
        switch batteryLevel {
        case ..<20: return .red
        case ..<40: return .yellow
        default: return .green
        }
    }

    private var batteryTimeText: String {
        if battery.isCharging {
            return battery.timeToFullCharge > 0 ? "\(formatMinutes(battery.timeToFullCharge)) to full" : "Charging"
        } else if battery.isPluggedIn {
            return "Plugged in"
        } else {
            return battery.timeToDischarge > 0 ? "\(formatMinutes(battery.timeToDischarge)) left" : "—"
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }

    private var batteryCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: battery.isCharging ? "battery.100.bolt" : "battery.100")
                        .font(.system(size: 11)).foregroundStyle(batteryColor)
                    Text("Battery").font(.system(size: 11, weight: .semibold)).foregroundStyle(.gray)
                    Spacer(minLength: 0)
                    Text("\(batteryLevel)%").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
                ProgressView(value: Double(batteryLevel) / 100)
                    .tint(batteryColor)
                    .scaleEffect(x: 1, y: 0.7, anchor: .center)
                HStack(spacing: 12) {
                    if let health = hw.batteryHealthPercent {
                        detail(icon: "heart.fill", text: "\(health)%")
                    }
                    if let cycles = hw.batteryCycleCount {
                        detail(icon: "arrow.triangle.2.circlepath", text: "\(cycles)")
                    }
                    Spacer(minLength: 0)
                }
                Text(batteryTimeText).font(.system(size: 10)).foregroundStyle(.gray)
            }
        }
    }

    private func detail(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9)).foregroundStyle(.gray)
            Text(text).font(.system(size: 10)).foregroundStyle(.white)
        }
    }

    // MARK: Wi-Fi + Uptime

    private var wifiUptimeCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "wifi").font(.system(size: 12)).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hw.wifiSSID ?? "Wi-Fi")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                        if let rssi = hw.wifiRSSI {
                            HStack(spacing: 5) {
                                signalBars(HardwareStatsManager.wifiBars(for: rssi))
                                Text("\(rssi) dBm").font(.system(size: 9)).foregroundStyle(.gray)
                            }
                        } else {
                            Text("Not connected").font(.system(size: 9)).foregroundStyle(.gray)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Divider().overlay(Color.white.opacity(0.1))
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.system(size: 11)).foregroundStyle(.orange)
                    Text("Uptime").font(.system(size: 11, weight: .semibold)).foregroundStyle(.gray)
                    Spacer(minLength: 0)
                    Text(hw.uptimeText).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                }
            }
        }
    }

    private func signalBars(_ level: Int) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < level ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 3, height: CGFloat(4 + index * 3))
            }
        }
    }

    // MARK: Per-core CPU

    private func coreColor(_ usage: Double) -> Color {
        switch usage {
        case ..<0.5: return .green
        case ..<0.8: return .yellow
        default: return .red
        }
    }

    private var coresCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "cpu").font(.system(size: 11)).foregroundStyle(.green)
                    Text("CPU cores").font(.system(size: 11, weight: .semibold)).foregroundStyle(.gray)
                    Spacer(minLength: 0)
                    if !hw.perCoreUsage.isEmpty {
                        Text("\(hw.perCoreUsage.count)").font(.system(size: 10)).foregroundStyle(.gray)
                    }
                }
                if hw.perCoreUsage.isEmpty {
                    Text("Reading…").font(.system(size: 10)).foregroundStyle(.gray)
                } else {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(hw.perCoreUsage) { core in
                            GeometryReader { geo in
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(coreColor(core.usage))
                                        .frame(height: max(2, geo.size.height * core.usage))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.15))
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Settings

struct HardwareSettings: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableHardwareTab) {
                    Text("Show Hardware tab")
                }
            } footer: {
                Text("Adds a tab with battery health, Wi-Fi, uptime and per-core CPU.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Hardware")
    }
}
