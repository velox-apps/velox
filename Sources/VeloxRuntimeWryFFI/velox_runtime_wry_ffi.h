#ifndef VELOX_RUNTIME_WRY_FFI_H
#define VELOX_RUNTIME_WRY_FFI_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

const char *velox_runtime_wry_library_name(void);
const char *velox_runtime_wry_crate_version(void);
const char *velox_runtime_wry_webview_version(void);

typedef struct {
  char _unused;
} VeloxEventLoopHandle;

typedef struct {
  char _unused;
} VeloxEventLoopProxyHandle;

typedef struct {
  char _unused;
} VeloxWindowHandle;

typedef struct {
  char _unused;
} VeloxWebviewHandle;

typedef enum {
  VELOX_CONTROL_FLOW_POLL = 0,
  VELOX_CONTROL_FLOW_WAIT = 1,
  VELOX_CONTROL_FLOW_EXIT = 2,
} VeloxControlFlow;

typedef struct {
  uint32_t width;
  uint32_t height;
  const char *title;
} VeloxWindowConfig;

typedef struct {
  const char *url;
} VeloxWebviewConfig;

typedef enum {
  VELOX_USER_ATTENTION_TYPE_INFORMATIONAL = 0,
  VELOX_USER_ATTENTION_TYPE_CRITICAL = 1,
} VeloxUserAttentionType;

typedef enum {
  VELOX_RESIZE_DIRECTION_EAST = 0,
  VELOX_RESIZE_DIRECTION_NORTH = 1,
  VELOX_RESIZE_DIRECTION_NORTH_EAST = 2,
  VELOX_RESIZE_DIRECTION_NORTH_WEST = 3,
  VELOX_RESIZE_DIRECTION_SOUTH = 4,
  VELOX_RESIZE_DIRECTION_SOUTH_EAST = 5,
  VELOX_RESIZE_DIRECTION_SOUTH_WEST = 6,
  VELOX_RESIZE_DIRECTION_WEST = 7,
} VeloxResizeDirection;

typedef VeloxControlFlow (*VeloxEventLoopCallback)(const char *event_description, void *user_data);

VeloxEventLoopHandle *velox_event_loop_new(void);
void velox_event_loop_free(VeloxEventLoopHandle *event_loop);
void velox_event_loop_pump(
  VeloxEventLoopHandle *event_loop,
  VeloxEventLoopCallback callback,
  void *user_data
);

VeloxEventLoopProxyHandle *velox_event_loop_create_proxy(VeloxEventLoopHandle *event_loop);
bool velox_event_loop_proxy_request_exit(VeloxEventLoopProxyHandle *proxy);
void velox_event_loop_proxy_free(VeloxEventLoopProxyHandle *proxy);

VeloxWindowHandle *velox_window_build(VeloxEventLoopHandle *event_loop, const VeloxWindowConfig *config);
void velox_window_free(VeloxWindowHandle *window);
bool velox_window_set_title(VeloxWindowHandle *window, const char *title);
bool velox_window_set_fullscreen(VeloxWindowHandle *window, bool fullscreen);
bool velox_window_set_decorations(VeloxWindowHandle *window, bool decorations);
bool velox_window_set_resizable(VeloxWindowHandle *window, bool resizable);
bool velox_window_set_always_on_top(VeloxWindowHandle *window, bool on_top);
bool velox_window_set_always_on_bottom(VeloxWindowHandle *window, bool on_bottom);
bool velox_window_set_visible_on_all_workspaces(
  VeloxWindowHandle *window,
  bool visible_on_all_workspaces
);
bool velox_window_set_content_protected(VeloxWindowHandle *window, bool protected_content);
bool velox_window_set_visible(VeloxWindowHandle *window, bool visible);
bool velox_window_request_redraw(VeloxWindowHandle *window);
bool velox_window_set_size(VeloxWindowHandle *window, double width, double height);
bool velox_window_set_position(VeloxWindowHandle *window, double x, double y);
bool velox_window_set_min_size(VeloxWindowHandle *window, double width, double height);
bool velox_window_set_max_size(VeloxWindowHandle *window, double width, double height);
bool velox_window_request_user_attention(
  VeloxWindowHandle *window,
  VeloxUserAttentionType attention_type
);
bool velox_window_clear_user_attention(VeloxWindowHandle *window);
bool velox_window_focus(VeloxWindowHandle *window);
bool velox_window_set_focusable(VeloxWindowHandle *window, bool focusable);
bool velox_window_set_cursor_grab(VeloxWindowHandle *window, bool grab);
bool velox_window_set_cursor_visible(VeloxWindowHandle *window, bool visible);
bool velox_window_set_cursor_position(
  VeloxWindowHandle *window,
  double x,
  double y
);
bool velox_window_set_ignore_cursor_events(VeloxWindowHandle *window, bool ignore);
bool velox_window_start_dragging(VeloxWindowHandle *window);
bool velox_window_start_resize_dragging(
  VeloxWindowHandle *window,
  VeloxResizeDirection direction
);

VeloxWebviewHandle *velox_webview_build(VeloxWindowHandle *window, const VeloxWebviewConfig *config);
void velox_webview_free(VeloxWebviewHandle *webview);
bool velox_webview_navigate(VeloxWebviewHandle *webview, const char *url);
bool velox_webview_reload(VeloxWebviewHandle *webview);
bool velox_webview_evaluate_script(VeloxWebviewHandle *webview, const char *script);
bool velox_webview_set_zoom(VeloxWebviewHandle *webview, double scale_factor);
bool velox_webview_show(VeloxWebviewHandle *webview);
bool velox_webview_hide(VeloxWebviewHandle *webview);
bool velox_webview_clear_browsing_data(VeloxWebviewHandle *webview);

#ifdef __cplusplus
}
#endif

#endif /* VELOX_RUNTIME_WRY_FFI_H */
