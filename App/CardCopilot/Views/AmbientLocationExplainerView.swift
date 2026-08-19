import SwiftUI
import CardCopilotEngine

/// A deliberate pre-permission surface: the system prompt never has to explain the purpose on
/// its own, and the owner can decline without losing manual checkout.
/// When already authorized, it presents the active status, recent diagnostics, and options to manage in Settings.
struct AmbientLocationExplainerView: View {
    var isEnabled: Bool = false
    var diagnostics: SuppressionLog? = nil
    let onEnable: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isEnabled {
                    enabledContent
                } else {
                    unenabledContent
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Arrival alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
                    .font(.headline)
            }
        }
    }

    private var unenabledContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 24)

            VStack(alignment: .leading, spacing: 10) {
                Text("Get advice when you arrive")
                    .font(.title2.bold())
                Text("PickMe can recognize arrival at up to 20 merchants you have already saved, then suggest a card before you pay.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("Location is used only for arrival detection at your saved merchants.", systemImage: "location.fill")
                Label("It does not continuously track your route, and your location never leaves this phone.", systemImage: "lock.fill")
                Label("You can keep using manual checkout if you decline.", systemImage: "hand.tap.fill")
            }
            .font(.subheadline)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

            Button("Enable arrival alerts", action: onEnable)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

            Button("Not now", action: onDone)
                .frame(maxWidth: .infinity)
        }
    }

    private var enabledContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Arrival alerts are active")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.12), in: Capsule())
                .frame(maxWidth: .infinity, alignment: .center)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Arrival alerts enabled")
                    .font(.title2.bold())
                Text("PickMe is actively monitoring when you arrive at your saved merchants to suggest the best card before you pay.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                Label("Monitoring arrival at up to 20 saved merchants.", systemImage: "mappin.and.ellipse")
                Label("Your location is processed on-device and never leaves this phone.", systemImage: "lock.fill")
                Label("Battery-efficient geofencing with no continuous route tracking.", systemImage: "battery.100.bolt")
            }
            .font(.subheadline)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

            if let diagnostics {
                HStack(spacing: 14) {
                    Image(systemName: "bell.badge.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recent Activity (Last 7 Days)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("\(diagnostics.fired) alerts fired · \(diagnostics.suppressed) suppressed")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }

            VStack(spacing: 12) {
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: settingsUrl) {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape")
                            Text("Manage in iOS Settings")
                        }
                        .font(.subheadline)
                    }
                    .padding(.top, 4)

                    Text("To turn off arrival alerts or change location permissions, visit iPhone Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
