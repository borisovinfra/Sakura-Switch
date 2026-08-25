import SwiftUI
import Installer

struct FileListView: View {
    let files: [TransferProgress.FileProgress]

    var body: some View {
        if files.isEmpty {
            ContentUnavailableView(
                "Нет файлов в очереди",
                systemImage: "tray",
                description: Text("Перетащите файлы игр сюда, чтобы начать")
            )
        } else {
            List(files) { file in
                FileRowView(file: file)
            }
            .listStyle(.plain)
        }
    }
}
