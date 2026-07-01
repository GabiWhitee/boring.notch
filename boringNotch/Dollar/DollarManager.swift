//
//  DollarManager.swift
//  boringNotch
//
//  Argentine dollar quotes via the free dolarapi.com API (no key).
//

import Combine
import Defaults
import Foundation
import SwiftUI

enum DollarType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case oficial
    case blue
    case bolsa
    case cripto
    case tarjeta
    case mayorista

    var id: String { rawValue }

    /// Path segment used by https://dolarapi.com/v1/dolares/<path>
    var apiPath: String { rawValue }

    var label: String {
        switch self {
        case .oficial: return "Dólar Oficial"
        case .blue: return "Dólar Blue"
        case .bolsa: return "Dólar MEP"
        case .cripto: return "Dólar Cripto"
        case .tarjeta: return "Dólar Tarjeta"
        case .mayorista: return "Dólar Mayorista"
        }
    }

    var shortLabel: String {
        switch self {
        case .oficial: return "Oficial"
        case .blue: return "Blue"
        case .bolsa: return "MEP"
        case .cripto: return "Cripto"
        case .tarjeta: return "Tarjeta"
        case .mayorista: return "Mayorista"
        }
    }
}

struct DollarQuote: Equatable {
    let type: DollarType
    let buy: Double
    let sell: Double
    let updated: Date?
}

final class DollarManager: ObservableObject {
    static let shared = DollarManager()

    @Published private(set) var quote: DollarQuote?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: AnyCancellable?
    private let refreshInterval: TimeInterval = 10 * 60

    private init() {
        Defaults.publisher(.dollarType)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        Defaults.publisher(.showDollar)
            .sink { [weak self] change in
                if change.newValue {
                    self?.startAutoRefresh()
                } else {
                    self?.stopAutoRefresh()
                }
            }
            .store(in: &cancellables)

        if Defaults[.showDollar] {
            startAutoRefresh()
        }
    }

    private func startAutoRefresh() {
        refresh()
        refreshTimer = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    private func stopAutoRefresh() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    func refresh() {
        guard Defaults[.showDollar] else {
            DispatchQueue.main.async {
                self.quote = nil
                self.errorMessage = nil
                self.isLoading = false
            }
            return
        }
        let type = Defaults[.dollarType]
        Task { await fetch(type: type) }
    }

    private func fetch(type: DollarType) async {
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }

        do {
            let url = URL(string: "https://dolarapi.com/v1/dolares/\(type.apiPath)")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(Response.self, from: data)

            let formatter = ISO8601DateFormatter()
            let date = decoded.fechaActualizacion.flatMap { formatter.date(from: $0) }

            let result = DollarQuote(
                type: type,
                buy: decoded.compra ?? 0,
                sell: decoded.venta ?? 0,
                updated: date
            )
            await MainActor.run {
                self.quote = result
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "No se pudo cargar la cotización"
                self.isLoading = false
            }
        }
    }

    private struct Response: Decodable {
        let compra: Double?
        let venta: Double?
        let fechaActualizacion: String?
    }
}
