import CoreGraphics

public extension DictationContext {

    static var preview: DictationContext = {
        DictationContext()
    }()
}

public extension DictationService where Self == Dictation.DisabledDictationService {

    static var preview: Self {
        Dictation.DisabledDictationService()
    }
}
