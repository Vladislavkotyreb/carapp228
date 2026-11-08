# Выпуск Beepy — 08.11.2026

Версия 1.0.0, новая сборка 5 (исправления после запроса Apple 2.1). Бесплатно, все доступные страны по решению
владельца. Подписок, покупок и платных экранов нет.

Build 5: кликабельные условия Яндекса и ограниченный кэш адресов.
Материалы: APPLE_MATERIALS.txt; видео ещё не приложено.

## Готово

- Новая карта и раздел «Ещё» в main (PR #10).
- Оригинальная иконка с жирафом 1024×1024 в main (PR #11).
- Платная команда Apple Developer 5BK4R35RB8; build 4 загружен в ASC и обработан.
- Sign in with Apple в новой сборке: системный вход, локальный Keychain,
  выход, удаление данных и инструкция ручного отзыва доступа Apple.
- Данные автомобилей хранятся на устройстве, сервера аккаунтов нет.
- Поиск по номеру без сервера скрыт. Ручное добавление без ограничений.
  При подключении API действует лимит на две машины с номером;
  прямая Debug-сборка владельца на iPhone без лимита.

## Карточка App Store Connect

- Публичная политика: https://vladislavkotyreb.github.io/carapp228/privacy.html
- Поддержка: https://vladislavkotyreb.github.io/carapp228/
- Описание, ключевые слова, контакты ревью и инструкции Apple-входа сохранены.
- Четыре скриншота 1206×2622 загружены; реальные экраны на тестовой базе.
- Категория «Утилиты», подзаголовок «Пробег, поездки и обслуживание», рейтинг 4+.
- Цена 0 во всех регионах; доступность 175 стран и регионов; автоматический релиз.
- Build 4 (1.0.0) прикреплён к версии. Старые build 1–3 не выбирать.
- App Privacy: точная геолокация, ID устройства и прочие данные (IP),
  функциональность приложения, связь через устройство, без отслеживания.
  Декларация опубликована после подтверждения владельцем точности сведений
  и обязательства обновлять их при изменениях.
- Права на сторонние материалы подтверждены владельцем и сохранены в ASC.
- Версия 1.0.0 (4) отправлена на App Review 08.11.2026 в 02:51
  (время, отображённое ASC). 08.11.2026 Apple отклонила заявку по 2.1:
  требуется дополнительная информация и видео с физического устройства.
  Черновик ответа: docs/APPLE_REVIEW_NOTES.txt. Перед отправкой заполнить
  сведения о видео и приложить применимые документы на сторонние материалы.
- Идентификатор отправки: fdf515df-0fdc-4c9f-9187-bb13f25bf6ab.
  https://appstoreconnect.apple.com/apps/6826206089/distribution/reviewsubmissions/details/fdf515df-0fdc-4c9f-9187-bb13f25bf6ab
- Публикация в магазине произойдёт автоматически после одобрения Apple.
  Отправка на проверку не означает, что приложение уже доступно в App Store.

Сервер поиска и баланс поставщика отложены владельцем. Они не нужны для
локального Apple-входа и ручного добавления; перед включением API обновить
политику и анкету данных.

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
