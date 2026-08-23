import SwiftUI

struct WalletCaptureBannerView: View {
    let banner: WalletCaptureBanner
    let onDismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: banner.isProblem ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                .foregroundStyle(banner.isProblem ? .orange : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title).font(.headline)
                Text(banner.body).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: onDismiss) { Image(systemName: "xmark").font(.caption.weight(.bold)) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator.opacity(0.35)))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }
}
