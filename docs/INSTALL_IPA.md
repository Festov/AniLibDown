# Как получить .ipa и установить на iPhone (без Mac)

Артефакт **AniLibDown-simulator** вам **не нужен** — это сборка для симулятора, на телефон она не ставится. Вам нужен workflow **Build IPA**.

## Шаг 1. Подготовьте Apple ID

Нужен обычный Apple ID (бесплатно) или Apple Developer (99 $/год).

1. Зайдите на [appleid.apple.com](https://appleid.apple.com)
2. Включите **двухфакторную аутентификацию**
3. Создайте **пароль для приложений** (App-Specific Password):
   - Безопасность → Пароли приложений → Создать
   - Сохраните пароль (формат `xxxx-xxxx-xxxx-xxxx`)

## Шаг 2. Узнайте Team ID

1. Откройте [developer.apple.com/account](https://developer.apple.com/account)
2. Войдите тем же Apple ID
3. Скопируйте **Team ID** (10 символов, например `AB12CD34EF`)

Если платного аккаунта нет — используйте **Personal Team** (тот же Apple ID, Team ID всё равно есть).

## Шаг 3. Узнайте UDID iPhone (рекомендуется)

UDID нужен, чтобы приложение установилось именно на ваш телефон.

**На Windows:**
1. Подключите iPhone к ПК
2. Откройте iTunes или приложение «Apple Devices» / 3uTools / iMazing
3. Скопируйте **UDID** (40 символов)

**Без ПК:** на iPhone откройте в Safari ссылку с [get.udid.io](https://get.udid.io) или аналогичный сервис.

## Шаг 4. Добавьте секреты в GitHub

Репозиторий → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

| Secret | Значение |
|--------|----------|
| `APPLE_ID` | Ваш email Apple ID |
| `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD` | Пароль для приложений из шага 1 |
| `TEAM_ID` | Team ID из шага 2 |
| `DEVICE_UDID` | UDID iPhone из шага 3 |

## Шаг 5. Запустите сборку IPA

1. Вкладка **Actions** → workflow **Build IPA**
2. **Run workflow** → **Run workflow**
3. Подождите 10–20 минут
4. Скачайте артефакт **AniLibDown-ipa**
5. Внутри будет файл **`AniLibDown.ipa`**

## Шаг 6. Установите на iPhone (Windows)

### Вариант A: Sideloadly (проще)

1. Скачайте [Sideloadly](https://sideloadly.io) на Windows
2. Подключите iPhone по USB
3. Перетащите `AniLibDown.ipa` в Sideloadly
4. Введите Apple ID и пароль для приложений
5. Нажмите **Start**

### Вариант B: AltStore

1. Установите [AltServer](https://altstore.io) на Windows
2. Установите AltStore на iPhone
3. Откройте `AniLibDown.ipa` через AltStore

## Ограничения бесплатного Apple ID

- Приложение работает **~7 дней**, потом нужно переустановить
- Одновременно до **3** sideload-приложений
- С платным Apple Developer — до 1 года и TestFlight

## Если сборка упала

| Ошибка | Решение |
|--------|---------|
| `No signing certificate` | Проверьте `APPLE_ID` и пароль для приложений |
| `Device not in provisioning profile` | Добавьте секрет `DEVICE_UDID` |
| `Team ID mismatch` | Проверьте `TEAM_ID` на developer.apple.com |
| Workflow не виден | Смержите PR в `main` или запустите с ветки, где есть workflow |

## Альтернатива без GitHub Secrets

Сервис **[Codemagic](https://codemagic.io)** (бесплатный тариф): подключите репозиторий, войдите Apple ID через веб-интерфейс — сервис сам соберёт и отдаст `.ipa`.
