//
//  DownloadMonitor.swift
//  DynamicIsland
//
//  Watches the Downloads folder and turns it into a live activity: a glyph on
//  the compact pill while something is coming down, and a row on the island when
//  it lands.
//
//  How a download is recognised: every browser writes to a partial file first
//  and renames it into place when it finishes — `.crdownload` (Chrome, Edge,
//  Brave), `.part` (Firefox), `.download` (Safari), `.opdownload` (Opera).
//  Their presence *is* the "downloading" state, and their disappearance
//  alongside a new complete file is the "finished" state. That covers every
//  mainstream browser without asking any of them anything.
//
//  What this deliberately does **not** show is a percentage. None of those
//  formats publishes the expected total size in a way a third party can read —
//  Chrome keeps it in its own database, Safari's `.download` is an opaque
//  package. A progress bar would have to be invented, and a made-up bar that
//  crawls to 90% and sticks is worse than an honest byte count. So the island
//  shows bytes received and the file name, both of which are true.
//
//  Detection is event-driven: a `DispatchSource` file-system watch on the folder
//  fires on any change. Byte counts are then polled, but only while a partial
//  file actually exists, so an idle Mac does no work at all.
//
//  A partial file is not the same thing as a download in progress. Browsers
//  leave them behind when a download fails or is cancelled, and one abandoned
//  `.download` package in Downloads used to put a downloading indicator on the
//  island permanently. So a partial only counts while it is actually *growing*:
//  stop gaining bytes for a few seconds and it is treated as stalled, which is
//  also why anything already sitting in the folder at launch starts out stalled
//  rather than active.
//

import Foundation

/// What the island shows about the Downloads folder right now.
struct DownloadActivity: Equatable {
    var fileName: String
    /// Bytes on disk so far. For a finished file this is its real size.
    var bytes: Int64
    var isComplete: Bool
    /// How many partial downloads are in flight, when it is more than one.
    var otherCount: Int = 0
}

final class DownloadMonitor {

    /// Called on the main queue while a download is in progress, and once with
    /// nil when the last one finishes or is cancelled.
    var onChange: ((DownloadActivity?) -> Void)?

    /// Called on the main queue when a download completes, for the transient.
    var onComplete: ((DownloadActivity) -> Void)?

    private(set) var activity: DownloadActivity?

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var pollTimer: Timer?

    /// Partial files seen on the last pass, so a rename into place can be told
    /// apart from a cancelled download.
    private var partials: [String: Int64] = [:]

    /// When each partial last gained bytes. A file that has not grown recently
    /// is stalled, not downloading.
    private var lastGrowth: [String: Date] = [:]

    /// Complete files seen on the last pass, so "new file" means new.
    private var completed: Set<String> = []

    private let folder: URL

    private static let partialExtensions: Set<String> = [
        "crdownload",   // Chrome, Edge, Brave, Vivaldi
        "part",         // Firefox
        "download",     // Safari
        "opdownload",   // Opera
    ]

    /// Only runs while something is downloading.
    private static let pollInterval: TimeInterval = 0.6

    /// Slower beat kept while partial files exist but none of them is growing,
    /// so an abandoned file costs almost nothing and a resumed one is still
    /// noticed. The folder watch alone would not see it: it fires on files
    /// appearing and disappearing, not on bytes being appended to one.
    private static let stalledPollInterval: TimeInterval = 5.0

    /// How long a partial may go without growing before it stops counting.
    private static let stallTimeout: TimeInterval = 6.0

    init(folder: URL? = nil) {
        self.folder = folder
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    deinit {
        stop()
    }

    // MARK: Lifecycle

    func start() {
        guard source == nil else { return }

        descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scan() }
        source.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        source.resume()
        self.source = source

        // Seed the baseline, so files already sitting in Downloads aren't
        // announced as though they just arrived.
        seed()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil

        source?.cancel()
        source = nil

        partials.removeAll()
        lastGrowth.removeAll()
        completed.removeAll()
        pollInterval_ = nil
        publish(nil)
    }

    // MARK: Scanning

    private func seed() {
        let (partial, complete) = contents()
        partials = partial
        completed = complete
        // Anything already here was not started by this session and is not
        // known to be moving, so it begins stalled and has to earn its way back.
        lastGrowth = partial.mapValues { _ in Date.distantPast }
        updatePolling()
    }

