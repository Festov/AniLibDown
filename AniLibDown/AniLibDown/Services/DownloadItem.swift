import Foundation

struct DownloadItem: Identifiable, Codable, Hashable {
    var id: String
    let episodeId: String
    let releaseId: Int?
    let releaseTitle: String
    let episodeTitle: String
    let episodeName: String?
    let episodeOrdinal: Double
    let quality: String
    let remoteURL: String
    var posterPath: String?
    var localBookmark: Data?
    var progress: Double
    var state: DownloadState
    var lastError: String?
    var createdAt: Date

    enum DownloadState: String, Codable {
        case queued
        case downloading
        case completed
        case failed
    }

    var groupingKey: String {
        if let releaseId {
            return "release:\(releaseId)"
        }
        return "title:\(releaseTitle)"
    }

    var displayEpisodeTitle: String {
        if let episodeName, !episodeName.isEmpty {
            return formattedEpisodeTitle(name: episodeName)
        }
        return episodeTitle
    }

    var playbackEpisodeName: String? {
        if let episodeName, !episodeName.isEmpty {
            return episodeName
        }
        guard episodeTitle.hasPrefix("Серия ") else { return nil }
        let parts = episodeTitle.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let name = parts[1].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private func formattedEpisodeTitle(name: String) -> String {
        let ordinalText = ReleaseFormatting.displayEpisodeOrdinal(episodeOrdinal)
        return "Серия \(ordinalText): \(name)"
    }

    init(
        id: String,
        episodeId: String,
        releaseId: Int?,
        releaseTitle: String,
        episodeTitle: String,
        episodeName: String?,
        episodeOrdinal: Double,
        quality: String,
        remoteURL: String,
        posterPath: String? = nil,
        localBookmark: Data?,
        progress: Double,
        state: DownloadState,
        lastError: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.episodeId = episodeId
        self.releaseId = releaseId
        self.releaseTitle = releaseTitle
        self.episodeTitle = episodeTitle
        self.episodeName = episodeName
        self.episodeOrdinal = episodeOrdinal
        self.quality = quality
        self.remoteURL = remoteURL
        self.posterPath = posterPath
        self.localBookmark = localBookmark
        self.progress = progress
        self.state = state
        self.lastError = lastError
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        episodeId = try container.decode(String.self, forKey: .episodeId)
        releaseId = try container.decodeIfPresent(Int.self, forKey: .releaseId)
        releaseTitle = try container.decode(String.self, forKey: .releaseTitle)
        episodeTitle = try container.decode(String.self, forKey: .episodeTitle)
        episodeName = try container.decodeIfPresent(String.self, forKey: .episodeName)
        episodeOrdinal = try container.decodeIfPresent(Double.self, forKey: .episodeOrdinal) ?? 0
        quality = try container.decode(String.self, forKey: .quality)
        remoteURL = try container.decode(String.self, forKey: .remoteURL)
        posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
        localBookmark = try container.decodeIfPresent(Data.self, forKey: .localBookmark)
        progress = try container.decode(Double.self, forKey: .progress)
        state = try container.decode(DownloadState.self, forKey: .state)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(episodeId, forKey: .episodeId)
        try container.encodeIfPresent(releaseId, forKey: .releaseId)
        try container.encode(releaseTitle, forKey: .releaseTitle)
        try container.encode(episodeTitle, forKey: .episodeTitle)
        try container.encodeIfPresent(episodeName, forKey: .episodeName)
        try container.encode(episodeOrdinal, forKey: .episodeOrdinal)
        try container.encode(quality, forKey: .quality)
        try container.encode(remoteURL, forKey: .remoteURL)
        try container.encodeIfPresent(posterPath, forKey: .posterPath)
        try container.encodeIfPresent(localBookmark, forKey: .localBookmark)
        try container.encode(progress, forKey: .progress)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encode(createdAt, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, episodeId, releaseId, releaseTitle, episodeTitle, episodeName, episodeOrdinal
        case quality, remoteURL, posterPath, localBookmark, progress, state, lastError, createdAt
    }
}