import SwiftUI

/// Fast, tactile amount capture. Entering an amount tracks exact value recovered,
/// while skipping uses the category average for instant card advice.
struct AmountCaptureView: View {
    let merchantName: String
    let onAmount: (Double?) -> Void
    let onCancel: () -> Void

    @State private var customText = ""
    @FocusState private var isInputFocused: Bool

    private let presets: [Double] = [10, 25, 50, 100, 200]

    var body: some View {
        VStack(spacing: 24) {
            // Merchant Header Card
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Image(systemName: "storefront.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                }

                Text(merchantName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("How much are you spending?")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)

            // Preset Quick Buttons
            VStack(alignment: .leading, spacing: 10) {
                Text("QUICK PRESETS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { amount in
                        Button {
                            onAmount(amount)
                        } label: {
                            Text("$\(Int(amount))")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(.secondarySystemGroupedBackground))
                                        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                                )
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)

            // Custom Amount Input
            VStack(alignment: .leading, spacing: 10) {
                Text("CUSTOM AMOUNT")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("$")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $customText)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .keyboardType(.decimalPad)
                            .focused($isInputFocused)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(isInputFocused ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 1.5)
                            )
                    )

                    Button {
                        if let value = Double(customText.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)), value > 0 {
                            onAmount(value)
                        }
                    } label: {
                        Text("Calculate")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 13)
                            .background(
                                isCustomValid ? Color.blue : Color.gray.opacity(0.4)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!isCustomValid)
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            // Skip Option
            Button {
                onAmount(nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Skip — just tell me which card")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
            }

            Text("Entering amounts feeds your value-recovered scoreboard. Skip anytime.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }

    private var isCustomValid: Bool {
        guard let value = Double(customText.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)) else {
            return false
        }
        return value > 0
    }
}
