import SwiftUI

/// Small ⓘ next to a setting: hover shows a tooltip, click shows the full
/// explanation in a popover.
struct InfoButton: View {
    let title: String
    let text: String
    @State private var showing = false
    @State private var hovering = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(hovering || showing ? Theme.text : Theme.textDim)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(text)
        .accessibilityLabel(tr("About ", "Tentang ") + title)
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(14)
            .frame(width: 300, alignment: .leading)
        }
    }
}
