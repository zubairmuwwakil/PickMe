import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// A deliberate pre-permission surface: the system prompt never has to explain the purpose on
/// its own, and the owner can decline without losing manual checkout.
/// When already authorized, it presents the active status, recent diagnostics, and options to manage in Settings.
struct AmbientLocationExplainerView: View {
    var isEnabled: Bool = false
    var diagnostics: SuppressionLog? = nil
    /// Deliberately a second parameter rather than fields folded into `diagnostics`. The two logs
    /// answer different questions — "what did the gate decide" versus "what never reached it" —
    /// and merging them would let a healthy gate hide an unhealthy budget.
    var coverage: AmbientCoverageLog? = nil
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

                        // The per-reason counters were always recorded and never shown, so
                        // "suppressed: 41" was unreadable — a silence with no stated cause looks
                        // identical to a bug. Each reason names a different fix: an unrecognised
                        // store is the app's problem, a threshold is a setting, a mute was a
                        // choice.
                        ForEach(diagnostics.suppressedByReason.sorted { $0.value > $1.value },
                                id: \.key) { reason, count in
                            Text("\(count) · \(reason.ownerFacingDescription)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }

            if let coverage, coverage.rotations > 0 || coverage.arrivals > 0 {
                coverageCard(coverage)
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

extension AmbientLocationExplainerView {
    /// The other half of the diagnostics, and the half that was missing.
    ///
    /// The suppression counters above describe arrivals that reached the gate. iOS monitors 20
    /// regions app-wide, and nothing recorded what fell off the end of that list — so a merchant
    /// that quietly lost its slot looked identical to one that never had a purchase worth
    /// mentioning. This card is what makes the difference visible.
    @ViewBuilder
    func coverageCard(_ coverage: AmbientCoverageLog) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "mappin.slash")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Coverage (Last 7 Days)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                if coverage.rotations > 0 {
                    Text("\(coverage.rotationsAtCapacity) of \(coverage.rotations) checks used all 20 places")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                // The eviction breakdown is the point. "20 places were dropped" says nothing on
                // its own — dropping plazas the owner has never entered costs nothing, and
                // dropping the shop they visit weekly costs the whole feature.
                ForEach(coverage.evictedByTier.sorted { $0.value > $1.value }, id: \.key) { tier, count in
                    Text("\(count) · \(tier.ownerFacingEvictionDescription)")
                        .font(.caption)
                        .foregroundStyle(tier.carriesStanding ? .orange : .secondary)
                }

                if coverage.arrivals > 0 {
                    Text("\(coverage.arrivals) arrivals · \(coverage.arrivalsReachingTheGate) evaluated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    if coverage.arrivalsUnresolved > 0 {
                        Text("\(coverage.arrivalsUnresolved) · could not tell which store it was")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if coverage.arrivalsNotAdvised > 0 {
                        Text("\(coverage.arrivalsNotAdvised) · no card advice was available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

extension AmbientRegionTier {
    /// What losing a slot cost, in the owner's terms. Names the evidence that was dropped rather
    /// than the tier, for the same reason `AmbientSuppressionReason` names the cause rather than
    /// the rule.
    var ownerFacingEvictionDescription: String {
        switch self {
        case .frequentedMerchant:
            return String(localized: "ambient.coverage.dropped-frequented",
                          defaultValue: "dropped a store you shop at often")
        case .confirmedMerchant:
            return String(localized: "ambient.coverage.dropped-confirmed",
                          defaultValue: "dropped a store you confirmed")
        case .savedMerchant:
            return String(localized: "ambient.coverage.dropped-saved",
                          defaultValue: "dropped a store you saved")
        case .discoveredArea:
            return String(localized: "ambient.coverage.dropped-area",
                          defaultValue: "dropped a nearby shopping area")
        }
    }
}

extension AmbientSuppressionReason {
    /// Why an arrival stayed silent, in the owner's terms. Deliberately names the cause rather
    /// than the rule: the counters exist to be acted on, and "advantageBelowUnverifiedThreshold"
    /// tells an owner nothing they can act on.
    var ownerFacingDescription: String {
        switch self {
        case .merchantConfidenceLow:
            return String(localized: "ambient.suppressed.unrecognised",
                          defaultValue: "the store could not be identified")
        case .recommendedDefaultCard:
            return String(localized: "ambient.suppressed.already-best",
                          defaultValue: "your usual card was already the best one")
        case .advantageBelowSwitchThreshold:
            return String(localized: "ambient.suppressed.below-threshold",
                          defaultValue: "the gain was below your switch threshold")
        case .advantageBelowUnverifiedThreshold:
            return String(localized: "ambient.suppressed.below-unverified",
                          defaultValue: "the gain was below the higher bar for unconfirmed stores")
        case .advantageBelowFrequentedThreshold:
            return String(localized: "ambient.suppressed.below-frequented",
                          defaultValue: "the gain was below your switch threshold at a store you shop at often")
        case .merchantMuted:
            return String(localized: "ambient.suppressed.muted",
                          defaultValue: "you muted that store")
        }
    }
}
