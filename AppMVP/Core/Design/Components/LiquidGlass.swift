import SwiftUI

/// Единые кривые движения. До этого на однотипные взаимодействия было шесть
/// разных кривых — теперь один источник правды.
enum Motion {
    /// Появление/уход шторок. Близко к системной пружине листов iOS.
    static let sheet = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Переключение сегментов и вкладок.
    static let selection = Animation.smooth(duration: 0.28)
    /// Перелистывание страниц (онбординг, карусель авто).
    static let page = Animation.interpolatingSpring(stiffness: 220, damping: 26)
    /// Всплывающее уведомление: приходит пружиной сверху.
    static let toast = Animation.spring(response: 0.38, dampingFraction: 0.82)
    /// Уход быстрее прихода и без движения. HIG: исчезновение временного
    /// сообщения не должно перетягивать внимание — оно отступает, а не улетает.
    static let toastOut = Animation.easeOut(duration: 0.22)
    /// Сколько тост висит. Двух слов хватает прочесть за это время, а системные
    /// баннеры Apple живут примерно столько же.
    static let toastDwell: Duration = .milliseconds(2500)

    /// При включённом Reduce Motion системные рекомендации требуют заменять
    /// перемещение на простое проявление.
    static func sheet(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : sheet
    }

    static func toast(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : toast
    }
}

/// Настоящий Liquid Glass на iOS 26 и вид из макета на более ранних версиях.
/// Таргет проекта — iOS 17, поэтому API закрыт проверкой доступности.
struct LiquidGlassBackground<S: Shape, Fallback: View>: ViewModifier {
    let shape: S
    var tint: Color?
    var isInteractive: Bool = false
    @ViewBuilder let fallback: () -> Fallback

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content.background { fallback() }
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var value = Glass.regular
        if let tint { value = value.tint(tint) }
        if isInteractive { value = value.interactive() }
        return value
    }
}

extension View {
    /// `tint` задаёт цвет стекла на iOS 26; `fallback` рисует подложку из макета
    /// на iOS 17–25.
    func liquidGlass<S: Shape, Fallback: View>(
        in shape: S,
        tint: Color? = nil,
        isInteractive: Bool = false,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) -> some View {
        modifier(LiquidGlassBackground(shape: shape, tint: tint,
                                       isInteractive: isInteractive, fallback: fallback))
    }
}
