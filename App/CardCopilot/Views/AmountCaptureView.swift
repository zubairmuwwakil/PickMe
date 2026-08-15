import SwiftUI

/// Near-zero-friction amount capture. The value-recovered counter depends on real amounts,
/// but a forced keyboard would kill checkout speed — chips first, skip always allowed.
struct AmountCaptureView: View {
    let merchantName: String
    let onAmount: (Double?) -> Void
    let onCancel: () -> Void
    @State private var customText = ""
    @FocusState private var customFocused: Bool

    private let presets: [Double] = [10, 25, 50, 100]

    var body: some View {
        VStack(spacing: 20) {
            Text("Roughly how much at \(merchantName)?")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 32)

            HStack(spacing: 10) {
                ForEach(presets, id: \.self) { amount in
                    Button("$\(Int(amount))") { onAmount(amount) }
                        .buttonStyle(.bordered)
                        .font(.headline)
                }
            }

            HStack {
                TextField("Custom", text: $customText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($customFocused)
                    .frame(width: 120)
                Button("Go") {
                    if let value = Double(customText), value > 0 { onAmount(value) }
                }
                .disabled(Double(customText) == nil)
            }

            Button("Skip — just tell me the card") { onAmount(nil) }
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
        }
    }
}
