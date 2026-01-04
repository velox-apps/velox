#ifndef VELOX_RUNTIME_WRY_FFI_H
#define VELOX_RUNTIME_WRY_FFI_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

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

typedef struct {
  char _unused;
} VeloxCheckMenuItemHandle;

typedef struct {
  char _unused;
} VeloxSeparatorHandle;
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
  const char *label;
  const char *const *extensions;
  size_t extension_count;
} VeloxDialogFilter;

typedef struct {
  const char *title;
  const char *default_path;
  const VeloxDialogFilter *filters;
  size_t filter_count;
  bool allow_directories;
  bool allow_multiple;
} VeloxDialogOpenOptions;

typedef struct {
  const char *title;
  const char *default_path;
  const char *default_name;
  const VeloxDialogFilter *filters;
  size_t filter_count;
} VeloxDialogSaveOptions;

typedef struct {
  char **paths;
  size_t count;
} VeloxDialogSelection;

typedef enum {
  VELOX_MESSAGE_DIALOG_LEVEL_INFO = 0,
  VELOX_MESSAGE_DIALOG_LEVEL_WARNING = 1,
  VELOX_MESSAGE_DIALOG_LEVEL_ERROR = 2,
} VeloxMessageDialogLevel;

typedef enum {
  VELOX_MESSAGE_DIALOG_BUTTONS_OK = 0,
  VELOX_MESSAGE_DIALOG_BUTTONS_OK_CANCEL = 1,
  VELOX_MESSAGE_DIALOG_BUTTONS_YES_NO = 2,
  VELOX_MESSAGE_DIALOG_BUTTONS_YES_NO_CANCEL = 3,
} VeloxMessageDialogButtons;

typedef struct {
  const char *title;
  const char *message;
  VeloxMessageDialogLevel level;
  VeloxMessageDialogButtons buttons;
  const char *ok_label;
  const char *cancel_label;
  const char *yes_label;
  const char *no_label;
} VeloxMessageDialogOptions;

typedef struct {
  const char *title;
  const char *message;
  VeloxMessageDialogLevel level;
  const char *ok_label;
  const char *cancel_label;
} VeloxConfirmDialogOptions;

typedef struct {
  const char *title;
  const char *message;
  VeloxMessageDialogLevel level;
  const char *yes_label;
  const char *no_label;
} VeloxAskDialogOptions;

typedef struct {
  const char *title;
  const char *message;
  const char *placeholder;
  const char *default_value;
  const char *ok_label;
  const char *cancel_label;
} VeloxPromptDialogOptions;

typedef struct {
  char *value;
  bool accepted;
} VeloxPromptDialogResult;

typedef struct {
  const char *name;
  const char *value;
} VeloxCustomProtocolHeader;

typedef struct {
  const VeloxCustomProtocolHeader *headers;
  size_t count;
} VeloxCustomProtocolHeaderList;

typedef struct {
  const uint8_t *ptr;
  size_t len;
} VeloxCustomProtocolBuffer;

typedef struct {
  const char *url;
  const char *method;
  VeloxCustomProtocolHeaderList headers;
  VeloxCustomProtocolBuffer body;
  const char *webview_id;
} VeloxCustomProtocolRequest;

typedef void (*VeloxCustomProtocolResponseFree)(void *user_data);

typedef struct {
  uint16_t status;
  VeloxCustomProtocolHeaderList headers;
  VeloxCustomProtocolBuffer body;
  const char *mime_type;
  VeloxCustomProtocolResponseFree free;
  void *user_data;
} VeloxCustomProtocolResponse;

typedef bool (*VeloxCustomProtocolHandler)(
  const VeloxCustomProtocolRequest *request,
  VeloxCustomProtocolResponse *response,
  void *user_data
);

typedef struct {
  const char *scheme;
  VeloxCustomProtocolHandler handler;
  void *user_data;
} VeloxCustomProtocolDefinition;

typedef struct VeloxCustomProtocolList {
  const VeloxCustomProtocolDefinition *protocols;
  size_t count;
} VeloxCustomProtocolList;

