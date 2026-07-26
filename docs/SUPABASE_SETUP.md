# Настройка Supabase

## 1. Создать проект

1. [supabase.com](https://supabase.com) → **New project**
2. Запишите **Project URL** и **anon public key** (Settings → API)

## 2. Выполнить SQL-схему

1. Dashboard → **SQL Editor** → New query
2. Вставьте содержимое файла [`supabase/schema.sql`](../supabase/schema.sql)
3. Run

## 3. Authentication

Dashboard → **Authentication** → **Providers**:

- **Email**: включить
- **Confirm email**: для MVP можно отключить (быстрее тестировать)
- **Apple** (опционально): настроить после Apple Developer

Dashboard → **Authentication** → **URL Configuration**:

- Site URL: `appmvp://login-callback` (для deep link позже)

## 4. Подключить к iOS

1. Скопируйте шаблон:

```bash
cp Config.example.plist Config.plist
```

2. Заполните в `Config.plist`:

```xml
<key>SUPABASE_URL</key>
<string>https://YOUR_PROJECT.supabase.co</string>
<key>SUPABASE_ANON_KEY</key>
<string>YOUR_ANON_KEY</string>
```

`Config.plist` в `.gitignore` — не коммитьте ключи.

## 5. Проверка

После запуска приложения:

1. Sign Up с тестовым email
2. В Dashboard → **Authentication** → **Users** должен появиться пользователь
3. В **Table Editor** → `items` — строки после добавления с клиента

## Модель данных

| Таблица | Поля |
|---------|------|
| `profiles` | `id` (uuid, FK auth.users), `display_name`, `created_at` |
| `items` | `id`, `user_id`, `title`, `created_at` |

Row Level Security включён: пользователь видит только свои `items`.
