import Foundation

enum L10n {
    static let catalog = NSLocalizedString("tab.catalog", bundle: .main, value: "Каталог", comment: "")
    static let collection = NSLocalizedString("tab.collection", bundle: .main, value: "Коллекция", comment: "")
    static let downloads = NSLocalizedString("tab.downloads", bundle: .main, value: "Загрузки", comment: "")
    static let profile = NSLocalizedString("tab.profile", bundle: .main, value: "Профиль", comment: "")
    static let continueWatching = NSLocalizedString("catalog.continue", bundle: .main, value: "Продолжить просмотр", comment: "")
    static let searchHistory = NSLocalizedString("catalog.searchHistory", bundle: .main, value: "Недавние запросы", comment: "")
    static let shikimori = NSLocalizedString("shikimori.title", bundle: .main, value: "Shikimori", comment: "")
    static let linkShikimori = NSLocalizedString("shikimori.link", bundle: .main, value: "Привязать к Shikimori", comment: "")
    static let offline = NSLocalizedString("network.offline", bundle: .main, value: "Нет сети — показаны сохранённые данные", comment: "")
}
