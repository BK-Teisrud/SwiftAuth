import SwiftUI

@main
struct ExampleAuthAppApp: App {
  @State private var model = AuthAppModel()

  var body: some Scene {
    WindowGroup {
      ContentView().environment(model)
    }
  }
}
