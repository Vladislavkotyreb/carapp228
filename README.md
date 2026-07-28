# Beepy — iOS-приложение

SwiftUI, таргет iOS 17.0. Дизайн ведётся в Figma
(файл `9GXgWezTGI6TjklsnuBns2`) и воспроизводится попиксельно.

Данные пользователя хранятся **локально на устройстве** (SwiftData) —
приложение делается для российских пользователей, и до появления сервера
в РФ персональные данные телефон не покидают. Подробности и план бэкенда —
[docs/BACKEND.md](docs/BACKEND.md).

## Быстрый старт

```bash
open Wheelly.xcodeproj
```

Схема `AppMVP`, ⌘R на симуляторе. Для запуска на своём iPhone —
[docs/DEVICE_TESTING.md](docs/DEVICE_TESTING.md).

## Структура

```
AppMVP/
  App/                    — точка входа, ModelContainer
  Core/Design/            — токены Figma и общие компоненты
  Features/Onboarding/    — онбординг
  Features/AddCar/        — добавление машины, шторка «Это ваш автомобиль?»
  Features/Main/          — раздел «Машина», добавление ТО
  Models/                 — Car, ServiceRecord (SwiftData)
  Navigation/             — RootView, AppState
  Resources/              — Assets
docs/                     — устройство проекта и процессы
docs/JOURNAL.md           — журнал решений и граблей, читать первым
docs/CAR_IMAGES.md        — откуда брать изображения машин
```

## Флоу

Онбординг → добавление машины → главный экран.
Маршрут задан в `AppMVP/Navigation/RootView.swift` и зависит от того,
есть ли машина в базе. Подробно — [docs/MVP_FLOWS.md](docs/MVP_FLOWS.md).

## Про проект Xcode

`Wheelly.xcodeproj/project.pbxproj` ведётся **вручную**: XcodeGen не
установлен, `project.yml` оставлен только для справки и уже разошёлся с
реальным проектом. Новый `.swift`-файл нужно прописать в четырёх местах —
`PBXBuildFile`, `PBXFileReference`, `children` группы и `PBXSourcesBuildPhase`.
После правки — `plutil -lint Wheelly.xcodeproj/project.pbxproj`.

## Bundle ID

`com.vladislavkotyrev.appmvp`, на устройстве приложение подписано как **Beepy**.