typedef struct {
  const char *url;
  VeloxCustomProtocolList custom_protocols;
  /// If true, create as a child webview with bounds
  bool is_child;
  /// X position for child webview (logical pixels)
  double x;
  /// Y position for child webview (logical pixels)
  double y;
  /// Width for child webview (logical pixels)
  double width;
  /// Height for child webview (logical pixels)
  double height;
} VeloxWebviewConfig;

typedef struct {
  uint8_t red;
  uint8_t green;
  uint8_t blue;
  uint8_t alpha;
} VeloxColor;

typedef struct {
  double x;
  double y;
} VeloxPoint;

typedef struct {
  double width;
  double height;
} VeloxSize;

typedef enum {
  VELOX_WINDOW_THEME_UNSPECIFIED = 0,
  VELOX_WINDOW_THEME_LIGHT = 1,
  VELOX_WINDOW_THEME_DARK = 2,
} VeloxWindowTheme;

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
bool velox_window_set_maximized(VeloxWindowHandle *window, bool maximized);
bool velox_window_set_minimized(VeloxWindowHandle *window, bool minimized);
bool velox_window_set_minimizable(VeloxWindowHandle *window, bool minimizable);
bool velox_window_set_maximizable(VeloxWindowHandle *window, bool maximizable);
bool velox_window_set_closable(VeloxWindowHandle *window, bool closable);
bool velox_window_set_skip_taskbar(VeloxWindowHandle *window, bool skip);
bool velox_window_set_background_color(VeloxWindowHandle *window, const VeloxColor *color);
bool velox_window_set_theme(VeloxWindowHandle *window, VeloxWindowTheme theme);
const char *velox_window_title(VeloxWindowHandle *window);
bool velox_window_is_fullscreen(VeloxWindowHandle *window);
bool velox_window_is_focused(VeloxWindowHandle *window);
bool velox_window_is_maximized(VeloxWindowHandle *window);
bool velox_window_is_minimized(VeloxWindowHandle *window);
bool velox_window_is_visible(VeloxWindowHandle *window);
bool velox_window_is_resizable(VeloxWindowHandle *window);
bool velox_window_is_decorated(VeloxWindowHandle *window);
bool velox_window_is_always_on_top(VeloxWindowHandle *window);
bool velox_window_is_minimizable(VeloxWindowHandle *window);
bool velox_window_is_maximizable(VeloxWindowHandle *window);
bool velox_window_is_closable(VeloxWindowHandle *window);
bool velox_window_scale_factor(VeloxWindowHandle *window, double *scale_factor);
bool velox_window_inner_position(VeloxWindowHandle *window, VeloxPoint *position);
bool velox_window_outer_position(VeloxWindowHandle *window, VeloxPoint *position);
bool velox_window_inner_size(VeloxWindowHandle *window, VeloxSize *size);
bool velox_window_outer_size(VeloxWindowHandle *window, VeloxSize *size);
const char *velox_window_current_monitor(VeloxWindowHandle *window);
const char *velox_window_primary_monitor(VeloxWindowHandle *window);
const char *velox_window_available_monitors(VeloxWindowHandle *window);
const char *velox_window_monitor_from_point(VeloxWindowHandle *window, VeloxPoint point);
bool velox_window_cursor_position(VeloxWindowHandle *window, VeloxPoint *position);
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

VeloxDialogSelection velox_dialog_open(const VeloxDialogOpenOptions *options);
VeloxDialogSelection velox_dialog_save(const VeloxDialogSaveOptions *options);
void velox_dialog_selection_free(VeloxDialogSelection selection);
bool velox_dialog_message(const VeloxMessageDialogOptions *options);
bool velox_dialog_confirm(const VeloxConfirmDialogOptions *options);
bool velox_dialog_ask(const VeloxAskDialogOptions *options);
VeloxPromptDialogResult velox_dialog_prompt(const VeloxPromptDialogOptions *options);
void velox_dialog_prompt_result_free(VeloxPromptDialogResult result);

