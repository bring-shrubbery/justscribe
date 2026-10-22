import Foundation
import SwiftUI

/// This type can be used to define important properties for
/// your app, and is also a namespace for app-based features.
///
/// You can create a static app value and add it to both the
/// app and its keyboard, to be able to use it in both, e.g.:
public struct KeyboardApp {
    
    /// Create a custom keyboard app value.
    public init(
        name: String,
        appGroupId: String? = nil,
        locales: [Locale] = .keyboardSupported,
        autocomplete: AutocompleteConfiguration = .init(),
        deepLinks: DeepLinks? = nil,
        keyboardSettingsKeyPrefix: String? = nil
    ) {
        self.name = name
        self.appGroupId = appGroupId
        self.locales = locales
        self.autocomplete = autocomplete
        self.deepLinks = deepLinks
        self.keyboardSettingsKeyPrefix = keyboardSettingsKeyPrefix
    }
    
    /// The name of the app.
    public let name: String
    /// The app's App Group identifier, if any.
    public let appGroupId: String?

    /// The locales to use in the app.
    public let locales: [Locale]

    /// App-specific deep links, if any.
    public let deepLinks: DeepLinks?

    /// The autocomplete configuration to use.
    public let autocomplete: AutocompleteConfiguration

    /// A custom keyboard settings key prefix, if any.
    public let keyboardSettingsKeyPrefix: String?
}

public extension KeyboardApp {

    /// This type can define app-specific deep links.
    ///
    /// You only have to provide an `app` url, and can leave
    /// the rest blank to use standard URLs.
    struct AutocompleteConfiguration {

        /// Create a custom autocomplete configuration.
        ///
        /// - Parameters:
        ///   - nextWordPredictionRequest: The next word prediction request to use, if any.
        public init(
            nextWordPredictionRequest: Autocomplete.NextWordPredictionRequest? = nil
        ) {
            self.nextWordPredictionRequest = nextWordPredictionRequest
        }

        /// The next word prediction request to use, if any.
        public let nextWordPredictionRequest: Autocomplete.NextWordPredictionRequest?
    }

    /// This type can define app-specific deep links.
    ///
    /// You only have to provide an `app` url, and can leave
    /// the rest blank, if you want to use standard patterns.
    ///
    /// > Important: You must register your `app` URL scheme
    /// within the app project, for these deep links to work.
    struct DeepLinks: KeyboardModel {

        /// Create a custom keyboard deep links value.
        ///
        /// - Parameters:
        ///   - app: A deep link for opening the app, e.g. `myapp://`.
        ///   - dictation: A deep link for opening the app and starting dictation, by default `myapp://dictation`.
        ///   - keyboardSettings: A deep link for opening the app's keyboard settings screen, by default `myapp://keyboardSettings`.
        ///   - languageSettings: A deep link for opening the app's language settings screen, by default `myapp://languageSettings`.
        ///   - themeSettings: A deep link for opening the app's theme settings screen, by default `myapp://themeSettings`.
        public init(
            app: String,
            dictation: String? = nil,
            keyboardSettings: String? = nil,
            languageSettings: String? = nil,
            themeSettings: String? = nil
        ) {
            self.app = app
            self.dictation = dictation ?? "\(app)dictation"
            self.keyboardSettings = keyboardSettings ?? "\(app)keyboardSettings"
            self.languageSettings = languageSettings ?? "\(app)languageSettings"
            self.themeSettings = themeSettings ?? "\(app)themeSettings"
        }

        /// A deep link for opening the app.
        public let app: String

        /// A deep link for opening the app and starting dictation.
        public let dictation: String

        /// A deep link for opening the app's keyboard settings screen.
        public let keyboardSettings: String

        /// A deep link for opening the app's language settings screen.
        public let languageSettings: String

        /// A deep link for opening the app's theme settings screen.
        public let themeSettings: String
    }
}

public extension KeyboardApp.DeepLinks {

    /// A deep link for opening the app.
    var appURL: URL? { .init(string: app) }

    /// A deep link for opening the app and starting dictation.
    var dictationURL: URL? { .init(string: dictation) }

    /// A deep link for opening the app's keyboard settings screen.
    var keyboardSettingsURL: URL? { .init(string: keyboardSettings) }

    /// A deep link for opening the app's language settings screen.
    var languageSettingsURL: URL? { .init(string: languageSettings) }

    /// A deep link for opening the app's theme settings screen.
    var themeSettingsURL: URL? { .init(string: themeSettings) }
}

