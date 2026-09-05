import SwiftUI
import CardCopilotEngine
import CardCopilotStore

#if FIELD_DIAGNOSTICS
/// The alert dials, and the bar they actually produce.
///
/// This exists because the shipped bar for drugstore arrivals was 2.0pp when the threshold said
/// 1.0pp, and nobody chose that. It fell out of `minAdvantageCad × multiplier ÷ estimate` and no
/// screen ever showed it. Every number on this page is derived from the same functions the gate
/// uses, so the two cannot drift.
///
/// Compiled only where `FIELD_DIAGNOSTICS` is defined. It is a field instrument, not a hidden
/// owner setting — the right threshold is what the engagement data says, and a dial the owner can
/// find would make that data describe nothing in particular.
///
/// Plain string literals throughout, deliberately: the string catalogue is for text the owner is
/// meant to read, and putting a debug dial in it would ask a translator to translate a lab bench.
struct AmbientDebugPolicySection: View {
    let ownerThreshold: SwitchThreshold
    @Binding var policy: AmbientAlertPolicy
    var fieldLogRecordCount: Int = 0
    /// The shipping counters, shown here rather than on a screen of their own.
    ///
    /// Counters and records answer different questions — how often, versus what happened that
    /// time — and neither is derived from the other, but they are read together, so they belong
    /// on one page.
    var radarMetrics: NearbyLookupMetrics = NearbyLookupMetrics()
    var coverage: AmbientCoverageLog? = nil
    /// Persists before this fires. The caller cancels any in-flight lookup and forces a fresh scan,
    /// so the next record cannot carry results from the previous radius.
    var onRadarRadiusChange: (Double) -> Void = { _ in }
    /// Writes the export and hands back a file URL. Returns nil when there is nothing to write.
    var onExportFieldLog: () -> URL? = { nil }

    /// Held rather than regenerated per redraw: the export is a file write and a receipt join,
    /// and a `ShareLink` that rebuilt it on every layout pass would do both repeatedly.
    @State private var exportURL: URL?

    /// Which tier's bar the table below reports. `.verified` is included so the unscaled floor is
    /// visible next to the scaled ones — the multipliers only mean anything as a comparison.
    @State private var tier: AmbientMerchantConfidence = .brandMatched
    @AppStorage(RadarDiagnosticSettings.radiusDefaultsKey)
    private var radarRadiusMeters = RadarDiagnosticSettings.defaultRadiusMeters

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FIELD DIAGNOSTICS · ALERT POLICY")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Text("Not shipped to the App Store. Changes take effect on the next arrival and are recorded on every field-log record, so an export says which policy produced it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            thresholdControls
            Divider()
            multiplierControls
            Divider()
            estimateControls
            Divider()
            effectiveBarTable
            Divider()
            radarRadiusControl
            Divider()
            radarCounters
            Divider()
            deliveryCounters
            Divider()
            wakeCounters
            Divider()
            fieldLogExport

            Button("Reset to shipped policy") { policy = .shipped }
                .font(.subheadline)
                .disabled(policy == .shipped)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Threshold

    private var activeThreshold: SwitchThreshold { policy.threshold(ownerThreshold: ownerThreshold) }

