import SwiftUI
import AppKit

struct AboutView: View {

    private var sakuraLogo: NSImage? {
        guard let url = Bundle.main.url(
            forResource: "SakuraLogo",
            withExtension: "png"
        ) else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    var body: some View {

        VStack(alignment: .center, spacing: 20) {

            if let sakuraLogo {
                Image(nsImage: sakuraLogo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
            }

            Text("Sakura Switch")
                .font(.largeTitle)
                .bold()

            Text("Project Sakura")
                .font(.title3)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 10) {

                Text("Инструмент управления Nintendo Switch")
                    .font(.headline)

                Text(
                    "Версия: \(BundleAppVersionProvider().displayVersion)"
                )

                Text("Возможности:")
                    .font(.headline)
                    .padding(.top, 8)

                Text("• Atmosphère Contents")
                Text("• Установка модификаций")
                Text("• Работа с SD-картой")
                Text("• Управление сохранениями")
                Text("• Галерея")
            }
            .frame(maxWidth: 420, alignment: .leading)

            Spacer()

            VStack(spacing: 2) {
                Text("Special thanks 🌸")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .opacity(0.55)

                Text("First blossom — digdat0")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .opacity(0.80)

                Text("Our first public supporter, and the first person to believe in Sakura Switch.")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .opacity(0.45)
            }

            Text("© Project Sakura")
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}
