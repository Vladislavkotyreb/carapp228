import AuthenticationServices
import SwiftUI
import UIKit

/// Кнопка входа с Apple из макета: тот же Glass Prominent, лейбл «\u{F8FF} Войти с Apple»
/// (SF Pro Medium 17, line-height 18 → высота 50). Нативный SignInWithAppleButton не
/// используется намеренно — у него системный лейбл и своя вёрстка, макет задаёт свою.
enum AppleSignInError: LocalizedError {
    case noCredential

    var errorDescription: String? {
        "Не удалось получить данные Apple ID."
    }
}

struct AppleSignInButton: View {
    let onCompletion: (Result<ASAuthorizationAppleIDCredential, Error>) -> Void

    @State private var coordinator: AppleSignInCoordinator?

    var body: some View {
        GlassProminentButton(
            title: "\u{F8FF} Войти с Apple ",
            lineHeight: 18,
            weight: .medium,
            tracking: 0,
            action: start
        )
    }

    private func start() {
        let coordinator = AppleSignInCoordinator { result in
            self.coordinator = nil
            onCompletion(result)
        }
        self.coordinator = coordinator

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email, .fullName]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = coordinator
        controller.presentationContextProvider = coordinator
        controller.performRequests()
    }
}

final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate,
                                    ASAuthorizationControllerPresentationContextProviding {
    private let completion: (Result<ASAuthorizationAppleIDCredential, Error>) -> Void

    init(completion: @escaping (Result<ASAuthorizationAppleIDCredential, Error>) -> Void) {
        self.completion = completion
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            completion(.failure(AppleSignInError.noCredential))
            return
        }
        completion(.success(credential))
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        completion(.failure(error))
    }
}
