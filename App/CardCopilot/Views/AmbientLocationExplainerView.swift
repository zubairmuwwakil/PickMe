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
    var runtimeStatus: AmbientRuntimeStatus? = nil
    /// The owner's own switch threshold, needed only by the field-diagnostics section: the
    /// effective bar cannot be reported without the floors it is derived from. Optional because
    /// the wallet may not be set up yet, in which case there is no policy to describe.
    var ownerThreshold: SwitchThreshold? = nil
    var alertPolicy: AmbientAlertPolicy = .shipped
    var onAlertPolicyChange: (AmbientAlertPolicy) -> Void = { _ in }
    let onEnable: () -> Void
    var onTestNotification: () -> Void = {}
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
                        .fill(readinessColor.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Image(systemName: readinessIcon)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(readinessColor)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)

                HStack(spacing: 6) {
                    Circle()
                        .fill(readinessColor)
                        .frame(width: 8, height: 8)
                    Text(readinessTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(readinessColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(readinessColor.opacity(0.12), in: Capsule())
                .frame(maxWidth: .infinity, alignment: .center)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(runtimeStatus?.isReady == true ? "Arrival alerts ready" : "Arrival alerts need attention")
                    .font(.title2.bold())
                Text(readinessExplanation)
                    .foregroundStyle(.secondary)
            }

            if let runtimeStatus {
                deliveryReadinessCard(runtimeStatus)
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

            fieldDiagnosticsSection

            VStack(spacing: 12) {
                Button("Send test notification", action: onTestNotification)
                    .buttonStyle(.bordered)
                    .disabled(runtimeStatus?.notificationsAllowed == false)

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
    /// Empty outside a field-diagnostics build, so a release binary carries neither the controls
    /// nor the state they would need.
    @ViewBuilder
    var fieldDiagnosticsSection: some View {
        #if FIELD_DIAGNOSTICS
        if let ownerThreshold {
            AmbientDebugPolicySection(
                ownerThreshold: ownerThreshold,
                policy: Binding(get: { alertPolicy }, set: onAlertPolicyChange))
        }
        #else
        EmptyView()
        #endif
    }
}

private extension AmbientLocationExplainerView {
    var readinessColor: Color {
        guard let runtimeStatus else { return .blue }
        if runtimeStatus.hasSystemBlocker { return .orange }
        return runtimeStatus.monitoredRegionCount > 0 ? .green : .blue
    }

    var readinessIcon: String {
        guard let runtimeStatus else { return "location.circle" }
        if runtimeStatus.hasSystemBlocker { return "exclamationmark.triangle.fill" }
        return runtimeStatus.monitoredRegionCount > 0 ? "checkmark.circle.fill" : "location.magnifyingglass"
    }

    var readinessTitle: String {
        guard let runtimeStatus else { return "Checking arrival alerts" }
        if runtimeStatus.hasSystemBlocker { return "Arrival alerts need attention" }
        return runtimeStatus.monitoredRegionCount > 0 ? "Arrival alerts are active" : "Preparing monitored places"
    }

    var readinessExplanation: String {
        guard let runtimeStatus else { return "Checking permissions and monitored places…" }
        if !runtimeStatus.locationAlways {
            return "Always Location is required so iOS can wake PickMe when you arrive, even when the app is not open."
        }
        if !runtimeStatus.notificationsAllowed {
            return "Notifications are off. PickMe cannot show arrival advice until notifications are allowed in Settings."
        }
        if runtimeStatus.backgroundRefresh != .available {
            return "Background App Refresh is unavailable, so iOS may not wake PickMe for an arrival."
        }
        if runtimeStatus.monitoredRegionCount == 0 {
            return "Permissions are ready. PickMe is waiting for a location refresh to register nearby shopping areas."
        }
        return "PickMe is monitoring nearby shopping areas and can suggest a different card when the gain clears your threshold."
    }

    func deliveryReadinessCard(_ status: AmbientRuntimeStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DELIVERY READINESS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            readinessRow("Always Location", ready: status.locationAlways,
                         detail: status.locationAlways ? "Allowed" : "Required")
            readinessRow("Notifications", ready: status.notificationsAllowed,
                         detail: notificationDescription(status.notificationAuthorization))
            readinessRow("Background App Refresh", ready: status.backgroundRefresh == .available,
                         detail: backgroundRefreshDescription(status.backgroundRefresh))
            readinessRow("Monitored places", ready: status.monitoredRegionCount > 0,
                         detail: "\(status.monitoredRegionCount) registered")

            if let date = status.lastNotificationScheduledAt {
                Text("Last notification accepted by iOS: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let issue = status.latestIssue {
                Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    func readinessRow(_ title: String, ready: Bool, detail: String) -> some View {
        HStack {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ready ? .green : .orange)
            Text(title)
            Spacer()
            Text(detail).foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    func notificationDescription(_ state: AmbientNotificationAuthorization) -> String {
        switch state {
        case .allowed: return "Allowed"
        case .denied: return "Off"
        case .unknown: return "Not requested"
        }
    }

    func backgroundRefreshDescription(_ state: AmbientBackgroundRefreshState) -> String {
        switch state {
        case .available: return "Available"
        case .denied: return "Off"
        case .restricted: return "Restricted"
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
    /// Why an arrival did not interrupt, in the owner's terms — and what they got instead.
    ///
    /// Deliberately names the cause rather than the rule: the counters exist to be acted on, and
    /// "advantageBelowUnverifiedThreshold" tells an owner nothing they can act on. Since the gate
    /// gained delivery tiers, only `merchantMuted` means the owner saw nothing at all; the rest
    /// describe an arrival that was visible without being audible.
    var ownerFacingDescription: String {
        switch self {
        case .merchantConfidenceLow:
            return String(localized: "ambient.suppressed.unrecognised",
                          defaultValue: "the store could not be identified, so PickMe showed up without naming a card")
        case .recommendedDefaultCard:
            return String(localized: "ambient.suppressed.already-best",
                          defaultValue: "your usual card was already the best one, so PickMe confirmed it quietly")
        case .advantageBelowSwitchThreshold:
            return String(localized: "ambient.suppressed.below-threshold",
                          defaultValue: "the gain was below your switch threshold, so PickMe confirmed your card quietly")
        case .advantageBelowUnverifiedThreshold:
            return String(localized: "ambient.suppressed.below-unverified",
                          defaultValue: "the gain was below the higher bar for unconfirmed stores, so PickMe confirmed your card quietly")
        case .advantageBelowFrequentedThreshold:
            return String(localized: "ambient.suppressed.below-frequented",
                          defaultValue: "the gain was below your switch threshold at a store you shop at often, so PickMe confirmed your card quietly")
        case .advantageBelowCategoryThreshold:
            return String(localized: "ambient.suppressed.below-category",
                          defaultValue: "PickMe knew the kind of store but not which one, and the gain was below the higher bar that earns, so it confirmed your card quietly")
        case .merchantMuted:
            return String(localized: "ambient.suppressed.muted",
                          defaultValue: "you muted that store, so PickMe stayed out of the way entirely")
        }
    }
}
