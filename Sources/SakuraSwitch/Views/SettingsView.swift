import SwiftUI

struct SettingsView: View {

    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            Text("Настройки Sakura Switch")
                .font(.title)

            Divider()

            GroupBox("Система") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "Версия Sakura Switch: \(BundleAppVersionProvider().displayVersion)"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Подключение") {
                ConnectionStatusView(
                    isConnected: appState.isDeviceConnected,
                    mode: appState.coordinator.transportMode
                )
            }

            GroupBox("Диагностика") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Расширенные логи: включены")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(24)
    }
}
