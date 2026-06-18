import Cocoa

enum SoundFeedback {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.soundEnabled)
    }

    static func play(_ sound: NSSound?) {
        guard isEnabled, let sound else {
            return
        }
        sound.play()
    }

    static func invalidAction() {
        guard isEnabled else { return }
        NSSound.beep()
    }
}
