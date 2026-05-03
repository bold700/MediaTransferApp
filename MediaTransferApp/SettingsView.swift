import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private let appBlue = Color(red: 0, green: 0.478, blue: 1.0)
    private let privacyURL = URL(string: "https://bold700.com/privacy")!
    private let supportURL = URL(string: "mailto:support@bold700.com")!
    // TODO: vervang door je echte App Store ID na publicatie van 1.3.0
    private let appStoreReviewURL = URL(string: "itms-apps://itunes.apple.com/app/id6741049924?action=write-review")!

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statRow(icon: "photo.on.rectangle.angled",
                            label: "Items transferred",
                            value: "\(UserStats.totalItems)")
                    statRow(icon: "arrow.right.circle",
                            label: "Transfers completed",
                            value: "\(UserStats.totalTransfers)")
                } header: {
                    Text("Your activity")
                }

                Section {
                    Link(destination: privacyURL) {
                        Label("Privacy Policy", systemImage: "lock.shield")
                    }
                    Link(destination: supportURL) {
                        Label("Contact Support", systemImage: "envelope")
                    }
                    Link(destination: appStoreReviewURL) {
                        Label("Rate this App", systemImage: "star")
                    }
                } header: {
                    Text("Support")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Made by")
                        Spacer()
                        Text("BOLD700")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func statRow(icon: String, label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(appBlue)
                .frame(width: 24)
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }
}

#Preview {
    SettingsView()
}
