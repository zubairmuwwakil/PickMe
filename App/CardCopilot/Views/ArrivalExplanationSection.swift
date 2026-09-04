import CardCopilotEngine
import CardCopilotStore
import SwiftUI

/// Current blockers are separate from historical outcomes: today's settings cannot explain a
/// past event, and being inside a monitored plaza does not establish which merchant was visited.
struct ArrivalExplanationSection: View {
    let model: ArrivalPlacesModel
    let merchant: NearbyPlace

    var body: some View {
        Section {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Right now").font(.subheadline.bold())
                    ForEach(currentConditions, id: \.self) { Text($0) }

                    if model.runtimeStatus.hasSystemBlocker,
                       let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open iPhone Settings", destination: url)
                    }
                    if merchant.hasMonitorableLocation, model.runtimeStatus.locationAlways,
                       !model.isMonitoring(merchant) {
                        Button("Refresh nearby monitoring") { model.refreshNearby() }
                    }

                    Divider()
                    if !merchant.hasMonitorableLocation {
                        Text("Choose a specific branch from the monitored areas or search results to see its arrival checks.")
                    } else if let match = model.latestArrivalExplanation(for: merchant) {
                        Text(match.isExactMerchant ? "Last check for this store" : "Last check in this shopping area")
                            .font(.subheadline.bold())
                        Text(match.record.recordedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                        if match.isExactMerchant {
                            Text(outcomeExplanation(match.record))
                            if match.record.activity != .notRequested {
                                Text(activityExplanation(match.record.activity))
                            }
                            if match.record.activity == .disabled,
                               let url = URL(string: UIApplication.openSettingsURLString) {
                                Link("Manage Live Activities in Settings", destination: url)
                            }
                        } else {
                            Text(areaExplanation(match.record))
                        }
                    } else {
                        Text("No recent arrival check recorded").font(.subheadline.bold())
                        Text("PickMe has no retained arrival check for this branch or its current monitored area. It cannot tell whether iOS missed an arrival, the place was outside coverage, or the explanation expired or was cleared.")
                    }
                    Text("Current conditions describe now. The last check describes that attempt only, and does not confirm a purchase or every later visit.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.vertical, 8)
            } label: {
                Label("Why didn't I get an alert?", systemImage: "questionmark.circle")
            }
        } footer: {
            Text("Only the latest check per place is kept, for up to seven days, on this iPhone.")
        }
    }

    private var currentConditions: [String] {
        guard merchant.hasMonitorableLocation else {
            return [String(localized: "This choice applies to a merchant, without a specific branch to check.")]
        }
        var issues: [String] = []
        if let preference = model.preference(for: merchant) {
            if preference.scope == .disabled {
                issues.append(String(localized: "Arrival advice is off for this merchant. Change the alert choice below and save to enable it."))
            } else if preference.scope == .exactLocation,
                      !preference.matchesLocation(identifier: merchant.id, latitude: merchant.latitude, longitude: merchant.longitude) {
                issues.append(String(localized: "Your alert choice allows a different branch only. Choose this location below and save if you want to switch."))
            }
        }
        if model.isMuted(merchant) {
            issues.append(String(localized: "This location is muted from a notification. Save an enabled alert choice below to unmute it."))
        }
        if !model.runtimeStatus.locationAlways {
            issues.append(String(localized: "Always Location is not enabled, so PickMe cannot monitor background arrivals."))
        }
        if !model.runtimeStatus.notificationsAllowed {
            issues.append(String(localized: "Notifications are not allowed. Enable them to receive arrival alerts."))
        }
        if model.runtimeStatus.backgroundRefresh != .available {
            issues.append(String(localized: "Background App Refresh is unavailable, which can prevent iOS from waking PickMe."))
        }
        if issues.isEmpty {
            if model.isMonitoring(merchant) {
                issues.append(String(localized: "This place is covered by a registered area and the arrival permissions are ready. iOS still needs to report an arrival before PickMe can evaluate it."))
            } else {
                issues.append(String(localized: "This place is outside the currently registered areas. Nearby places share 20 slots; saving a merchant does not reserve one."))
            }
        }
        return issues
    }

    private func outcomeExplanation(_ record: ArrivalExplanationRecord) -> String {
        switch record.outcome {
        case .checking:
            return String(localized: "An arrival check started, but no completed result has been recorded. The exact cause is unknown.")
        case .unresolved:
            return String(localized: "PickMe could not identify the store, so it could not request a card alert.")
        case .noRecommendation:
            return String(localized: "PickMe evaluated this place but could not produce a card recommendation. Check your wallet setup or try a manual checkout.")
        case .notificationAccepted:
            if record.notificationPermission == .blocked {
                return String(localized: "iOS accepted the request, but notifications were not allowed for PickMe at that time. An accepted request alone does not mean a notification appeared.")
            }
            if record.notificationPermission == .quiet {
                return String(localized: "iOS accepted the request with provisional notification permission, which allows quiet delivery. PickMe cannot confirm whether it was displayed or seen.")
            }
            return String(localized: "iOS accepted the arrival notification request. That does not confirm it was displayed or seen. Check Focus and notification delivery settings if it did not appear.")
        case .notificationFailed:
            return String(localized: "A card alert qualified, but the notification request failed. PickMe did not record successful delivery.")
        case .evaluated:
            let reasons = Set(record.reasons)
            if reasons.contains(.merchantMuted) {
                return String(localized: "The merchant was muted or excluded by your alert choice at the time of this check, so PickMe requested no arrival advice.")
            }
            if reasons.contains(.merchantConfidenceLow) {
                return String(localized: "PickMe did not have enough category or merchant evidence to name a card confidently, so no interrupting alert was requested.")
            }
            if reasons.contains(.recommendedDefaultCard) {
                return String(localized: "Your default card was already the recommended card. PickMe chose quiet advice instead of an interrupting alert.")
            }
            if reasons.contains(.advantageBelowUnverifiedThreshold) || reasons.contains(.advantageBelowCategoryThreshold) {
                return String(localized: "The estimated gain did not meet the threshold used for uncertain merchant or category evidence at that time. PickMe chose quiet advice.")
            }
            if reasons.contains(.advantageBelowSwitchThreshold) || reasons.contains(.advantageBelowFrequentedThreshold) {
                return String(localized: "The estimated gain did not meet the switch threshold in use at that time. PickMe chose quiet advice.")
            }
            return String(localized: "The arrival was evaluated without an interrupting alert. No more specific reason was recorded.")
        }
    }

    private func areaExplanation(_ record: ArrivalExplanationRecord) -> String {
        switch record.outcome {
        case .checking:
            return String(localized: "A check started in this shopping area, but no completed result was recorded. This does not establish an arrival at this store.")
        case .unresolved:
            return String(localized: "PickMe received an arrival for this shopping area but could not identify a store. That check cannot be attributed to this branch.")
        default:
            return String(localized: "The latest check in this shopping area was attributed to another store. It cannot explain an alert for this branch or confirm that you visited it.")
        }
    }

    private func activityExplanation(_ activity: LiveActivityRequestOutcome) -> String {
        switch activity {
        case .notRequested: return ""
        case .accepted:
            return String(localized: "iOS accepted the Lock Screen card request. PickMe cannot confirm whether you saw it.")
        case .disabled:
            return String(localized: "Live Activities were disabled at that time, so the quiet Lock Screen card could not appear.")
        case .dismissed:
            return String(localized: "The Lock Screen card had been dismissed during this visit. PickMe respected that choice and did not bring it back.")
        case .failed:
            return String(localized: "The Lock Screen card could not be started. No more specific cause was recorded.")
        }
    }
}
