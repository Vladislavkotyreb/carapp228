# Apple Developer Program — чеклист

TestFlight доступен только с платным аккаунтом разработчика.

## Шаги (выполните вручную)

1. Откройте [developer.apple.com/programs](https://developer.apple.com/programs/enroll/)
2. Войдите с Apple ID (обязательна **двухфакторная аутентификация**)
3. Выберите тип: **Individual** (физлицо) или **Organization** (компания)
4. Оплатите **$99/год**
5. Пройдите верификацию личности (обычно 1–3 рабочих дня)
6. После одобрения откройте [App Store Connect](https://appstoreconnect.apple.com)

## Проверка готовности

- [ ] Статус в [developer.apple.com/account](https://developer.apple.com/account) — **Active**
- [ ] В Xcode → Settings → Accounts видна ваша Team
- [ ] В App Store Connect доступен раздел **My Apps**

## Bundle ID для этого проекта

Зарегистрируйте в [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list):

```
com.vladislavkotyrev.appmvp
```

Или измените `PRODUCT_BUNDLE_IDENTIFIER` в Xcode на свой уникальный ID.

## Sign in with Apple (если используете email + Apple login)

1. Identifiers → ваш App ID → включите **Sign in with Apple**
2. В Supabase Dashboard → Authentication → Apple — добавьте Service ID и ключ
