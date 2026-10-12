import SwiftUI

/// Убирает клавиатуру. Вызывать только из замыканий: чтение UIApplication
/// в `body` однажды уже дало цикл AttributeGraph.
@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                    to: nil, from: nil, for: nil)
}

/// Переводит фокус на следующее текстовое поле окна — сверху вниз, слева
/// направо; после последнего закрывает клавиатуру. Ходит по UIKit-иерархии:
/// у SwiftUI нет понятия «следующее поле», а общий `FocusState` пришлось бы
/// заводить в каждой форме заново. Вызывать только из замыканий — по той же
/// причине, что и `dismissKeyboard()`.
@MainActor
func focusNextField() {
    let window = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first { $0.isKeyWindow }
    guard let window else { return dismissKeyboard() }

    var fields: [UITextField] = []
    func collect(_ view: UIView) {
        for sub in view.subviews {
            if let field = sub as? UITextField, field.isEnabled, !field.isHidden {
                fields.append(field)
            }
            collect(sub)
        }
    }
    collect(window)

    guard let current = fields.first(where: { $0.isFirstResponder }) else {
        return dismissKeyboard()
    }
    let ordered = fields.sorted {
        let a = $0.convert($0.bounds.origin, to: window)
        let b = $1.convert($1.bounds.origin, to: window)
        return a.y == b.y ? a.x < b.x : a.y < b.y
    }
    guard let index = ordered.firstIndex(of: current), index + 1 < ordered.count else {
        return dismissKeyboard()
    }
    ordered[index + 1].becomeFirstResponder()
}

/// Общая механика шторок: затемнение с кросс-фейдом, выезд снизу пружиной,
/// закрытие свайпом вниз и тапом по фону. До этого три шторки были написаны
/// по отдельности и анимировались по-разному (одна вообще просто проявлялась).
private struct BottomSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let allowsDragToDismiss: Bool
    /// Насколько ручка ниже верха содержимого. У шторок Detent = Large верх
    /// содержимого — верх экрана, а сама шторка начинается отступом ниже;
    /// без поправки зона захвата стояла над шторкой, в статус-баре, и свайп
    /// за ручку шторку не закрывал (снято на симуляторе 06.10.2026).
    let grabberInset: CGFloat
    @ViewBuilder let sheetContent: () -> SheetContent

    @State private var dragY: CGFloat = 0
    @State private var sheetHeight: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            ZStack(alignment: .bottom) {
                if isPresented {
                    scrim
                    sheet
                }
            }
            // без этого контейнер оверлея учитывает нижнюю safe area (34pt на
            // устройствах с home indicator) и шторка встаёт выше макета
            .ignoresSafeArea()
            .animation(Motion.sheet(reduceMotion: reduceMotion), value: isPresented)
            // Шторка сама убирает клавиатуру: иначе она остаётся поднятой и
            // закрывает кнопки внутри шторки. Касается любой из них.
            .onChange(of: isPresented) { _, shown in
                if shown { dismissKeyboard() }
            }
        }
    }

    private var scrim: some View {
        Figma.overlaysDefault
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { close() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Закрыть")
            .transition(.opacity)
    }

    private var sheet: some View {
        sheetContent()
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { sheetHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, new in sheetHeight = new }
                }
            }
            // Граббер — настоящая ручка (замечание пользователя: часть
            // грабберов была декором). Невидимая хит-зона 140×30 по центру
            // верха ловит жест ПОВЕРХ содержимого — работает и в шторках со
            // ScrollView, где скролл перехватывал общий жест ниже. Узкая,
            // чтобы не накрывать кнопки тулбаров по краям.
            .overlay(alignment: .top) {
                if allowsDragToDismiss {
                    Color.clear
                        .frame(width: 140, height: 30)
                        .contentShape(Rectangle())
                        .gesture(dragGesture)
                        .padding(.top, grabberInset)
                }
            }
            .offset(y: dragY)
            .gesture(allowsDragToDismiss ? dragGesture : nil)
            // при Reduce Motion — проявление вместо выезда
            .transition(reduceMotion ? .opacity : .move(edge: .bottom))
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // тянуть можно только вниз; вверх — с сопротивлением
                dragY = value.translation.height > 0
                    ? value.translation.height
                    : value.translation.height / 4
            }
            .onEnded { value in
                let passedDistance = value.translation.height > sheetHeight * 0.25
                let flickedDown = value.predictedEndTranslation.height > sheetHeight * 0.5
                if passedDistance || flickedDown {
                    close()
                } else {
                    withAnimation(Motion.sheet(reduceMotion: reduceMotion)) { dragY = 0 }
                }
            }
    }

    private func close() {
        withAnimation(Motion.sheet(reduceMotion: reduceMotion)) {
            isPresented = false
            dragY = 0
        }
    }
}

extension View {
    /// Шторка снизу с системным поведением: свайп вниз и тап по затемнению закрывают.
    func bottomSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        allowsDragToDismiss: Bool = true,
        grabberInset: CGFloat = 0,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(BottomSheetModifier(isPresented: isPresented,
                                     allowsDragToDismiss: allowsDragToDismiss,
                                     grabberInset: grabberInset,
                                     sheetContent: content))
    }
}

