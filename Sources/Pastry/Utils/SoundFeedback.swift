import Cocoa

enum SoundFeedback {
    static func play(_ sound: NSSound?) {
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.soundEnabled),
              let sound else {
            return
        }
        sound.play()
    }

    static func invalidAction() {
        NSSound.beep()
    }
}
