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

                Text(L10n.aboutToolkit)
                    .font(.headline)

                Text(
                    String(
                        format: L10n.aboutVersionFormat,
                        BundleAppVersionProvider().displayVersion
                    )
                )

                Text(L10n.aboutFeatures)
                    .font(.headline)
                    .padding(.top, 8)

                Text(L10n.aboutAtmosphereContents)
                Text(L10n.aboutModInstallation)
                Text(L10n.aboutSDCard)
                Text(L10n.aboutSaves)
            }
            .frame(maxWidth: 420, alignment: .leading)

            Spacer()

            VStack(spacing: 2) {
                Text(L10n.aboutSpecialThanks)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .opacity(0.55)

                Text(L10n.aboutFirstBlossom)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .opacity(0.80)

                Text(L10n.aboutFirstSupporter)
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
