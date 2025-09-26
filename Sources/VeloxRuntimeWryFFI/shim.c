#include "velox_runtime_wry_ffi.h"

// This translation unit ensures the C target is picked up by SwiftPM while
// leaving all functionality delegated to the Rust static library.
void velox_runtime_wry_ffi_link_helper(void) {
  (void)velox_runtime_wry_library_name;
  (void)velox_runtime_wry_crate_version;
  (void)velox_runtime_wry_webview_version;
  (void)velox_event_loop_new;
  (void)velox_event_loop_free;
  (void)velox_event_loop_pump;
  (void)velox_event_loop_create_proxy;
  (void)velox_event_loop_proxy_request_exit;
  (void)velox_event_loop_proxy_free;
  (void)velox_window_build;
  (void)velox_window_free;
  (void)velox_webview_build;
  (void)velox_webview_free;
}
