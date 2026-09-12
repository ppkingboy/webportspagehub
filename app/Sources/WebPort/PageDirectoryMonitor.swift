import CoreServices
import Foundation

final class PageDirectoryMonitor {
    private let directoryURL: URL
    private let handler: () -> Void
    private let queue = DispatchQueue(label: "com.webport.staticpages.pages-monitor")
    private var stream: FSEventStreamRef?

    init(directoryURL: URL, handler: @escaping () -> Void) {
        self.directoryURL = directoryURL
        self.handler = handler
        start()
    }

    deinit {
        stop()
    }

    func stop() {
        guard let stream else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func start() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, contextInfo, _, _, _, _ in
            guard let contextInfo else {
                return
            }

            let monitor = Unmanaged<PageDirectoryMonitor>
                .fromOpaque(contextInfo)
                .takeUnretainedValue()
            monitor.handler()
        }

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [directoryURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.6,
            flags
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }
}
