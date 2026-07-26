# Установка Xcode и первый запуск

На вашем Mac сейчас установлены только **Command Line Tools**, полный Xcode отсутствует.

## Установка

1. Откройте **App Store** → найдите **Xcode** → Install (~12–15 GB)
2. После установки запустите Xcode один раз и примите лицензию
3. В терминале переключите активный developer directory:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

4. Проверка:

```bash
xcodebuild -version
# Xcode 16.x ...
```

## Открыть проект

```bash
open /Users/vladislavkotyrev/Desktop/ios-app/AppMVP.xcodeproj
```

## Первый запуск

1. Выберите симулятор **iPhone 16** (или любой iPhone)
2. Нажмите **Run** (⌘R)
3. При первом запуске Xcode предложит **Resolve Package Versions** для Supabase SDK — согласитесь

## Signing

1. Target **AppMVP** → **Signing & Capabilities**
2. Team: ваш Apple Developer аккаунт
3. **Automatically manage signing**: включено
4. Bundle Identifier: `com.vladislavkotyrev.appmvp` (или свой)

Без Developer Program можно запускать только на симуляторе. Для TestFlight нужен платный аккаунт.
