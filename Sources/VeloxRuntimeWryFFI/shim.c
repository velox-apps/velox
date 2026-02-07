#include "velox_runtime_wry_ffi.h"

bool velox_custom_protocol_handler_bridge(
  const VeloxCustomProtocolRequest *request,
  VeloxCustomProtocolResponse *response,
  void *user_data
);

void velox_custom_protocol_response_bridge(void *user_data);

bool velox_custom_protocol_handler_trampoline(
  const VeloxCustomProtocolRequest *request,
  VeloxCustomProtocolResponse *response,
  void *user_data
) {
  return velox_custom_protocol_handler_bridge(request, response, user_data);
}

void velox_custom_protocol_response_free_trampoline(void *user_data) {
  velox_custom_protocol_response_bridge(user_data);
}

// This translation unit ensures the C target is picked up by SwiftPM while
// leaving all functionality delegated to the Rust static library.
void velox_runtime_wry_ffi_link_helper(void) {
  (void)velox_runtime_wry_library_name;
  (void)velox_runtime_wry_ffi_abi_version;
  (void)velox_runtime_wry_crate_version;
  (void)velox_runtime_wry_webview_version;
  (void)velox_event_loop_new;
  (void)velox_event_loop_free;
  (void)velox_event_loop_pump;
  (void)velox_event_loop_create_proxy;
  (void)velox_event_loop_proxy_request_exit;
  (void)velox_event_loop_proxy_send_user_event;
  (void)velox_event_loop_proxy_free;
  (void)velox_event_loop_set_activation_policy;
  (void)velox_event_loop_set_dock_visibility;
  (void)velox_event_loop_hide_application;
  (void)velox_event_loop_show_application;
  (void)velox_window_build;
  (void)velox_window_free;
  (void)velox_window_identifier;
  (void)velox_window_set_title;
  (void)velox_window_set_fullscreen;
  (void)velox_window_set_decorations;
  (void)velox_window_set_resizable;
  (void)velox_window_set_always_on_top;
  (void)velox_window_set_always_on_bottom;
  (void)velox_window_set_visible_on_all_workspaces;
  (void)velox_window_set_content_protected;
  (void)velox_window_set_visible;
  (void)velox_window_set_maximized;
  (void)velox_window_set_minimized;
  (void)velox_window_set_minimizable;
  (void)velox_window_set_maximizable;
  (void)velox_window_set_closable;
  (void)velox_window_set_skip_taskbar;
  (void)velox_window_set_background_color;
  (void)velox_window_set_theme;
  (void)velox_window_title;
  (void)velox_window_is_fullscreen;
  (void)velox_window_is_focused;
  (void)velox_window_is_maximized;
  (void)velox_window_is_minimized;
  (void)velox_window_is_visible;
  (void)velox_window_is_resizable;
  (void)velox_window_is_decorated;
  (void)velox_window_is_always_on_top;
  (void)velox_window_is_minimizable;
  (void)velox_window_is_maximizable;
  (void)velox_window_is_closable;
  (void)velox_window_scale_factor;
  (void)velox_window_inner_position;
  (void)velox_window_outer_position;
  (void)velox_window_inner_size;
  (void)velox_window_outer_size;
  (void)velox_window_current_monitor;
  (void)velox_window_primary_monitor;
  (void)velox_window_available_monitors;
  (void)velox_window_monitor_from_point;
  (void)velox_window_cursor_position;
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
  (void)velox_custom_protocol_handler_trampoline;
  (void)velox_custom_protocol_response_free_trampoline;
  (void)velox_webview_build;
  (void)velox_webview_free;
  (void)velox_webview_navigate;
  (void)velox_webview_reload;
  (void)velox_webview_evaluate_script;
  (void)velox_webview_set_zoom;
  (void)velox_webview_show;
  (void)velox_webview_hide;
  (void)velox_webview_clear_browsing_data;
  (void)velox_dialog_open;
  (void)velox_dialog_save;
  (void)velox_dialog_selection_free;
  (void)velox_dialog_message;
  (void)velox_dialog_confirm;
  (void)velox_dialog_ask;
  (void)velox_dialog_prompt;
  (void)velox_dialog_prompt_result_free;
  (void)velox_tray_new;
  (void)velox_tray_free;
  (void)velox_tray_identifier;
  (void)velox_tray_set_title;
  (void)velox_tray_set_tooltip;
  (void)velox_tray_set_visible;
  (void)velox_tray_set_show_menu_on_left_click;
  (void)velox_tray_set_menu;
#if defined(__APPLE__)
  (void)velox_menu_bar_new;
  (void)velox_menu_bar_new_with_id;
  (void)velox_menu_bar_free;
  (void)velox_menu_bar_identifier;
  (void)velox_menu_bar_append_submenu;
  (void)velox_menu_bar_append;
  (void)velox_menu_bar_prepend;
  (void)velox_menu_bar_insert;
  (void)velox_menu_bar_remove;
  (void)velox_menu_bar_remove_at;
  (void)velox_menu_bar_popup;
  (void)velox_menu_bar_set_app_menu;
  (void)velox_submenu_new;
  (void)velox_submenu_new_with_id;
  (void)velox_submenu_free;
  (void)velox_submenu_identifier;
  (void)velox_submenu_text;
  (void)velox_submenu_set_text;
  (void)velox_submenu_is_enabled;
  (void)velox_submenu_set_enabled;
  (void)velox_submenu_set_native_icon;
  (void)velox_submenu_append_item;
  (void)velox_submenu_append;
  (void)velox_submenu_prepend;
  (void)velox_submenu_insert;
  (void)velox_submenu_remove;
  (void)velox_submenu_remove_at;
  (void)velox_submenu_popup;
  (void)velox_submenu_set_as_windows_menu_for_nsapp;
  (void)velox_submenu_set_as_help_menu_for_nsapp;
  (void)velox_menu_item_new;
  (void)velox_menu_item_free;
  (void)velox_menu_item_set_enabled;
  (void)velox_menu_item_is_enabled;
  (void)velox_menu_item_text;
  (void)velox_menu_item_set_text;
  (void)velox_menu_item_set_accelerator;
  (void)velox_menu_item_identifier;
  (void)velox_icon_menu_item_new;
  (void)velox_icon_menu_item_free;
  (void)velox_icon_menu_item_identifier;
  (void)velox_icon_menu_item_text;
  (void)velox_icon_menu_item_set_text;
  (void)velox_icon_menu_item_set_enabled;
  (void)velox_icon_menu_item_is_enabled;
  (void)velox_icon_menu_item_set_accelerator;
  (void)velox_icon_menu_item_set_native_icon;
  (void)velox_predefined_menu_item_new;
  (void)velox_predefined_menu_item_free;
  (void)velox_predefined_menu_item_identifier;
  (void)velox_predefined_menu_item_text;
  (void)velox_predefined_menu_item_set_text;
  (void)velox_separator_new;
  (void)velox_separator_free;
  (void)velox_separator_identifier;
  (void)velox_submenu_append_separator;
  (void)velox_check_menu_item_new;
  (void)velox_check_menu_item_free;
  (void)velox_check_menu_item_is_checked;
  (void)velox_check_menu_item_set_checked;
  (void)velox_check_menu_item_is_enabled;
  (void)velox_check_menu_item_set_enabled;
  (void)velox_check_menu_item_text;
  (void)velox_check_menu_item_set_text;
  (void)velox_check_menu_item_set_accelerator;
  (void)velox_check_menu_item_identifier;
  (void)velox_submenu_append_check_item;
#endif
}
