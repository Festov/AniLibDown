import Foundation

@MainActor
enum AppCacheManager {
    static func clearAll() {
        CatalogStore.shared.clearSessionCache()
        CollectionStore.shared.invalidate()
        URLCache.shared.removeAllCachedResponses()
        WatchProgressStore.shared.clearAll()
    }

    static var estimatedCacheDescription: String {
        "Кеш каталога, изображений и прогресса просмотра на этом устройстве"
    }
}
