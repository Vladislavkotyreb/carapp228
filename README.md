# AppMVP — iOS приложение (SwiftUI + Supabase)

Каркас для пути **Figma → TestFlight**: 5 экранов MVP, MVVM, Supabase Auth и данные.

## Быстрый старт

1. **Xcode** из App Store → [docs/XCODE_SETUP.md](docs/XCODE_SETUP.md)
2. **Apple Developer** $99/год → [docs/APPLE_DEVELOPER.md](docs/APPLE_DEVELOPER.md)
3. **Supabase** проект + SQL → [docs/SUPABASE_SETUP.md](docs/SUPABASE_SETUP.md)
4. Сгенерировать Xcode-проект:

```bash
brew install xcodegen   # один раз
chmod +x scripts/setup.sh
./scripts/setup.sh
open AppMVP.xcodeproj
```

5. Заполните `Config.plist` ключами Supabase
6. Run на симуляторе (⌘R)

## Структура

```
AppMVP/
  App/              — точка входа
  Core/             — Config, Design, Services
  Features/         — Onboarding, Auth, Home, Profile
  Models/           — UserProfile, AppItem
  Navigation/       — RootView, AppState
  Resources/        — Assets
supabase/schema.sql — SQL для Supabase
docs/               — гайды по каждому этапу
```

## Экраны MVP

| Экран | Файл |
|-------|------|
| Onboarding | `Features/Onboarding/OnboardingView.swift` |
| Login | `Features/Auth/LoginView.swift` |
| SignUp | `Features/Auth/SignUpView.swift` |
| Home | `Features/Home/HomeView.swift` |
| Profile | `Features/Profile/ProfileView.swift` |

User flows: [docs/MVP_FLOWS.md](docs/MVP_FLOWS.md)

## TestFlight

Полный чеклист: [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md)

## Figma

Пришлите ссылку на макет — обновим `Theme.swift` и экраны под ваш дизайн.

## Bundle ID

`com.vladislavkotyrev.appmvp` — измените в Xcode при необходимости.
