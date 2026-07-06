# AniLibDown

Нативное iOS-приложение на **SwiftUI** для просмотра и скачивания аниме с [AniLiberty API](https://aniliberty.top/api/docs/v1).

## Возможности

- **Каталог и новинки** — просмотр списков аниме с поиском и пагинацией
- **Карточка релиза** — описание, жанры, список серий
- **Онлайн-просмотр** — HLS-плеер (480p / 720p / 1080p) через `AVPlayer`
- **Офлайн-загрузки** — скачивание серий через `AVAssetDownloadURLSession` и просмотр без сети
- **Авторизация** — вход в аккаунт AniLiberty, просмотр профиля и коллекций

## Сборка без Mac

Собрать iOS-приложение **локально на Windows или Linux нельзя** — Apple требует Xcode, который работает только на macOS. Но Mac вам не обязателен: сборку можно делать в облаке.

### Вариант 1: GitHub Actions (рекомендуется)

В репозитории настроен workflow `.github/workflows/ios-build.yml`. Он собирает приложение на облачном Mac GitHub при каждом push.

1. Откройте вкладку **Actions** в GitHub-репозитории
2. Выберите workflow **iOS Build** → **Run workflow** (или дождитесь запуска после push)
3. После успешной сборки скачайте артефакт **AniLibDown-simulator**

Это сборка для **симулятора iOS** — её можно запустить только в симуляторе Xcode (на Mac). На реальный iPhone `.app` из симулятора **не установить**.

### Вариант 2: Установка на iPhone без своего Mac

Для установки на телефон нужен подписанный **.ipa** и аккаунт Apple Developer (99 $/год) или бесплатный Apple ID (с ограничениями).

| Способ | Нужен Mac? | Что потребуется |
|--------|------------|-----------------|
| **GitHub Actions + секреты** | Нет | Сертификат `.p12`, provisioning profile, секреты в репозитории |
| **[Codemagic](https://codemagic.io)** | Нет | Apple ID, настройка через веб-интерфейс |
| **[Bitrise](https://bitrise.io)** | Нет | Аналогично Codemagic |
| **Аренда облачного Mac** ([MacinCloud](https://www.macincloud.com), [Scaleway](https://www.scaleway.com/en/apple-silicon/)) | Нет (аренда) | SSH/RDP на Mac, Xcode в облаке |
| **Попросить друга с Mac** | Один раз | Подписать и собрать IPA |

#### Секреты для подписанного IPA в GitHub Actions

Если есть Apple Developer аккаунт, добавьте в **Settings → Secrets and variables → Actions**:

| Secret | Описание |
|--------|----------|
| `BUILD_CERTIFICATE_BASE64` | Distribution/Development сертификат `.p12` в base64 |
| `P12_PASSWORD` | Пароль от `.p12` |
| `KEYCHAIN_PASSWORD` | Любой пароль для временного keychain |
| `PROVISIONING_PROFILE_BASE64` | Provisioning profile в base64 |

После этого раскомментируйте job `build-ipa` в `.github/workflows/ios-build.yml`.

Готовый `.ipa` можно установить через **AltStore**, **Sideloadly** или **TestFlight**.

### Вариант 3: Только посмотреть, что проект компилируется

Достаточно GitHub Actions: если workflow зелёный — код собирается. Скачивать артефакт не обязательно.

## Запуск (если Mac есть)

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
