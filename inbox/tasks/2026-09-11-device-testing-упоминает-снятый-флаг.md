---
status: todo
kind: task
scope: docs/DEVICE_TESTING.md
---

`docs/DEVICE_TESTING.md`, строка 97, в разделе про повтор онбординга называет
флаг `hasAddedCar` в `UserDefaults`. Флага больше нет: наличие машины
выводится из SwiftData — см. `AppMVP/Navigation/AppState.swift:9` и
`docs/DECISIONS.md`. По этой инструкции онбординг повторно не откроется.

## Готово, когда
- Документ описывает настоящий способ сбросить онбординг.
- `hasCompletedOnboarding` перепроверен: он-то существует или тоже снят?
- Строка про этот хвост вычеркнута в `docs/TAILS.md`.
