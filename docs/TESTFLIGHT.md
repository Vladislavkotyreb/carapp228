# TestFlight: от Archive до тестеров

## Предусловия

- [ ] Apple Developer Program активен
- [ ] Приложение стабильно на реальном iPhone
- [ ] App Icon 1024×1024 в `Assets.xcassets/AppIcon`

## 1. App Store Connect — создать приложение

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **My Apps** → **+** → **New App**
2. Platform: iOS
3. Name: отображаемое имя (например `App MVP`)
4. Bundle ID: `com.vladislavkotyrev.appmvp`
5. SKU: любой внутренний ID (например `appmvp-001`)

## 2. Версионирование в Xcode

Target AppMVP → General:

| Поле | Значение |
|------|----------|
| Version | `1.0.0` |
| Build | `1` (увеличивать при каждой загрузке) |

## 3. Archive

1. Схема: **Any iOS Device (arm64)** — не симулятор
2. **Product → Archive**
3. Organizer → **Distribute App**
4. **App Store Connect** → **Upload**
5. Оставить defaults (Include bitcode — нет для современных проектов)

Ожидание обработки в ASC: 15–60 минут.

## 4. TestFlight

1. App Store Connect → ваше приложение → **TestFlight**
2. Билд появится со статусом **Processing**, затем **Ready to Test**
3. **Export Compliance**: для стандартного HTTPS обычно «No» на custom encryption
4. Заполните **Beta App Information** (описание, feedback email)

### Internal testing (мгновенно)

- До 100 пользователей с ролью в App Store Connect
- TestFlight → Internal Testing → добавить группу

### External testing (1–2 дня review первый раз)

- До 10 000 тестеров
- Нужен **Privacy Policy URL**
- TestFlight → External Testing → Submit for Review

## 5. Приглашение тестеров

Тестеры устанавливают **TestFlight** из App Store → принимают invite по email или public link.

## Типичные ошибки

| Ошибка | Решение |
|--------|---------|
| Archive disabled | Выбрать Any iOS Device |
| Invalid Bundle | Уникальный Bundle ID, совпадает с ASC |
| Missing compliance | TestFlight → ответить на encryption questionnaire |
| Build не появляется | Проверить email от Apple, подождать до 1 ч |

## Следующий билд

Увеличьте **Build** number → Archive → Upload снова.
