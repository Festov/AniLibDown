import SwiftUI

struct ShikimoriReleaseSection: View {
    let release: ReleaseDetail
    @ObservedObject var viewModel: ReleaseDetailViewModel
    @ObservedObject var shikimoriAuth: ShikimoriAuthService
    let onLinkTapped: () -> Void

    private let accent = Color(red: 0.35, green: 0.42, blue: 0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
                .padding(14)
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [accent.opacity(0.55), accent.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.shikimori)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 34, height: 34)
                Text("S")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.shikimori)
                    .font(.headline)
                Text("Статус списка и серии")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isUpdatingShikimori {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var content: some View {
        if !ShikimoriConfig.isConfigured {
            infoRow(
                icon: "exclamationmark.triangle",
                text: ShikimoriConfig.configurationHint
            )
        } else if !shikimoriAuth.isAuthenticated {
            infoRow(
                icon: "person.crop.circle.badge.plus",
                text: "Подключите аккаунт Shikimori в профиле, чтобы отмечать статус просмотра."
            )
        } else if let link = viewModel.shikimoriLink {
            linkedContent(link: link)
        } else {
            unlinkedContent
        }

        if let error = viewModel.shikimoriError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.top, 6)
        }
    }

    private func linkedContent(link: ShikimoriLink) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "link.circle.fill")
                    .font(.title2)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(link.title)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let episodes = viewModel.shikimoriEpisodes, episodes > 0 {
                        Label("Серий на Shikimori: \(episodes)", systemImage: "play.rectangle.on.rectangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            statusChips

            HStack(spacing: 10) {
                Button {
                    onLinkTapped()
                } label: {
                    Label("Сменить", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(accent)

                Button(role: .destructive) {
                    viewModel.unlinkShikimori(releaseId: release.id)
                } label: {
                    Label("Отвязать", systemImage: "link.badge.minus")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var statusChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ShikimoriListStatus.allCases.filter { $0 != .rewatching }) { status in
                    Button {
                        Task { await viewModel.setShikimoriStatus(status, releaseId: release.id) }
                    } label: {
                        Text(status.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background {
                                Capsule()
                                    .fill(viewModel.shikimoriStatus == status ? accent : Color(.tertiarySystemFill))
                            }
                            .foregroundStyle(viewModel.shikimoriStatus == status ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isUpdatingShikimori)
                    .accessibilityAddTraits(viewModel.shikimoriStatus == status ? .isSelected : [])
                }
            }
        }
    }

    private var unlinkedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow(
                icon: "sparkles",
                text: "Привяжите релиз к тайтлу на Shikimori, чтобы ставить статусы и синхронизировать номер серии."
            )

            Button(action: onLinkTapped) {
                Label(L10n.linkShikimori, systemImage: "link.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
