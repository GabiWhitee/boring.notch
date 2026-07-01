//
//  WeatherManager.swift
//  boringNotch
//
//  Lightweight weather widget backed by the free Open-Meteo API
//  (no API key, no system location permission — city is set manually).
//

import Combine
import Defaults
import Foundation
import SwiftUI

struct WeatherInfo: Equatable {
    let temperature: Double
    let weatherCode: Int
    let cityName: String
    let isCelsius: Bool

    var symbol: String { WeatherManager.symbol(for: weatherCode) }
    var summary: String { WeatherManager.summary(for: weatherCode) }

    var formattedTemperature: String {
        "\(Int(temperature.rounded()))°\(isCelsius ? "C" : "F")"
    }
}

final class WeatherManager: ObservableObject {
    static let shared = WeatherManager()

    @Published private(set) var info: WeatherInfo?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: AnyCancellable?
    private let refreshInterval: TimeInterval = 15 * 60

    private init() {
        // Refresh when the city text settles.
        Defaults.publisher(.weatherCity)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // Refresh immediately when the unit changes.
        Defaults.publisher(.weatherUseCelsius)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // Start/stop the periodic refresh with the feature toggle.
        Defaults.publisher(.showWeather)
            .sink { [weak self] change in
                if change.newValue {
                    self?.startAutoRefresh()
                } else {
                    self?.stopAutoRefresh()
                }
            }
            .store(in: &cancellables)

        if Defaults[.showWeather] {
            startAutoRefresh()
        }
    }

    // MARK: - Refresh lifecycle

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
        let city = Defaults[.weatherCity].trimmingCharacters(in: .whitespacesAndNewlines)
        guard Defaults[.showWeather], !city.isEmpty else {
            DispatchQueue.main.async {
                self.info = nil
                self.errorMessage = nil
                self.isLoading = false
            }
            return
        }
        Task { await fetch(city: city, celsius: Defaults[.weatherUseCelsius]) }
    }

    // MARK: - Networking

    private func fetch(city: String, celsius: Bool) async {
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }

        do {
            guard let place = try await geocode(city: city) else {
                await MainActor.run {
                    self.info = nil
                    self.errorMessage = "City not found"
                    self.isLoading = false
                }
                return
            }

            let current = try await fetchCurrent(
                latitude: place.latitude,
                longitude: place.longitude,
                celsius: celsius
            )

            let resolved = WeatherInfo(
                temperature: current.temperature,
                weatherCode: current.weatherCode,
                cityName: place.displayName,
                isCelsius: celsius
            )

            await MainActor.run {
                self.info = resolved
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Couldn't load weather"
                self.isLoading = false
            }
        }
    }

    private struct GeocodePlace {
        let latitude: Double
        let longitude: Double
        let displayName: String
    }

    private func geocode(city: String) async throws -> GeocodePlace? {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let decoded = try JSONDecoder().decode(GeocodeResponse.self, from: data)
        guard let first = decoded.results?.first else { return nil }
        let name = [first.name, first.admin1, first.country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .first ?? first.name
        return GeocodePlace(latitude: first.latitude, longitude: first.longitude, displayName: name)
    }

    private func fetchCurrent(latitude: Double, longitude: Double, celsius: Bool) async throws -> (temperature: Double, weatherCode: Int) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "temperature_unit", value: celsius ? "celsius" : "fahrenheit")
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let decoded = try JSONDecoder().decode(ForecastResponse.self, from: data)
        return (decoded.current.temperature_2m, decoded.current.weather_code)
    }

    // MARK: - Decodable models

    private struct GeocodeResponse: Decodable {
        let results: [GeocodeResult]?
    }

    private struct GeocodeResult: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let admin1: String?
    }

    private struct ForecastResponse: Decodable {
        let current: Current
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
        }
    }

    // MARK: - WMO weather code mapping

    static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1: return "sun.max.fill"
        case 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func summary(for code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm"
        default: return "—"
        }
    }
}
