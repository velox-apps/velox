import Foundation
import VeloxRuntimeWryFFI

final class VeloxCustomProtocolHandlerBox: @unchecked Sendable {
  let handler: VeloxRuntimeWry.CustomProtocol.Handler

  init(handler: @escaping VeloxRuntimeWry.CustomProtocol.Handler) {
    self.handler = handler
  }
}

final class VeloxCustomProtocolResponseStorage: @unchecked Sendable {
  var headerPointer: UnsafeMutablePointer<VeloxCustomProtocolHeader>?
  var headerNamePointers: [UnsafeMutablePointer<CChar>?] = []
  var headerValuePointers: [UnsafeMutablePointer<CChar>?] = []
  var mimeTypePointer: UnsafeMutablePointer<CChar>?
  var bodyPointer: UnsafeMutablePointer<UInt8>?

  func cleanup() {
    for pointer in headerNamePointers {
      if let pointer { free(pointer) }
    }
    headerNamePointers.removeAll(keepingCapacity: false)

    for pointer in headerValuePointers {
      if let pointer { free(pointer) }
    }
    headerValuePointers.removeAll(keepingCapacity: false)

    if let headerPointer {
      headerPointer.deallocate()
      self.headerPointer = nil
    }

    if let mimeTypePointer {
      free(mimeTypePointer)
      self.mimeTypePointer = nil
    }

    if let bodyPointer {
      bodyPointer.deallocate()
      self.bodyPointer = nil
    }
  }

  deinit {
    cleanup()
  }
}
