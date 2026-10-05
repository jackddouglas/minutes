import Testing

@testable import Minutes

@Test func browserAudioScopeIncludesOnlySelectedBrowserAndEmbeddedHelpers() {
  let scope = BrowserAudioScope(
    processID: 42, bundleID: "net.imput.helium", bundlePath: "/Applications/Helium.app")
  #expect(scope.includes(pid: 42, bundle: nil, executablePath: nil))
  #expect(scope.includes(pid: 80, bundle: "net.imput.helium", executablePath: nil))
  #expect(
    scope.includes(
      pid: 81, bundle: "net.imput.helium.helper",
      executablePath:
        "/Applications/Helium.app/Contents/Frameworks/Helium Helper.app/Contents/MacOS/Helium Helper"
    ))
  #expect(
    !scope.includes(
      pid: 82, bundle: "com.apple.Music",
      executablePath: "/System/Applications/Music.app/Contents/MacOS/Music"))
  #expect(
    !scope.includes(
      pid: 83, bundle: "net.imput.helium.other",
      executablePath: "/Applications/Helium.app.other/Contents/MacOS/Other"))
  #expect(!scope.includes(pid: 84, bundle: nil, executablePath: nil))
}
