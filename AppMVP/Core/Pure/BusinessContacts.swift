import Foundation

/// Чем, кроме звонка, можно записаться в организацию.
///
/// Порядок случаев — порядок кнопок на карточке: онлайн-запись сразу ведёт
/// к слоту, мессенджер — к живому человеку без звонка, а сайт — только к
/// тому, чтобы там же искать, как записаться.
enum ContactChannel: String, CaseIterable, Sendable {
    case booking
    case telegram
    case whatsapp
    case viber
    case vk
    case website

    var title: String {
        switch self {
        case .booking: "Онлайн-запись"
        case .telegram: "Telegram"
        case .whatsapp: "WhatsApp"
        case .viber: "Viber"
        case .vk: "ВКонтакте"
        case .website: "Сайт"
        }
    }
}

/// Готовая к открытию ссылка организации.
struct ContactLink: Equatable, Sendable {
    let channel: ContactChannel
    let url: URL
}

/// Разбор ссылок из карточки организации Яндекса.
///
/// Яндекс отдаёт их одним списком «адрес + тег»: `self` — свой сайт,
/// `social` — соцсети и мессенджеры вперемешку, `booking` — онлайн-запись,
/// а `attribution` и `showtimes` к связи с организацией отношения не имеют.
/// Мессенджер по тегу не отличить от соцсети, поэтому он узнаётся по домену.
enum BusinessContacts {
    /// Домены мессенджеров и соцсетей, которые показываем. Остальные соцсети
    /// отбрасываются: записаться через ленту фотографий нельзя.
    private static let domains: [(String, ContactChannel)] = [
        ("t.me", .telegram), ("telegram.me", .telegram),
        ("wa.me", .whatsapp), ("whatsapp.com", .whatsapp),
        ("vk.com", .vk), ("vk.ru", .vk)
    ]

    /// По одной ссылке на канал, в порядке `ContactChannel`.
    ///
    /// Первая ссылка канала побеждает: у сети сервисов Яндекс перечисляет
    /// сначала ссылки этой точки, потом общие для сети.
    static func links(from raw: [(href: String, tag: String?)]) -> [ContactLink] {
        var byChannel: [ContactChannel: URL] = [:]
        for item in raw {
            guard let link = link(href: item.href, tag: item.tag),
                  byChannel[link.channel] == nil else { continue }
            byChannel[link.channel] = link.url
        }
        return ContactChannel.allCases.compactMap { channel in
            byChannel[channel].map { ContactLink(channel: channel, url: $0) }
        }
    }

    /// Одна ссылка или `nil`, если показывать её незачем.
    static func link(href: String, tag: String?) -> ContactLink? {
        guard let url = url(from: href), let scheme = url.scheme?.lowercased() else { return nil }

        // Свои схемы мессенджеров открывают приложение напрямую.
        if scheme == "tg" { return ContactLink(channel: .telegram, url: url) }
        if scheme == "viber" { return ContactLink(channel: .viber, url: url) }
        if scheme == "whatsapp" { return ContactLink(channel: .whatsapp, url: url) }
        guard scheme == "http" || scheme == "https", let host = url.host?.lowercased() else {
            return nil
        }

        if let channel = domains.first(where: { matches(host, $0.0) })?.1 {
            return ContactLink(channel: channel, url: url)
        }
        switch tag?.lowercased() {
        case "booking": return ContactLink(channel: .booking, url: url)
        case "self": return ContactLink(channel: .website, url: url)
        default: return nil
        }
    }

    /// Адрес без схемы («www.servis.ru») Яндекс присылает тоже — ему
    /// дописывается `https://`, иначе у него нет хоста и он не откроется.
    private static func url(from href: String) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let full = trimmed.contains("://") || trimmed.hasPrefix("tg:")
            || trimmed.hasPrefix("viber:") || trimmed.hasPrefix("whatsapp:")
            ? trimmed : "https://" + trimmed
        return URL(string: full)
    }

    /// Домен или его поддомен: `m.vk.com` — это ВКонтакте, `notvk.com` — нет.
    private static func matches(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}

/// Что Яндекс знает об организации сверх названия и адреса: фото, рейтинг,
/// часы работы, рубрики. Из этого собирается карточка места в списке.
///
/// В базу не сохраняется — как и ссылки для записи: приходит заново с каждым
/// поиском, и у своей точки, поставленной булавкой, пусто по построению.
struct PlaceDetails: Equatable, Sendable {
    /// Шаблон адреса фото: `https://avatars.mds.yandex.net/get-altay/…/%s`,
    /// на месте `%s` — размер. Так его отдаёт сниппет фото MapKit (снято
    /// пробой на симуляторе 03.10.2026).
    var photo: String?
    /// Все фото из сниппета в том же виде — для ленты в карточке места.
    /// Первое совпадает с `photo`.
    var photos: [String] = []
    /// Оценка от 1 до 5.
    var rating: Double?
    /// Сколько оценок за ней стоит.
    var ratings = 0
    /// «До 20:00» или «Закрыто до 10:00» — как отдаёт Яндекс.
    var hours: String?
    /// Рубрики: «Автосервис, автотехцентр», «Шиномонтаж».
    var categories: [String] = []

    /// Размеры хранилища фото Яндекса. `large` — 800 px по ширине: карточка
    /// списка на трёхкратном экране занимает 1100, и следующий размер уже
    /// вчетверо тяжелее ради разницы, которой на фото фасада не видно.
    enum PhotoSize: String, Sendable {
        case medium = "L"
        case large = "XL"
    }

    /// Адрес фото нужного размера. `nil`, если шаблона нет, в нём нет места
    /// под размер или он не по https — такой адрес система всё равно не
    /// загрузит, а пустая рамка хуже карточки без фото.
    func photoURL(_ size: PhotoSize) -> URL? {
        photo.flatMap { Self.url($0, size) }
    }

    /// Адреса фото для ленты, не больше `limit`: негодные шаблоны и повторы
    /// выпадают. Сниппет иногда отдаёт десятки снимков — лента из них
    /// грузила бы мегабайты ради карточки на полэкрана.
    func photoURLs(_ size: PhotoSize, limit: Int = 8) -> [URL] {
        var seen = Set<String>()
        return photos.filter { seen.insert($0).inserted }
            .compactMap { Self.url($0, size) }
            .prefix(limit).map { $0 }
    }

    private static func url(_ template: String, _ size: PhotoSize) -> URL? {
        guard template.hasPrefix("https://"), template.contains("%s") else { return nil }
        return URL(string: template.replacingOccurrences(of: "%s", with: size.rawValue))
    }

    /// «4,9» — с запятой и одним знаком. Без оценок `nil`: ноль звёзд у
    /// места, которое никто не оценивал, читался бы как приговор.
    var ratingLabel: String? {
        guard let rating, rating > 0, ratings > 0 else { return nil }
        let tenths = Int((rating * 10).rounded())
        return "\(tenths / 10),\(tenths % 10)"
    }
}
