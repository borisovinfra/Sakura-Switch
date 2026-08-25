import SwiftUI
import AppKit

@main
struct SakuraSwitchApp: App {

    @State private var appState = AppState()

    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    init() {
        // SPM executables launch as background processes by default.
        // Make Sakura Switch a normal foreground macOS application.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {

        WindowGroup {
            ContentView(appState: appState)
                .frame(
                    minWidth: 900,
                    minHeight: 560
                )
        }
        .defaultSize(
            width: 1100,
            height: 700
        )
    }
}


// MARK: - Window Geometry

final class AppDelegate:
    NSObject,
    NSApplicationDelegate,
    NSWindowDelegate
{

    private let preferredSize =
        NSSize(
            width: 1100,
            height: 700
        )

    private let minimumSize =
        NSSize(
            width: 900,
            height: 560
        )


    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {

        /*
         SwiftUI may create the WindowGroup window slightly after
         applicationDidFinishLaunching, so normalize it on the next
         main-loop cycles.
         */

        DispatchQueue.main.async {
            self.configureMainWindow()
        }

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.15
        ) {
            self.configureMainWindow()
        }
    }


    private func configureMainWindow() {

        guard
            let window =
                NSApplication.shared.windows
                    .first(where: {
                        $0.canBecomeMain
                    })
        else {
            return
        }

        window.minSize =
            minimumSize

        window.delegate =
            self

        normalizeWindowFrame(
            window
        )
    }


    private func normalizeWindowFrame(
        _ window: NSWindow
    ) {

        guard
            let screen =
                bestScreen(
                    for: window
                )
                ?? NSScreen.main
                ?? NSScreen.screens.first
        else {
            return
        }

        let visible =
            screen.visibleFrame

        var frame =
            window.frame


        // ----------------------------------------------------
        // Keep the window smaller than the usable screen.
        // ----------------------------------------------------

        let maximumWidth =
            max(
                minimumSize.width,
                visible.width - 40
            )

        let maximumHeight =
            max(
                minimumSize.height,
                visible.height - 40
            )

        frame.size.width =
            min(
                max(
                    frame.size.width,
                    minimumSize.width
                ),
                maximumWidth
            )

        frame.size.height =
            min(
                max(
                    frame.size.height,
                    minimumSize.height
                ),
                maximumHeight
            )


        // ----------------------------------------------------
        // Detect a broken/off-screen saved position.
        // ----------------------------------------------------

        let visiblePart =
            frame.intersection(
                visible
            )

        let sufficientlyVisible =
            !visiblePart.isNull &&
            visiblePart.width >= 300 &&
            visiblePart.height >= 180


        if !sufficientlyVisible {

            /*
             Saved geometry is unusable.
             Use our preferred size when possible and center.
             */

            frame.size.width =
                min(
                    preferredSize.width,
                    maximumWidth
                )

            frame.size.height =
                min(
                    preferredSize.height,
                    maximumHeight
                )

            frame.origin.x =
                visible.midX -
                frame.size.width / 2

            frame.origin.y =
                visible.midY -
                frame.size.height / 2

        } else {

            /*
             Window is usable, but make sure no edge is left
             outside the visible desktop area.
             */

            if frame.minX < visible.minX {
                frame.origin.x =
                    visible.minX
            }

            if frame.maxX > visible.maxX {
                frame.origin.x =
                    visible.maxX -
                    frame.width
            }

            if frame.minY < visible.minY {
                frame.origin.y =
                    visible.minY
            }

            if frame.maxY > visible.maxY {
                frame.origin.y =
                    visible.maxY -
                    frame.height
            }
        }

        window.setFrame(
            frame,
            display: true,
            animate: false
        )
    }


    private func bestScreen(
        for window: NSWindow
    ) -> NSScreen? {

        if let current =
            window.screen {
            return current
        }

        let frame =
            window.frame

        return NSScreen.screens.max {
            lhs,
            rhs in

            lhs.visibleFrame
                .intersection(frame)
                .area
            <
            rhs.visibleFrame
                .intersection(frame)
                .area
        }
    }
}


// MARK: - CGRect Area

private extension CGRect {

    var area: CGFloat {

        guard
            !isNull,
            !isEmpty
        else {
            return 0
        }

        return
            width * height
    }
}
