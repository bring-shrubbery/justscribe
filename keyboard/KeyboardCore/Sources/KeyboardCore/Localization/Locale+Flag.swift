import Foundation
import SwiftUI


public extension Locale {
    
    /// The locale-specific flag emoji.
    ///
    /// This will use a white placeholder flag if the locale
    /// doesn't have a proper emoji flag.
    var flag: String {
        switch self {
        case .albanian: "🇦🇱"
        case .arabic: "🇦🇪"
        case .armenian: "🇦🇲"
        case .azerbaijani: "🇦🇿"
        case .belarusian: "🇧🇾"
        case .bengali: "🇧🇩"
        case .bulgarian: "🇧🇬"
        case .catalan: "🇦🇩"
        case .cherokee: "🏳️"
        case .chuvash: "🏳️"
        
        case .croatian: "🇭🇷"
        case .czech: "🇨🇿"
        case .danish: "🇩🇰"
        case .dutch: "🇳🇱"
        case .dutch_belgium: "🇧🇪"
        case .english: "🇺🇸"
        case .english_australia: "🇦🇺"
        case .english_canada: "🇨🇦"
        case .english_gb: "🇬🇧"
        case .english_us: "🇺🇸"
        
        case .estonian: "🇪🇪"
        case .faroese: "🇫🇴"
        case .filipino: "🇵🇭"
        case .finnish: "🇫🇮"
        case .french: "🇫🇷"
        case .french_canada: "🇨🇦"
        case .french_belgium: "🇧🇪"
        case .french_switzerland: "🇨🇭"
        case .georgian: "🇬🇪"
        case .german: "🇩🇪"
        
        case .german_austria: "🇦🇹"
        case .german_switzerland: "🇨🇭"
        case .greek: "🇬🇷"
        case .hawaiian: "🇺🇸"
        case .hebrew: "🇮🇱"
        case .hungarian: "🇭🇺"
        case .icelandic: "🇮🇸"
        case .inari_sami: "🏳️"
        case .indonesian: "🇮🇩"
        case .irish: "🇮🇪"
        
        case .italian: "🇮🇹"
        case .kazakh: "🇰🇿"
        case .kurdish_sorani: "🇹🇯"
        case .kurdish_sorani_arabic: "🇹🇯"
        case .kurdish_sorani_pc: "🇹🇯"
        case .latvian: "🇱🇻"
        case .lithuanian: "🇱🇹"
        case .macedonian: "🇲🇰"
        case .malay: "🇲🇾"
        case .maltese: "🇲🇹"
        
        case .mongolian: "🇲🇳"
        case .northern_sami: "🏳️"
        case .norwegian: "🇳🇴"
        case .norwegian_nynorsk: "🇳🇴"
        case .persian: "🇮🇷"
        case .polish: "🇵🇱"
        case .portuguese: "🇵🇹"
        case .portuguese_brazil: "🇧🇷"
        case .romanian: "🇷🇴"
        case .russian: "🇷🇺"
        
        case .serbian: "🇷🇸"
        case .serbian_latin: "🇷🇸"
        case .shughni_tajik: "🇹🇯"
        case .slovenian: "🇸🇮"
        case .slovak: "🇸🇰"
        case .spanish: "🇪🇸"
        case .spanish_latinAmerica: "🇦🇷"
        case .spanish_mexico: "🇲🇽"
        case .swedish: "🇸🇪"
        case .swahili: "🇰🇪"
        case .turkish: "🇹🇷"
        
        case .ukrainian: "🇺🇦"
        case .uzbek: "🇺🇿"
        case .vietnamese: "🇻🇳"
        case .welsh: "🏴󠁧󠁢󠁷󠁬󠁳󠁿"

        default: "🏳️"
        }
    }
}
