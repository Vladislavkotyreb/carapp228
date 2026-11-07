# Выпуск Beepy — 08.11.2026

Версия 1.0.0, новая сборка 2. Бесплатно, все доступные страны по решению
владельца. Подписок, покупок и платных экранов нет.

## Готово

- Новая карта и раздел «Ещё» в main (PR #10).
- Оригинальная иконка с жирафом 1024×1024 в main (PR #11).
- Платная команда Apple Developer 5BK4R35RB8; build 1 загружен в ASC.
- Sign in with Apple в новой сборке: системный вход, локальный Keychain,
  выход, удаление данных и инструкция ручного отзыва доступа Apple.
- Данные автомобилей хранятся на устройстве, сервера аккаунтов нет.
- Поиск по номеру без сервера скрыт. Ручное добавление без ограничений.
  При подключении API действует лимит на две машины с номером;
  прямая Debug-сборка владельца на iPhone без лимита.

## До отправки на ревью

- Apple-вход на iPhone подтверждён владельцем; build 2 успешно загружен.
  Дождаться обработки Apple и выбрать его вместо build 1 с подпиской.
- Опубликовать политику конфиденциальности с заполненными реквизитами
  оператора. Черновики: `Core/Pure/LegalText.swift`, `server/src/privacy.ts`.
- Скриншоты, возрастной рейтинг, App Privacy, бесплатная цена и доступность
  всех стран в App Store Connect должны соответствовать новой сборке.
- Сервер поиска и баланс поставщика отложены владельцем. Они не нужны для
  локального Apple-входа и ручного добавления; перед включением API
  обновить политику и анкету данных.

## Контакты для Apple

Владелец разрешил указать Vladislav Kotyrev, kotvlad2016@gmail.com,
+995597125736. Вход через Apple обязателен; собственных логина и пароля
Beepy нет. В заметках ревью объяснить системный Sign in with Apple.

## Заметки для ревью

Beepy is a free local car journal. Sign in with Apple is required; use
Sign in with Apple with your Apple Account. No separate Beepy password is
needed. We do not request the user's name or email. Car records stay on
the device. The More screen offers sign out and account/data deletion.
After deletion the app explains how to revoke Sign in with Apple access
in Apple Account settings. License-plate lookup is unavailable in this
release. Cars can be added manually without a subscription or purchase.
Background location supports optional automatic mileage tracking. Engine
sound is analyzed on device. Yandex Maps provides maps and geocoding.

## Проверки

`tools/run-pure-checks.sh`, `tools/check-project.py`,
`tools/check-typography.py`, `tools/build-licenses.py --check`, серверные
тесты и XCTest схемы AppMVP. UI-тесты используют in-memory базу;
флаг `-beepy-test-authenticated` действует только в DEBUG.
Фактические команды и результаты записываются в JOURNAL.md.
