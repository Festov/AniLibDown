# AniLibDown

Нативное iOS-приложение на **SwiftUI** для просмотра и скачивания аниме с [AniLiberty API](https://aniliberty.top/api/docs/v1).

> **Важно:** приложение полностью написано нейросетью. Возможны баги и нестабильная работа.  
> Если что-то сломалось — создайте запись в разделе [Проблемы](https://github.com/Festov/AniLibDown/issues) (желательно со скриншотом).

## Возможности

- **Новинки и каталог** — списки аниме, поиск, фильтр по жанрам, статус (Онгоинг / Вышло / Не вышло)
- **Карточка релиза** — описание, жанры, серии, выбор качества, скачивание всех серий
- **Онлайн-просмотр** — HLS-плеер (480p / 720p / 1080p), смена серий, перемотка двойным тапом
- **Офлайн-загрузки** — скачивание серий и просмотр без сети, группировка по аниме
- **Авторизация** — вход в аккаунт AniLiberty, профиль, коллекции (Смотрю / Запланировано / Просмотрено и др.)
- **Тема** — светлая, тёмная или системная

## Установка на iPhone (без Mac)

### 1. Скачайте IPA

1. Откройте раздел **[Releases](https://github.com/Festov/AniLibDown/releases)** репозитория
2. Скачайте файл **`AniLibDown.ipa`** из последнего релиза

### 2. Установите через Sideloadly (Windows)

1. Скачайте и установите **[Sideloadly](https://sideloadly.io)**
2. Подключите iPhone по USB и разблокируйте его
3. Перетащите `AniLibDown.ipa` в окно Sideloadly
4. Введите **Apple ID** и **пароль для приложений** (не обычный пароль)
   - Пароль создаётся на [appleid.apple.com](https://appleid.apple.com) → Безопасность → Пароли приложений
5. Нажмите **Start** и дождитесь завершения установки
6. На iPhone: **Настройки → Основные → VPN и управление устройством** → доверьте разработчику

### Ограничения бесплатного Apple ID

- Приложение работает **~7 дней**, затем нужно переустановить
- Одновременно до **3** sideload-приложений

## Структура проекта

```
AniLibDown/
├── AniLibDown.xcodeproj
└── AniLibDown/
    ├── AniLibDownApp.swift
    ├── ContentView.swift
    ├── Models/
    ├── Services/
    └── Views/
```

## API

Приложение использует **AniLiberty API v1**:

| Функция | Endpoint |
|---------|----------|
| Вход | `POST /accounts/users/auth/login` |
| Профиль | `GET /accounts/users/me/profile` |
| Новинки | `GET /anime/releases/latest` |
| Каталог | `GET /anime/catalog/releases` |
| Жанры каталога | `GET /anime/catalog/references/genres` |
| Релиз | `GET /anime/releases/{id}` |
| Коллекции (чтение) | `GET /accounts/users/me/collections/releases` |
| Коллекции (добавить) | `POST /accounts/users/me/collections` |
| Коллекции (удалить) | `DELETE /accounts/users/me/collections` |

Базовый URL: `https://aniliberty.top/api/v1`

Документация: [aniliberty.top/api/docs/v1](https://aniliberty.top/api/docs/v1)

## Лицензия

Проект создан в образовательных целях. Контент принадлежит правообладателям и предоставляется через AniLiberty.
