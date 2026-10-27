// Send one file from this Mac to a nearby AirDrop device with the system AirDrop service (opens the picker; click the target).
// Build: swiftc -O airdrop-send-from-mac.swift -o airdrop-send-from-mac    Run: ./airdrop-send-from-mac FILE
// Prints SHARED, FAILED <error> or TIMEOUT (120 s). Used to test Mac to M3 AirDrop without Finder drag and drop.
import AppKit
let args = CommandLine.arguments
guard args.count > 1 else { print("usage: send FILE"); exit(2) }
let url = URL(fileURLWithPath: args[1])
guard let svc = NSSharingService(named: .sendViaAirDrop) else { print("no AirDrop service"); exit(1) }
guard svc.canPerform(withItems: [url]) else { print("cannot perform with this file"); exit(1) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
class D: NSObject, NSSharingServiceDelegate {
  func sharingService(_ s: NSSharingService, didShareItems items: [Any]) { print("SHARED"); exit(0) }
  func sharingService(_ s: NSSharingService, didFailToShareItems items: [Any], error: Error) { print("FAILED \(error)"); exit(1) }
}
let d = D(); svc.delegate = d
DispatchQueue.main.async { svc.perform(withItems: [url]) }
DispatchQueue.main.asyncAfter(deadline: .now() + 120) { print("TIMEOUT"); exit(3) }
app.run()
