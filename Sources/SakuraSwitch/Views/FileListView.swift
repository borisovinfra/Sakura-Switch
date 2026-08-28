import SwiftUI
import Installer

struct FileListView: View {
    let files: [TransferProgress.FileProgress]

    var body: some View {
        if files.isEmpty {
            ContentUnavailableView(
                L10n.noFiles,
                systemImage: "tray",
                description: Text(L10n.noFilesDescription)
            )
        } else {
            List(files) { file in
                FileRowView(file: file)
            }
            .listStyle(.plain)
        }
    }
}
