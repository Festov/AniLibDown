import Foundation

enum AppCacheKind: String, CaseIterable, Identifiable {
    case catalog
    case images
    case watchProgress
    case collection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .catalog: return "Кеш каталога"
        case .images: return "Кеш изображений"
        case .watchProgress: return "Прогресс просмотра"
        case .collection: return "Кеш коллекции"
        }
    }

    var detail: String {
        switch self {
        case .catalog:
            return "Список релизов каталога (хранится на устройстве до 1 часа)"
        case .images:
            return "Постеры и аватары, загруженные из сети"
        case .watchProgress:
            return "Позиция воспроизведения и последняя серия"
        case .collection:
            return "Загруженные списки коллекции на этом устройстве"
        }
    }
}

@MainActor
enum AppCacheManager {
    static func clear(_ kinds: Set<AppCacheKind>) {
        if kinds.contains(.catalog) {
            CatalogStore.shared.clearSessionCache()
        }
        if kinds.contains(.images) {
            URLCache.shared.removeAllCachedResponses()
        }
        if kinds.contains(.watchProgress) {
            WatchProgressStore.shared.clearAll()
        }
        if kinds.contains(.collection) {
            CollectionStore.shared.invalidate()
        }
    }

    static func clearAll() {
        clear(Set(AppCacheKind.allCases))
    }
}
