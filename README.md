# AniLibDown

Нативное iOS-приложение на **SwiftUI** для просмотра и скачивания аниме с [AniLiberty API](https://aniliberty.top/api/docs/v1).

## Возможности

- **Каталог и новинки** — просмотр списков аниме с поиском и пагинацией
- **Карточка релиза** — описание, жанры, список серий
- **Онлайн-просмотр** — HLS-плеер (480p / 720p / 1080p) через `AVPlayer`
- **Офлайн-загрузки** — скачивание серий через `AVAssetDownloadURLSession` и просмотр без сети
- **Авторизация** — вход в аккаунт AniLiberty, просмотр профиля и коллекций

## Установка на iPhone без Mac

**Артефакт `AniLibDown-simulator` не нужен** — это сборка для симулятора, на телефон не ставится.

### Быстрый способ (без секретов GitHub)

1. **Actions** → **Build IPA** → **Run workflow**
2. Тип сборки: **`unsigned`** (по умолчанию)
3. Скачайте артефакт **AniLibDown-ipa** → файл `AniLibDown.ipa`
4. Установите через **[Sideloadly](https://sideloadly.io)** на Windows (Sideloadly сам подпишет приложение вашим Apple ID)

Подробная инструкция: **[docs/INSTALL_IPA.md](docs/INSTALL_IPA.md)**

## Проверка сборки (для разработчиков)

Workflow **iOS Build** собирает версию для симулятора — это только проверка, что код компилируется. Для установки на телефон используйте **Build IPA**.

## Запуск (если Mac есть)
## Требования

- Xcode 16+
- iOS 17.0+
- Аккаунт на [aniliberty.top](https://aniliberty.top) (для входа и коллекций)

## Запуск

1. Откройте `AniLibDown/AniLibDown.xcodeproj` в Xcode
2. Выберите симулятор или устройство
3. Укажите **Development Team** в настройках таргета (Signing & Capabilities)
4. Соберите и запустите (`Cmd+R`)

## Требования

- Xcode 16+ (только для локальной разработки)
- iOS 17.0+
- Аккаунт на [aniliberty.top](https://aniliberty.top) (для входа и коллекций)

## Структура проекта

```
AniLibDown/
├── AniLibDown.xcodeproj
└── AniLibDown/
    ├── AniLibDownApp.swift      # Точка входа
    ├── ContentView.swift        # TabView
    ├── Models/                  # Модели API
    ├── Services/                # API, авторизация, загрузки
    └── Views/                   # Экраны SwiftUI
```

## API

Приложение использует **AniLiberty API v1**:

| Функция | Endpoint |
|---------|----------|
| Вход | `POST /accounts/users/auth/login` |
| Профиль | `GET /accounts/users/me/profile` |
| Новинки | `GET /anime/releases/latest` |
| Каталог | `GET /anime/catalog/releases` |
| Релиз | `GET /anime/releases/{id}` |
| Коллекции | `GET /accounts/users/me/collections/releases` |

Базовый URL: `https://aniliberty.top/api/v1`

## Архитектура

- **SwiftUI** + **MVVM**
- `APIClient` (actor) — сетевой слой с async/await
- `AuthService` — JWT в Keychain, восстановление сессии
- `DownloadManager` — фоновые HLS-загрузки с индексом в Documents

## Лицензия

Проект создан в образовательных целях. Контент принадлежит правообладателям и предоставляется через AniLiberty.
