public extension Dictation {
    
    /// This enum defines various dictation statuses.
    enum AuthorizationStatus: Int, KeyboardModel {
        
        case disabledService = -1
        case notDetermined = 0
        case denied = 1
        case restricted = 2
        case authorized = 3
    }
}

#if os(iOS)
import Speech
 
public extension SFSpeechRecognizerAuthorizationStatus {

    /// Get a dictation-mapped status.
    var keyboardDictationStatus: Dictation.AuthorizationStatus {
        switch self {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .authorized
        @unknown default: .notDetermined
        }
    }
}
#endif
