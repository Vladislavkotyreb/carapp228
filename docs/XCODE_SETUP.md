# Установка Xcode и первый запуск

**Xcode уже стоит** (26.6, `xcode-select -p` → `/Applications/Xcode.app`), сборка
и симулятор работают. Этот документ нужен на новой машине или после переустановки
системы: когда в терминале есть только **Command Line Tools**, а полного Xcode нет.

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
# Xcode 26.6 ...
```

## Открыть проект

Проект называется `Wheelly.xcodeproj`, схема — `AppMVP`. Из папки проекта:

```bash
open Wheelly.xcodeproj
```

## Первый запуск

1. Выберите симулятор **iPhone 16** (или любой iPhone)
2. Нажмите **Run** (⌘R)

## Signing

1. Target **AppMVP** → **Signing & Capabilities**
2. Team: ваш Apple Developer аккаунт
3. **Automatically manage signing**: включено
4. Bundle Identifier: `com.vladislavkotyrev.appmvp` (или свой)

Без Developer Program можно запускать только на симуляторе. Для TestFlight нужен платный аккаунт.
