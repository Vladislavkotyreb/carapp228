# Тестирование Beepy на реальном iPhone

Проект — `Wheelly.xcodeproj`, схема `AppMVP`, bundle ID
`com.vladislavkotyrev.appmvp`, deployment target iOS 17.0.
На домашнем экране приложение подписано **Beepy**.

## Ограничения бесплатного Apple ID

Сейчас сборка подписывается личной командой (бесплатный Apple ID). Из этого
следует три вещи, и обойти их нельзя — это правила Apple:

- **Профиль живёт 7 дней.** Потом приложение перестаёт запускаться, надо
  переустановить (раздел «Установка» ниже, те же команды).
- **Sign in with Apple не работает.** Это платная capability, поэтому
  `CODE_SIGN_ENTITLEMENTS` из проекта убран. Кнопка «Войти с Apple» в
  онбординге остаётся на месте по макету, но по тапу системная шторка не
  покажется — `ASAuthorizationController` вернёт ошибку.
- **Push-уведомления и другие платные capability тоже недоступны.**

Когда появится платный Apple Developer Program, вернуть Sign in with Apple —
одна строка: в обе конфигурации таргета в `project.pbxproj` добавить
`CODE_SIGN_ENTITLEMENTS = AppMVP/App/AppMVP.entitlements;`. Сам файл никуда
не девался и лежит на месте.

## Подготовка (один раз)

### 1. Apple ID в Xcode

**Xcode → Settings → Accounts → «+» → Apple ID**, войти. Xcode сам выпустит
development-сертификат и создаст личную команду.

Проверить, что сертификат появился:

```sh
security find-identity -v -p codesigning
```

Должна быть хотя бы одна строка `Apple Development: ...`.

### 2. Режим разработчика на iPhone

**Настройки → Конфиденциальность и безопасность → Режим разработчика** →
включить → перезагрузить телефон → после разблокировки подтвердить.

Проверить состояние:

```sh
xcrun devicectl list devices
```

Устройство должно быть `connected`, а не `connected (no DDI)`.

## Установка

Узнать UDID устройства:

```sh
xcrun devicectl list devices -j /dev/stdout | grep udid
```

Собрать, установить и запустить (подставить свой UDID):

```sh
UDID=00008130-000A38DA0E04001C

xcodebuild -project Wheelly.xcodeproj -scheme AppMVP \
  -destination "id=$UDID" -allowProvisioningUpdates \
  -derivedDataPath build/device build

xcrun devicectl device install app --device "$UDID" \
  build/device/Build/Products/Debug-iphoneos/Wheelly.app

xcrun devicectl device process launch --device "$UDID" \
  com.vladislavkotyrev.appmvp
```

При первом запуске iPhone скажет, что разработчик не доверен:
**Настройки → Основные → VPN и управление устройством** → выбрать свой
Apple ID → «Доверять».

Альтернатива — открыть проект в Xcode, выбрать iPhone в списке устройств
и нажать ⌘R. Signing & Capabilities → Team должна быть личная команда.

## Что проверять

Флоу приложения задан в `AppMVP/Navigation/RootView.swift`:
онбординг → добавление авто → главный экран. Состояние хранится в
`UserDefaults` (`hasCompletedOnboarding`, `hasAddedCar`), поэтому для повтора
с нуля приложение надо удалить с телефона.

### Онбординг
- [ ] Показывается при первом запуске
- [ ] Перелистывание страниц анимировано
- [ ] Кнопка «Войти с Apple» видна (работать не будет, см. ограничения выше)

### Добавление авто
- [ ] Сегментед-контрол «По номеру» / «По названию» переключается с анимацией
- [ ] Ввод `b777op777` с латинской раскладки даёт `В 777 ОР 777` —
      кириллица, пробелы расставляются сами, десятый символ не вводится
- [ ] Короткий номер → тряска поля и текст ошибки
- [ ] Найденное авто открывается шторкой, выезжающей снизу
- [ ] Шторка закрывается свайпом вниз и тапом по затемнению

### Главный экран
- [ ] Карусель листается свайпом, элементы не прыгают
- [ ] Градиент прижат к верху контента и уходит при скролле
- [ ] Тени карточек ТО не обрезаны
- [ ] Шторка «Добавление ТО» выезжает снизу, текст читается поверх стекла

### Разное
- [ ] Reduce Motion (Настройки → Универсальный доступ → Движение) —
      шторки проявляются, а не выезжают
- [ ] Тёмная тема не ломает вёрстку

## Логи

```sh
xcrun devicectl device process view --device "$UDID" com.vladislavkotyrev.appmvp
```

Или Xcode → Debug area (⌘⇧Y) при запуске через ⌘R.