/// Верх шторки по HIG (эталон пользователя — iOS 26/27 UI Kit): тулбар стоит
/// на размытии с градиентным затуханием, контент прокручивается под ним.
/// Сплошная заливка верхней части — тот самый косяк, который уже ловили на
/// главном экране.
struct SheetTopBlur: View {
    /// Цвет-подмес шторки, чтобы блюр не серел на чёрном контенте.
    var tint: Color

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(tint.opacity(0.55))
        }
        .environment(\.colorScheme, .dark)
        .mask(
            LinearGradient(
                stops: [.init(color: .black, location: 0),
                        .init(color: .black, location: 0.62),
                        .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom)
        )
        .allowsHitTesting(false)
    }
}

/// Верхняя панель шторки: заголовок, «Закрыть» и, если есть что
/// подтверждать, главное действие справа.
///
/// На iOS 26+ это системный тулбар, а не нарисованный (решение пользователя
/// 06.10.2026: «переведи остальные шторки на системную панель»). Кнопки,
/// стекло и начертание даёт система — на iOS 27 панель выглядит как в
/// iOS 27 без правок здесь. По HIG «Toolbars»: стандартные Close и Done без
/// подписей, без своих подложек и подкраски, главное действие одно и справа.
///
/// Панель встаёт в то же место и той же высоты, что прежняя нарисованная:
/// содержимое шторок в навигационный контейнер не переезжает, поэтому их
/// вёрстка, клавиатура и безопасные зоны не меняются. Исключение —
/// `SavedCheckSheet`: она целиком в `NavigationStack`, и край прокрутки под
/// панелью там тоже системный.
///
/// На iOS 17–25 остаётся прежняя нарисованная панель: системный тулбар там
/// выглядит иначе, чем остальной интерфейс шторок.
struct SheetBar: View {
    enum CloseSide { case leading, trailing }

    let title: String
    /// Где «Закрыть». У шторок с одной кнопкой она по макету справа.
    var closeSide: CloseSide = .leading
    /// Сколько горизонтального поля уже дал контейнер. Системная панель
    /// держит свои 16 сама — лишнее поле контейнера она возвращает.
    var containerInset: CGFloat = 0
    let onClose: () -> Void
    /// Подпись главного действия для VoiceOver: «Сохранить», «Добавить авто».
    var confirmLabel: String = "Готово"
    var onConfirm: (() -> Void)? = nil

    static let height: CGFloat = 44
    /// Системная панель оставляет над кнопками своё поле: центр кнопок на
    /// 32 pt ниже верха контейнера, а не на 22 (замер на симуляторах
    /// iOS 26.5 и 27.0, 06.10.2026). Контейнеру даём это поле сверху и снизу;
    /// внешняя рамка 44 ставит его по центру, то есть на то же поле выше, —
    /// кнопки встают туда же, где стояли нарисованные, и стекло кнопки не
    /// обрезается рамкой.
    private static let systemInset: CGFloat = 10

    var body: some View {
        if #available(iOS 26.0, *) {
            NavigationStack {
                Color.clear
                    .containerBackground(.clear, for: .navigation)
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: closeSide == .leading ? .topBarLeading
                                                                     : .topBarTrailing) {
                            Button(role: .close, action: onClose)
                        }
                        if let onConfirm {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(role: .confirm, action: onConfirm)
                                    .accessibilityLabel(confirmLabel)
                            }
                        }
                    }
            }
            // Без подкраски «Закрыть»: по умолчанию кнопка панели берёт
            // акцент приложения и выходила синей.
            .tint(Figma.labelsPrimary)
            .frame(height: Self.height + Self.systemInset * 2)
            .frame(height: Self.height)
            .padding(.horizontal, -containerInset)
        } else {
            drawn
        }
    }

    /// Панель до iOS 26 — та, что была у шторок раньше: стеклянный кружок
    /// с крестиком и белая галочка-акцент.
    private var drawn: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.43)
                .foregroundStyle(Figma.vibrantControlsPrimary)

            HStack {
                if closeSide == .leading { closeDrawn }
                Spacer(minLength: 0)
                if closeSide == .trailing { closeDrawn }

                if let onConfirm {
                    Button(action: onConfirm) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.black)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Figma.labelsPrimary))
                            .contentShape(Circle())
                    }
                    .accessibilityLabel(confirmLabel)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(height: Self.height)
        .padding(.horizontal, max(0, 16 - containerInset))
    }

    private var closeDrawn: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                // Кромку круглой кнопки даёт системное стекло
                .liquidGlass(in: Circle(), tint: Figma.sheetControl) {
                    Circle()
                        .fill(Figma.sheetControl)
                        .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                }
                .contentShape(Circle())
                .motionRim(in: Circle())
                .shadow(color: .black.opacity(0.02), radius: 7.5, y: 8)
        }
        .accessibilityLabel("Закрыть")
    }
}
