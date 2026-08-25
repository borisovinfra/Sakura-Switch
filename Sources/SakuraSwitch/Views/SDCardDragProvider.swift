import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Installer

struct SDCardDragSourceView: NSViewRepresentable {
    let item: InstallationCoordinator.SDCardItem
    let parentPath: String
    let coordinator: InstallationCoordinator
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> DragSourceNSView {
        let view = DragSourceNSView()

        view.configure(
            item: item,
            parentPath: parentPath,
            coordinator: coordinator,
            onDoubleClick: onDoubleClick
        )

        return view
    }

    func updateNSView(
        _ nsView: DragSourceNSView,
        context: Context
    ) {
        nsView.configure(
            item: item,
            parentPath: parentPath,
            coordinator: coordinator,
            onDoubleClick: onDoubleClick
        )
    }
}


// MARK: - Sendable drag context

private final class SDCardDragContext: @unchecked Sendable {
    let item: InstallationCoordinator.SDCardItem
    let parentPath: String
    let coordinator: InstallationCoordinator

    init(
        item: InstallationCoordinator.SDCardItem,
        parentPath: String,
        coordinator: InstallationCoordinator
    ) {
        self.item = item
        self.parentPath = parentPath
        self.coordinator = coordinator
    }
}


// MARK: - Finder completion wrapper

private final class FilePromiseCompletion: @unchecked Sendable {
    private let handler: (Error?) -> Void

    init(_ handler: @escaping (Error?) -> Void) {
        self.handler = handler
    }

    func finish(_ error: Error?) {
        handler(error)
    }
}


// MARK: - Native AppKit drag source

final class DragSourceNSView:
    NSView,
    NSDraggingSource,
    NSFilePromiseProviderDelegate
{
    nonisolated(unsafe)
    private var dragContext: SDCardDragContext?

    private var onDoubleClick: (() -> Void)?

    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.projectsakura.sakuraswitch.filepromise"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    func configure(
        item: InstallationCoordinator.SDCardItem,
        parentPath: String,
        coordinator: InstallationCoordinator,
        onDoubleClick: @escaping () -> Void
    ) {
        dragContext = SDCardDragContext(
            item: item,
            parentPath: parentPath,
            coordinator: coordinator
        )

        self.onDoubleClick = onDoubleClick
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let context = dragContext else {
            return
        }

        let type = context.item.isDirectory
            ? UTType.folder.identifier
            : UTType.data.identifier

        let provider = NSFilePromiseProvider(
            fileType: type,
            delegate: self
        )

        provider.userInfo = context.item.name

        let draggingItem = NSDraggingItem(
            pasteboardWriter: provider
        )

        let image =
            NSImage(
                systemSymbolName:
                    context.item.isDirectory
                        ? "folder.fill"
                        : "doc.fill",
                accessibilityDescription:
                    context.item.name
            )
            ?? NSImage(
                size: NSSize(
                    width: 32,
                    height: 32
                )
            )

        draggingItem.setDraggingFrame(
            NSRect(
                x: 0,
                y: 0,
                width: 32,
                height: 32
            ),
            contents: image
        )

        beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: self
        )
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        dragContext?.item.name ?? "Sakura Switch"
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo destinationURL: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let context = dragContext else {
            completionHandler(
                NSError(
                    domain: "SakuraSwitch",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Не удалось подготовить объект для копирования"
                    ]
                )
            )
            return
        }

        let completion =
            FilePromiseCompletion(completionHandler)

        Task { @MainActor in
            do {
                let materialized =
                    try await context.coordinator.materializeSDCardItem(
                        context.item,
                        parentPath: context.parentPath
                    )

                // Finder уже передаёт конечный URL обещанного файла.
                // Имя повторно добавлять нельзя.
                let destination = destinationURL

                let fm = FileManager.default

                try fm.copyItem(
                    at: materialized,
                    to: destination
                )

                try? fm.removeItem(
                    at:
                        materialized
                            .deletingLastPathComponent()
                )

                completion.finish(nil)

            } catch {
                completion.finish(error)
            }
        }
    }

    nonisolated func operationQueue(
        for filePromiseProvider: NSFilePromiseProvider
    ) -> OperationQueue {
        promiseQueue
    }
}
