import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var store = StoreManager.shared

    @State private var step: OnboardingStep = .welcome
    @State private var activationSource: OnboardingActivationSource?
    @State private var copyDetection: OnboardingCopyDetection
    @State private var accessibilityTrusted = false
    @State private var sampleCopyButtonHovered = false
    @State private var sampleTextCopied = false
    @State private var copyPromptAttempts: CGFloat = 0

    let onStepChange: (OnboardingStep) -> Void
    let onFinish: (_ openOverlay: Bool) -> Void

    init(
        onStepChange: @escaping (OnboardingStep) -> Void = { _ in },
        onFinish: @escaping (_ openOverlay: Bool) -> Void
    ) {
        self.onStepChange = onStepChange
        self.onFinish = onFinish
        _copyDetection = State(
            initialValue: OnboardingCopyDetection(
                baselineItemIDs: Set(StoreManager.shared.items.map(\.id))
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                switch step {
                case .welcome:
                    welcomeStep
                case .shortcut:
                    shortcutStep
                case .copy:
                    copyStep
                case .permission:
                    permissionStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: UIConstants.Motion.soft), value: step)

            footer
        }
        .frame(
            width: UIConstants.Onboarding.windowWidth,
            height: UIConstants.Onboarding.windowHeight
        )
        .background(PastryPalette.cream)
        .foregroundStyle(PastryPalette.ink)
        .accessibilityIdentifier(AccessibilityIdentifiers.Onboarding.root)
        .onReceive(NotificationCenter.default.publisher(for: .onboardingActivationDetected)) { notification in
            guard step == .shortcut,
                  let source = notification.object as? OnboardingActivationSource
            else { return }
            withAnimation(.easeOut(duration: UIConstants.Motion.short)) {
                activationSource = source
            }
        }
        .onReceive(store.$items) { items in
            guard step == .copy else { return }
            withAnimation(.easeOut(duration: UIConstants.Motion.short)) {
                _ = copyDetection.observe(itemIDs: Set(items.map(\.id)))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
        .onChange(of: step) { _, newStep in
            onStepChange(newStep)
            if newStep == .copy {
                copyDetection = OnboardingCopyDetection(baselineItemIDs: Set(store.items.map(\.id)))
                sampleTextCopied = false
            } else if newStep == .permission {
                refreshAccessibilityStatus()
            }
        }
        .onAppear {
            onStepChange(step)
            refreshAccessibilityStatus()
        }
    }

    private var header: some View {
        HStack(spacing: UIConstants.Onboarding.headerSpacing) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(
                    width: UIConstants.Onboarding.appIconSize,
                    height: UIConstants.Onboarding.appIconSize
                )

            Text("Pastry")
                .font(.system(size: UIConstants.TypeSize.titleMedium, weight: .bold))

            Spacer()

            HStack(spacing: UIConstants.Onboarding.progressSpacing) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                    Capsule(style: .continuous)
                        .fill(
                            item == step
                                ? PastryPalette.warmAccent
                                : PastryPalette.ink.opacity(UIConstants.Onboarding.progressInactiveOpacity)
                        )
                        .frame(
                            width: item == step
                                ? UIConstants.Onboarding.progressActiveWidth
                                : UIConstants.Onboarding.progressInactiveSize,
                            height: UIConstants.Onboarding.progressInactiveSize
                        )
                }
            }
            .animation(.easeOut(duration: UIConstants.Motion.short), value: step)

            Text("\(step.rawValue + 1) / \(OnboardingStep.allCases.count)")
                .font(.system(size: UIConstants.TypeSize.label, weight: .medium, design: .monospaced))
                .foregroundStyle(PastryPalette.muted)
                .frame(width: UIConstants.Onboarding.progressLabelWidth, alignment: .trailing)
        }
        .padding(.horizontal, UIConstants.Onboarding.headerHorizontalPadding)
        .frame(height: UIConstants.Onboarding.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PastryPalette.hairline)
                .frame(height: UIConstants.Stroke.hairline)
        }
    }

    private var footer: some View {
        HStack(spacing: UIConstants.Onboarding.footerSpacing) {
            Button(L10n["onboarding.later"]) {
                OnboardingPreferences.markCompleted()
                onFinish(false)
            }
            .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
            .accessibilityIdentifier(AccessibilityIdentifiers.Onboarding.laterButton)

            Spacer()

            if let previous = step.previous {
                Button(L10n["onboarding.back"]) {
                    withAnimation { step = previous }
                }
                .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                .accessibilityIdentifier(AccessibilityIdentifiers.Onboarding.backButton)
            }

            Button(primaryButtonTitle) {
                if step == .permission {
                    OnboardingPreferences.markCompleted()
                    onFinish(true)
                } else if step.shouldPromptForCopy(copyComplete: copyDetection.isComplete) {
                    promptForSampleCopy()
                } else {
                    advance()
                }
            }
            .buttonStyle(SettingsPillButtonStyle(kind: .primary))
            .accessibilityIdentifier(AccessibilityIdentifiers.Onboarding.primaryButton)
        }
        .padding(.horizontal, UIConstants.Onboarding.headerHorizontalPadding)
        .frame(height: UIConstants.Onboarding.footerHeight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PastryPalette.hairline)
                .frame(height: UIConstants.Stroke.hairline)
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome:
            return L10n["onboarding.start"]
        case .shortcut:
            return L10n["onboarding.continue"]
        case .copy:
            return L10n["onboarding.continue"]
        case .permission:
            return L10n["onboarding.finish_open"]
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: UIConstants.Onboarding.contentSpacing) {
            stepHeading(
                icon: "doc.on.clipboard.fill",
                title: L10n["onboarding.welcome.title"],
                subtitle: L10n["onboarding.welcome.subtitle"]
            )

            HStack(spacing: UIConstants.Onboarding.featureSpacing) {
                welcomeFeature(
                    icon: "lock.shield.fill",
                    title: L10n["onboarding.welcome.local_title"],
                    subtitle: L10n["onboarding.welcome.local_subtitle"]
                )
                welcomeFeature(
                    icon: "eye.slash.fill",
                    title: L10n["onboarding.welcome.excluded_title"],
                    subtitle: L10n["onboarding.welcome.excluded_subtitle"]
                )
                welcomeFeature(
                    icon: "menubar.rectangle",
                    title: L10n["onboarding.welcome.menubar_title"],
                    subtitle: L10n["onboarding.welcome.menubar_subtitle"]
                )
            }
            .frame(maxWidth: UIConstants.Onboarding.featureRowMaxWidth)
        }
        .padding(.horizontal, UIConstants.Onboarding.contentHorizontalPadding)
    }

    private var shortcutStep: some View {
        let feedback = OnboardingActivationFeedback(source: activationSource)
        return VStack(spacing: UIConstants.Onboarding.shortcutContentSpacing) {
            stepHeading(
                icon: activationSource == nil ? "command" : "checkmark.circle.fill",
                title: L10n[feedback.titleKey],
                subtitle: L10n[feedback.subtitleKey]
            )

            Text(GlobalHotkeyManager.shared.currentShortcutDisplay)
                .font(.system(size: UIConstants.TypeSize.displayLarge, weight: .bold, design: .rounded))
                .foregroundStyle(feedback.highlightsShortcut ? PastryPalette.successDeep : PastryPalette.ink)
                .padding(.horizontal, UIConstants.Onboarding.shortcutHorizontalPadding)
                .frame(height: UIConstants.Onboarding.shortcutHeight)
                .settingsCardChrome(cornerRadius: UIConstants.Radius.cardLarge)

            Group {
                if activationSource == nil {
                    Label(
                        L10n["onboarding.shortcut.menubar_hint"],
                        systemImage: "menubar.rectangle"
                    )
                        .font(.system(size: UIConstants.TypeSize.callout))
                        .foregroundStyle(PastryPalette.muted)
                } else {
                    Color.clear
                }
            }
            .frame(height: UIConstants.Onboarding.shortcutFeedbackHeight)
            .contentTransition(.opacity)
        }
        .padding(.horizontal, UIConstants.Onboarding.contentHorizontalPadding)
    }

    private var copyStep: some View {
        let actionFeedback = OnboardingCopyActionFeedback(isComplete: sampleTextCopied)
        return VStack(spacing: UIConstants.Onboarding.contentSpacing) {
            stepHeading(
                icon: copyDetection.isComplete ? "checkmark.circle.fill" : "doc.on.doc",
                title: copyDetection.isComplete
                    ? L10n["onboarding.copy.detected_title"]
                    : L10n["onboarding.copy.title"],
                subtitle: copyDetection.isComplete
                    ? L10n["onboarding.copy.detected_subtitle"]
                    : L10n["onboarding.copy.subtitle"]
            )

            HStack(spacing: UIConstants.Onboarding.sampleCodeBlockSpacing) {
                Text(L10n["onboarding.copy.sample_text"])
                    .font(.system(size: UIConstants.TypeSize.body, weight: .medium, design: .monospaced))
                    .foregroundStyle(PastryPalette.ink)
                    .lineLimit(2)
                    .textSelection(.enabled)

                Spacer()

                Button(action: copySampleText) {
                    animatedSymbol(
                        actionFeedback.iconName,
                        size: UIConstants.TypeSize.title,
                        color: sampleTextCopied ? PastryPalette.successDeep : PastryPalette.warmAccent
                    )
                        .frame(
                            width: UIConstants.Onboarding.sampleCopyButtonSize,
                            height: UIConstants.Onboarding.sampleCopyButtonSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .settingsCardChrome(
                    cornerRadius: UIConstants.Radius.control,
                    fill: sampleCopyButtonHovered ? PastryPalette.cardFill : PastryPalette.cardFillSoft
                )
                .animation(.easeOut(duration: UIConstants.Motion.instant), value: sampleCopyButtonHovered)
                .onHover { sampleCopyButtonHovered = $0 }
                .help(L10n[actionFeedback.labelKey])
                .accessibilityLabel(L10n[actionFeedback.labelKey])
                .accessibilityIdentifier(AccessibilityIdentifiers.Onboarding.copySampleButton)
            }
            .padding(.horizontal, UIConstants.Onboarding.sampleCodeBlockHorizontalPadding)
            .frame(width: UIConstants.Onboarding.sampleCardWidth)
            .frame(minHeight: UIConstants.Onboarding.sampleCardMinHeight)
            .settingsCardChrome(cornerRadius: UIConstants.Radius.cardLarge, fill: PastryPalette.cardFillSoft)
            .modifier(
                OnboardingShakeEffect(
                    progress: copyPromptAttempts,
                    distance: UIConstants.Onboarding.copyPromptShakeDistance,
                    oscillations: UIConstants.Onboarding.copyPromptShakeOscillations
                )
            )

            Text(L10n["onboarding.copy.anywhere_hint"])
                .font(.system(size: UIConstants.TypeSize.callout))
                .foregroundStyle(PastryPalette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if !copyDetection.isComplete {
                Button(L10n["onboarding.skip_step"]) {
                    advance()
                }
                .buttonStyle(.plain)
                .font(.system(size: UIConstants.TypeSize.callout, weight: .medium))
                .foregroundStyle(PastryPalette.muted)
                .padding(.trailing, UIConstants.Onboarding.copyStepTrailingActionInset)
                .padding(.bottom, UIConstants.Onboarding.copyStepBottomActionInset)
                .accessibilityIdentifier(AccessibilityIdentifiers.Onboarding.skipStepButton)
            }
        }
    }

    private var permissionStep: some View {
        VStack(spacing: UIConstants.Onboarding.contentSpacing) {
            stepHeading(
                icon: accessibilityTrusted ? "checkmark.shield.fill" : "hand.raised.fill",
                title: L10n["onboarding.permission.title"],
                subtitle: L10n["onboarding.permission.subtitle"]
            )

            let model = AccessibilityPermissionRowModel.resolve(isTrusted: accessibilityTrusted)
            HStack(spacing: UIConstants.Onboarding.permissionRowSpacing) {
                Image(systemName: model.iconName)
                    .font(.system(size: UIConstants.TypeSize.title3, weight: .bold))
                    .foregroundStyle(model.iconColor)
                    .frame(width: UIConstants.Onboarding.permissionIconWidth)

                VStack(alignment: .leading, spacing: UIConstants.Onboarding.permissionTextSpacing) {
                    Text(model.title)
                        .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
                    Text(model.subtitle)
                        .font(.system(size: UIConstants.TypeSize.label))
                        .foregroundStyle(PastryPalette.muted)
                }

                Spacer()

                if !accessibilityTrusted {
                    Button(L10n["settings.accessibility_grant_btn"]) {
                        AccessibilityPermissionChecker.openSystemSettings()
                    }
                    .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                    .accessibilityIdentifier(AccessibilityIdentifiers.Onboarding.permissionButton)
                }
            }
            .padding(UIConstants.Onboarding.cardPadding)
            .frame(width: UIConstants.Onboarding.permissionCardWidth)
            .frame(minHeight: UIConstants.Onboarding.permissionCardMinHeight)
            .settingsCardChrome(cornerRadius: UIConstants.Radius.cardLarge)

            Text(L10n["onboarding.permission.optional_hint"])
                .font(.system(size: UIConstants.TypeSize.callout))
                .foregroundStyle(PastryPalette.muted)
        }
        .padding(.horizontal, UIConstants.Onboarding.contentHorizontalPadding)
    }

    private func stepHeading(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: UIConstants.Onboarding.headingSpacing) {
            animatedSymbol(
                icon,
                size: UIConstants.Onboarding.heroSymbolSize,
                color: PastryPalette.warmAccent
            )

            Text(title)
                .font(.system(size: UIConstants.TypeSize.displayLarge, weight: .bold))
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: UIConstants.TypeSize.body))
                .foregroundStyle(PastryPalette.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(UIConstants.Onboarding.headingLineSpacing)
                .frame(maxWidth: UIConstants.Onboarding.headingMaxWidth)
        }
    }

    private func animatedSymbol(_ name: String, size: CGFloat, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .contentTransition(.symbolEffect(.replace))
    }

    private func welcomeFeature(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Onboarding.featureContentSpacing) {
            Image(systemName: icon)
                .font(.system(size: UIConstants.TypeSize.headline, weight: .semibold))
                .foregroundStyle(PastryPalette.warmAccent)
            Text(title)
                .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: UIConstants.Onboarding.featureTitleHeight, alignment: .topLeading)
            Text(subtitle)
                .font(.system(size: UIConstants.TypeSize.label))
                .foregroundStyle(PastryPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(UIConstants.Onboarding.featurePadding)
        .frame(
            maxWidth: .infinity,
            minHeight: UIConstants.Onboarding.featureHeight,
            maxHeight: UIConstants.Onboarding.featureHeight,
            alignment: .topLeading
        )
        .clipped()
        .settingsCardChrome(cornerRadius: UIConstants.Radius.cardLarge)
    }

    private func advance() {
        guard let next = step.next else { return }
        withAnimation { step = next }
    }

    private func promptForSampleCopy() {
        withAnimation(.easeInOut(duration: UIConstants.Onboarding.copyPromptShakeDuration)) {
            copyPromptAttempts += 1
        }
    }

    private func copySampleText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(L10n["onboarding.copy.sample_text"], forType: .string)
        withAnimation(.easeOut(duration: UIConstants.Motion.short)) {
            sampleTextCopied = true
        }
    }

    private func refreshAccessibilityStatus() {
        accessibilityTrusted = AccessibilityPermissionChecker.shared.isTrusted()
    }
}

private struct OnboardingShakeEffect: GeometryEffect {
    var progress: CGFloat
    let distance: CGFloat
    let oscillations: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = sin(progress * .pi * 2 * oscillations) * distance
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
