import SwiftUI
import UIKit

private struct SkeletonShimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.2),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: geometry.size.width * 0.9)
                    .rotationEffect(.degrees(18))
                    .offset(x: geometry.size.width * phase)
                    .blendMode(.plusLighter)
                }
                .clipped()
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}

extension View {
    func skeletonShimmer() -> some View {
        modifier(SkeletonShimmer())
    }
}

struct SkeletonPoster: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.18),
                        Color.gray.opacity(0.28),
                        Color.gray.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .skeletonShimmer()
    }
}

struct SkeletonCircle: View {
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.18),
                        Color.gray.opacity(0.28),
                        Color.gray.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .skeletonShimmer()
    }
}

struct PosterImage: View {
    let path: String?
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let localImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
            } else if let url = APIConfig.mediaURL(for: path), !isLocalFilePath {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        SkeletonPoster(cornerRadius: cornerRadius)
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var isLocalFilePath: Bool {
        path?.hasPrefix("file:") == true
    }

    private var localImage: UIImage? {
        guard let path, path.hasPrefix("file:"),
              let url = URL(string: path) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
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

struct PosterFullscreenView: View {
    let path: String?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if let path, path.hasPrefix("file:"),
                   let url = URL(string: path),
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else if let url = APIConfig.mediaURL(for: path) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.5))
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = max(1, min(lastScale * value, 4))
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale < 1.05 {
                            withAnimation(.easeOut(duration: 0.2)) {
                                scale = 1
                                lastScale = 1
                            }
                        }
                    }
            )
            .onTapGesture {
                dismiss()
            }
            .padding()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

struct ReleaseRowView: View {
    let title: String
    let subtitle: String
    let posterPath: String?

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(path: posterPath)
                .frame(width: 56, height: 80)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}

struct ReleaseRowSkeletonView: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonPoster(cornerRadius: 8)
                .frame(width: 56, height: 80)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.22))
                    .frame(height: 16)
                    .skeletonShimmer()

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.18))
                    .frame(width: 84, height: 22)
                    .skeletonShimmer()

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.18))
                    .frame(height: 12)
                    .skeletonShimmer()

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.16))
                    .frame(width: 120, height: 12)
                    .skeletonShimmer()
            }
        }
        .redacted(reason: .placeholder)
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
