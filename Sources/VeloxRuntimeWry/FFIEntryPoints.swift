import Foundation
import VeloxRuntimeWryFFI

@_cdecl("velox_custom_protocol_handler_bridge")
func velox_custom_protocol_handler_bridge(
  _ requestPointer: UnsafePointer<VeloxCustomProtocolRequest>?,
  _ responsePointer: UnsafeMutablePointer<VeloxCustomProtocolResponse>?,
  _ userData: UnsafeMutableRawPointer?
) -> Bool {
  guard
    let requestPointer,
    let responsePointer,
    let userData
  else {
    return false
  }

  let handlerBox = Unmanaged<VeloxCustomProtocolHandlerBox>
    .fromOpaque(userData)
    .takeUnretainedValue()

  let requestStruct = requestPointer.pointee
  let url = VeloxRuntimeWry.stringFromNullablePointer(requestStruct.url)
  let method = VeloxRuntimeWry.stringFromNullablePointer(requestStruct.method)
  let identifier = VeloxRuntimeWry.stringFromNullablePointer(requestStruct.webview_id)

  var headers: [String: String] = [:]
  if requestStruct.headers.count > 0, let headerBase = requestStruct.headers.headers {
    let headerBuffer = UnsafeBufferPointer(
      start: headerBase,
      count: Int(requestStruct.headers.count)
    )
    for entry in headerBuffer {
      let name = VeloxRuntimeWry.stringFromNullablePointer(entry.name)
      let value = VeloxRuntimeWry.stringFromNullablePointer(entry.value)
      headers[name] = value
    }
  }

  let body: Data
  if requestStruct.body.len > 0, let pointer = requestStruct.body.ptr {
    body = Data(
      bytes: UnsafeRawPointer(pointer),
      count: Int(requestStruct.body.len)
    )
  } else {
    body = Data()
  }

  let request = VeloxRuntimeWry.CustomProtocol.Request(
    url: url,
    method: method,
    headers: headers,
    body: body,
    webviewIdentifier: identifier
  )

  guard let response = handlerBox.handler(request) else {
    return false
  }

  var ffiResponse = VeloxCustomProtocolResponse()
  ffiResponse.status = UInt16(clamping: response.status)

  var headerEntries: [(UnsafeMutablePointer<CChar>, UnsafeMutablePointer<CChar>)] = []
  headerEntries.reserveCapacity(response.headers.count)
  for (key, value) in response.headers {
    guard let namePtr = VeloxRuntimeWry.duplicateCString(key) else { continue }
    guard let valuePtr = VeloxRuntimeWry.duplicateCString(value) else {
      free(namePtr)
      continue
    }
    headerEntries.append((namePtr, valuePtr))
  }

  let storage = VeloxCustomProtocolResponseStorage()

  if !headerEntries.isEmpty {
    let headerPointer = UnsafeMutablePointer<VeloxCustomProtocolHeader>.allocate(capacity: headerEntries.count)
    for (index, entry) in headerEntries.enumerated() {
      storage.headerNamePointers.append(entry.0)
      storage.headerValuePointers.append(entry.1)
      headerPointer[index] = VeloxCustomProtocolHeader(
        name: UnsafePointer(entry.0),
        value: UnsafePointer(entry.1)
      )
    }
    storage.headerPointer = headerPointer
    ffiResponse.headers = VeloxCustomProtocolHeaderList(
      headers: UnsafePointer(headerPointer),
      count: headerEntries.count
    )
  } else {
    ffiResponse.headers = VeloxCustomProtocolHeaderList(headers: nil, count: 0)
  }

  if !response.body.isEmpty {
    let bodyPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: response.body.count)
    response.body.withUnsafeBytes { buffer in
      guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else {
        return
      }
      bodyPointer.initialize(from: base, count: response.body.count)
    }
    storage.bodyPointer = bodyPointer
    ffiResponse.body = VeloxCustomProtocolBuffer(
      ptr: UnsafePointer(bodyPointer),
      len: response.body.count
    )
  } else {
    ffiResponse.body = VeloxCustomProtocolBuffer(ptr: nil, len: 0)
  }

  if let mime = response.mimeType, let pointer = VeloxRuntimeWry.duplicateCString(mime) {
    storage.mimeTypePointer = pointer
    ffiResponse.mime_type = UnsafePointer(pointer)
  } else {
    ffiResponse.mime_type = nil
  }

  ffiResponse.free = velox_custom_protocol_response_free_trampoline
  ffiResponse.user_data = Unmanaged.passRetained(storage).toOpaque()

  responsePointer.pointee = ffiResponse
  return true
}

@_cdecl("velox_custom_protocol_response_bridge")
func velox_custom_protocol_response_bridge(_ userData: UnsafeMutableRawPointer?) {
  guard let userData else { return }
  let storage = Unmanaged<VeloxCustomProtocolResponseStorage>
    .fromOpaque(userData)
    .takeRetainedValue()
  storage.cleanup()
}
