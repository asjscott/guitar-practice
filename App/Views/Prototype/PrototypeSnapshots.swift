// PROTOTYPE — throwaway. With PROTO_SNAPSHOT=<dir> set, renders every variant to PNG and quits.
// Native controls (pickers, forms) render as placeholders; it's for checking layout only.

import AppKit
import SwiftUI

#if DEBUG
@MainActor
enum ProtoSnapshots {
    static func runIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["PROTO_SNAPSHOT"] else { return }
        let listen = ProtoListen()
        func save(_ name: String, _ view: some View) {
            let r = ImageRenderer(content: view.frame(width: 920, height: 560).background(Color(nsColor: .windowBackgroundColor)))
            r.scale = 1
            guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        save("T1", TunerT1(listen: listen))
        save("T2", TunerT2(listen: listen))
        save("T3", TunerT3(listen: listen))
        save("D2-setup", DrillD2(listen: listen))
        save("D4-idle", DrillD4(listen: listen))
        listen.start()
        listen.playWrong()
        save("D1-wrong", DrillD1(listen: listen))
        save("D2-wrong", DrillD2(listen: listen))
        save("D3-wrong", DrillD3(listen: listen))
        save("D4-wrong", DrillD4(listen: listen))
        listen.playCorrect()
        save("D1-correct", DrillD1(listen: listen))
        save("D3-correct", DrillD3(listen: listen))
        save("D4-correct", DrillD4(listen: listen))
        exit(0)
    }
}
#endif
