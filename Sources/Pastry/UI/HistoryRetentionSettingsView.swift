import SwiftUI

struct HistoryRetentionSettingsView: View {
    @Binding var maxItems: Int
    @Binding var maxAgeDays: Int
    let onPolicyChange: () -> Void

    var body: some View {
        Section {
            Picker(L10n["settings.history.max_items"], selection: Binding(
                get: { HistoryRetentionPolicy.sanitizedMaxItems(maxItems) },
                set: { value in
                    maxItems = value
                    onPolicyChange()
                }
            )) {
                ForEach(HistoryRetentionPolicy.maxItemsOptions, id: \.self) { value in
                    Text(HistoryRetentionPolicy.maxItemsLabel(value)).tag(value)
                }
            }

            Picker(L10n["settings.history.max_age"], selection: Binding(
                get: { HistoryRetentionPolicy.sanitizedMaxAgeDays(maxAgeDays) },
                set: { value in
                    maxAgeDays = value
                    onPolicyChange()
                }
            )) {
                ForEach(HistoryRetentionPolicy.maxAgeDayOptions, id: \.self) { value in
                    Text(HistoryRetentionPolicy.maxAgeLabel(value)).tag(value)
                }
            }

            Text(L10n["settings.history.retention_hint"])
                .font(.caption)
                .foregroundColor(.secondary)
        } header: {
            Text(L10n["settings.history.section"])
                .font(.system(size: UIConstants.TypeSize.label, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}
