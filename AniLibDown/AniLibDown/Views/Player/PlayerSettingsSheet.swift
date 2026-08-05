import SwiftUI
import AVKit

struct PlayerSettingsSheet: View {
    @Binding var currentQuality: VideoQuality
    let availableQualities: [VideoQuality]
    let subtitleOptions: [AVMediaSelectionOption]
    @Binding var selectedSubtitleOption: AVMediaSelectionOption?
    let onQualityChange: (VideoQuality) -> Void
    let onSubtitleChange: (AVMediaSelectionOption?) -> Void

    @ObservedObject private var settings = PlayerSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !availableQualities.isEmpty {
                        Picker(
                            "Качество",
                            selection: Binding(
                                get: { currentQuality },
                                set: { onQualityChange($0) }
                            )
                        ) {
                            ForEach(availableQualities) { quality in
                                Text(quality.rawValue).tag(quality)
                            }
                        }
                        .accessibilityLabel("Качество видео")
                    }

                    if !subtitleOptions.isEmpty {
                        Picker(
                            "Субтитры",
                            selection: Binding(
                                get: { selectedSubtitleOption },
                                set: { onSubtitleChange($0) }
                            )
                        ) {
                            Text("Выкл").tag(Optional<AVMediaSelectionOption>.none)
                            ForEach(subtitleOptions, id: \.self) { option in
                                Text(option.displayName).tag(Optional(option))
                            }
                        }
                    }

                    Picker("Шаг перемотки", selection: $settings.seekInterval) {
                        ForEach(SeekInterval.allCases) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }

                    Toggle("Пропуск опенинга и эндинга", isOn: $settings.skipOPED)
                    Toggle("Автозапуск следующей серии", isOn: $settings.autoPlayNext)

                    Picker("Ускорение при удержании", selection: $settings.holdSpeedRate) {
                        ForEach(HoldSpeedRate.allCases) { rate in
                            Text(rate.title).tag(rate)
                        }
                    }
                }
            }
            .navigationTitle("Настройки плеера")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .white
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
