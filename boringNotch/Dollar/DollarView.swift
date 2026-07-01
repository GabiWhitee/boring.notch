//
//  DollarView.swift
//  boringNotch
//
//  Home widget + settings for the Argentine dollar quote.
//

import Defaults
import SwiftUI

// MARK: - Home widget

struct DollarView: View {
    @ObservedObject private var dollar = DollarManager.shared

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "es_AR")
        return f
    }()

    private func money(_ value: Double) -> String {
        "$" + (Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "\(Int(value))")
    }

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
        .onAppear { dollar.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if let quote = dollar.quote {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
                Text(quote.type.shortLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(money(quote.sell))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Compra \(money(quote.buy))")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            }
        } else if dollar.isLoading {
            centered { ProgressView().controlSize(.small) }
        } else if let error = dollar.errorMessage {
            centered {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.yellow)
                    Text(error).font(.system(size: 10)).foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                }
            }
        } else {
            centered {
                Text("Sin datos").font(.system(size: 11)).foregroundStyle(.gray)
            }
        }
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack { Spacer(); content(); Spacer() }
            .frame(maxHeight: .infinity)
    }
}

// MARK: - Settings

struct DollarSettings: View {
    @ObservedObject private var dollar = DollarManager.shared

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showDollar) {
                    Text("Show dollar quote in Home")
                }
            } footer: {
                Text("Shows the Argentine dollar rate next to the music player when the notch is open. Source: dolarapi.com")
            }

            Section(header: Text("Quote")) {
                Picker("Type", selection: Binding(
                    get: { Defaults[.dollarType] },
                    set: { Defaults[.dollarType] = $0 }
                )) {
                    ForEach(DollarType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
            }

            Section {
                HStack {
                    Button("Refresh now") { dollar.refresh() }
                    Spacer()
                    if dollar.isLoading {
                        ProgressView().controlSize(.small)
                    } else if let quote = dollar.quote {
                        Text("\(quote.type.shortLabel): $\(Int(quote.sell))")
                            .foregroundStyle(.secondary)
                    } else if let error = dollar.errorMessage {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Dólar")
    }
}
