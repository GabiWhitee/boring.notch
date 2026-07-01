//
//  WeatherView.swift
//  boringNotch
//
//  Compact weather widget shown in the open-notch Home view + its settings.
//

import Defaults
import SwiftUI

// MARK: - Home widget

struct WeatherView: View {
    @ObservedObject private var weather = WeatherManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .secondarySystemFill).opacity(0.35))
        )
        .onAppear { weather.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if let info = weather.info {
            HStack(spacing: 10) {
                Image(systemName: info.symbol)
                    .font(.system(size: 26))
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.formattedTemperature)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(info.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                }
            }
            Text(info.cityName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.gray)
                .lineLimit(1)
        } else if weather.isLoading {
            centeredMessage {
                ProgressView()
                    .controlSize(.small)
            }
        } else if let error = weather.errorMessage {
            centeredMessage {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                }
            }
        } else {
            centeredMessage {
                VStack(spacing: 4) {
                    Image(systemName: "location.slash")
                        .foregroundStyle(.gray)
                    Text("Set a city in Settings")
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func centeredMessage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Spacer()
            content()
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Settings

struct WeatherSettings: View {
    @ObservedObject private var weather = WeatherManager.shared
    @Default(.weatherCity) var city

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showWeather) {
                    Text("Show weather in Home")
                }
            } footer: {
                Text("Displays current conditions next to the music player when the notch is open.")
            }

            Section(header: Text("Location")) {
                TextField("City", text: $city, prompt: Text("e.g. Buenos Aires"))
                    .textFieldStyle(.roundedBorder)
                Picker("Units", selection: Binding(
                    get: { Defaults[.weatherUseCelsius] },
                    set: { Defaults[.weatherUseCelsius] = $0 }
                )) {
                    Text("Celsius (°C)").tag(true)
                    Text("Fahrenheit (°F)").tag(false)
                }
                .pickerStyle(.segmented)
            }

            Section {
                HStack {
                    Button("Refresh now") {
                        weather.refresh()
                    }
                    Spacer()
                    if weather.isLoading {
                        ProgressView().controlSize(.small)
                    } else if let info = weather.info {
                        Text("\(info.cityName) · \(info.formattedTemperature)")
                            .foregroundStyle(.secondary)
                    } else if let error = weather.errorMessage {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Weather")
    }
}
