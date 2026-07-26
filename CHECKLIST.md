# Чеклист: Figma → TestFlight

Отмечайте по порядку. Код и документация уже в [`ios-app`](/Users/vladislavkotyrev/Desktop/ios-app).

## 1. Apple Developer (вы)

- [ ] Зарегистрироваться: [developer.apple.com/programs](https://developer.apple.com/programs/)
- [ ] Дождаться статуса **Active**
- [ ] Подробнее: [docs/APPLE_DEVELOPER.md](docs/APPLE_DEVELOPER.md)

## 2. Xcode (вы)

- [ ] Установить **Xcode** из App Store
- [ ] `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
- [ ] `open AppMVP.xcodeproj`
- [ ] Подробнее: [docs/XCODE_SETUP.md](docs/XCODE_SETUP.md)

## 3. MVP и Figma (вы + AI)

- [x] 5 экранов описаны: [docs/MVP_FLOWS.md](docs/MVP_FLOWS.md)
- [ ] Прислать ссылку на Figma для подгонки дизайна
- [ ] Добавить App Icon 1024×1024 в `Assets.xcassets/AppIcon`

## 4. Supabase (вы)

- [ ] Создать проект на [supabase.com](https://supabase.com)
- [ ] Выполнить [supabase/schema.sql](supabase/schema.sql) в SQL Editor
- [ ] Скопировать URL и anon key в `Config.plist`
- [ ] Подробнее: [docs/SUPABASE_SETUP.md](docs/SUPABASE_SETUP.md)

## 5. Сборка (вы)

- [ ] Xcode → Resolve Package Versions (Supabase SDK)
- [ ] Signing → выбрать Team
- [ ] Run на симуляторе (⌘R)
- [ ] Пройти onboarding → регистрация → home

## 6. iPhone (вы)

- [ ] Подключить iPhone, включить Developer Mode
- [ ] Run на устройстве
- [ ] Чеклист: [docs/DEVICE_TESTING.md](docs/DEVICE_TESTING.md)

## 7. TestFlight (вы)

- [ ] Создать app в App Store Connect
- [ ] Product → Archive → Upload
- [ ] TestFlight → Internal/External testing
- [ ] Подробнее: [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md)

## Уже сделано в проекте

- SwiftUI приложение с MVVM (5 экранов)
- Supabase Auth + CRUD для `items`
- SQL-схема с RLS
- Xcode-проект `AppMVP.xcodeproj`
- Design tokens и переиспользуемые компоненты
