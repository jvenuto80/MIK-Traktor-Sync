import Foundation

/// Watches files for changes using DispatchSource
final class FileWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private let paths: [String]
    private let queue = DispatchQueue(label: "com.miktraktorsync.filewatcher", qos: .utility)

    var onChange: ((String) -> Void)?

    init(paths: [String]) {
        self.paths = paths
    }

    func start() {
        stop()

        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else { continue }

            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete],
                queue: queue
            )

            source.setEventHandler { [weak self] in
                self?.onChange?(path)
            }

            source.setCancelHandler {
                close(fd)
            }

            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
    }

    deinit {
        stop()
    }
}
