import Testing

@testable import Minutes

@Test func browserSourcesExcludeNonBrowserWebHandlers() {
  for id in ["net.imput.helium", "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox"] {
    #expect(BrowserSource.isBrowser(id))
  }
  for id in [
    "com.openai.codex", "com.cmuxterm.app", "app.bearing.mac", "com.tinyspeck.slackmacgap",
    "com.google.Chrome.helper", "",
  ] {
    #expect(!BrowserSource.isBrowser(id))
  }
}
