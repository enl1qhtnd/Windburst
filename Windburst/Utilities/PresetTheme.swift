import SwiftUI
import WindburstShared

enum PresetTheme {
    static func accentColor(for preset: FanPreset?) -> Color {
        guard let preset else { return .orange }
        switch preset.id {
        case FanPreset.silentID: return .blue
        case FanPreset.balancedID: return .teal
        case FanPreset.performanceID: return .purple
        case FanPreset.burstID: return .red
        default: return .secondary
        }
    }

    static func cardBackground(for preset: FanPreset?) -> Color {
        guard let preset, preset.isBuiltIn else {
            return Color(nsColor: .quaternaryLabelColor).opacity(0.25)
        }
        return accentColor(for: preset).opacity(0.14)
    }
}