    private func scan() {
        let (partial, complete) = contents()

        // A partial file that vanished while a matching complete file appeared
        // is a finished download. Matching is by the name with the marker
        // extension stripped, which is exactly the rename every browser does.
        let finishedNames = partials.keys
            .filter { partial[$0] == nil }
            .map { Self.completedName(for: $0) }

        for name in finishedNames where complete.contains(name) && !completed.contains(name) {
            let size = fileSize(named: name)
            let done = DownloadActivity(fileName: name, bytes: size, isComplete: true)
            onComplete?(done)
        }

        noteGrowth(partial)
        partials = partial
        completed = complete
        updatePolling()
        publishCurrent()
    }

    /// Move a partial's growth timestamp forward only when it actually grew.
    private func noteGrowth(_ fresh: [String: Int64]) {
        let now = Date()
        for (name, size) in fresh {
            guard let previous = partials[name] else {
                // First sighting during this session — a download starting.
                lastGrowth[name] = now
                continue
            }
            if size > previous { lastGrowth[name] = now }
        }
        lastGrowth = lastGrowth.filter { fresh[$0.key] != nil }
    }

    /// The partials that are actually moving.
    private var activePartials: [String: Int64] {
        let cutoff = Date().addingTimeInterval(-Self.stallTimeout)
        return partials.filter { (lastGrowth[$0.key] ?? .distantPast) > cutoff }
    }

    /// Byte counts only move while a partial file exists, so the timer only runs
    /// then. An idle Downloads folder costs one dormant dispatch source.
    private func updatePolling() {
        let wanted: TimeInterval? = partials.isEmpty
            ? nil
            : (activePartials.isEmpty ? Self.stalledPollInterval : Self.pollInterval)

        guard wanted != pollInterval_ else { return }
        pollInterval_ = wanted

        pollTimer?.invalidate()
        pollTimer = nil
        guard let wanted else { return }

        let timer = Timer(timeInterval: wanted, repeats: true) { [weak self] _ in
            guard let self else { return }
            let fresh = self.contents().partial
            self.noteGrowth(fresh)
            self.partials = fresh
            self.updatePolling()
            self.publishCurrent()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// The rate the timer is currently running at, so it is only rebuilt when
    /// the rate actually has to change.
    private var pollInterval_: TimeInterval?

    private func publishCurrent() {
        guard let biggest = activePartials.max(by: { $0.value < $1.value }) else {
            publish(nil)
            return
        }
        publish(DownloadActivity(fileName: Self.completedName(for: biggest.key),
                                 bytes: biggest.value,
                                 isComplete: false,
                                 otherCount: max(0, activePartials.count - 1)))
    }

    private func publish(_ new: DownloadActivity?) {
        guard new != activity else { return }
        activity = new
        onChange?(new)
    }

    // MARK: Folder reading

    private func contents() -> (partial: [String: Int64], complete: Set<String>) {
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        else { return ([:], []) }

        var partial: [String: Int64] = [:]
        var complete: Set<String> = []

        for entry in entries {
            let name = entry.lastPathComponent
            if Self.partialExtensions.contains(entry.pathExtension.lowercased()) {
                // Safari's `.download` is a package, so its size is the sum of
                // what is inside it rather than a single file's length.
                partial[name] = size(of: entry)
            } else {
                complete.insert(name)
            }
        }
        return (partial, complete)
    }

    private func size(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values?.isDirectory == true {
            guard let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]) else { return 0 }
            return enumerator.reduce(Int64(0)) { total, item in
                guard let item = item as? URL,
                      let size = try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize
                else { return total }
                return total + Int64(size)
            }
        }
        return Int64(values?.fileSize ?? 0)
    }

    private func fileSize(named name: String) -> Int64 {
        size(of: folder.appendingPathComponent(name))
    }

    /// "report.pdf.crdownload" → "report.pdf".
    private static func completedName(for partialName: String) -> String {
        let url = URL(fileURLWithPath: partialName)
        guard partialExtensions.contains(url.pathExtension.lowercased()) else { return partialName }
        return url.deletingPathExtension().lastPathComponent
    }
}
