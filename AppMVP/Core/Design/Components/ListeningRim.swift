import SwiftUI

/// Светящаяся рамка по краям экрана на время прослушивания.
///
/// Референс — подсветка Apple Intelligence. Ключевое в ней не обводка, а
/// **сияние**: многоцветный градиент втекает внутрь от кромки экрана, медленно
/// поворачивается по кругу и разгорается на голос. Поэтому здесь нет ни одной
/// чёткой линии — только размытые слои.
///
/// Рамка ничего не перехватывает и живёт поверх всего экрана, включая модалку
/// записи: сигнал «телефон слушает» не должен зависеть от того, какой слой
/// сейчас сверху.
struct ListeningRim: View {
    /// Уровень с микрофона, 0…1.
    var level: Double

    /// Идёт ли запись. Отдельно от уровня намеренно: в тишине уровень нулевой,
    /// но рамка обязана остаться на экране — иначе она читается как «перестал
    /// слушать», хотя запись идёт.
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Угол поворота градиента. Крутится бесконечной анимацией, а не таймером:
    /// поворот слоя система тянет сама, не пересобирая `body` на каждом кадре.
    @State private var phase: Double = 0
    /// Медленное «дыхание» рамки в тишине.
    @State private var breathing = false

    /// Скругление экрана. Публичного API у него нет (`_displayCornerRadius`
    /// приватный и в App Store с ним нельзя), поэтому берём наибольшее из
    /// нынейшей линейки — 55pt. Промах на устройствах с 47.33 не виден:
    /// рамка размыта на десятки точек, её угол мягче любого из этих радиусов.
    private static let screenCorner: CGFloat = 55

    /// Оборот градиента. Медленно: быстрое вращение читается как «идёт
    /// загрузка», а рамка сообщает не о прогрессе, а о том, что микрофон открыт.
    private static let spinDuration: Double = 9

    /// Тона сияния. Не из Figma — раздела с рамкой в макете нет. Взяты в
    /// палитре живого шара с того же экрана (мятный, голубой, фиолетовый),
    /// чтобы рамка и шар читались одним материалом, плюс розовый и тёплый:
    /// без них круг замыкается через грязь, а не через свет.
    /// Последний цвет повторяет первый — иначе на стыке оборота видна щель.
    private static let hues: [Color] = [
        Color(red: 0.36, green: 0.78, blue: 1.00),
        Color(red: 0.62, green: 0.51, blue: 1.00),
        Color(red: 1.00, green: 0.44, blue: 0.78),
        Color(red: 1.00, green: 0.63, blue: 0.38),
        Color(red: 0.42, green: 0.93, blue: 0.78),
        Color(red: 0.36, green: 0.78, blue: 1.00)
    ]

    var body: some View {
        ZStack {
            // Два слоя, а не один меняющейся толщины. Толщина и размытие здесь
            // постоянные, потому что маска с ними рисуется один раз; гони их от
            // уровня — и полноэкранное размытие пересчитывалось бы сорок раз в
            // секунду. Меняются только прозрачности, а это ничего не стоит.
            rim(width: 22, blur: 16).opacity(0.5)
            rim(width: 72, blur: 50).opacity(bloom)
        }
        // Сияние складывается с тем, что под ним, а не закрашивает его. Экран
        // раздела чёрный, поэтому в худшем случае сложение идёт с чёрным —
        // то есть даёт ровно сам цвет.
        .blendMode(.plusLighter)
        .scaleEffect(breathing ? 1.014 : 1)
        .opacity(isActive ? 1 : 0)
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.45), value: isActive)
        .onAppear { if isActive { spin() } }
        .onChange(of: isActive) { _, active in
            if active { spin() } else { rest() }
        }
    }

    /// Один слой сияния: вращающийся градиент, обрезанный размытой кромкой.
    /// Маска статична и растрируется один раз — крутится только градиент под ней.
    ///
    /// Если на устройстве всё же обнаружится проседание кадров, первое, что
    /// надо попробовать, — `.drawingGroup()` на содержимом маски: он заставит
    /// размытие лечь в одну текстуру вместо пересчёта на каждом кадре.
    private func rim(width: CGFloat, blur: CGFloat) -> some View {
        spinningGradient
            .mask {
                // strokeBorder, а не stroke: он уводит обводку внутрь фигуры,
                // и наружу уходит только размытие. У stroke половина толщины
                // оказалась бы за краем экрана и просто пропала.
                RoundedRectangle(cornerRadius: Self.screenCorner, style: .continuous)
                    .strokeBorder(.white, lineWidth: width)
                    .blur(radius: blur)
            }
    }

    private var spinningGradient: some View {
        GeometryReader { geo in
            // Квадрат по диагонали экрана: при повороте углы не должны
            // обнажаться, иначе по рамке едет пустая зона.
            let side = hypot(geo.size.width, geo.size.height) * 1.2

            AngularGradient(colors: Self.hues, center: .center)
                .frame(width: side, height: side)
                .rotationEffect(.degrees(phase))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    /// Насколько разгорелось внешнее сияние. Корень вытягивает тихую речь:
    /// на линейной шкале рамка оставалась почти погасшей при обычном разговоре,
    /// хотя `AudioLevelMeter` уже отдаёт нормированный уровень.
    ///
    /// Нижние 0.12 — не ноль намеренно: в паузах между словами рамка тускнеет,
    /// но не гаснет, иначе она мигает на каждом вдохе.
    private var bloom: Double {
        let shaped = pow(min(1, max(0, level)), 0.6)
        // Reduce Motion: рамка остаётся и по-прежнему отвечает на голос, но
        // размах втрое меньше — резкие перепады яркости просят гасить те же
        // рекомендации, что и движение.
        return 0.12 + shaped * (reduceMotion ? 0.3 : 0.88)
    }

    private func spin() {
        guard !reduceMotion else { return }

        withAnimation(.linear(duration: Self.spinDuration).repeatForever(autoreverses: false)) {
            phase = 360
        }
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }

    /// Бесконечную анимацию не останавливает ничто, кроме присваивания вне
    /// анимации: без этого погасший слой продолжал бы крутиться и дышать.
    private func rest() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            phase = 0
            breathing = false
        }
    }
}
