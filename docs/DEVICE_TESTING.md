# Тестирование на реальном iPhone

## Подготовка iPhone

1. iOS 17+ (deployment target проекта)
2. **Settings → Privacy & Security → Developer Mode** → On (после первой установки с Xcode)
3. Подключите iPhone по USB или Wi-Fi debugging

## Запуск из Xcode

1. Откройте `AppMVP.xcodeproj`
2. Вверху выберите ваш **iPhone** (не симулятор)
3. Signing & Capabilities → Team = ваш Developer аккаунт
4. **Run** (⌘R)
5. На iPhone: **Trust** этот компьютер / разработчика

## Чеклист тестирования MVP

### Onboarding
- [ ] Показывается при первом запуске
- [ ] Кнопка «Начать» ведёт на Login
- [ ] Повторный запуск пропускает onboarding

### Auth
- [ ] Регистрация создаёт пользователя в Supabase
- [ ] Вход с верными данными → Home
- [ ] Неверный пароль → понятная ошибка
- [ ] Выход из Profile → Login

### Home
- [ ] Список загружается
- [ ] Pull-to-refresh работает
- [ ] Empty state при пустой таблице

### Сеть
- [ ] Airplane mode → error state
- [ ] Восстановление сети → retry работает

## Wi-Fi debugging (опционально)

Xcode → Window → Devices and Simulators → Connect via network

## Логи

Xcode → Debug area (⌘⇧Y) — смотрите `print` и ошибки Supabase.
