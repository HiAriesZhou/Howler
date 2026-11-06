import Foundation

enum ConfigurationFailure: LocalizedError {
    case missingKey, emptyKey, invalidKey, changed, busy

    var errorDescription: String? {
        switch self {
        case .missingKey: "No API key is set. Add one in Settings > General > API Key."
        case .emptyKey: "Paste an API key before saving."
        case .invalidKey: "The API key contains spaces or line breaks. Paste a single key."
        case .changed: "The model setup changed. Reopen the API key editor for the current service."
        case .busy: "Wait for the current save or connection check to finish."
        }
    }
}
