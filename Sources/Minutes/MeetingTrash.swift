import Foundation
import MinutesCore

/// Moves owned artifacts to Finder's Trash. Never unlinks the user's recordings.
enum MeetingTrash {
  typealias TrashItem = (URL) throws -> URL

  static func move(
    _ meeting: Meeting, remaining: [Meeting], store: MeetingStore,
    recordings: URL, exportDirectories: [URL], shareDirectory: URL,
    trash: TrashItem = finderTrash
  ) throws {
    let files = FileManager.default
    let owned = recordings.appendingPathComponent(meeting.id.uuidString)
    var metadataBackups: [(URL, Data)] = []
    var copied: [URL] = []
    var moved: [(original: URL, trashed: URL)] = []
    do {
      // Older reprocessed meetings reference the original's audio directory.
      // Give survivors their own files before removing that directory.
      for survivor in remaining {
        let directory = recordings.appendingPathComponent(survivor.id.uuidString)
        let metadata = directory.appendingPathComponent("tracks.json")
        guard files.fileExists(atPath: metadata.path) else { continue }
        let data = try Data(contentsOf: metadata)
        var tracks = try JSONDecoder().decode(AudioTracks.self, from: data)
        var changed = false
        func preserve(_ source: URL?) throws -> URL? {
          guard let source, isInside(source, owned) else { return source }
          let destination = directory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(source.pathExtension)
          try files.copyItem(at: source, to: destination)
          copied.append(destination)
          changed = true
          return destination
        }
        tracks.remote = try preserve(tracks.remote)
        tracks.microphone = try preserve(tracks.microphone)
        if changed {
          metadataBackups.append((metadata, data))
          try JSONEncoder().encode(tracks).write(to: metadata, options: .atomic)
        }
      }
      var exports = (meeting.exportFiles ?? []).filter {
        MarkdownExporter.owns($0, meeting: meeting)
      }
      for directory in exportDirectories where files.fileExists(atPath: directory.path) {
        exports += try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
          .filter { MarkdownExporter.owns($0, meeting: meeting) }
      }
      // Share sheets create transient copies, which also belong to this meeting.
      if let enumerator = files.enumerator(at: shareDirectory, includingPropertiesForKeys: nil) {
        for case let url as URL in enumerator
        where MarkdownExporter.owns(url, meeting: meeting) {
          exports.append(url)
        }
      }
      let transcript = store.directory.appendingPathComponent(meeting.id.uuidString + ".json")
      var seen = Set<URL>()
      for url in [owned] + exports + [transcript] {
        let path = url.standardizedFileURL
        guard seen.insert(path).inserted, files.fileExists(atPath: path.path) else { continue }
        moved.append((path, try trash(path)))
      }
    } catch {
      var recoveryFailures: [String] = []
      for item in moved.reversed() {
        do { try files.moveItem(at: item.trashed, to: item.original) } catch {
          recoveryFailures.append(item.trashed.path)
        }
      }
      // If restoration failed, keep survivors' independent audio and metadata.
      if recoveryFailures.isEmpty {
        for (url, data) in metadataBackups {
          do { try data.write(to: url, options: .atomic) } catch {
            recoveryFailures.append(url.path)
          }
        }
        if recoveryFailures.isEmpty {
          for url in copied { try? files.removeItem(at: url) }  // Only new, redundant copies.
        }
      }
      let recovery =
        recoveryFailures.isEmpty
        ? "Nothing was deleted. Check file permissions and try again."
        : "Some files could not be restored automatically. Recover them from: \(recoveryFailures.joined(separator: ", "))."
      throw MinutesError.message(
        "Could not move this meeting to Trash. \(recovery) \(error.localizedDescription)")
    }
  }

  private static func isInside(_ file: URL, _ directory: URL) -> Bool {
    file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(
      directory.resolvingSymlinksInPath().standardizedFileURL.path + "/")
  }

  static func finderTrash(_ url: URL) throws -> URL {
    var result: NSURL?
    try FileManager.default.trashItem(at: url, resultingItemURL: &result)
    // Foundation supplies the resulting URL on successful trashing.
    guard let result else {
      throw MinutesError.message(
        "Finder did not return the Trash location for \(url.lastPathComponent).")
    }
    return result as URL
  }
}