VeloxWebviewHandle *velox_webview_build(VeloxWindowHandle *window, const VeloxWebviewConfig *config);
void velox_webview_free(VeloxWebviewHandle *webview);
const char *velox_webview_identifier(VeloxWebviewHandle *webview);
bool velox_webview_navigate(VeloxWebviewHandle *webview, const char *url);
bool velox_webview_reload(VeloxWebviewHandle *webview);
bool velox_webview_evaluate_script(VeloxWebviewHandle *webview, const char *script);
bool velox_webview_set_zoom(VeloxWebviewHandle *webview, double scale_factor);
bool velox_webview_show(VeloxWebviewHandle *webview);
bool velox_webview_hide(VeloxWebviewHandle *webview);
bool velox_webview_clear_browsing_data(VeloxWebviewHandle *webview);
bool velox_webview_set_bounds(
  VeloxWebviewHandle *webview,
  double x,
  double y,
  double width,
  double height
);

VeloxTrayHandle *velox_tray_new(const VeloxTrayConfig *config);
void velox_tray_free(VeloxTrayHandle *handle);
const char *velox_tray_identifier(VeloxTrayHandle *handle);
bool velox_tray_set_title(VeloxTrayHandle *handle, const char *title);
bool velox_tray_set_tooltip(VeloxTrayHandle *handle, const char *tooltip);
bool velox_tray_set_visible(VeloxTrayHandle *handle, bool visible);
bool velox_tray_set_show_menu_on_left_click(VeloxTrayHandle *handle, bool enable);

#if defined(__APPLE__)
typedef enum {
  VELOX_ACTIVATION_POLICY_REGULAR = 0,
  VELOX_ACTIVATION_POLICY_ACCESSORY = 1,
  VELOX_ACTIVATION_POLICY_PROHIBITED = 2,
} VeloxActivationPolicy;

bool velox_event_loop_set_activation_policy(VeloxEventLoopHandle *event_loop, VeloxActivationPolicy policy);
bool velox_event_loop_set_dock_visibility(VeloxEventLoopHandle *event_loop, bool visible);
bool velox_event_loop_hide_application(VeloxEventLoopHandle *event_loop);
bool velox_event_loop_show_application(VeloxEventLoopHandle *event_loop);

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
bool velox_menu_item_is_enabled(VeloxMenuItemHandle *item);
const char *velox_menu_item_text(VeloxMenuItemHandle *item);
bool velox_menu_item_set_text(VeloxMenuItemHandle *item, const char *title);
bool velox_menu_item_set_accelerator(VeloxMenuItemHandle *item, const char *accelerator);
const char *velox_menu_item_identifier(VeloxMenuItemHandle *item);

VeloxSeparatorHandle *velox_separator_new(void);
void velox_separator_free(VeloxSeparatorHandle *separator);
const char *velox_separator_identifier(VeloxSeparatorHandle *separator);
bool velox_submenu_append_separator(
  VeloxSubmenuHandle *submenu,
  VeloxSeparatorHandle *separator
);

VeloxCheckMenuItemHandle *velox_check_menu_item_new(
  const char *identifier,
  const char *title,
  bool enabled,
  bool checked,
  const char *accelerator
);
void velox_check_menu_item_free(VeloxCheckMenuItemHandle *item);
bool velox_check_menu_item_is_checked(VeloxCheckMenuItemHandle *item);
bool velox_check_menu_item_set_checked(VeloxCheckMenuItemHandle *item, bool checked);
bool velox_check_menu_item_is_enabled(VeloxCheckMenuItemHandle *item);
bool velox_check_menu_item_set_enabled(VeloxCheckMenuItemHandle *item, bool enabled);
const char *velox_check_menu_item_text(VeloxCheckMenuItemHandle *item);
bool velox_check_menu_item_set_text(VeloxCheckMenuItemHandle *item, const char *title);
bool velox_check_menu_item_set_accelerator(VeloxCheckMenuItemHandle *item, const char *accelerator);
const char *velox_check_menu_item_identifier(VeloxCheckMenuItemHandle *item);
bool velox_submenu_append_check_item(
  VeloxSubmenuHandle *submenu,
  VeloxCheckMenuItemHandle *item
);

bool velox_tray_set_menu(VeloxTrayHandle *handle, VeloxMenuBarHandle *menu);

void velox_app_state_force_launched(void);
#endif

#ifdef __cplusplus
}
#endif

#endif /* VELOX_RUNTIME_WRY_FFI_H */
