import Cocoa

enum SoundFeedback {
    private nonisolated(unsafe) static var lastPlayedAt: [String: Date] = [:]

    static func play(_ sound: NSSound?, key: String, minimumInterval: TimeInterval = 0.18) {
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.soundEnabled),
              let sound,
              shouldPlay(key: key, minimumInterval: minimumInterval) else {
            return
        }
        sound.play()
    }

    static func invalidAction() {
        NSSound.beep()
    }

    private static func shouldPlay(key: String, minimumInterval: TimeInterval) -> Bool {
        let now = Date()
        if let last = lastPlayedAt[key], now.timeIntervalSince(last) < minimumInterval {
            return false
        }
        lastPlayedAt[key] = now
        return true
    }
}
