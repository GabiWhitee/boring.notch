//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

/// The tabs available in the open notch, built from the currently enabled features.
var availableTabs: [TabModel] {
    var result: [TabModel] = [
        TabModel(label: "Home", icon: "house.fill", view: .home)
    ]
    if Defaults[.enableCalendarTab] {
        result.append(TabModel(label: "Calendar", icon: "calendar", view: .calendar))
    }
    if Defaults[.boringShelf] {
        result.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
    }
    if Defaults[.enablePomodoro] {
        result.append(TabModel(label: "Timer", icon: "timer", view: .pomodoro))
    }
    if Defaults[.enableSystemStats] {
        result.append(TabModel(label: "System", icon: "gauge.with.dots.needle.67percent", view: .system))
    }
    if Defaults[.enableHardwareTab] {
        result.append(TabModel(label: "Hardware", icon: "laptopcomputer", view: .hardware))
    }
    return result
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.boringShelf) var boringShelf
    @Default(.enablePomodoro) var enablePomodoro
    @Default(.enableSystemStats) var enableSystemStats
    @Default(.enableCalendarTab) var enableCalendarTab
    @Default(.enableHardwareTab) var enableHardwareTab
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(availableTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
