import MdCore
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text(greet(name: "Scribe"))
            .font(.title2)
            .padding()
    }
}

#Preview {
    ContentView()
}