    @ViewBuilder
    private var thresholdControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Override the owner's switch threshold", isOn: Binding(
                get: { policy.switchThresholdOverride != nil },
                // Seeded from the owner's own threshold rather than from zero, so turning the
                // override on changes nothing until a dial is actually moved.
                set: { policy.switchThresholdOverride = $0 ? ownerThreshold : nil }))
                .font(.subheadline)

            if policy.switchThresholdOverride != nil {
                stepperRow("Minimum gain", value: Binding(
                    get: { activeThreshold.minAdvantagePercentagePoints },
                    set: { policy.switchThresholdOverride?.minAdvantagePercentagePoints = $0 }),
                    step: 0.1, format: { String(format: "%.2fpp", $0) })

                stepperRow("Minimum gain", value: Binding(
                    get: { activeThreshold.minAdvantageCad },
                    set: { policy.switchThresholdOverride?.minAdvantageCad = $0 }),
                    step: 0.05, format: { String(format: "$%.2f", $0) })

                Picker("Semantics", selection: Binding(
                    get: { activeThreshold.semantics },
                    set: { policy.switchThresholdOverride?.semantics = $0 })) {
                        Text("both floors").tag("both")
                        Text("either floor").tag("either")
                    }
                    .pickerStyle(.segmented)
            } else {
                Text("Owner's threshold: \(String(format: "%.2fpp", ownerThreshold.minAdvantagePercentagePoints)) \(ownerThreshold.semantics == "either" ? "OR" : "AND") \(String(format: "$%.2f", ownerThreshold.minAdvantageCad))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Multipliers

    @ViewBuilder
    private var multiplierControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tier multipliers")
                .font(.subheadline.weight(.semibold))
            Text("Scales both floors for that tier. The verified tier is never scaled — it is measured against the owner's own floor, which is the one bar here that was earned.")
                .font(.caption)
                .foregroundStyle(.secondary)

            stepperRow("Brand matched", value: $policy.unverifiedAdvantageMultiplier,
                       step: 0.25, format: { String(format: "×%.2f", $0) })
            stepperRow("Frequented", value: $policy.frequentedAdvantageMultiplier,
                       step: 0.25, format: { String(format: "×%.2f", $0) })
            stepperRow("Category only", value: $policy.categoryAdvantageMultiplier,
                       step: 0.25, format: { String(format: "×%.2f", $0) })
        }
    }

    // MARK: - Estimate

    @ViewBuilder
    private var estimateControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Amount estimate")
                .font(.subheadline.weight(.semibold))
            Text("On arrival nothing has been bought, so the engine scores a guessed basket. The CAD floor is divided by that guess, which is what makes the effective bar depend on the category.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Amount estimate", selection: Binding(
                get: { isFixedEstimate },
                set: { policy.amountEstimate = $0 ? .fixed(amountCad: fixedAmount) : .perCategory })) {
                    Text("per category").tag(false)
                    Text("one amount").tag(true)
                }
                .pickerStyle(.segmented)

            if isFixedEstimate {
                stepperRow("Every category", value: Binding(
                    get: { fixedAmount },
                    set: { policy.amountEstimate = .fixed(amountCad: $0) }),
                    step: 5, format: { String(format: "$%.0f", $0) })
            }
        }
    }

    private var isFixedEstimate: Bool {
        if case .fixed = policy.amountEstimate { return true }
        return false
    }

    /// The fallback estimate, so switching to "one amount" starts somewhere defensible rather
    /// than at zero — which would make every CAD floor free.
    private var fixedAmount: Double {
        if case .fixed(let amount) = policy.amountEstimate { return amount }
        return ambientEstimatedAmountCad(category: "other", estimate: .perCategory)
    }

    // MARK: - The bar this policy actually produces

    @ViewBuilder
    private var effectiveBarTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Effective bar by category")
                .font(.subheadline.weight(.semibold))

            Picker("Tier", selection: $tier) {
                Text("verified").tag(AmbientMerchantConfidence.verified)
                Text("brand").tag(AmbientMerchantConfidence.brandMatched)
                Text("frequented").tag(AmbientMerchantConfidence.frequented)
                Text("category").tag(AmbientMerchantConfidence.categoryMatched)
            }
            .pickerStyle(.segmented)

            ForEach(effectiveAlertBars(ownerThreshold: ownerThreshold, policy: policy,
                                       confidence: tier), id: \.category) { bar in
                HStack(alignment: .firstTextBaseline) {
                    Text(bar.category)
                        .font(.caption.monospaced())
                    Spacer()
                    Text(String(format: "$%.0f", bar.estimatedAmountCad))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2fpp", bar.effectivePercentagePoints))
                        .font(.caption.monospaced().weight(.semibold))
                        // Orange means the CAD floor, not the percentage floor, is deciding —
                        // the accidental bar nobody chose. This is the whole point of the table.
                        .foregroundStyle(bar.effectivePercentagePoints
                                            > bar.scaledMinAdvantagePercentagePoints + 1e-9
                                         ? .orange : .primary)
                        .frame(width: 66, alignment: .trailing)
                }
            }

            Text("Orange: the dollar floor is deciding, not the percentage floor. That bar is a consequence of the guessed basket, not a number anyone chose.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Counters

    @ViewBuilder
    private var radarRadiusControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Radar query radius")
                .font(.subheadline.weight(.semibold))

            Picker("Radar query radius", selection: Binding(
                get: {
                    RadarDiagnosticSettings.allowedRadiusMeters.contains(radarRadiusMeters)
                        ? radarRadiusMeters
                        : RadarDiagnosticSettings.defaultRadiusMeters
                },
                set: { newRadius in
                    radarRadiusMeters = newRadius
                    onRadarRadiusChange(newRadius)
                })) {
                    ForEach(RadarDiagnosticSettings.allowedRadiusMeters, id: \.self) { radius in
                        Text("\(Int(radius)) m").tag(radius)
                    }
                }
                .pickerStyle(.segmented)

            Text("Changing this cancels any in-flight lookup and runs a fresh Radar scan. Every field record stores the radius that produced it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// One row is the reason this section exists: how often a recognised chain was in the result
    /// set and something else was ranked above it.
    @ViewBuilder
    private var radarCounters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Radar reliability")
                .font(.subheadline.weight(.semibold))

            counterRow("Launch prefetches", "\(radarMetrics.prefetchAttempts)")
            counterRow("Radar taps", "\(radarMetrics.preparedTaps + radarMetrics.tapLookups)")
            counterRow("Instant prepared taps", "\(radarMetrics.preparedTaps)")
            counterRow("Movement cache hits", "\(radarMetrics.movementCacheHits)")
            counterRow("Location timeouts", "\(radarMetrics.locationTimeouts)",
                       tint: radarMetrics.locationTimeouts > 0 ? .orange : nil)
            counterRow("Apple Maps timeouts", "\(radarMetrics.merchantTimeouts)",
                       tint: radarMetrics.merchantTimeouts > 0 ? .orange : nil)
            counterRow("Other location failures", "\(radarMetrics.locationFailures)",
                       tint: radarMetrics.locationFailures > 0 ? .orange : nil)
            counterRow("Other Apple Maps failures", "\(radarMetrics.merchantFailures)",
                       tint: radarMetrics.merchantFailures > 0 ? .orange : nil)
            counterRow("Empty results", "\(radarMetrics.emptyResults)")

            if let average = radarMetrics.averageTapLatencyMilliseconds {
                counterRow("Average tap latency", "\(average) ms")
                counterRow("Slowest tap", "\(radarMetrics.maximumTapLatencyMilliseconds) ms")
            }

            Text("These counters stay on this iPhone. They identify which stage failed without recording a location or merchant name.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Text("Radar scan results")
                .font(.subheadline.weight(.semibold))

            if radarMetrics.radarScans == 0 {
                Text("No successful Apple Maps response has been recorded yet. Failure counts above still apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                counterRow("Scans", "\(radarMetrics.radarScans)")
                counterRow("…with a recognised chain",
                           "\(radarMetrics.radarScansWithARecognisedChain)")
                counterRow("…where something else ranked first",
                           "\(radarMetrics.radarScansWhereTopRankedMissedAChain)",
                           tint: radarMetrics.radarScansWhereTopRankedMissedAChain > 0
                               ? .orange : nil)
                counterRow("Eligible checkout POIs",
                           "\(radarMetrics.radarEligibleResults)")
                counterRow("Defensively excluded transit POIs",
                           "\(radarMetrics.radarExcludedPublicTransportResults)")
                counterRow("Defensively excluded uncategorized POIs",
                           "\(radarMetrics.radarExcludedMissingCategoryResults)")
                counterRow("Defensively excluded unsupported POIs",
                           "\(radarMetrics.radarExcludedUnsupportedCategoryResults)")

                Text("Raw \(bucketSummary(radarMetrics.radarRawResultBuckets))  ·  deduped \(bucketSummary(radarMetrics.radarDedupedResultBuckets))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)

                Text("Orange counts the pin-geometry signature: the store was returned and outranked. A large gap between the raw and deduped buckets is the other mechanism — a bounded response crowding the anchor tenant out.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var deliveryCounters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alert delivery")
                .font(.subheadline.weight(.semibold))

            if let coverage, !coverage.notificationDeliveryByOutcome.isEmpty {
                counterRow("Asked iOS for an alert", "\(coverage.notificationsRequested)")
                counterRow("…and it was in Notification Center",
                           "\(coverage.notificationsThatLanded)")
                counterRow("…accepted then absent",
                           "\(coverage.notificationDeliveryByOutcome[.acceptedThenAbsent] ?? 0)",
                           tint: (coverage.notificationDeliveryByOutcome[.acceptedThenAbsent] ?? 0) > 0
                               ? .orange : nil)
                counterRow("…the request threw",
                           "\(coverage.notificationDeliveryByOutcome[.requestFailed] ?? 0)")
                counterRow("Never asked (gate stayed quiet)",
                           "\(coverage.notificationDeliveryByOutcome[.neverRequested] ?? 0)")

                Text("A gap between the first two is a delivery defect. No gap at all means the silence was policy, and the dials above are where to look.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No arrivals recorded in the last seven days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var wakeCounters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background wakes (last 7 days)")
                .font(.subheadline.weight(.semibold))

            if let coverage, coverage.wakes > 0 {
                counterRow("Wakes", "\(coverage.wakes)")
                ForEach(AmbientWakeCause.allCases, id: \.self) { cause in
                    if let count = coverage.wakesByCause[cause], count > 0 {
                        counterRow("  \(wakeCauseLabel(cause))",
                                   "\(count) · avg \(coverage.averageWakeMilliseconds(for: cause) ?? 0) ms")
                    }
                }
                counterRow("Longest wake", "\(coverage.longestWakeMilliseconds) ms")
                counterRow("Total awake", "\(coverage.totalWakeMilliseconds / 1_000) s")
                counterRow("Fix asked for and never arrived",
                           "\(coverage.wakeFixOutcomes[.fixUnavailable] ?? 0)",
                           tint: (coverage.wakeFixOutcomes[.fixUnavailable] ?? 0) > 0
                               ? .orange : nil)
                counterRow("Fix asked for and landed",
                           "\(coverage.wakeFixOutcomes[.fixLanded] ?? 0)")
                counterRow("No fix requested",
                           "\(coverage.wakeFixOutcomes[.notRequested] ?? 0)")

                Text("A wake that waits out its whole window for a fix that never comes is the expensive kind. This is the only figure that says whether ambient monitoring is affordable.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No background wakes recorded in the last seven days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func counterRow(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(tint ?? .primary)
        }
    }

    private func bucketSummary(_ buckets: [NearbyResultBucket: Int]) -> String {
        let parts = NearbyResultBucket.allCases.compactMap { bucket -> String? in
            guard let count = buckets[bucket], count > 0 else { return nil }
            return "\(bucket.rawValue)×\(count)"
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    private func wakeCauseLabel(_ cause: AmbientWakeCause) -> String {
        switch cause {
        case .regionEntry: return "region entry"
        case .regionExit: return "region exit"
        case .significantChange: return "significant change"
        case .stateSynthesis: return "asked if already inside"
        }
    }

    // MARK: - Export

    @ViewBuilder
    private var fieldLogExport: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Field log")
                .font(.subheadline.weight(.semibold))
            Text("\(fieldLogRecordCount) arrivals recorded, newest last. One record each: every candidate, the fix, the raw gate input, and the dials above. Wallet captures within 90 minutes are joined on export.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Two taps on purpose. Preparing the export runs the receipt join and writes a file;
            // doing that inside a `ShareLink`'s item closure would run it on every redraw.
            Button("Prepare export") { exportURL = onExportFieldLog() }
                .font(.subheadline)
                .disabled(fieldLogRecordCount == 0)

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share \(exportURL.lastPathComponent)", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Shared row

    private func stepperRow(_ title: String, value: Binding<Double>, step: Double,
                            format: @escaping (Double) -> String) -> some View {
        Stepper(value: value, in: 0...100, step: step) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
