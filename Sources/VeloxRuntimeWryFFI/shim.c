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
  (void)velox_window_set_title;
  (void)velox_window_set_fullscreen;
  (void)velox_window_set_decorations;
  (void)velox_window_set_resizable;
  (void)velox_window_set_always_on_top;
  (void)velox_window_set_always_on_bottom;
  (void)velox_window_set_visible_on_all_workspaces;
  (void)velox_window_set_content_protected;
  (void)velox_window_set_visible;
  (void)velox_window_request_redraw;
  (void)velox_window_set_size;
  (void)velox_window_set_position;
  (void)velox_window_set_min_size;
  (void)velox_window_set_max_size;
  (void)velox_window_request_user_attention;
  (void)velox_window_clear_user_attention;
  (void)velox_window_focus;
  (void)velox_window_set_focusable;
  (void)velox_window_set_cursor_grab;
  (void)velox_window_set_cursor_visible;
  (void)velox_window_set_cursor_position;
  (void)velox_window_set_ignore_cursor_events;
  (void)velox_window_start_dragging;
  (void)velox_window_start_resize_dragging;
  (void)velox_webview_build;
  (void)velox_webview_free;
  (void)velox_webview_navigate;
  (void)velox_webview_reload;
  (void)velox_webview_evaluate_script;
  (void)velox_webview_set_zoom;
  (void)velox_webview_show;
  (void)velox_webview_hide;
  (void)velox_webview_clear_browsing_data;
}
