import SwiftUI

struct ReleaseTeamView: View {
    let releaseId: Int
    let initialMembers: [ReleaseMember]

    @State private var members: [ReleaseMember]
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(releaseId: Int, initialMembers: [ReleaseMember]) {
        self.releaseId = releaseId
        self.initialMembers = initialMembers
        _members = State(initialValue: initialMembers)
    }

    private var sections: [(title: String, members: [ReleaseMember])] {
        ReleaseMemberRoleOrder.sections(from: members)
    }

    var body: some View {
        Group {
            if isLoading && members.isEmpty {
                ProgressView("Загрузка команды...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, members.isEmpty {
                ContentUnavailableView {
                    Label("Не удалось загрузить", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Повторить") {
                        Task { await loadMembers(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if members.isEmpty {
                ContentUnavailableView(
                    "Команда не указана",
                    systemImage: "person.3",
                    description: Text("Для этого релиза пока нет списка участников")
                )
            } else {
                List {
                    ForEach(sections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.members) { member in
                                HStack(spacing: 12) {
                                    memberAvatar(member)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(member.nickname)
                                            .font(.body.weight(.medium))
                                        Text(member.roleTitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 2)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(member.nickname), \(member.roleTitle)")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Команда")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if members.isEmpty {
                await loadMembers(force: false)
            }
        }
        .refreshable {
            await loadMembers(force: true)
        }
    }

    @ViewBuilder
    private func memberAvatar(_ member: ReleaseMember) -> some View {
        let path = member.user?.avatar?.displayURL
        if path != nil {
            PosterImage(path: path, cornerRadius: 18)
                .frame(width: 36, height: 36)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.18))
                Text(String(member.nickname.prefix(1)).uppercased())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 36, height: 36)
        }
    }

    private func loadMembers(force: Bool) async {
        if isLoading { return }
        if !force, !members.isEmpty { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loaded = try await APIClient.shared.getReleaseMembers(idOrAlias: String(releaseId))
            members = loaded
        } catch {
            if members.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}
