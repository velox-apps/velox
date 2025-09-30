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

typedef struct {
  char _unused;
} VeloxTrayHandle;

typedef struct {
  const char *identifier;
  const char *title;
  const char *tooltip;
  bool visible;
  bool show_menu_on_left_click;
} VeloxTrayConfig;

#if defined(__APPLE__)
typedef struct {
  char _unused;
} VeloxMenuBarHandle;

typedef struct {
  char _unused;
} VeloxSubmenuHandle;

typedef struct {
  char _unused;
} VeloxMenuItemHandle;
#endif

typedef enum {
  VELOX_CONTROL_FLOW_POLL = 0,
  VELOX_CONTROL_FLOW_WAIT = 1,
  VELOX_CONTROL_FLOW_EXIT = 2,
} VeloxEventLoopControlFlow;

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

typedef VeloxEventLoopControlFlow (*VeloxEventLoopCallback)(const char *event_description, void *user_data);

VeloxEventLoopHandle *velox_event_loop_new(void);
void velox_event_loop_free(VeloxEventLoopHandle *event_loop);
void velox_event_loop_pump(
  VeloxEventLoopHandle *event_loop,
  VeloxEventLoopCallback callback,
  void *user_data
);

VeloxEventLoopProxyHandle *velox_event_loop_create_proxy(VeloxEventLoopHandle *event_loop);
bool velox_event_loop_proxy_request_exit(VeloxEventLoopProxyHandle *proxy);
bool velox_event_loop_proxy_send_user_event(
  VeloxEventLoopProxyHandle *proxy,
  const char *payload
);
void velox_event_loop_proxy_free(VeloxEventLoopProxyHandle *proxy);

VeloxWindowHandle *velox_window_build(VeloxEventLoopHandle *event_loop, const VeloxWindowConfig *config);
void velox_window_free(VeloxWindowHandle *window);
const char *velox_window_identifier(VeloxWindowHandle *window);
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

VeloxTrayHandle *velox_tray_new(const VeloxTrayConfig *config);
void velox_tray_free(VeloxTrayHandle *handle);
const char *velox_tray_identifier(VeloxTrayHandle *handle);
bool velox_tray_set_title(VeloxTrayHandle *handle, const char *title);
bool velox_tray_set_tooltip(VeloxTrayHandle *handle, const char *tooltip);
bool velox_tray_set_visible(VeloxTrayHandle *handle, bool visible);
bool velox_tray_set_show_menu_on_left_click(VeloxTrayHandle *handle, bool enable);

#if defined(__APPLE__)
VeloxMenuBarHandle *velox_menu_bar_new(void);
VeloxMenuBarHandle *velox_menu_bar_new_with_id(const char *identifier);
void velox_menu_bar_free(VeloxMenuBarHandle *menu);
const char *velox_menu_bar_identifier(VeloxMenuBarHandle *menu);
bool velox_menu_bar_append_submenu(
  VeloxMenuBarHandle *menu,
  VeloxSubmenuHandle *submenu
);
bool velox_menu_bar_set_app_menu(VeloxMenuBarHandle *menu);

VeloxSubmenuHandle *velox_submenu_new(const char *title, bool enabled);
VeloxSubmenuHandle *velox_submenu_new_with_id(
  const char *identifier,
  const char *title,
  bool enabled
);
void velox_submenu_free(VeloxSubmenuHandle *submenu);
const char *velox_submenu_identifier(VeloxSubmenuHandle *submenu);
bool velox_submenu_append_item(
  VeloxSubmenuHandle *submenu,
  VeloxMenuItemHandle *item
);

VeloxMenuItemHandle *velox_menu_item_new(
  const char *identifier,
  const char *title,
  bool enabled,
  const char *accelerator
);
void velox_menu_item_free(VeloxMenuItemHandle *item);
bool velox_menu_item_set_enabled(VeloxMenuItemHandle *item, bool enabled);
const char *velox_menu_item_identifier(VeloxMenuItemHandle *item);

bool velox_tray_set_menu(VeloxTrayHandle *handle, VeloxMenuBarHandle *menu);

void velox_app_state_force_launched(void);
#endif

#ifdef __cplusplus
}
#endif

#endif /* VELOX_RUNTIME_WRY_FFI_H */
