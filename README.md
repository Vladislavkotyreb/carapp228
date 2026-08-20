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
```

## Документы

| Файл | Что |
|---|---|
| [CLAUDE.md](CLAUDE.md) | **Точка входа.** Продукт, порядок работы, сборка, минимум проверок, ограничения окружения |
| [docs/STATE.md](docs/STATE.md) | **Источник правды:** состояние двенадцати компонентов и их дефекты. При расхождении с любым доком верить коду, потом ему |
| [docs/TRAPS.md](docs/TRAPS.md) | Грабли — механизмы, а не симптомы. Читать перед работой над вью |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Решения с причинами. Решения, которого здесь нет, не существует |
| [docs/JOURNAL.md](docs/JOURNAL.md) | Хроника работ и разборы |
| [docs/TAILS.md](docs/TAILS.md) | Хвосты размером в вечер |
| [CHECKLIST.md](CHECKLIST.md) | Что сделано и что дальше — от вас и от меня |
| [docs/MVP_FLOWS.md](docs/MVP_FLOWS.md) | Экраны, маршрутизация, соответствие нодам Figma |
| [docs/DIAGNOSIS.md](docs/DIAGNOSIS.md) | Разбор звука: сервер, модель, пороги |
| [docs/BACKEND.md](docs/BACKEND.md), [docs/DATABASES.md](docs/DATABASES.md) | План бэкенда и где держать базу в РФ |
| [docs/CAR_IMAGES.md](docs/CAR_IMAGES.md) | Откуда брать изображения машин |
| [docs/DEVICE_TESTING.md](docs/DEVICE_TESTING.md), [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md), [docs/APPLE_DEVELOPER.md](docs/APPLE_DEVELOPER.md), [docs/XCODE_SETUP.md](docs/XCODE_SETUP.md) | Как поставить, подписать, раздать |

Полная карта со слоями и правилом для каждого — [docs/STATE.md](docs/STATE.md), Часть V.

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
