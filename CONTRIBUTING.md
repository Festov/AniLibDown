# Разработка AniLibDown

## Требования

- macOS с **Xcode 16.x**
- iOS 17+ симулятор или устройство
- Для Shikimori: `ShikimoriSecrets.plist` (см. `ShikimoriSecrets.plist.example`)

## Сборка

```bash
cd AniLibDown
xcodebuild -project AniLibDown.xcodeproj -scheme AniLibDown \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Тесты

```bash
xcodebuild -project AniLibDown.xcodeproj -scheme AniLibDown \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## SwiftLint (опционально)

```bash
brew install swiftlint
swiftlint
```

## Структура

| Папка | Назначение |
|-------|------------|
| `AniLibDown/Models/` | DTO и доменные типы |
| `AniLibDown/Services/` | API, загрузки, хранилища |
| `AniLibDown/Views/` | SwiftUI-экраны |
| `AniLibDownTests/` | Unit-тесты |

## Релиз IPA

1. Обновите `MARKETING_VERSION` в `project.pbxproj` (User-Agent берётся из версии бандла)
2. Добавьте запись в `CHANGELOG.md`
3. Создайте тег `v1.x.x` — CI соберёт IPA и опубликует Release

Поддерживаемые теги: `v*`, `release_*`, `update*`

## Чек-лист тестирования

См. [TESTING_CHECKLIST.md](TESTING_CHECKLIST.md).
