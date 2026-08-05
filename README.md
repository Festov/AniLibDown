# AniLibDown

Нативное iOS-приложение на **SwiftUI** для просмотра и скачивания аниме с [AniLiberty](https://aniliberty.top).

**Версия:** 1.1.2 · **iOS:** 17+

> **Важно:** приложение полностью написано нейросетью. Возможны баги и нестабильная работа.  
> Если что-то сломалось — создайте запись в [Проблемах](https://github.com/Festov/AniLibDown/issues) (желательно со скриншотом).

## Возможности

- **Каталог** — лента аниме, поиск с историей запросов, фильтры по жанрам, сортировке и году, блок «Продолжить просмотр»
- **Расписание** — ближайшие выходы и расписание на неделю, подписка на напоминания о сериях
- **Карточка тайтла** — описание, жанры, связанные релизы, команда озвучки, список серий
- **Онлайн-просмотр** — HLS-плеер с выбором качества (в том числе во время просмотра), сменой серий, перемоткой, пропуском OP/ED, субтитрами (если есть в потоке), Picture-in-Picture и AirPlay
- **Прогресс** — сохранение места просмотра и продолжение с той же серии
- **Офлайн** — скачивание серий (по одной или все сразу), очередь загрузок, повтор при ошибке, просмотр без интернета
- **Уведомления** — о выходе новых серий и о завершении загрузки; напоминание в день выхода (для онгоингов)
- **Аккаунт AniLiberty** — вход, профиль, коллекции («Смотрю», «В планах», «Просмотрено» и др.) с синхронизацией
- **Shikimori** (опционально) — привязка тайтлов, статусы списка, синхронизация серии при досмотре, экспорт/импорт привязок
- **Настройки** — тема, заставка, качество по умолчанию, параметры плеера и загрузок (в т.ч. только Wi‑Fi), очистка кэша

## Установка на iPhone

### 1. Скачайте IPA

1. Откройте **[Releases](https://github.com/Festov/AniLibDown/releases)**
2. Скачайте **`AniLibDown.ipa`** из последнего релиза

### 2. Установите через Sideloadly (Windows)

1. На iPhone: **Настройки → Конфиденциальность и безопасность → Режим разработчика**
2. Установите **[Sideloadly](https://sideloadly.io)**
3. Подключите iPhone по USB и разблокируйте
4. Перетащите IPA в Sideloadly (или выберите через «Выбор .ipa»)
5. Укажите Apple ID и устройство
6. Нажмите **Start**
7. На iPhone: **Настройки → Основные → VPN и управление устройством** → доверьте разработчику

### Ограничения бесплатного Apple ID

- Приложение живёт **~7 дней**, затем нужна переустановка
- До **10** sideload-приложений одновременно
- Можно настроить обновление по Wi‑Fi в одной сети с компьютером

## API

Базовый URL: `https://aniliberty.top/api/v1`  
Документация: [aniliberty.top/api/docs/v1](https://aniliberty.top/api/docs/v1)

| Функция | Endpoint |
|---------|----------|
| Вход | `POST /accounts/users/auth/login` |
| Профиль | `GET /accounts/users/me/profile` |
| Каталог | `GET /anime/catalog/releases` |
| Жанры | `GET /anime/catalog/references/genres` |
| Релиз | `GET /anime/releases/{id}` |
| Участники релиза | `GET /anime/releases/{id}/members` |
| Расписание | `GET /anime/schedule/now`, `…/week` |
| Коллекции | `GET/POST/DELETE …/collections…` |

## Shikimori (опционально)

1. Создайте OAuth-приложение на [shikimori.io/oauth/applications](https://shikimori.io/oauth/applications)
2. **Redirect URI:** `anilibdown://shikimori/callback`
3. Скопируйте `AniLibDown/AniLibDown/ShikimoriSecrets.plist.example` → `ShikimoriSecrets.plist`
4. Впишите `ClientId` и `ClientSecret`
5. В приложении: **Профиль → Shikimori → Подключить**, в карточке — **Привязать к Shikimori**

Синхронизируются статус списка и номер серии при досмотре. Привязки хранятся локально; в профиле есть экспорт и импорт JSON.

## Разработка

- **Xcode** 16.x, iOS 17+
- Проект: `AniLibDown/AniLibDown.xcodeproj`, схема `AniLibDown`
- Unit-тесты: `AniLibDownTests`
- CI **Build IPA**: тесты и неподписанный IPA; релиз по тегу

```bash
cd AniLibDown
xcodebuild -project AniLibDown.xcodeproj -scheme AniLibDown \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

| Папка | Назначение |
|-------|------------|
| `AniLibDown/Models/` | Модели API и домена |
| `AniLibDown/Services/` | Сеть, загрузки, хранилища, настройки |
| `AniLibDown/Views/` | Экраны SwiftUI |
| `AniLibDownTests/` | Unit-тесты |

## Лицензия

Проект создан в образовательных целях. Контент принадлежит правообладателям и предоставляется через AniLiberty.
