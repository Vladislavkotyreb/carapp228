import AVFAudio
import SwiftData
import SwiftUI

/// Раздел «Ещё»: автопробег и история поездок.
///
/// Автопробег считает километры поездок (`TripTracker`). Переключатель в
/// карточке включает автоопределение: Beepy замечает поездку сам, кнопки и
/// «Команд» при этом нет. Выключен — поездку начинает кнопка «Начать
/// поездку» или команды из автоматизации по Bluetooth, которую человек
/// собирает в «Быстрых командах». Переключатель один, а не «Автопробег»
/// плюс «Автоопределение»: два слова на «авто» рядом читались двумя
/// функциями (вопрос пользователя 09.10.2026). Экран даёт ещё выключатель
/// геопозиции, строку с системным доступом, привязку Bluetooth машины
/// (`TripLink`), синхронизацию с сервером (`TripSync`) и историю; лишнюю
/// поездку удаляет её экран.
///
/// Тексты короткие намеренно (замечание пользователя 08.10.2026: «поменьше
/// текста, выглядит нейронно»): подпись там, где без неё непонятно, что
/// делать, и нигде больше.
struct MoreScreen: View {
    @ObservedObject private var tracker = TripTracker.shared
    @ObservedObject private var sync = TripSync.shared
    @Query(sort: \Trip.endedAt, order: .reverse) private var trips: [Trip]
    @Query private var cars: [Car]
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(LocationSwitch.key) private var locationOn = true
    @AppStorage(AutoSwitch.key) private var autoOn = false
    /// Машина для поездок без явного выбора; пусто — первая добавленная.
    @AppStorage(TripCar.key) private var tripCar = ""

    /// Последняя поездка с экрана вышла короче порога и не записалась.
    @State private var tooShort = false
    /// Поездка, открытая экраном с картой.
    @State private var opened: TripDetails?
    /// Выходы звука сейчас: к чему подключён телефон.
    @State private var outputs: [TripLink.Port] = []
    /// Выход, который человек собрался привязать, — ждёт подтверждения.
    @State private var binding: TripLink.Port?
    /// Нажали «Bluetooth», а привязывать нечего.
    @State private var noBluetooth = false
    /// Согласие на синхронизацию: открыто, ждёт сервера, чем кончилось.
    @State private var consentShown = false
    @State private var consentBusy = false
    @State private var consentError: String?
    @State private var confirmWipe = false
    @State private var licensesShown = false

    private enum Layout {
        static let margin: CGFloat = 16
        static let section: CGFloat = 32
        static let row: CGFloat = 52
        static let radius: CGFloat = 26
        static let button: CGFloat = 52
        /// Высота затухания под статус-баром поверх его собственной зоны.
        static let statusFade: CGFloat = 16
        /// Сколько поездок показывать: экран — настройка и свежая история, а
        /// не журнал за год.
        static let tripsShown = 6
        /// Под плавающий таббар на iOS до 26.
        static let tail: CGFloat = 110
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Layout.section) {
                Text("Ещё")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Figma.labelsPrimary)

