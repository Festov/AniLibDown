import SwiftUI

struct PosterImage: View {
    let path: String?
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let url = APIConfig.mediaURL(for: path) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder.overlay(ProgressView())
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.2))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }
}

struct BroadcastStatusBadge: View {
    let status: BroadcastStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor.opacity(0.2))
            .foregroundStyle(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch status {
        case .ongoing: return .green
        case .released: return .blue
        case .upcoming: return .orange
        }
    }
}

struct ReleaseRowView: View {
    let title: String
    let subtitle: String
    let posterPath: String?
    var status: BroadcastStatus?

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(path: posterPath)
                .frame(width: 56, height: 80)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                if let status {
                    BroadcastStatusBadge(status: status)
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
