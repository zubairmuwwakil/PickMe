import SwiftUI

struct WalletCaptureBannerView: View {
    let banner: WalletCaptureBanner
    let onDismiss: () -> Void

    private var iconName: String {
        banner.isProblem ? "exclamationmark.triangle.fill" : "bell.fill"
    }

    private var tint: Color {
        banner.isProblem ? .orange : .blue
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(banner.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(banner.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 12)
    }
}

#Preview {
    VStack {
        WalletCaptureBannerView(
            banner: .init(id: "sample", title: "Wallet Capture is up to date", body: "1 saved purchase synced.", isProblem: false),
            onDismiss: {}
        )
        WalletCaptureBannerView(
            banner: .init(id: "err", title: "Reconnect Wallet Capture", body: "Purchases are saved on this iPhone and need a new secure connection.", isProblem: true),
            onDismiss: {}
        )
    }
    .padding()
}
