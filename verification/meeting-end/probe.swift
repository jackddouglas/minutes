import AppKit
import CoreAudio

// Report only changes in the selected application's Core Audio state.
guard CommandLine.arguments.count == 3,
  let duration = Int(CommandLine.arguments[2]), duration > 0
else {
  fputs("Usage: probe /path/to/Application.app seconds\n", stderr)
  exit(2)
}

let application = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
guard let bundleID = Bundle(url: application)?.bundleIdentifier else {
  fputs("Application bundle could not be identified.\n", stderr)
  exit(2)
}

func matches(_ process: AudioHardwareProcess) throws -> Bool {
  if try process.bundleID == bundleID { return true }
  var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
  let count = proc_pidpath(try process.pid, &path, UInt32(path.count))
  guard count > 0 else { return false }
  return String(cString: path).hasPrefix(application.path + "/")
}

func snapshot() throws -> String {
  let processes = try AudioHardwareSystem.shared.processes
  guard !processes.isEmpty else { return "Core Audio process list unavailable or empty" }
  let selected = try processes.filter(matches)
  guard !selected.isEmpty else { return "no matching audio process" }
  let input = try selected.contains { try $0.isRunningInput }
  let output = try selected.contains { try $0.isRunningOutput }
  return "input=\(input) output=\(output) processes=\(selected.count)"
}

let start = ProcessInfo.processInfo.systemUptime
var previous = ""
repeat {
  let state: String
  do { state = try snapshot() } catch { state = "unavailable: \(error.localizedDescription)" }
  if state != previous {
    print("\(Date().formatted(date: .omitted, time: .standard))  \(state)")
    fflush(stdout)
    previous = state
  }
  Thread.sleep(forTimeInterval: 0.5)
} while ProcessInfo.processInfo.systemUptime - start < Double(duration)
