import SwiftUI

/// Убирает клавиатуру. Вызывать только из замыканий: чтение UIApplication
/// в `body` однажды уже дало цикл AttributeGraph.
@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                    to: nil, from: nil, for: nil)
}

/// Общая механика шторок: затемнение с кросс-фейдом, выезд снизу пружиной,
/// закрытие свайпом вниз и тапом по фону. До этого три шторки были написаны
/// по отдельности и анимировались по-разному (одна вообще просто проявлялась).
private struct BottomSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let allowsDragToDismiss: Bool
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
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(BottomSheetModifier(isPresented: isPresented,
                                     allowsDragToDismiss: allowsDragToDismiss,
                                     sheetContent: content))
    }
}
