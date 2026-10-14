import SwiftUI

struct PreferencesView: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferensi").font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Opasitas background")
                    Spacer()
                    Text("\(Int(prefs.opacity * 100))%")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textDim)
                }
                Slider(value: $prefs.opacity, in: 0.3...1.0)
                HStack {
                    Text("Transparan")
                    Spacer()
                    Text("Solid")
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)
            }

            Toggle("Blur di belakang panel (vibrancy)", isOn: $prefs.blur)

            Divider()

            LabeledContent("Folder repo") {
                TextField("~/Project", text: $prefs.rootFolder)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono)
                    .frame(width: 170)
            }
            LabeledContent("Editor") {
                TextField("code -g", text: $prefs.editorCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono)
                    .frame(width: 170)
            }
        }
        .font(.system(size: 13))
        .padding(16)
        .frame(width: 320)
    }
}
