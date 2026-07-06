# Как получить .ipa и установить на iPhone (без Mac)

## Способ 1: Без секретов GitHub (рекомендуется)

Sideloadly сам подпишет приложение вашим Apple ID при установке. Секреты в GitHub **не нужны**.

### Шаг 1. Запустите сборку

1. GitHub → вкладка **Actions**
2. Workflow **Build IPA** → **Run workflow**
3. Тип сборки: **`unsigned`** (по умолчанию)
4. Нажмите **Run workflow**
5. Через 5–15 минут скачайте артефакт **AniLibDown-ipa**

Внутри будет файл **`AniLibDown.ipa`**.

### Шаг 2. Установите через Sideloadly (Windows)

1. Скачайте [Sideloadly](https://sideloadly.io)
2. Подключите iPhone по USB
3. Перетащите `AniLibDown.ipa` в Sideloadly
4. Введите **Apple ID** и **пароль для приложений**
   - Пароль создаётся на [appleid.apple.com](https://appleid.apple.com) → Безопасность → Пароли приложений
5. Нажмите **Start**

Готово — приложение появится на iPhone.

### Ограничения бесплатного Apple ID

- Приложение работает **~7 дней**, потом переустановите
- Одновременно до **3** sideload-приложений

---

## Способ 2: Подписанная сборка в GitHub (опционально)

Нужен, только если Sideloadly не подходит. Требует секреты в GitHub.

### Секреты

Репозиторий → **Settings** → **Secrets and variables** → **Actions**

| Secret | Значение |
|--------|----------|
| `APPLE_ID` | Email Apple ID |
| `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD` | Пароль для приложений |
| `TEAM_ID` | Team ID с [developer.apple.com/account](https://developer.apple.com/account) |
| `DEVICE_UDID` | UDID iPhone (необязательно) |

### Запуск

1. **Actions** → **Build IPA** → **Run workflow**
2. Тип сборки: **`signed`**
3. Скачайте артефакт **AniLibDown-ipa-signed**

---

## Частые ошибки

| Ошибка | Решение |
|--------|---------|
| `exit code 1` на шаге Build signed IPA | Используйте тип **`unsigned`** — секреты не нужны |
| `Не задан секрет APPLE_ID` | Выбрали `signed`, но секреты не добавлены |
| Sideloadly не ставит | Проверьте пароль для приложений, не обычный пароль Apple ID |
| Приложение пропало через неделю | Нормально для бесплатного Apple ID — переустановите |

## Альтернатива

**[Codemagic](https://codemagic.io)** — подключите репозиторий, войдите Apple ID через сайт, скачайте `.ipa`.
