//
//  SystemView.swift
//  boringNotch
//
//  "System" notch tab: live CPU / memory / network / disk + Bluetooth battery.
//

import Defaults
import SwiftUI

// MARK: - Notch tab

struct SystemView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var stats = SystemStatsManager.shared
    @ObservedObject private var bluetooth = BluetoothBatteryManager.shared

    @Default(.systemShowCPU) private var showCPU
    @Default(.systemShowMemory) private var showMemory
    @Default(.systemShowNetwork) private var showNetwork
    @Default(.systemShowDisk) private var showDisk
    @Default(.systemShowBluetooth) private var showBluetooth

    private var diskUsedFraction: Double {
        stats.diskTotalBytes > 0 ? 1 - Double(stats.diskFreeBytes) / Double(stats.diskTotalBytes) : 0
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 8) {
                // Two wide cards with a gap in the middle so the physical camera
                // notch doesn't cover them (left of notch / right of notch).
                HStack(alignment: .top, spacing: 8) {
                    metricsCard {
                        if showCPU {
                            metricRow(icon: "cpu", label: "CPU",
                                      value: percentText(stats.cpuUsage),
                                      progress: stats.cpuUsage, color: .green)
                        }
                        if showMemory {
                            metricRow(icon: "memorychip", label: "RAM",
                                      value: percentText(stats.memoryUsage),
                                      progress: stats.memoryUsage, color: .blue)
                        }
                    }

                    Color.clear.frame(width: vm.closedNotchSize.width + 24)

                    metricsCard {
                        if showDisk {
                            metricRow(icon: "internaldrive", label: "Disk",
                                      value: "\(SystemStatsManager.formatBytes(stats.diskFreeBytes)) free",
                                      progress: diskUsedFraction, color: .orange)
                        }
                        if showNetwork {
                            networkRow
                        }
                    }
                }

                if showMemory {
                    topMemoryCard
                }

                if showBluetooth && !bluetooth.devices.isEmpty {
                    bluetoothCard
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func percentText(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    // MARK: Metric cards

    private func metricsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 8) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .secondarySystemFill).opacity(0.3))
        )
    }

    private func metricRow(icon: String, label: String, value: String, progress: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(color).frame(width: 16)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.gray)
                    .fixedSize()
                Spacer(minLength: 6)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
            ProgressView(value: min(max(progress, 0), 1))
                .tint(color)
                .scaleEffect(x: 1, y: 0.7, anchor: .center)
        }
    }

    private var networkRow: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "network").font(.system(size: 11)).foregroundStyle(.purple).frame(width: 16)
                Text("Net")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.gray)
                    .fixedSize()
                Spacer(minLength: 6)
                HStack(spacing: 8) {
                    Label(SystemStatsManager.formatSpeed(stats.networkDownBytesPerSec), systemImage: "arrow.down")
                    Label(SystemStatsManager.formatSpeed(stats.networkUpBytesPerSec), systemImage: "arrow.up")
                }
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
            }
            // Keep the same height as the other rows for visual balance.
            Color.clear.frame(height: 4)
        }
    }

    // MARK: Top memory

    private var topMemoryCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.fill").font(.system(size: 11)).foregroundStyle(.blue)
                Text("Top RAM").font(.system(size: 11, weight: .semibold)).foregroundStyle(.gray)
                Spacer(minLength: 0)
                Text("\(SystemStatsManager.formatBytes(Int64(stats.memoryUsedBytes))) / \(SystemStatsManager.formatBytes(Int64(stats.memoryTotalBytes)))")
                    .font(.system(size: 10)).foregroundStyle(.gray)
            }
            if stats.topMemoryProcesses.isEmpty {
                Text("Reading…").font(.system(size: 10)).foregroundStyle(.gray)
            } else {
                let maxMB = stats.topMemoryProcesses.map(\.megabytes).max() ?? 1
                ForEach(stats.topMemoryProcesses) { proc in
                    HStack(spacing: 8) {
                        Text(proc.name)
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: 150, alignment: .leading)
                        GeometryReader { geo in
                            Capsule()
                                .fill(Color.blue.opacity(0.6))
                                .frame(width: max(3, geo.size.width * (proc.megabytes / maxMB)))
                                .frame(maxHeight: .infinity, alignment: .leading)
                        }
                        .frame(height: 6)
                        Text(proc.formatted)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.gray)
                            .monospacedDigit()
                            .frame(width: 54, alignment: .trailing)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .secondarySystemFill).opacity(0.3))
        )
    }

    // MARK: Bluetooth

    private var bluetoothCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "wave.3.right.circle").font(.system(size: 11)).foregroundStyle(.cyan)
                Text("Bluetooth").font(.system(size: 11, weight: .semibold)).foregroundStyle(.gray)
            }
            ForEach(bluetooth.devices) { device in
                HStack(spacing: 6) {
                    Image(systemName: device.symbol).font(.system(size: 11)).foregroundStyle(.white)
                    Text(device.name)
                        .font(.system(size: 11)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 0)
                    if let level = device.primaryLevel {
                        Text("\(level)%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(batteryColor(level))
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .secondarySystemFill).opacity(0.3))
        )
    }

    private func batteryColor(_ level: Int) -> Color {
        switch level {
        case ..<20: return .red
        case ..<40: return .yellow
        default: return .green
        }
    }
}

// MARK: - Settings

struct SystemSettings: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableSystemStats) {
                    Text("Show System tab")
                }
            } footer: {
                Text("Adds a tab with live system stats to the open notch.")
            }

            Section(header: Text("Indicators")) {
                Defaults.Toggle(key: .systemShowCPU) { Text("CPU usage") }
                Defaults.Toggle(key: .systemShowMemory) { Text("Memory usage") }
                Defaults.Toggle(key: .systemShowNetwork) { Text("Network speed") }
                Defaults.Toggle(key: .systemShowDisk) { Text("Disk space") }
                Defaults.Toggle(key: .systemShowBluetooth) { Text("Bluetooth battery") }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("System")
    }
}
