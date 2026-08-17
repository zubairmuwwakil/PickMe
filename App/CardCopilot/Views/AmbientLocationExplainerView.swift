import SwiftUI

/// A deliberate pre-permission surface: the system prompt never has to explain the purpose on
/// its own, and the owner can decline without losing manual checkout.
struct AmbientLocationExplainerView: View {
    let onEnable: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
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
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Arrival alerts")
        .navigationBarTitleDisplayMode(.inline)
    }
}
