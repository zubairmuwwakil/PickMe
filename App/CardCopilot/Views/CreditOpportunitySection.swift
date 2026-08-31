import SwiftUI
import CardCopilotEngine

/// A deliberately small action list, not a credit dashboard. PickMe stores only enrollment and
/// per-window aggregates; issuer statements remain the source of truth.
struct CreditOpportunitySection: View {
    @Environment(CopilotEnvironment.self) private var environment
    let graph: DependencyGraph

    @State private var remindersEnabled = false
    @State private var saveFailed = false

    private var today: String { Date().formatted(.iso8601.year().month().day()) }
    private var opportunities: [CreditOpportunity] {
        CreditAdvisor.opportunities(catalogue: graph.catalogue,
                                    ownerState: graph.ownerState, asOf: today)
    }

    var body: some View {
        if !opportunities.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("USE BEFORE YOU LOSE IT")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(.orange)
                        Text("Expiring card credits")
                            .font(.headline)
                    }
                    Spacer()
                    Button(remindersEnabled ? "Reminders on" : "Remind me") {
                        Task {
                            remindersEnabled = await CreditReminderScheduler
                                .enableAndRefresh(opportunities)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .disabled(remindersEnabled)
                }

                let visible = Array(opportunities.prefix(3))
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, opportunity in
                    opportunityRow(opportunity)
                    if index < visible.count - 1 { Divider() }
                }

                if opportunities.count > 3 {
                    Text("\(opportunities.count - 3) more credit\(opportunities.count == 4 ? "" : "s") in your wallet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Based on what you mark here—not a live issuer balance.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .alert("Couldn’t save credit status", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your wallet was not changed. Try again.")
            }
            .task {
                remindersEnabled = await CreditReminderScheduler.isAuthorized()
                if remindersEnabled { await CreditReminderScheduler.refresh(opportunities) }
            }
        }
    }

    private func opportunityRow(_ opportunity: CreditOpportunity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon(for: opportunity.status))
                    .foregroundStyle(color(for: opportunity.status))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(opportunity.label).font(.subheadline.weight(.semibold))
                    Text(cardName(opportunity.cardId))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(detail(for: opportunity))
                        .font(.caption).foregroundStyle(color(for: opportunity.status))
                }
                Spacer()
                Text(money(opportunity.remainingAmount,
                           currency: opportunity.value.currency.rawValue))
                    .font(.subheadline.monospacedDigit().weight(.bold))
            }

            HStack(spacing: 10) {
                switch opportunity.status {
                case .available:
                    actionButton("Mark used", opportunity: opportunity, action: .markConsumed())
                case .needsEnrollment:
                    actionButton("I enrolled", opportunity: opportunity,
                                 action: .setEnrollment(.enrolled))
                case .used where opportunity.realizedAmount + 0.005 < opportunity.consumedAmount:
                    actionButton("Credit posted", opportunity: opportunity,
                                 action: .confirmRealized())
                    actionButton("Undo", role: .destructive, opportunity: opportunity,
                                 action: .clearCurrentWindow)
                case .used:
                    actionButton("Undo", role: .destructive, opportunity: opportunity,
                                 action: .clearCurrentWindow)
                case .notYetEligible, .scheduleUnresolved:
                    EmptyView()
                }
            }
            .padding(.leading, 32)
        }
    }

    private func actionButton(_ title: String, role: ButtonRole? = nil,
                              opportunity: CreditOpportunity,
                              action: CreditStateAction) -> some View {
        Button(title, role: role) { apply(action, to: opportunity) }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private func apply(_ action: CreditStateAction, to opportunity: CreditOpportunity) {
        saveFailed = !environment.applyCreditAction(
            action, cardId: opportunity.cardId, creditId: opportunity.creditId, asOf: today
        )
        guard !saveFailed, let graph = environment.graph else { return }
        Task {
            await CreditReminderScheduler.refresh(CreditAdvisor.opportunities(
                catalogue: graph.catalogue, ownerState: graph.ownerState, asOf: today
            ))
        }
    }

    private func cardName(_ cardId: String) -> String {
        graph.catalogue.cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }

    private func detail(for opportunity: CreditOpportunity) -> String {
        switch opportunity.status {
        case .available:
            return expiryText(opportunity) ?? "Available now"
        case .used:
            return opportunity.realizedAmount + 0.005 < opportunity.consumedAmount
                ? "Marked used · confirm when it posts" : "Credit confirmed"
        case .needsEnrollment:
            return "Enrollment required" + (expiryText(opportunity).map { " · \($0)" } ?? "")
        case .notYetEligible:
            return opportunity.window.nextEligibleOn.map { "Available \(shortDate($0))" }
                ?? "Not yet eligible"
        case .scheduleUnresolved:
            return "Add the account-open date to resolve its window"
        }
    }

    private func expiryText(_ opportunity: CreditOpportunity) -> String? {
        guard let expiry = opportunity.window.expiresOn else { return nil }
        if opportunity.daysRemaining == 0 { return "Expires today" }
        if let days = opportunity.daysRemaining { return "\(days) days left · \(shortDate(expiry))" }
        return "Expires \(shortDate(expiry))"
    }

    private func shortDate(_ iso: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: iso) else { return iso }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func money(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = amount.rounded() == amount ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(currency)"
    }

    private func icon(for status: CreditOpportunityStatus) -> String {
        switch status {
        case .available: return "clock.badge.exclamationmark"
        case .used: return "checkmark.circle.fill"
        case .needsEnrollment: return "person.crop.circle.badge.checkmark"
        case .notYetEligible: return "calendar"
        case .scheduleUnresolved: return "questionmark.circle"
        }
    }

    private func color(for status: CreditOpportunityStatus) -> Color {
        switch status {
        case .available: return .orange
        case .used: return .green
        case .needsEnrollment: return .indigo
        case .notYetEligible, .scheduleUnresolved: return .secondary
        }
    }
}
