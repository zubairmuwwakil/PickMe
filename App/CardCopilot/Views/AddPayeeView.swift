import SwiftUI
import CardCopilotEngine

/// Production-grade Add Payee & Canadian Smart Reward Router View.
/// Supports Durham Water, Region of Durham, utilities, property taxes, and rent routing.
public struct AddPayeeView: View {
    @Environment(\.dismiss) private var dismiss

    // Form inputs
    @State private var payeeName: String = "DURHAM WATER, REG MUN OF"
    @State private var accountNumber: String = "1643208999"
    @State private var nickname: String = "Durham Water"
    @State private var selectedCategory: BillCategory = .utilitiesWater
    @State private var monthlyAmountCad: Double = 150.0
    @State private var selectedRouteId: String = "chexy_scotiabank-momentum-vi"
    
    // Owned cards state (mock or injected from wallet)
    @State private var ownedCardIds: [String] = ["scotiabank-momentum-vi", "triangle-we"]

    @State private var showInfoSheet: Bool = false
    @State private var activeIntermediaryInfo: BillIntermediary?

    private var currentPayee: BillPayee {
        BillPayee(
            payeeName: payeeName,
            accountNumber: accountNumber,
            nickname: nickname.isEmpty ? nil : nickname,
            category: selectedCategory,
            estimatedMonthlyCad: monthlyAmountCad
        )
    }

    private var scoredRoutes: [RouteRecommendation] {
        let scorer = BillRouteScorer.loadDefault()
        return scorer.scoreRoutes(for: currentPayee, ownedCardIds: ownedCardIds)
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Payee Details Form Card
                    payeeDetailsCard

                    // MARK: - Smart Reward Router Section
                    smartRewardRouterSection

                    // MARK: - Action Button
                    Button(action: {
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save Payee & Set Routing")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .padding(.top, 12)
            }
            .navigationTitle("Add Payee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $activeIntermediaryInfo) { intermediary in
                IntermediaryGuideSheet(intermediary: intermediary)
            }
        }
    }

    // MARK: - Payee Form
    private var payeeDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: selectedCategory.iconSymbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Payee Information")
                        .font(.headline)
                    Text("Canadian municipal, utility, or household payee")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Payee Name *")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                TextField("Payee Name", text: $payeeName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: payeeName) { _, newName in
                        selectedCategory = BillCategory.detect(from: newName)
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Account Number *")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                TextField("Account Number", text: $accountNumber)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Nickname (optional)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                TextField("e.g. Durham Water", text: $nickname)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Bill Type (optional)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Picker("Category", selection: $selectedCategory) {
                    ForEach(BillCategory.allCases, id: \.self) { cat in
                        Label(cat.displayName, systemImage: cat.iconSymbol).tag(cat)
                    }
                }
                .pickerStyle(.menu)
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    // MARK: - Smart Reward Router Section
    private var smartRewardRouterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Smart Reward Router", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text("PickMe Engine")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.12))
                    .foregroundColor(.purple)
                    .cornerRadius(8)
            }

            Text("We calculated your net rewards after all intermediary fees based on your active wallet.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Scored Route Tiles
            ForEach(scoredRoutes) { route in
                routeTile(route)
            }
        }
        .padding(18)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    private func routeTile(_ route: RouteRecommendation) -> some View {
        let isSelected = selectedRouteId == route.id || (selectedRouteId.isEmpty && route.isOptimal)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(route.intermediary.name)
                            .font(.subheadline)
                            .fontWeight(.bold)

                        if route.isOptimal {
                            Text("BEST NET SPREAD")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }

                    if let cardName = route.cardOfficialName {
                        Text(cardName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if route.estimatedAnnualNetCad > 0 {
                        Text(String(format: "+$%.2f/yr", route.estimatedAnnualNetCad))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    } else {
                        Text("$0.00")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                    Text(route.mathBreakdown)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Text(route.instruction)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)

            HStack {
                Button(action: {
                    activeIntermediaryInfo = route.intermediary
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                        Text("How it works")
                    }
                    .font(.caption2)
                    .foregroundColor(.blue)
                }

                Spacer()

                Button(action: {
                    selectedRouteId = route.id
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        Text(isSelected ? "Selected" : "Select Route")
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .blue : .secondary)
                }
            }
        }
        .padding(14)
        .background(isSelected ? Color.blue.opacity(0.06) : Color(UIColor.tertiarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
        )
        .cornerRadius(12)
    }
}

// MARK: - Modal Explainer Sheet
struct IntermediaryGuideSheet: View {
    let intermediary: BillIntermediary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(intermediary.name)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(intermediary.description)
                    .font(.body)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Details & Constraints")
                        .font(.headline)

                    HStack {
                        Text("Processing Fee:")
                        Spacer()
                        Text(String(format: "%.2f%%", intermediary.feeRate * 100))
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)

                    HStack {
                        Text("Settlement Time:")
                        Spacer()
                        Text("\(intermediary.settlementDays) business days")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)

                Spacer()
            }
            .padding()
            .navigationTitle("Intermediary Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
