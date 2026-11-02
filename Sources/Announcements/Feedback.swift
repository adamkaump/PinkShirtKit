import SwiftUI

extension View {
    /// Presents the feedback form, which sends a message to Megaphone's Feedback tab.
    ///
    ///     Button("Send Feedback") { showingFeedback = true }
    ///         .feedbackSheet(isPresented: $showingFeedback, app: "pinpoint")
    ///
    /// The message goes with the app version, platform, device model, system version and language, and the form
    /// says so. It's sent even when usage reporting is off, since the person chose to send it.
    public func feedbackSheet(isPresented: Binding<Bool>, app: String) -> some View {
        sheet(isPresented: isPresented) {
            FeedbackForm(app: app)
        }
    }
}

public struct FeedbackForm: View {
    public static let maxLength = 4000

    let app: String
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var email = ""
    @State private var isSending = false
    @State private var didSend = false
    @State private var error: LocalizedStringResource?
    @FocusState private var messageFocused: Bool

    public init(app: String) {
        self.app = app
    }

    private var trimmedMessage: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }

    private var emailLooksValid: Bool {
        trimmedEmail.isEmpty || trimmedEmail.wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]+/) != nil
    }

    private var canSend: Bool {
        !trimmedMessage.isEmpty && message.count <= Self.maxLength && emailLooksValid && !isSending
    }

    public var body: some View {
        NavigationStack {
            Group {
                if didSend {
                    thanks
                } else {
                    form
                }
            }
            .navigationTitle(Text("Send Feedback", bundle: .module))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if didSend {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss() } label: { Text("Done", bundle: .module) }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSending {
                            ProgressView()
                        } else {
                            Button { Task { await send() } } label: { Text("Send", bundle: .module) }
                                .disabled(!canSend)
                        }
                    }
                }
            }
            .alert(Text("Couldn't Send Feedback", bundle: .module), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button { error = nil } label: { Text("OK", bundle: .module) }
            } message: {
                if let error { Text(error) }
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 420)
        #endif
    }

    private var form: some View {
        Form {
            Section {
                TextEditor(text: $message)
                    .focused($messageFocused)
                    .frame(minHeight: 160)
                    .overlay(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("What's on your mind? Ideas, problems and questions are all welcome.", bundle: .module)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                if message.count > Self.maxLength - 200 {
                    Text("\(message.count) of \(Self.maxLength) characters", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(message.count > Self.maxLength ? .red : .secondary)
                }
            } footer: {
                Text("Your app version, device model and system version are sent with your message.", bundle: .module)
            }
            Section {
                TextField(text: $email) { Text("Email (optional)", bundle: .module) }
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
            } footer: {
                if emailLooksValid {
                    Text("Add your email if you'd like a reply.", bundle: .module)
                } else {
                    Text("That email address doesn't look right.", bundle: .module).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(isSending)
        .onAppear { messageFocused = true }
    }

    private var thanks: some View {
        ContentUnavailableView {
            Label { Text("Thanks for Your Feedback", bundle: .module) } icon: { Image(systemName: "checkmark.circle") }
        } description: {
            Text("Every message gets read.", bundle: .module)
        }
    }

    private func send() async {
        guard canSend else { return }
        isSending = true
        defer { isSending = false }
        var body = DeviceContext.current(app: app)
        body["message"] = trimmedMessage
        if !trimmedEmail.isEmpty { body["email"] = trimmedEmail }
        do {
            _ = try await API.send("v1/feedback", body)
            didSend = true
        } catch .offline {
            error = LocalizedStringResource("Check your internet connection and try again.", bundle: .atURL(Bundle.module.bundleURL))
        } catch .tooManyRequests {
            error = LocalizedStringResource("You've sent several messages in a row. Try again in a minute.", bundle: .atURL(Bundle.module.bundleURL))
        } catch {
            self.error = LocalizedStringResource("Something went wrong. Try again later.", bundle: .atURL(Bundle.module.bundleURL))
        }
    }
}

#Preview {
    FeedbackForm(app: "pinpoint")
}
