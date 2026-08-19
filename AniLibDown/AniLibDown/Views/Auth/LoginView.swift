import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var login = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Логин", text: $login)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                }

                if let error = authService.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task {
                            await authService.login(login: login, password: password)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if authService.isLoading {
                                ProgressView()
                            } else {
                                Text("Войти")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(login.isEmpty || password.isEmpty || authService.isLoading)
                }
            }
            .navigationTitle("Вход")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
