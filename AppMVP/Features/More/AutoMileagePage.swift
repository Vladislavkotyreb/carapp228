import AVFAudio
import SwiftData
import SwiftUI

/// «Ещё» → «Автопробег»: считает километры поездок (`TripTracker`) и
/// прибавляет их к пробегу. Всё, что нужно автопробегу, — на одном экране
/// (замечание пользователя 23.10.2026: «автопробег и настройка — одно и то
/// же»): переключатель и поездка сверху, под ними геопозиция, доступ, машина,
/// привязка Bluetooth машины (`TripLink`) или «Быстрые команды», ниже —
/// синхронизация с сервером (`TripSync`, пока не выкатывается).
///
/// Переключатель включает автоопределение: Beepy замечает поездку сам, кнопки
/// и «Команд» при этом нет. Выключен — поездку начинает кнопка «Начать
/// поездку» или команды из автоматизации по Bluetooth. Переключатель один, а
/// не «Автопробег» плюс «Автоопределение»: два слова на «авто» рядом читались
/// двумя функциями (вопрос пользователя 09.10.2026).
struct AutoMileagePage: View {
    @ObservedObject private var tracker = TripTracker.shared
    @ObservedObject private var sync = TripSync.shared
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

    var body: some View {
        MorePage(title: "Автопробег") {
            card
            setup
            if TripSync.isShipped, TripSync.serverURL != nil { syncSection }
        }
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
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Text(note)
                    .font(.system(size: 15))
                    .foregroundStyle(Figma.graysGray)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Без геопозиции включать нечего — переключателя нет, как и
                // кнопки ниже.
                if locationOn {
                    Toggle(isOn: Binding(get: { autoOn }, set: { on in
                        tracker.setAuto(on)
                        // «Поездка началась» придёт уведомлением — спросить сейчас,
                        // с экрана: из фона вопрос не покажется.
                        if on { TripNotice.requestPermission() }
                    })) {
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
                        .frame(maxWidth: .infinity, minHeight: MoreLayout.button)
                        .background(Figma.fillsSecondary, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Figma.fillsTertiary, in: RoundedRectangle(cornerRadius: MoreLayout.radius))
        .animation(Motion.sheet, value: autoOn)
    }

    /// Подпись — по тому, что включено. Без геопозиции — что её выключатель
    /// ниже.
    private var note: String {
        guard locationOn else { return "Нужна геопозиция\u{00A0}— включите её ниже" }
        guard autoOn else { return "Считает километры поездок и\u{00A0}обновляет пробег" }
        return tracker.access.autoNote(bound: chosenCar.flatMap(TripTracker.bond) != nil)
    }

    // MARK: - Геопозиция, доступ, машина

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            MoreCard {
                // Выключатель самого приложения: выключен — Beepy геопозицию
                // не трогает, ни для поездок, ни для карты.
                Toggle(isOn: $locationOn) {
                    Text("Геопозиция")
                        .font(.system(size: 17))
                        .foregroundStyle(Figma.labelsPrimary)
                }
                .tint(Figma.accentsGreen)
                .padding(.horizontal, 16)
                .frame(height: MoreLayout.row)

                if locationOn {
                    MoreSeparator()
                    // Системное разрешение: приложение его только просит,
                    // отзывают в «Настройках» — строка туда и ведёт.
                    MoreLinkRow(title: "Доступ", value: tracker.access.status,
                                highlighted: tracker.access.worksFromCommand) {
                        if tracker.access == .notAsked {
                            tracker.requestAccess()
                        } else if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .accessibilityHint("Откроет настройки")

                    if autoOn, tracker.motionDenied {
                        MoreSeparator()
                        MoreLinkRow(title: "Движение", value: "Запрещено") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .accessibilityHint("Откроет настройки")
                    }

                    if fleet.count > 1 {
                        MoreSeparator()
                        carRow
                    }

                    if autoOn {
                        MoreSeparator()
                        bluetoothRow
                    }

                    if !autoOn {
                        MoreSeparator()
                        MoreLinkRow(title: "Автоматизация", value: "Команды") {
                            if let url = URL(string: "shortcuts://") { openURL(url) }
                        }
                    }
                }
            }

            // Автопробег включён — собирать в «Командах» нечего, и подсказка
            // про них уходит вместе со строкой «Автоматизация». Вместо неё —
            // зачем Bluetooth.
            // Выключатель общий для всего приложения — без геопозиции и
            // карта не покажет «я здесь», это стоит сказать здесь же.
            MoreFootnote(locationOn
                         ? (autoOn ? bluetoothHint : automationHint)
                         : "Выключена\u{00A0}— Beepy не\u{00A0}берёт геопозицию ни для поездок, ни для карты.")
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
            MoreRowLabel(title: "Машина", value: chosen?.name ?? "", icon: "chevron.up.chevron.down")
        }
        .accessibilityElement(children: .combine)
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
                MoreRowLabel(title: "Bluetooth", value: bond.name.isEmpty ? "Привязан" : bond.name,
                             highlighted: live, icon: "chevron.up.chevron.down")
            }
            .accessibilityElement(children: .combine)
        } else {
            let port = TripLink.bindable(outputs)
            Button {
                outputs = CarAudio.outputs
                if let port = TripLink.bindable(outputs) { binding = port } else { noBluetooth = true }
            } label: {
                MoreRowLabel(title: "Bluetooth", value: "Привязать", highlighted: port != nil)
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
        TripNotice.requestPermission()
        // Привязали, сидя в машине: выход уже подключён, смены не будет.
        tracker.linkChanged()
    }

    private func unbind(_ car: Car) {
        car.bluetoothUID = nil
        car.bluetoothName = nil
        try? modelContext.save()
    }

    // MARK: - Синхронизация

    /// Сохранять поездки на сервере. Включение — только через согласие:
    /// до него ничего не уходит.
    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MoreSectionTitle("Синхронизация")

            MoreCard {
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
                .frame(height: MoreLayout.row)

                if sync.isOn {
                    MoreSeparator()
                    MoreLinkRow(title: "Последняя", value: syncStatus) {
                        Task { await sync.syncNow() }
                    }
                    .accessibilityHint("Синхронизировать сейчас")
                }
                if sync.isOn || sync.hasAccount {
                    MoreSeparator()
                    Button { confirmWipe = true } label: {
                        Text("Удалить с\u{00A0}сервера")
                            .font(.system(size: 17))
                            .foregroundStyle(Figma.accentsRed)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: MoreLayout.row, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(CardPressStyle())
                }
            }

            MoreFootnote(sync.isOn
                         ? "Маршруты, госномер и\u{00A0}VIN остаются на\u{00A0}телефоне."
                         : "Поездки и\u{00A0}пробег\u{00A0}— на\u{00A0}сервер в\u{00A0}России, чтобы не\u{00A0}потерять их со\u{00A0}сменой телефона.")
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
}
