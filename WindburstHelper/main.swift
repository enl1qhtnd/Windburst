import Foundation
import WindburstShared

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: WindburstXPCConstants.machServiceName)
listener.delegate = delegate
listener.resume()

NSLog("WindburstHelper started on \(WindburstXPCConstants.machServiceName)")
RunLoop.main.run()