                tripCard
                setup
                if TripSync.isShipped, TripSync.serverURL != nil { syncSection }
                history
                about
            }
            .padding(.horizontal, Layout.margin)
            .padding(.top, 8)
            .padding(.bottom, Layout.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Figma.backgroundsPrimary.ignoresSafeArea())
        // Под статус-баром контент гаснет в фон: без этого прокрученные
        // карточки наезжали на часы (кадр 08.10.2026).
        .overlay(alignment: .top) {
            LinearGradient(colors: [Figma.backgroundsPrimary, Figma.backgroundsPrimary.opacity(0)],
                           startPoint: .init(x: 0.5, y: 0.7), endPoint: .bottom)
                // Порядок важен: сначала выход под статус-бар, потом высота.
                // Наоборот полоса оставалась 16 pt у самого верха экрана и
                // часы не закрывала.
                .ignoresSafeArea(edges: .top)
                .frame(height: Layout.statusFade)
                .allowsHitTesting(false)
        }
        .sheet(item: $opened) { trip in
            TripSheet(trip: trip, onDelete: { delete(trip) }) { opened = nil }
        }
        .onChange(of: locationOn) { _, _ in tracker.locationSwitched() }
        .onAppear { outputs = CarAudio.outputs }
        // Свёрнутому приложению смену выхода система не сообщает: отключились
        // от машины в фоне — строка горела бы зелёным до перезапуска.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { outputs = CarAudio.outputs }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)) { _ in outputs = CarAudio.outputs }
        // Имя выхода — в вопросе: подключены наушники, а не машина, — видно
        // до привязки, а не после.
        .confirmationDialog(binding.map { "Привязать «\($0.name)»?" } ?? "",
                            isPresented: Binding(get: { binding != nil }, set: { if !$0 { binding = nil } }),
                            titleVisibility: .visible, presenting: binding) { port in
            Button("Привязать") { bind(port) }
            Button("Отмена", role: .cancel) {}
        } message: { _ in
            Text("Поездки \(chosenCar?.name ?? "машины") будут записываться, только пока он\u{00A0}подключён.")
        }
        .sheet(isPresented: $licensesShown) {
            LicensesSheet { licensesShown = false }
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $consentShown) {
            SyncConsentSheet(isBusy: consentBusy, error: consentError, onAgree: agree) { consentShown = false }
                .presentationDetents(SyncConsentSheet.detents)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(consentBusy)
        }
        .confirmationDialog("Удалить данные с\u{00A0}сервера?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                Task { try? await sync.deleteFromServer() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Поездки на\u{00A0}телефоне останутся.")
        }
        .alert("Bluetooth не\u{00A0}подключён", isPresented: $noBluetooth) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Сядьте в\u{00A0}машину и\u{00A0}подключите к\u{00A0}ней телефон.")
        }
        // Новая поездка в списке — ей нужны адреса начала и конца.
        .task(id: trips.first?.persistentModelID) { await resolveAddresses() }
    }

    // MARK: - Поездка

    private var tripCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Автопробег")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Figma.labelsPrimary)

                    Text(cardNote)
                        .font(.system(size: 15))
                        .foregroundStyle(Figma.graysGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Без геопозиции включать нечего — переключателя нет, как и
                // кнопки ниже.
                if locationOn {
                    Toggle(isOn: Binding(get: { autoOn }, set: { tracker.setAuto($0) })) {
                        Text("Автопробег")
                    }
                    .labelsHidden()
                    .tint(Figma.accentsGreen)
                }
            }

            if let active = tracker.active {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Идёт поездка")
                        .font(.system(size: 15))
                        .foregroundStyle(Figma.accentsGreen)
                    Text(TripMath.liveDistance(active.progress.meters))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Figma.labelsPrimary)
                        .contentTransition(.numericText())
                }
                .accessibilityElement(children: .combine)

                GlassProminentButton(title: "Закончить") {
                    tooShort = tracker.finish() == .tooShort
                }
            } else if locationOn, !autoOn {
                if tooShort {
                    Text("Меньше 100\u{00A0}м\u{00A0}— не\u{00A0}записана")
                        .font(.system(size: 15))
                        .foregroundStyle(Figma.graysGray)
                }
                // Своя заливка, а не `GlassButton`: стекло на серой карточке
                // сливалось с ней, и кнопка читалась строкой текста.
                Button {
                    tooShort = false
                    // С экрана хватит и доступа «При использовании», но
                    // спросить его надо.
                    if tracker.access == .notAsked { tracker.requestAccess() }
                    tracker.start()
                } label: {
                    Text("Начать поездку")
                        .font(.system(size: 17))
                        .foregroundStyle(Figma.labelsPrimary)
                        .frame(maxWidth: .infinity, minHeight: Layout.button)
                        .background(Figma.fillsSecondary, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: Layout.radius))
        .animation(Motion.sheet, value: autoOn)
    }

    /// Подпись карточки — по тому, что включено.
    private var cardNote: String {
        guard locationOn, autoOn else {
            return "Считает километры поездок и\u{00A0}обновляет пробег"
        }
        return tracker.access.worksFromCommand
            ? "Записывает поездки сам. Лишнюю\u{00A0}можно\u{00A0}удалить."
            : "Нужен доступ «Всегда»"
    }

    // MARK: - Настройка

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Настройка")

            VStack(spacing: 0) {
                // Выключатель самого приложения: выключен — Beepy геопозицию
                // не трогает, ни для поездок, ни для карты.
                Toggle(isOn: $locationOn) {
                    Text("Геопозиция")
                        .font(.system(size: 17))
                        .foregroundStyle(Figma.labelsPrimary)
                }
                .tint(Figma.accentsGreen)
                .padding(.horizontal, 16)
                .frame(height: Layout.row)

                if locationOn {
                    separator
                    // Системное разрешение: приложение его только просит,
                    // отзывают в «Настройках» — строка туда и ведёт.
                    linkRow("Доступ", value: tracker.access.status,
                            highlighted: tracker.access.worksFromCommand) {
                        if tracker.access == .notAsked {
                            tracker.requestAccess()
                        } else if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .accessibilityHint("Откроет настройки")

                    if autoOn, tracker.motionDenied {
                        separator
                        linkRow("Движение", value: "Запрещено", highlighted: false) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .accessibilityHint("Откроет настройки")
                    }

                    if fleet.count > 1 {
                        separator
                        carRow
                    }

                    if autoOn {
                        separator
                        bluetoothRow
                    }

                    if !autoOn {
                        separator
                        linkRow("Автоматизация", value: "Команды", highlighted: false) {
                            if let url = URL(string: "shortcuts://") { openURL(url) }
                        }
                    }
                }
            }
            .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: Layout.radius))

            // Автопробег включён — собирать в «Командах» нечего, и подсказка
            // про них уходит вместе со строкой «Автоматизация». Вместо неё —
            // зачем Bluetooth.
            if locationOn {
                Text(autoOn ? bluetoothHint : automationHint)
                    .font(.system(size: 13))
                    .foregroundStyle(Figma.graysGray)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
        }
        .animation(Motion.sheet, value: locationOn)
        .animation(Motion.sheet, value: autoOn)
    }

    /// Что собрать в «Командах» — одной строкой.
    private var automationHint: String {
        let hint = "Bluetooth машины подключён\u{00A0}— «Начать поездку», отключён\u{00A0}— «Закончить поездку»."
        return fleet.count > 1 ? hint + " Машину укажите в\u{00A0}действии." : hint
    }

    /// Машины в порядке добавления: первая — машина по умолчанию.
    private var fleet: [Car] {
        cars.sorted { $0.createdAt < $1.createdAt }
    }

    /// Машина из строки «Машина»: ей идут поездки без выбора, её Bluetooth
    /// привязывается.
    private var chosenCar: Car? {
        fleet.first { TripTracker.carID(of: $0) == tripCar } ?? fleet.first
    }

    // MARK: - Синхронизация

    /// Сохранять поездки на сервере. Включение — только через согласие:
    /// до него ничего не уходит.
    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Синхронизация")

            VStack(spacing: 0) {
                Toggle(isOn: Binding(get: { sync.isOn }, set: { on in
                    if on {
                        consentError = nil
                        consentShown = true
                    } else {
                        sync.disable()
                    }
                })) {
                    Text("Сохранять поездки")
                        .font(.system(size: 17))
                        .foregroundStyle(Figma.labelsPrimary)
                }
                .tint(Figma.accentsGreen)
                .padding(.horizontal, 16)
                .frame(height: Layout.row)

                if sync.isOn {
                    separator
                    linkRow("Последняя", value: syncStatus, highlighted: false) {
                        Task { await sync.syncNow() }
                    }
                    .accessibilityHint("Синхронизировать сейчас")
                }
                if sync.isOn || sync.hasAccount {
                    separator
                    Button { confirmWipe = true } label: {
                        Text("Удалить с\u{00A0}сервера")
                            .font(.system(size: 17))
                            .foregroundStyle(Figma.accentsRed)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: Layout.row, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(CardPressStyle())
                }
            }
            .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: Layout.radius))

            Text(sync.isOn
                 ? "Маршруты, госномер и\u{00A0}VIN остаются на\u{00A0}телефоне."
                 : "Поездки и\u{00A0}пробег\u{00A0}— на\u{00A0}сервер в\u{00A0}России, чтобы не\u{00A0}потерять их со\u{00A0}сменой телефона.")
                .font(.system(size: 13))
                .foregroundStyle(Figma.graysGray)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
        }
        .animation(Motion.sheet, value: sync.isOn)
    }

    private var syncStatus: String {
        switch sync.status {
        case .idle: return "Ещё не\u{00A0}было"
        case .syncing: return "Идёт…"
        case .failed(let reason): return reason
        case .done(let at):
            if Date.now.timeIntervalSince(at) < 60 { return "Только что" }
            return "в\u{00A0}" + at.formatted(date: .omitted, time: .shortened)
        }
    }

    private func agree() {
        consentBusy = true
        consentError = nil
        Task {
            do {
                try await sync.enable()
                consentShown = false
            } catch TripSync.Failure.offline {
                consentError = "Нет связи с\u{00A0}сервером"
            } catch TripSync.Failure.consentOutdated {
                consentError = "Обновите приложение"
            } catch {
                consentError = "Не\u{00A0}получилось. Попробуйте ещё раз."
            }
            consentBusy = false
        }
    }

    // MARK: - Bluetooth машины

    private var bluetoothHint: String {
        chosenCar.flatMap(TripTracker.bond) == nil
            ? "Привяжите Bluetooth машины, сидя в\u{00A0}ней,\u{00A0}— и\u{00A0}такси не\u{00A0}попадёт в\u{00A0}пробег."
            : "Поездки пишутся, пока телефон подключён к\u{00A0}машине."
    }

    /// Привязан — имя выхода, зелёное, пока он подключён; тап предлагает
    /// отвязать. Не привязан — тап привязывает то, к чему телефон подключён.
    @ViewBuilder
    private var bluetoothRow: some View {
        if let car = chosenCar, let bond = TripTracker.bond(of: car) {
            let live = TripLink.connected(outputs, bonds: [bond]) != nil
            Menu {
                Button("Отвязать", role: .destructive) { unbind(car) }
            } label: {
                rowLabel("Bluetooth", value: bond.name.isEmpty ? "Привязан" : bond.name,
                         highlighted: live, icon: "chevron.up.chevron.down")
            }
            .accessibilityElement(children: .combine)
        } else {
            let port = TripLink.bindable(outputs)
            Button {
                outputs = CarAudio.outputs
                if let port = TripLink.bindable(outputs) { binding = port } else { noBluetooth = true }
            } label: {
                rowLabel("Bluetooth", value: "Привязать", highlighted: port != nil, icon: "chevron.right")
            }
            .buttonStyle(CardPressStyle())
            .accessibilityElement(children: .combine)
        }
    }

    /// Привязать выход к выбранной машине. У другой машины он отвязывается:
    /// телефон за раз в одной машине.
    private func bind(_ port: TripLink.Port) {
        guard let car = chosenCar else { return }
        for other in cars where other.persistentModelID != car.persistentModelID {
            if let bond = TripTracker.bond(of: other), TripLink.matches(port, uid: bond.uid, name: bond.name) {
                other.bluetoothUID = nil
                other.bluetoothName = nil
            }
        }
        car.bluetoothUID = port.uid
        car.bluetoothName = port.name
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func unbind(_ car: Car) {
        car.bluetoothUID = nil
        car.bluetoothName = nil
        try? modelContext.save()
    }

    /// Чьи это поездки, когда машин несколько: выбор для автопробега и
    /// кнопки «Начать поездку».
    private var carRow: some View {
        let chosen = chosenCar
        return Menu {
            Picker("Машина", selection: Binding(
                get: { chosen.map(TripTracker.carID) ?? "" },
                set: { tracker.setCar($0) }
            )) {
                ForEach(fleet) { car in
                    Text(car.name).tag(TripTracker.carID(of: car))
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("Машина")
                    .font(.system(size: 17))
                    .foregroundStyle(Figma.labelsPrimary)
                Spacer(minLength: 8)
                Text(chosen?.name ?? "")
                    .font(.system(size: 17))
                    .foregroundStyle(Figma.graysGray)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Figma.graysGray)
            }
            .padding(.horizontal, 16)
            .frame(height: Layout.row)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
    }

    /// Строка-ссылка: название, значение справа и шеврон.
    private func linkRow(_ title: String, value: String, highlighted: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(title, value: value, highlighted: highlighted, icon: "chevron.right")
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .combine)
    }

    private func rowLabel(_ title: String, value: String, highlighted: Bool, icon: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(Figma.labelsPrimary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 17))
                .foregroundStyle(highlighted ? Figma.accentsGreen : Figma.graysGray)
                .lineLimit(1)
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Figma.graysGray)
        }
        .padding(.horizontal, 16)
        .frame(height: Layout.row)
        .contentShape(Rectangle())
    }

    // MARK: - Поездки

    /// История карточками, как в Делимобиле (образец пользователя,
    /// 08.10.2026): у каждой поездки карта с путём, дата и машина, справа
    /// расстояние. Тап открывает экран поездки.
    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Поездки")

            if trips.isEmpty {
                Text("Пока нет")
                    .font(.system(size: 15))
                    .foregroundStyle(Figma.graysGray)
                    .padding(.horizontal, 16)
            } else {
                // Ленивая стопка: кадр карты рисуется, когда карточка подошла
                // к экрану, а не для всех разом.
                LazyVStack(spacing: 12) {
                    ForEach(trips.prefix(Layout.tripsShown)) { trip in
                        let details = TripDetails(trip)
                        Button { opened = details } label: { TripCard(trip: details) }
                            .buttonStyle(CardPressStyle())
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Открыть поездку")
                    }
                }
            }
        }
    }

    /// Адреса начала и конца у поездок, где их ещё нет. Геокодеру Яндекса
    /// уходят две точки маршрута (решение пользователя 08.10.2026). Не
    /// ответил — поля остаются пустыми, следующий заход на экран спросит снова.
    private func resolveAddresses() async {
        var changed = false
        // Список снят заранее: `trips` — живой запрос и за время ожидания
        // может поменяться под циклом.
        let pending = Array(trips.prefix(Layout.tripsShown))
        for trip in pending where trip.modelContext != nil
            && (trip.startAddress == nil || trip.endAddress == nil) {
            guard let data = trip.track,
                  let ends = TripTrack.endpoints(TripTrack.decode(data)) else { continue }
            // После каждого ожидания поездка могла исчезнуть: машину удалили
            // на другой вкладке, и каскад унёс её поездки. Запись в удалённую
            // модель SwiftData роняет приложение.
            if trip.startAddress == nil, let address = await TripGeocoder.shared.address(at: ends.start),
               trip.modelContext != nil {
                trip.startAddress = address
                changed = true
            }
            if trip.modelContext != nil, trip.endAddress == nil,
               let address = await TripGeocoder.shared.address(at: ends.end), trip.modelContext != nil {
                trip.endAddress = address
                changed = true
            }
        }
        if changed { try? modelContext.save() }
    }

    /// Поездку удалили с её экрана — правила в `TripEdits.remove`.
    private func delete(_ details: TripDetails) {
        opened = nil
        guard let trip = trips.first(where: { $0.snapshotKey == details.snapshotKey }) else { return }
        TripEdits.remove(trip, in: modelContext)
    }

    // MARK: - О приложении

    /// Политика конфиденциальности и лицензии — App Store требует ссылку на
    /// политику внутри приложения, MIT и Apache — тексты лицензий в каждой
    /// копии. Внизу версия: по ней сверяют сборку при жалобе.
    private var about: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("О\u{00A0}приложении")

            VStack(spacing: 0) {
                if let privacy = BeepyServer.privacyURL {
                    linkRow("Политика конфиденциальности", value: "", highlighted: false) {
                        openURL(privacy)
                    }
                    separator
                }
                linkRow("Лицензии", value: "", highlighted: false) { licensesShown = true }
            }
            .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: Layout.radius))

            Text("Версия \(Self.version)")
                .font(.system(size: 13))
                .foregroundStyle(Figma.graysGray)
                .padding(.horizontal, 16)
        }
    }

    /// «1.0.0 (1)» — версия и номер сборки из бандла.
    private static let version: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }()

    // MARK: - Общее

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Figma.labelsPrimary)
    }

    private var separator: some View {
        Rectangle()
            .fill(Figma.separatorsOnDark)
            .frame(height: 0.5)
            .padding(.leading, 16)
    }
}
