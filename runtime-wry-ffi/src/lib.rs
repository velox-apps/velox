use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
#[cfg(target_os = "macos")]
use std::rc::Rc;
use std::sync::OnceLock;
use std::{cell::RefCell, thread::LocalKey};

#[cfg(target_os = "macos")]
use tray_icon::{menu::Menu as TrayMenu, TrayIcon, TrayIconBuilder, TrayIconEvent};

#[cfg(target_os = "macos")]
use muda::{accelerator::Accelerator, Menu, MenuEvent, MenuId, MenuItem, Submenu};
use serde::Serialize;
use serde_json::{json, Map};
use tao::{
    dpi::{LogicalPosition, LogicalSize, Size},
    event::{
        ElementState, Event, MouseButton, MouseScrollDelta,
        WindowEvent as TaoWindowEvent,
    },
    event_loop::{ControlFlow, EventLoop, EventLoopBuilder, EventLoopProxy},
    keyboard::ModifiersState,
    monitor::MonitorHandle,
    platform::run_return::EventLoopExtRunReturn,
    window::{
        Fullscreen, ResizeDirection as TaoResizeDirection, Theme,
        UserAttentionType as TaoUserAttentionType, Window, WindowBuilder as TaoWindowBuilder,
    },
};

use rfd::{FileDialog, MessageButtons, MessageDialog, MessageDialogResult, MessageLevel};
#[cfg(target_os = "macos")]
use tao::platform::macos::{ActivationPolicy, EventLoopWindowTargetExtMacOS};
use url::Url;
use wry::{
    http::{
        header::{HeaderName, HeaderValue, CONTENT_TYPE},
        Response as WryHttpResponse, StatusCode,
    },
    Rect, WebView, WebViewBuilder,
};

static LIBRARY_NAME: OnceLock<CString> = OnceLock::new();
static RUNTIME_VERSION: OnceLock<CString> = OnceLock::new();
static WEBVIEW_VERSION: OnceLock<CString> = OnceLock::new();

thread_local! {
    static TITLE_BUFFER: RefCell<CString> = RefCell::new(CString::new("").expect("empty string"));
    static MONITOR_BUFFER: RefCell<CString> = RefCell::new(CString::new("").expect("empty string"));
    static MONITOR_LIST_BUFFER: RefCell<CString> = RefCell::new(CString::new("").expect("empty string"));
}

#[derive(Debug, Clone)]
enum VeloxUserEvent {
    Exit,
    Custom(String),
    #[cfg(target_os = "macos")]
    Menu(String),
    #[cfg(target_os = "macos")]
    Tray(VeloxTrayEvent),
}

pub struct VeloxEventLoop {
    event_loop: EventLoop<VeloxUserEvent>,
}

pub struct VeloxEventLoopProxyHandle {
    proxy: EventLoopProxy<VeloxUserEvent>,
}

pub struct VeloxWindowHandle {
    window: Window,
    identifier: CString,
}

pub struct VeloxWebviewHandle {
    webview: WebView,
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct VeloxColor {
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8,
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct VeloxPoint {
    pub x: f64,
    pub y: f64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct VeloxSize {
    pub width: f64,
    pub height: f64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VeloxWindowTheme {
    Unspecified = 0,
    Light = 1,
    Dark = 2,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VeloxActivationPolicy {
    Regular = 0,
    Accessory = 1,
    Prohibited = 2,
}

#[cfg(target_os = "macos")]
pub struct VeloxMenuBarHandle {
    menu: Menu,
    submenus: Vec<Rc<RefCell<Submenu>>>,
    identifier: CString,
}

#[cfg(target_os = "macos")]
pub struct VeloxSubmenuHandle {
    submenu: Rc<RefCell<Submenu>>,
    identifier: CString,
    items: Vec<MenuItem>,
}

#[cfg(target_os = "macos")]
pub struct VeloxMenuItemHandle {
    item: MenuItem,
    identifier: CString,
}

#[cfg(not(target_os = "macos"))]
pub struct VeloxMenuBarHandle {
    _private: (),
}

#[cfg(not(target_os = "macos"))]
pub struct VeloxSubmenuHandle {
    _private: (),
}

#[cfg(not(target_os = "macos"))]
pub struct VeloxMenuItemHandle {
    _private: (),
}

#[cfg(target_os = "macos")]
pub struct VeloxTrayHandle {
    tray: TrayIcon,
    menu: Option<TrayMenu>,
    identifier: CString,
}

#[cfg(not(target_os = "macos"))]
pub struct VeloxTrayHandle {
    _private: (),
}

#[cfg(target_os = "macos")]
#[derive(Debug, Clone)]
struct VeloxTrayEvent {
    identifier: String,
    kind: VeloxTrayEventKind,
    position: Option<(f64, f64)>,
    rect: Option<VeloxTrayRect>,
    button: Option<String>,
    button_state: Option<String>,
}

#[cfg(target_os = "macos")]
#[derive(Debug, Clone, Copy)]
enum VeloxTrayEventKind {
    Click,
    DoubleClick,
    Enter,
    Move,
    Leave,
}

#[cfg(target_os = "macos")]
#[derive(Debug, Clone, Copy)]
struct VeloxTrayRect {
    origin_x: f64,
    origin_y: f64,
    width: f64,
    height: f64,
}

#[cfg(target_os = "macos")]
impl From<tray_icon::Rect> for VeloxTrayRect {
    fn from(rect: tray_icon::Rect) -> Self {
        Self {
            origin_x: rect.position.x,
            origin_y: rect.position.y,
            width: rect.size.width as f64,
            height: rect.size.height as f64,
        }
    }
}

#[cfg(target_os = "macos")]
impl From<tray_icon::TrayIconEvent> for VeloxTrayEvent {
    fn from(event: tray_icon::TrayIconEvent) -> Self {
        match event {
            TrayIconEvent::Click {
                id,
                position,
                rect,
                button,
                button_state,
            } => Self {
                identifier: id.as_ref().to_string(),
                kind: VeloxTrayEventKind::Click,
                position: Some((position.x, position.y)),
                rect: Some(rect.into()),
                button: Some(match button {
                    tray_icon::MouseButton::Left => "left".to_string(),
                    tray_icon::MouseButton::Right => "right".to_string(),
                    tray_icon::MouseButton::Middle => "middle".to_string(),
                }),
                button_state: Some(match button_state {
                    tray_icon::MouseButtonState::Up => "up".to_string(),
                    tray_icon::MouseButtonState::Down => "down".to_string(),
                }),
            },
            TrayIconEvent::DoubleClick {
                id,
                position,
                rect,
                button,
            } => Self {
                identifier: id.as_ref().to_string(),
                kind: VeloxTrayEventKind::DoubleClick,
                position: Some((position.x, position.y)),
                rect: Some(rect.into()),
                button: Some(match button {
                    tray_icon::MouseButton::Left => "left".to_string(),
                    tray_icon::MouseButton::Right => "right".to_string(),
                    tray_icon::MouseButton::Middle => "middle".to_string(),
                }),
                button_state: None,
            },
            TrayIconEvent::Enter { id, position, rect } => Self {
                identifier: id.as_ref().to_string(),
                kind: VeloxTrayEventKind::Enter,
                position: Some((position.x, position.y)),
                rect: Some(rect.into()),
                button: None,
                button_state: None,
            },
            TrayIconEvent::Move { id, position, rect } => Self {
                identifier: id.as_ref().to_string(),
                kind: VeloxTrayEventKind::Move,
                position: Some((position.x, position.y)),
                rect: Some(rect.into()),
                button: None,
                button_state: None,
            },
            TrayIconEvent::Leave { id, position, rect } => Self {
                identifier: id.as_ref().to_string(),
                kind: VeloxTrayEventKind::Leave,
                position: Some((position.x, position.y)),
                rect: Some(rect.into()),
                button: None,
                button_state: None,
            },
            other => Self {
                identifier: other.id().as_ref().to_string(),
                kind: VeloxTrayEventKind::Move,
                position: None,
                rect: None,
                button: None,
                button_state: None,
            },
        }
    }
}

#[repr(C)]
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum VeloxEventLoopControlFlow {
    Poll = 0,
    Wait = 1,
    Exit = 2,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxWindowConfig {
    pub width: u32,
    pub height: u32,
    pub title: *const c_char,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxWebviewConfig {
    pub url: *const c_char,
    pub custom_protocols: VeloxCustomProtocolList,
    /// If true, create as a child webview with bounds
    pub is_child: bool,
    /// X position for child webview (logical pixels)
    pub x: f64,
    /// Y position for child webview (logical pixels)
    pub y: f64,
    /// Width for child webview (logical pixels)
    pub width: f64,
    /// Height for child webview (logical pixels)
    pub height: f64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct VeloxTrayConfig {
    pub identifier: *const c_char,
    pub title: *const c_char,
    pub tooltip: *const c_char,
    pub visible: bool,
    pub show_menu_on_left_click: bool,
}

impl Default for VeloxTrayConfig {
    fn default() -> Self {
        Self {
            identifier: ptr::null(),
            title: ptr::null(),
            tooltip: ptr::null(),
            visible: true,
            show_menu_on_left_click: true,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxDialogFilter {
    pub label: *const c_char,
    pub extensions: *const *const c_char,
    pub extension_count: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxDialogOpenOptions {
    pub title: *const c_char,
    pub default_path: *const c_char,
    pub filters: *const VeloxDialogFilter,
    pub filter_count: usize,
    pub allow_directories: bool,
    pub allow_multiple: bool,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxDialogSaveOptions {
    pub title: *const c_char,
    pub default_path: *const c_char,
    pub default_name: *const c_char,
    pub filters: *const VeloxDialogFilter,
    pub filter_count: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxDialogSelection {
    pub paths: *mut *mut c_char,
    pub count: usize,
}

#[repr(C)]
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum VeloxMessageDialogLevel {
    Info = 0,
    Warning = 1,
    Error = 2,
}

impl Default for VeloxMessageDialogLevel {
    fn default() -> Self {
        Self::Info
    }
}

#[repr(C)]
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum VeloxMessageDialogButtons {
    Ok = 0,
    OkCancel = 1,
    YesNo = 2,
    YesNoCancel = 3,
}

impl Default for VeloxMessageDialogButtons {
    fn default() -> Self {
        Self::Ok
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxMessageDialogOptions {
    pub title: *const c_char,
    pub message: *const c_char,
    pub level: VeloxMessageDialogLevel,
    pub buttons: VeloxMessageDialogButtons,
    pub ok_label: *const c_char,
    pub cancel_label: *const c_char,
    pub yes_label: *const c_char,
    pub no_label: *const c_char,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxConfirmDialogOptions {
    pub title: *const c_char,
    pub message: *const c_char,
    pub level: VeloxMessageDialogLevel,
    pub ok_label: *const c_char,
    pub cancel_label: *const c_char,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxAskDialogOptions {
    pub title: *const c_char,
    pub message: *const c_char,
    pub level: VeloxMessageDialogLevel,
    pub yes_label: *const c_char,
    pub no_label: *const c_char,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxPromptDialogOptions {
    pub title: *const c_char,
    pub message: *const c_char,
    pub placeholder: *const c_char,
    pub default_value: *const c_char,
    pub ok_label: *const c_char,
    pub cancel_label: *const c_char,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxPromptDialogResult {
    pub value: *mut c_char,
    pub accepted: bool,
}

pub type VeloxCustomProtocolHandler = Option<
    unsafe extern "C" fn(
        request: *const VeloxCustomProtocolRequest,
        response: *mut VeloxCustomProtocolResponse,
        user_data: *mut c_void,
    ) -> bool,
>;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxCustomProtocolDefinition {
    pub scheme: *const c_char,
    pub handler: VeloxCustomProtocolHandler,
    pub user_data: *mut c_void,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxCustomProtocolList {
    pub protocols: *const VeloxCustomProtocolDefinition,
    pub count: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxCustomProtocolHeader {
    pub name: *const c_char,
    pub value: *const c_char,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxCustomProtocolHeaderList {
    pub headers: *const VeloxCustomProtocolHeader,
    pub count: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxCustomProtocolBuffer {
    pub ptr: *const u8,
    pub len: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxCustomProtocolRequest {
    pub url: *const c_char,
    pub method: *const c_char,
    pub headers: VeloxCustomProtocolHeaderList,
    pub body: VeloxCustomProtocolBuffer,
    pub webview_id: *const c_char,
}

pub type VeloxCustomProtocolResponseFree = Option<unsafe extern "C" fn(user_data: *mut c_void)>;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct VeloxCustomProtocolResponse {
    pub status: u16,
    pub headers: VeloxCustomProtocolHeaderList,
    pub body: VeloxCustomProtocolBuffer,
    pub mime_type: *const c_char,
    pub free: VeloxCustomProtocolResponseFree,
    pub user_data: *mut c_void,
}

#[repr(C)]
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum VeloxUserAttentionType {
    Informational = 0,
    Critical = 1,
}

#[repr(C)]
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum VeloxResizeDirection {
    East = 0,
    North = 1,
    NorthEast = 2,
    NorthWest = 3,
    South = 4,
    SouthEast = 5,
    SouthWest = 6,
    West = 7,
}

pub type VeloxEventLoopCallback = Option<
    extern "C" fn(
        event_description: *const c_char,
        user_data: *mut c_void,
    ) -> VeloxEventLoopControlFlow,
>;

fn cached_cstring(storage: &OnceLock<CString>, builder: impl FnOnce() -> String) -> *const c_char {
    storage
        .get_or_init(|| CString::new(builder()).expect("ffi string contains null byte"))
        .as_ptr()
}

fn opt_cstring(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        None
    } else {
        unsafe { CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_owned()) }
    }
}

fn opt_color(color: *const VeloxColor) -> Option<(u8, u8, u8, u8)> {
    if color.is_null() {
        None
    } else {
        let color = unsafe { &*color };
        Some((color.red, color.green, color.blue, color.alpha))
    }
}

fn theme_from_ffi(theme: VeloxWindowTheme) -> Option<Theme> {
    match theme {
        VeloxWindowTheme::Unspecified => None,
        VeloxWindowTheme::Light => Some(Theme::Light),
        VeloxWindowTheme::Dark => Some(Theme::Dark),
    }
}

fn dialog_apply_filters(mut dialog: FileDialog, filters: &[VeloxDialogFilter]) -> FileDialog {
    const EMPTY_EXTS: [&str; 0] = [];
    for filter in filters {
        let Some(label) = opt_cstring(filter.label) else {
            continue;
        };

        if filter.extension_count == 0 || filter.extensions.is_null() {
            dialog = dialog.add_filter(&label, &EMPTY_EXTS);
            continue;
        }

        let raw_exts =
            unsafe { std::slice::from_raw_parts(filter.extensions, filter.extension_count) };
        let mut owned_exts = Vec::with_capacity(raw_exts.len());
        for &ext_ptr in raw_exts {
            if ext_ptr.is_null() {
                continue;
            }
            if let Some(ext) = opt_cstring(ext_ptr) {
                owned_exts.push(ext);
            }
        }
        let ext_refs: Vec<&str> = owned_exts.iter().map(|s| s.as_str()).collect();
        dialog = dialog.add_filter(&label, &ext_refs);
    }
    dialog
}

fn dialog_selection_from_paths(paths: Vec<std::path::PathBuf>) -> VeloxDialogSelection {
    if paths.is_empty() {
        return VeloxDialogSelection::default();
    }

    let mut raw_paths: Vec<*mut c_char> = Vec::with_capacity(paths.len());
    for path in paths {
        let display = path.to_string_lossy().into_owned();
        match CString::new(display) {
            Ok(cstr) => raw_paths.push(cstr.into_raw()),
            Err(_) => continue,
        }
    }

    if raw_paths.is_empty() {
        return VeloxDialogSelection::default();
    }

    let count = raw_paths.len();
    let boxed = raw_paths.into_boxed_slice();
    let ptr = Box::into_raw(boxed) as *mut *mut c_char;
    VeloxDialogSelection { paths: ptr, count }
}

fn message_level_from_ffi(level: VeloxMessageDialogLevel) -> MessageLevel {
    match level {
        VeloxMessageDialogLevel::Info => MessageLevel::Info,
        VeloxMessageDialogLevel::Warning => MessageLevel::Warning,
        VeloxMessageDialogLevel::Error => MessageLevel::Error,
    }
}

fn prompt_result_from_string(value: Option<String>) -> VeloxPromptDialogResult {
    if let Some(value) = value {
        if let Ok(cstr) = CString::new(value) {
            let ptr = cstr.into_raw();
            VeloxPromptDialogResult {
                value: ptr,
                accepted: true,
            }
        } else {
            VeloxPromptDialogResult::default()
        }
    } else {
        VeloxPromptDialogResult::default()
    }
}

#[no_mangle]
pub extern "C" fn velox_dialog_open(
    options: *const VeloxDialogOpenOptions,
) -> VeloxDialogSelection {
    guard_panic_value(|| {
        let Some(options) = (unsafe { options.as_ref() }) else {
            return VeloxDialogSelection::default();
        };

        let mut dialog = FileDialog::new();
        if let Some(title) = opt_cstring(options.title) {
            dialog = dialog.set_title(&title);
        }
        if let Some(path) = opt_cstring(options.default_path) {
            dialog = dialog.set_directory(std::path::Path::new(&path));
        }

        if options.filter_count > 0 && !options.filters.is_null() && !options.allow_directories {
            let filters =
                unsafe { std::slice::from_raw_parts(options.filters, options.filter_count) };
            dialog = dialog_apply_filters(dialog, filters);
        }

        let selection_paths = if options.allow_directories {
            if options.allow_multiple {
                dialog.pick_folders().unwrap_or_default()
            } else {
                dialog.pick_folder().into_iter().collect()
            }
        } else if options.allow_multiple {
            dialog.pick_files().unwrap_or_default()
        } else {
            dialog.pick_file().into_iter().collect()
        };

        dialog_selection_from_paths(selection_paths)
    })
}

#[no_mangle]
pub extern "C" fn velox_dialog_save(
    options: *const VeloxDialogSaveOptions,
) -> VeloxDialogSelection {
    guard_panic_value(|| {
        let Some(options) = (unsafe { options.as_ref() }) else {
            return VeloxDialogSelection::default();
        };

        let mut dialog = FileDialog::new();
        if let Some(title) = opt_cstring(options.title) {
            dialog = dialog.set_title(&title);
        }
        if let Some(path) = opt_cstring(options.default_path) {
            dialog = dialog.set_directory(std::path::Path::new(&path));
        }
        if let Some(name) = opt_cstring(options.default_name) {
            dialog = dialog.set_file_name(&name);
        }

        if options.filter_count > 0 && !options.filters.is_null() {
            let filters =
                unsafe { std::slice::from_raw_parts(options.filters, options.filter_count) };
            dialog = dialog_apply_filters(dialog, filters);
        }

        let selection_paths = dialog.save_file().into_iter().collect();
        dialog_selection_from_paths(selection_paths)
    })
}

#[no_mangle]
pub extern "C" fn velox_dialog_selection_free(selection: VeloxDialogSelection) {
    if selection.count == 0 || selection.paths.is_null() {
        return;
    }

    unsafe {
        let slice = std::slice::from_raw_parts_mut(selection.paths, selection.count);
        let boxed = Box::from_raw(slice as *mut [*mut c_char]);
        for &ptr in boxed.iter() {
            if !ptr.is_null() {
                drop(CString::from_raw(ptr));
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn velox_dialog_message(options: *const VeloxMessageDialogOptions) -> bool {
    guard_panic_bool(|| {
        let Some(options) = (unsafe { options.as_ref() }) else {
            return false;
        };

        let mut dialog = MessageDialog::new();
        if let Some(title) = opt_cstring(options.title) {
            dialog = dialog.set_title(&title);
        }
        let message = opt_cstring(options.message).unwrap_or_default();
        dialog = dialog.set_description(&message);

        dialog = dialog.set_level(message_level_from_ffi(options.level));

        let ok_label = opt_cstring(options.ok_label);
        let cancel_label = opt_cstring(options.cancel_label);
        let yes_label = opt_cstring(options.yes_label);
        let no_label = opt_cstring(options.no_label);

        dialog = match options.buttons {
            VeloxMessageDialogButtons::Ok => {
                if let Some(label) = ok_label {
                    dialog.set_buttons(MessageButtons::OkCustom(label))
                } else {
                    dialog.set_buttons(MessageButtons::Ok)
                }
            }
            VeloxMessageDialogButtons::OkCancel => {
                if let (Some(ok), Some(cancel)) = (ok_label.clone(), cancel_label.clone()) {
                    dialog.set_buttons(MessageButtons::OkCancelCustom(ok, cancel))
                } else {
                    dialog.set_buttons(MessageButtons::OkCancel)
                }
            }
            VeloxMessageDialogButtons::YesNo => dialog.set_buttons(MessageButtons::YesNo),
            VeloxMessageDialogButtons::YesNoCancel => {
                if let (Some(yes), Some(no), Some(cancel)) =
                    (yes_label.clone(), no_label.clone(), cancel_label)
                {
                    dialog.set_buttons(MessageButtons::YesNoCancelCustom(yes, no, cancel))
                } else {
                    dialog.set_buttons(MessageButtons::YesNoCancel)
                }
            }
        };

        match dialog.show() {
            MessageDialogResult::Ok | MessageDialogResult::Yes => true,
            MessageDialogResult::Cancel
            | MessageDialogResult::No
            | MessageDialogResult::Custom(_) => false,
        }
    })
}

#[no_mangle]
pub extern "C" fn velox_dialog_confirm(options: *const VeloxConfirmDialogOptions) -> bool {
    guard_panic_bool(|| {
        let Some(options) = (unsafe { options.as_ref() }) else {
            return false;
        };

        let mut dialog = MessageDialog::new();
        if let Some(title) = opt_cstring(options.title) {
            dialog = dialog.set_title(&title);
        }
        let message = opt_cstring(options.message).unwrap_or_default();
        dialog = dialog.set_description(&message);
        dialog = dialog.set_level(message_level_from_ffi(options.level));

        let ok_label = opt_cstring(options.ok_label);
        let cancel_label = opt_cstring(options.cancel_label);
        let positive_label = ok_label.clone();

        dialog = if let (Some(ref ok), Some(ref cancel)) = (&ok_label, &cancel_label) {
            dialog.set_buttons(MessageButtons::OkCancelCustom(ok.clone(), cancel.clone()))
        } else {
            dialog.set_buttons(MessageButtons::OkCancel)
        };

        match dialog.show() {
            MessageDialogResult::Ok => true,
            MessageDialogResult::Custom(choice) => positive_label
                .map(|expected| choice == expected)
                .unwrap_or(false),
            MessageDialogResult::Yes => true,
            _ => false,
        }
    })
}

#[no_mangle]
pub extern "C" fn velox_dialog_ask(options: *const VeloxAskDialogOptions) -> bool {
    guard_panic_bool(|| {
        let Some(options) = (unsafe { options.as_ref() }) else {
            return false;
        };

        let mut dialog = MessageDialog::new();
        if let Some(title) = opt_cstring(options.title) {
            dialog = dialog.set_title(&title);
        }
        let message = opt_cstring(options.message).unwrap_or_default();
        dialog = dialog.set_description(&message);
        dialog = dialog.set_level(message_level_from_ffi(options.level));

        let yes_label = opt_cstring(options.yes_label);
        let no_label = opt_cstring(options.no_label);
        let positive_label = yes_label.clone();

        dialog = if let (Some(ref yes), Some(ref no)) = (&yes_label, &no_label) {
            dialog.set_buttons(MessageButtons::OkCancelCustom(yes.clone(), no.clone()))
        } else {
            dialog.set_buttons(MessageButtons::YesNo)
        };

        match dialog.show() {
            MessageDialogResult::Yes => true,
            MessageDialogResult::Ok => true,
            MessageDialogResult::Custom(choice) => positive_label
                .map(|expected| choice == expected)
                .unwrap_or(false),
            _ => false,
        }
    })
}

#[no_mangle]
pub extern "C" fn velox_dialog_prompt(
    options: *const VeloxPromptDialogOptions,
) -> VeloxPromptDialogResult {
    guard_panic_value(|| {
        let Some(options) = (unsafe { options.as_ref() }) else {
            return VeloxPromptDialogResult::default();
        };

        let title = opt_cstring(options.title).unwrap_or_default();
        let message = opt_cstring(options.message).unwrap_or_default();
        if message.is_empty() {
            return VeloxPromptDialogResult::default();
        }

        let default_value = opt_cstring(options.default_value);
        let placeholder = opt_cstring(options.placeholder);
        let default_text = default_value.or(placeholder).unwrap_or_default();
        let title_ref = if title.is_empty() {
            "Prompt"
        } else {
            title.as_str()
        };

        let input = tinyfiledialogs::input_box(title_ref, &message, default_text.as_str());
        prompt_result_from_string(input)
    })
}

#[no_mangle]
pub extern "C" fn velox_dialog_prompt_result_free(result: VeloxPromptDialogResult) {
    if !result.value.is_null() {
        unsafe {
            drop(CString::from_raw(result.value));
        }
    }
}

#[cfg(target_os = "macos")]
fn activation_policy_from_ffi(policy: VeloxActivationPolicy) -> ActivationPolicy {
    match policy {
        VeloxActivationPolicy::Regular => ActivationPolicy::Regular,
        VeloxActivationPolicy::Accessory => ActivationPolicy::Accessory,
        VeloxActivationPolicy::Prohibited => ActivationPolicy::Prohibited,
    }
}

fn monitor_to_json(monitor: &MonitorHandle) -> serde_json::Value {
    let name = monitor.name().unwrap_or_default();
    let position = monitor.position();
    let size = monitor.size();
    json!({
        "name": name,
        "scale_factor": monitor.scale_factor(),
        "position": {
            "x": position.x,
            "y": position.y,
        },
        "size": {
            "width": size.width,
            "height": size.height,
        }
    })
}

fn write_json_to_buffer(
    buffer: &'static LocalKey<RefCell<CString>>,
    value: serde_json::Value,
) -> *const c_char {
    let json_string = value.to_string();
    buffer.with(|cell| {
        let mut storage = cell.borrow_mut();
        *storage =
            CString::new(json_string).unwrap_or_else(|_| CString::new("{}").expect("static JSON"));
        storage.as_ptr()
    })
}

fn write_string_to_buffer(
    buffer: &'static LocalKey<RefCell<CString>>,
    value: String,
) -> *const c_char {
    buffer.with(|cell| {
        let mut storage = cell.borrow_mut();
        *storage = CString::new(value).unwrap_or_else(|_| CString::new("").expect("empty string"));
        storage.as_ptr()
    })
}

#[cfg(target_os = "macos")]
fn guard_panic<T>(f: impl FnOnce() -> *mut T) -> *mut T {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(ptr) => ptr,
        Err(_) => ptr::null_mut(),
    }
}

fn guard_panic_bool(f: impl FnOnce() -> bool) -> bool {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(result) => result,
        Err(_) => false,
    }
}

fn guard_panic_value<T: Default>(f: impl FnOnce() -> T) -> T {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(value) => value,
        Err(_) => T::default(),
    }
}

#[cfg(all(target_os = "macos", feature = "local-dev"))]
#[no_mangle]
pub extern "C" fn velox_app_state_force_launched() {
    tao::platform::macos::force_app_state_launched_for_testing();
}

#[cfg(all(target_os = "macos", not(feature = "local-dev")))]
#[no_mangle]
pub extern "C" fn velox_app_state_force_launched() {
    // No-op when using crates.io tao (velox-testing feature not available)
}

fn with_window<R>(window: *mut VeloxWindowHandle, f: impl FnOnce(&Window) -> R) -> Option<R> {
    unsafe { window.as_ref() }.map(|handle| f(&handle.window))
}

fn with_webview<R>(webview: *mut VeloxWebviewHandle, f: impl FnOnce(&WebView) -> R) -> Option<R> {
    unsafe { webview.as_ref() }.map(|handle| f(&handle.webview))
}

fn tao_user_attention_from_ffi(kind: VeloxUserAttentionType) -> TaoUserAttentionType {
    match kind {
        VeloxUserAttentionType::Informational => TaoUserAttentionType::Informational,
        VeloxUserAttentionType::Critical => TaoUserAttentionType::Critical,
    }
}

fn tao_resize_direction_from_ffi(direction: VeloxResizeDirection) -> TaoResizeDirection {
    match direction {
        VeloxResizeDirection::East => TaoResizeDirection::East,
        VeloxResizeDirection::North => TaoResizeDirection::North,
        VeloxResizeDirection::NorthEast => TaoResizeDirection::NorthEast,
        VeloxResizeDirection::NorthWest => TaoResizeDirection::NorthWest,
        VeloxResizeDirection::South => TaoResizeDirection::South,
        VeloxResizeDirection::SouthEast => TaoResizeDirection::SouthEast,
        VeloxResizeDirection::SouthWest => TaoResizeDirection::SouthWest,
        VeloxResizeDirection::West => TaoResizeDirection::West,
    }
}

#[no_mangle]
pub extern "C" fn velox_runtime_wry_library_name() -> *const c_char {
    cached_cstring(&LIBRARY_NAME, || "VeloxRuntimeWry".to_string())
}

#[no_mangle]
pub extern "C" fn velox_runtime_wry_crate_version() -> *const c_char {
    cached_cstring(&RUNTIME_VERSION, || env!("CARGO_PKG_VERSION").to_string())
}

#[no_mangle]
pub extern "C" fn velox_runtime_wry_webview_version() -> *const c_char {
    cached_cstring(&WEBVIEW_VERSION, || {
        wry::webview_version().unwrap_or_default()
    })
}

#[no_mangle]
pub extern "C" fn velox_event_loop_new() -> *mut VeloxEventLoop {
    let event_loop = EventLoopBuilder::<VeloxUserEvent>::with_user_event().build();

    #[cfg(target_os = "macos")]
    {
        let proxy = event_loop.create_proxy();
        MenuEvent::set_event_handler(Some(move |event: MenuEvent| {
            let _ = proxy.send_event(VeloxUserEvent::Menu(event.id().as_ref().to_string()));
        }));

        let tray_proxy = event_loop.create_proxy();
        TrayIconEvent::set_event_handler(Some(move |event: TrayIconEvent| {
            let _ = tray_proxy.send_event(VeloxUserEvent::Tray(event.into()));
        }));
    }

    Box::into_raw(Box::new(VeloxEventLoop { event_loop }))
}

#[no_mangle]
pub extern "C" fn velox_event_loop_free(event_loop: *mut VeloxEventLoop) {
    if !event_loop.is_null() {
        unsafe { drop(Box::from_raw(event_loop)) };
        #[cfg(target_os = "macos")]
        MenuEvent::set_event_handler::<fn(MenuEvent)>(None);
        #[cfg(target_os = "macos")]
        TrayIconEvent::set_event_handler::<fn(TrayIconEvent)>(None);
    }
}

#[no_mangle]
pub extern "C" fn velox_event_loop_create_proxy(
    event_loop: *mut VeloxEventLoop,
) -> *mut VeloxEventLoopProxyHandle {
    if event_loop.is_null() {
        return ptr::null_mut();
    }

    #[cfg(all(target_os = "macos", feature = "local-dev"))]
    tao::platform::macos::force_app_state_launched_for_testing();

    let event_loop = unsafe { &mut *event_loop };
    let proxy = event_loop.event_loop.create_proxy();
    Box::into_raw(Box::new(VeloxEventLoopProxyHandle { proxy }))
}

#[no_mangle]
pub extern "C" fn velox_event_loop_proxy_request_exit(
    proxy: *mut VeloxEventLoopProxyHandle,
) -> bool {
    if proxy.is_null() {
        return false;
    }

    let proxy = unsafe { &mut *proxy };
    proxy.proxy.send_event(VeloxUserEvent::Exit).is_ok()
}

#[no_mangle]
pub extern "C" fn velox_event_loop_proxy_send_user_event(
    proxy: *mut VeloxEventLoopProxyHandle,
    payload: *const c_char,
) -> bool {
    if proxy.is_null() {
        return false;
    }

    let proxy = unsafe { &mut *proxy };
    let message = opt_cstring(payload).unwrap_or_default();
    proxy
        .proxy
        .send_event(VeloxUserEvent::Custom(message))
        .is_ok()
}

#[no_mangle]
pub extern "C" fn velox_event_loop_proxy_free(proxy: *mut VeloxEventLoopProxyHandle) {
    if !proxy.is_null() {
        unsafe { drop(Box::from_raw(proxy)) };
    }
}

#[no_mangle]
pub extern "C" fn velox_event_loop_set_activation_policy(
    event_loop: *mut VeloxEventLoop,
    policy: VeloxActivationPolicy,
) -> bool {
    #[cfg(target_os = "macos")]
    {
        if event_loop.is_null() {
            return false;
        }

        let event_loop = unsafe { &mut *event_loop };
        event_loop
            .event_loop
            .set_activation_policy_at_runtime(activation_policy_from_ffi(policy));
        true
    }

    #[cfg(not(target_os = "macos"))]
    {
        let _ = (event_loop, policy);
        false
    }
}

#[no_mangle]
pub extern "C" fn velox_event_loop_set_dock_visibility(
    event_loop: *mut VeloxEventLoop,
    visible: bool,
) -> bool {
    #[cfg(target_os = "macos")]
    {
        if event_loop.is_null() {
            return false;
        }

        let event_loop = unsafe { &mut *event_loop };
        event_loop.event_loop.set_dock_visibility(visible);
        true
    }

    #[cfg(not(target_os = "macos"))]
    {
        let _ = (event_loop, visible);
        false
    }
}

#[no_mangle]
pub extern "C" fn velox_event_loop_hide_application(event_loop: *mut VeloxEventLoop) -> bool {
    #[cfg(target_os = "macos")]
    {
        if event_loop.is_null() {
            return false;
        }

        let event_loop = unsafe { &mut *event_loop };
        event_loop.event_loop.hide_application();
        true
    }

    #[cfg(not(target_os = "macos"))]
    {
        let _ = event_loop;
        false
    }
}

#[no_mangle]
pub extern "C" fn velox_event_loop_show_application(event_loop: *mut VeloxEventLoop) -> bool {
    #[cfg(target_os = "macos")]
    {
        if event_loop.is_null() {
            return false;
        }

        let event_loop = unsafe { &mut *event_loop };
        event_loop.event_loop.show_application();
        true
    }

    #[cfg(not(target_os = "macos"))]
    {
        let _ = event_loop;
        false
    }
}

#[cfg(target_os = "macos")]
fn accelerator_from_ptr(ptr: *const c_char) -> Option<Accelerator> {
    opt_cstring(ptr)?.parse().ok()
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_menu_bar_new() -> *mut VeloxMenuBarHandle {
    guard_panic(|| {
        let menu = Menu::new();
        let identifier = CString::new(menu.id().as_ref()).expect("menu id contains null byte");
        Box::into_raw(Box::new(VeloxMenuBarHandle {
            menu,
            submenus: Vec::new(),
            identifier,
        }))
    })
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_menu_bar_new_with_id(id: *const c_char) -> *mut VeloxMenuBarHandle {
    guard_panic(|| {
        let identifier_string = opt_cstring(id).unwrap_or_default();
        let menu = Menu::with_id(MenuId::new(identifier_string.clone()));
        let identifier = CString::new(identifier_string).expect("menu id contains null byte");
        Box::into_raw(Box::new(VeloxMenuBarHandle {
            menu,
            submenus: Vec::new(),
            identifier,
        }))
    })
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_menu_bar_free(menu: *mut VeloxMenuBarHandle) {
    if !menu.is_null() {
        unsafe { drop(Box::from_raw(menu)) };
    }
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_menu_bar_identifier(menu: *mut VeloxMenuBarHandle) -> *const c_char {
    let Some(menu) = (unsafe { menu.as_ref() }) else {
        return ptr::null();
    };
    menu.identifier.as_ptr()
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_menu_bar_append_submenu(
    menu: *mut VeloxMenuBarHandle,
    submenu: *mut VeloxSubmenuHandle,
) -> bool {
    let Some(menu) = (unsafe { menu.as_mut() }) else {
        return false;
    };
    let Some(submenu) = (unsafe { submenu.as_ref() }) else {
        return false;
    };

    let result = {
        let submenu_ref = submenu.submenu.borrow();
        menu.menu.append(&*submenu_ref)
    };

    if result.is_ok() {
        menu.submenus.push(submenu.submenu.clone());
        true
    } else {
        false
    }
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_menu_bar_set_app_menu(menu: *mut VeloxMenuBarHandle) -> bool {
    let Some(menu) = (unsafe { menu.as_ref() }) else {
        return false;
    };
    menu.menu.init_for_nsapp();
    true
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_submenu_new(
    title: *const c_char,
    enabled: bool,
) -> *mut VeloxSubmenuHandle {
    guard_panic(|| {
        let title = opt_cstring(title).unwrap_or_default();
        let submenu = Submenu::new(title, enabled);
        let identifier =
            CString::new(submenu.id().as_ref()).expect("submenu id contains null byte");
        Box::into_raw(Box::new(VeloxSubmenuHandle {
            submenu: Rc::new(RefCell::new(submenu)),
            identifier,
            items: Vec::new(),
        }))
    })
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_submenu_new_with_id(
    id: *const c_char,
    title: *const c_char,
    enabled: bool,
) -> *mut VeloxSubmenuHandle {
    guard_panic(|| {
        let title = opt_cstring(title).unwrap_or_default();
        let id_string = opt_cstring(id).unwrap_or_default();
        let submenu = Submenu::with_id(MenuId::new(id_string.clone()), title, enabled);
        let identifier = CString::new(id_string).expect("submenu id contains null byte");
        Box::into_raw(Box::new(VeloxSubmenuHandle {
            submenu: Rc::new(RefCell::new(submenu)),
            identifier,
            items: Vec::new(),
        }))
    })
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_submenu_free(submenu: *mut VeloxSubmenuHandle) {
    if !submenu.is_null() {
        unsafe { drop(Box::from_raw(submenu)) };
    }
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_submenu_identifier(submenu: *mut VeloxSubmenuHandle) -> *const c_char {
    let Some(submenu) = (unsafe { submenu.as_ref() }) else {
        return ptr::null();
    };
    submenu.identifier.as_ptr()
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_submenu_append_item(
    submenu: *mut VeloxSubmenuHandle,
    item: *mut VeloxMenuItemHandle,
) -> bool {
    let Some(submenu) = (unsafe { submenu.as_mut() }) else {
        return false;
    };
    let Some(item) = (unsafe { item.as_ref() }) else {
        return false;
    };

    if submenu.submenu.borrow().append(&item.item).is_ok() {
        submenu.items.push(item.item.clone());
        true
    } else {
        false
    }
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_menu_item_new(
    id: *const c_char,
    title: *const c_char,
    enabled: bool,
    accelerator: *const c_char,
) -> *mut VeloxMenuItemHandle {
    guard_panic(|| {
        let title = opt_cstring(title).unwrap_or_default();
        let accelerator = accelerator_from_ptr(accelerator);
        let item = if let Some(id) = opt_cstring(id) {
            MenuItem::with_id(MenuId::new(id.clone()), title, enabled, accelerator)
        } else {
            MenuItem::new(title, enabled, accelerator)
        };
        let identifier = CString::new(item.id().as_ref()).expect("menu item id contains null byte");
        Box::into_raw(Box::new(VeloxMenuItemHandle { item, identifier }))
    })
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_menu_item_free(item: *mut VeloxMenuItemHandle) {
    if !item.is_null() {
        unsafe { drop(Box::from_raw(item)) };
    }
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_menu_item_set_enabled(
    item: *mut VeloxMenuItemHandle,
    enabled: bool,
) -> bool {
    let Some(item) = (unsafe { item.as_mut() }) else {
        return false;
    };
    item.item.set_enabled(enabled);
    true
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_menu_item_is_enabled(item: *mut VeloxMenuItemHandle) -> bool {
    guard_panic_bool(|| {
        let Some(item) = (unsafe { item.as_ref() }) else {
            return false;
        };
        item.item.is_enabled()
    })
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_menu_item_text(item: *mut VeloxMenuItemHandle) -> *const c_char {
    guard_panic_value(|| {
        let Some(item) = (unsafe { item.as_ref() }) else {
            return ptr::null();
        };
        write_string_to_buffer(&TITLE_BUFFER, item.item.text())
    })
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_menu_item_set_text(
    item: *mut VeloxMenuItemHandle,
    title: *const c_char,
) -> bool {
    guard_panic_bool(|| {
        let Some(item) = (unsafe { item.as_mut() }) else {
            return false;
        };
        let text = opt_cstring(title).unwrap_or_default();
        item.item.set_text(text);
        true
    })
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_menu_item_set_accelerator(
    item: *mut VeloxMenuItemHandle,
    accelerator: *const c_char,
) -> bool {
    guard_panic_bool(|| {
        let Some(item) = (unsafe { item.as_mut() }) else {
            return false;
        };
        item.item
            .set_accelerator(accelerator_from_ptr(accelerator))
            .is_ok()
    })
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_menu_item_identifier(item: *mut VeloxMenuItemHandle) -> *const c_char {
    let Some(item) = (unsafe { item.as_ref() }) else {
        return ptr::null();
    };
    item.identifier.as_ptr()
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_tray_new(config: *const VeloxTrayConfig) -> *mut VeloxTrayHandle {
    guard_panic(|| {
        let cfg = unsafe { config.as_ref() }.copied().unwrap_or_default();
        let identifier = opt_cstring(cfg.identifier);
        let title = opt_cstring(cfg.title);
        let tooltip = opt_cstring(cfg.tooltip);

        let mut builder = TrayIconBuilder::new();
        if let Some(ref id) = identifier {
            builder = builder.with_id(id.clone());
        }
        if let Some(ref title) = title {
            builder = builder.with_title(title.clone());
        }
        if let Some(ref tooltip) = tooltip {
            builder = builder.with_tooltip(tooltip.clone());
        }
        builder = builder.with_menu_on_left_click(cfg.show_menu_on_left_click);

        let tray = match builder.build() {
            Ok(tray) => tray,
            Err(_) => return ptr::null_mut(),
        };

        if !cfg.visible {
            let _ = tray.set_visible(false);
        }

        tray.set_show_menu_on_left_click(cfg.show_menu_on_left_click);

        let identifier = CString::new(tray.id().as_ref())
            .unwrap_or_else(|_| CString::new("velox-tray").expect("static string has no nulls"));

        Box::into_raw(Box::new(VeloxTrayHandle {
            tray,
            menu: None,
            identifier,
        }))
    })
}

#[cfg(not(target_os = "macos"))]
#[no_mangle]
pub extern "C" fn velox_tray_new(_config: *const VeloxTrayConfig) -> *mut VeloxTrayHandle {
    ptr::null_mut()
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_tray_free(tray: *mut VeloxTrayHandle) {
    if !tray.is_null() {
        unsafe { drop(Box::from_raw(tray)) };
    }
}

#[cfg(not(target_os = "macos"))]
#[no_mangle]
pub extern "C" fn velox_tray_free(_tray: *mut VeloxTrayHandle) {}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_tray_identifier(tray: *mut VeloxTrayHandle) -> *const c_char {
    let Some(tray) = (unsafe { tray.as_ref() }) else {
        return ptr::null();
    };
    tray.identifier.as_ptr()
}

#[cfg(not(target_os = "macos"))]
#[no_mangle]
pub extern "C" fn velox_tray_identifier(_tray: *mut VeloxTrayHandle) -> *const c_char {
    ptr::null()
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_tray_set_title(tray: *mut VeloxTrayHandle, title: *const c_char) -> bool {
    let Some(tray) = (unsafe { tray.as_mut() }) else {
        return false;
    };
    let result_title = opt_cstring(title);
    tray.tray.set_title(result_title.as_deref());
    true
}

#[cfg(not(target_os = "macos"))]
#[no_mangle]
pub extern "C" fn velox_tray_set_title(_tray: *mut VeloxTrayHandle, _title: *const c_char) -> bool {
    false
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_tray_set_tooltip(
    tray: *mut VeloxTrayHandle,
    tooltip: *const c_char,
) -> bool {
    let Some(tray) = (unsafe { tray.as_mut() }) else {
        return false;
    };
    let tooltip = opt_cstring(tooltip);
    tray.tray.set_tooltip(tooltip.as_deref()).is_ok()
}

#[cfg(not(target_os = "macos"))]
#[no_mangle]
pub extern "C" fn velox_tray_set_tooltip(
    _tray: *mut VeloxTrayHandle,
    _tooltip: *const c_char,
) -> bool {
    false
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_tray_set_visible(tray: *mut VeloxTrayHandle, visible: bool) -> bool {
    let Some(tray) = (unsafe { tray.as_mut() }) else {
        return false;
    };
    tray.tray.set_visible(visible).is_ok()
}

#[cfg(not(target_os = "macos"))]
#[no_mangle]
pub extern "C" fn velox_tray_set_visible(_tray: *mut VeloxTrayHandle, _visible: bool) -> bool {
    false
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_tray_set_show_menu_on_left_click(
    tray: *mut VeloxTrayHandle,
    enable: bool,
) -> bool {
    let Some(tray) = (unsafe { tray.as_mut() }) else {
        return false;
    };
    tray.tray.set_show_menu_on_left_click(enable);
    true
}

#[cfg(not(target_os = "macos"))]
#[no_mangle]
pub extern "C" fn velox_tray_set_show_menu_on_left_click(
    _tray: *mut VeloxTrayHandle,
    _enable: bool,
) -> bool {
    false
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub extern "C" fn velox_tray_set_menu(
    tray: *mut VeloxTrayHandle,
    menu: *mut VeloxMenuBarHandle,
) -> bool {
    let Some(tray) = (unsafe { tray.as_mut() }) else {
        return false;
    };

    if menu.is_null() {
        tray.tray
            .set_menu(None::<Box<dyn tray_icon::menu::ContextMenu>>);
        tray.menu = None;
        return true;
    }

    let Some(menu_handle) = (unsafe { menu.as_ref() }) else {
        return false;
    };

    let cloned_menu = menu_handle.menu.clone();
    tray.tray.set_menu(Some(
        Box::new(cloned_menu.clone()) as Box<dyn tray_icon::menu::ContextMenu>
    ));
    tray.menu = Some(cloned_menu);
    true
}

#[cfg(not(target_os = "macos"))]
#[no_mangle]
pub extern "C" fn velox_tray_set_menu(
    _tray: *mut VeloxTrayHandle,
    _menu: *mut VeloxMenuBarHandle,
) -> bool {
    false
}

#[no_mangle]
pub extern "C" fn velox_event_loop_pump(
    event_loop: *mut VeloxEventLoop,
    callback: VeloxEventLoopCallback,
    user_data: *mut c_void,
) {
    if event_loop.is_null() {
        return;
    }

    let event_loop = unsafe { &mut *event_loop };
    event_loop
        .event_loop
        .run_return(|event, _target, control_flow| {
            if let Some(cb) = callback {
                let description = serialize_event(&event);
                if let Ok(c_description) = CString::new(description) {
                    let desired_flow = cb(c_description.as_ptr(), user_data);
                    match desired_flow {
                        VeloxEventLoopControlFlow::Poll => *control_flow = ControlFlow::Poll,
                        VeloxEventLoopControlFlow::Wait => *control_flow = ControlFlow::Wait,
                        VeloxEventLoopControlFlow::Exit => *control_flow = ControlFlow::Exit,
                    }
                } else {
                    *control_flow = ControlFlow::Exit;
                }
            } else {
                *control_flow = ControlFlow::Exit;
            }

            if matches!(event, Event::UserEvent(VeloxUserEvent::Exit)) {
                *control_flow = ControlFlow::Exit;
            }

            if matches!(event, Event::LoopDestroyed) {
                *control_flow = ControlFlow::Exit;
            }
        });
}

#[no_mangle]
pub extern "C" fn velox_window_build(
    event_loop: *mut VeloxEventLoop,
    config: *const VeloxWindowConfig,
) -> *mut VeloxWindowHandle {
    if event_loop.is_null() {
        return ptr::null_mut();
    }

    let event_loop = unsafe { &mut *event_loop };
    let cfg = unsafe { config.as_ref().copied().unwrap_or_default() };

    let build_result = catch_unwind(AssertUnwindSafe(|| {
        let mut result = None;
        let mut built = false;
        event_loop
            .event_loop
            .run_return(|event, target, control_flow| {
                // Build window on first event (Init, Poll, or any NewEvents)
                // Init only fires once per event loop lifetime, so we can't rely on it
                // for creating multiple windows
                if !built {
                    if let Event::NewEvents(_) = event {
                        built = true;
                        let mut builder = TaoWindowBuilder::new();

                        if let Some(title) = opt_cstring(cfg.title) {
                            builder = builder.with_title(title);
                        }

                        if cfg.width > 0 && cfg.height > 0 {
                            builder = builder
                                .with_inner_size(LogicalSize::new(cfg.width as f64, cfg.height as f64));
                        }

                        result = Some(builder.build(target));
                        *control_flow = ControlFlow::Exit;
                        return;
                    }
                }

                *control_flow = ControlFlow::Exit;
            });

        result
    }));

    match build_result {
        Ok(Some(Ok(window))) => {
            let id_string = format!("{:?}", window.id());
            let identifier = CString::new(id_string).unwrap_or_else(|_| {
                CString::new("velox-window").expect("static string has no nulls")
            });
            Box::into_raw(Box::new(VeloxWindowHandle { window, identifier }))
        }
        _ => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn velox_window_free(window: *mut VeloxWindowHandle) {
    if !window.is_null() {
        unsafe { drop(Box::from_raw(window)) };
    }
}

#[no_mangle]
pub extern "C" fn velox_window_identifier(window: *mut VeloxWindowHandle) -> *const c_char {
    if window.is_null() {
        return ptr::null();
    }

    unsafe { &*window }.identifier.as_ptr()
}

#[no_mangle]
pub extern "C" fn velox_window_set_title(
    window: *mut VeloxWindowHandle,
    title: *const c_char,
) -> bool {
    let Some(title) = opt_cstring(title) else {
        return false;
    };
    with_window(window, |w| {
        w.set_title(&title);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_fullscreen(
    window: *mut VeloxWindowHandle,
    fullscreen: bool,
) -> bool {
    with_window(window, |w| {
        if fullscreen {
            w.set_fullscreen(Some(Fullscreen::Borderless(None)));
        } else {
            w.set_fullscreen(None);
        }
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_decorations(
    window: *mut VeloxWindowHandle,
    decorations: bool,
) -> bool {
    with_window(window, |w| {
        w.set_decorations(decorations);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_always_on_bottom(
    window: *mut VeloxWindowHandle,
    on_bottom: bool,
) -> bool {
    with_window(window, |w| {
        w.set_always_on_bottom(on_bottom);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_visible_on_all_workspaces(
    window: *mut VeloxWindowHandle,
    visible_on_all_workspaces: bool,
) -> bool {
    with_window(window, |w| {
        w.set_visible_on_all_workspaces(visible_on_all_workspaces);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_content_protected(
    window: *mut VeloxWindowHandle,
    protected: bool,
) -> bool {
    with_window(window, |w| {
        w.set_content_protection(protected);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_resizable(
    window: *mut VeloxWindowHandle,
    resizable: bool,
) -> bool {
    with_window(window, |w| {
        w.set_resizable(resizable);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_always_on_top(
    window: *mut VeloxWindowHandle,
    on_top: bool,
) -> bool {
    with_window(window, |w| {
        w.set_always_on_top(on_top);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_visible(window: *mut VeloxWindowHandle, visible: bool) -> bool {
    with_window(window, |w| {
        let _ = w.set_visible(visible);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_maximized(
    window: *mut VeloxWindowHandle,
    maximized: bool,
) -> bool {
    with_window(window, |w| {
        w.set_maximized(maximized);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_minimized(
    window: *mut VeloxWindowHandle,
    minimized: bool,
) -> bool {
    with_window(window, |w| {
        w.set_minimized(minimized);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_skip_taskbar(
    window: *mut VeloxWindowHandle,
    skip: bool,
) -> bool {
    with_window(window, |w| {
        #[cfg(target_os = "windows")]
        {
            use tao::platform::windows::WindowExtWindows;
            return w.set_skip_taskbar(skip).is_ok();
        }

        #[cfg(any(
            target_os = "linux",
            target_os = "dragonfly",
            target_os = "freebsd",
            target_os = "netbsd",
            target_os = "openbsd"
        ))]
        {
            use tao::platform::unix::WindowExtUnix;
            return w.set_skip_taskbar(skip).is_ok();
        }

        #[cfg(not(any(
            target_os = "windows",
            target_os = "linux",
            target_os = "dragonfly",
            target_os = "freebsd",
            target_os = "netbsd",
            target_os = "openbsd"
        )))]
        {
            let _ = (w, skip);
            return false;
        }
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_minimizable(
    window: *mut VeloxWindowHandle,
    minimizable: bool,
) -> bool {
    with_window(window, |w| {
        w.set_minimizable(minimizable);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_maximizable(
    window: *mut VeloxWindowHandle,
    maximizable: bool,
) -> bool {
    with_window(window, |w| {
        w.set_maximizable(maximizable);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_closable(
    window: *mut VeloxWindowHandle,
    closable: bool,
) -> bool {
    with_window(window, |w| {
        w.set_closable(closable);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_background_color(
    window: *mut VeloxWindowHandle,
    color: *const VeloxColor,
) -> bool {
    let color = opt_color(color);
    with_window(window, |w| {
        w.set_background_color(color);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_is_maximized(window: *mut VeloxWindowHandle) -> bool {
    with_window(window, |w| w.is_maximized()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_is_minimized(window: *mut VeloxWindowHandle) -> bool {
    with_window(window, |w| w.is_minimized()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_is_visible(window: *mut VeloxWindowHandle) -> bool {
    with_window(window, |w| w.is_visible()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_is_resizable(window: *mut VeloxWindowHandle) -> bool {
    with_window(window, |w| w.is_resizable()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_is_decorated(window: *mut VeloxWindowHandle) -> bool {
    with_window(window, |w| w.is_decorated()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_is_always_on_top(window: *mut VeloxWindowHandle) -> bool {
    with_window(window, |w| w.is_always_on_top()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_is_minimizable(window: *mut VeloxWindowHandle) -> bool {
    with_window(window, |w| w.is_minimizable()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_is_maximizable(window: *mut VeloxWindowHandle) -> bool {
    with_window(window, |w| w.is_maximizable()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_is_closable(window: *mut VeloxWindowHandle) -> bool {
    with_window(window, |w| w.is_closable()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_scale_factor(
    window: *mut VeloxWindowHandle,
    scale_factor: *mut f64,
) -> bool {
    if scale_factor.is_null() {
        return false;
    }

    with_window(window, |w| {
        unsafe {
            *scale_factor = w.scale_factor();
        }
        true
    })
    .unwrap_or(false)
}

fn write_position(target: *mut VeloxPoint, position: LogicalPosition<f64>) {
    unsafe {
        (*target).x = position.x;
        (*target).y = position.y;
    }
}

fn write_size(target: *mut VeloxSize, size: LogicalSize<f64>) {
    unsafe {
        (*target).width = size.width;
        (*target).height = size.height;
    }
}

#[no_mangle]
pub extern "C" fn velox_window_inner_position(
    window: *mut VeloxWindowHandle,
    position: *mut VeloxPoint,
) -> bool {
    if position.is_null() {
        return false;
    }

    with_window(window, |w| match w.inner_position() {
        Ok(pos) => {
            write_position(position, pos.to_logical(w.scale_factor()));
            true
        }
        Err(_) => false,
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_outer_position(
    window: *mut VeloxWindowHandle,
    position: *mut VeloxPoint,
) -> bool {
    if position.is_null() {
        return false;
    }

    with_window(window, |w| match w.outer_position() {
        Ok(pos) => {
            write_position(position, pos.to_logical(w.scale_factor()));
            true
        }
        Err(_) => false,
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_inner_size(
    window: *mut VeloxWindowHandle,
    size: *mut VeloxSize,
) -> bool {
    if size.is_null() {
        return false;
    }

    with_window(window, |w| {
        let inner = w.inner_size().to_logical::<f64>(w.scale_factor());
        write_size(size, inner);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_outer_size(
    window: *mut VeloxWindowHandle,
    size: *mut VeloxSize,
) -> bool {
    if size.is_null() {
        return false;
    }

    with_window(window, |w| {
        let outer = w.outer_size().to_logical::<f64>(w.scale_factor());
        write_size(size, outer);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_title(window: *mut VeloxWindowHandle) -> *const c_char {
    with_window(window, |w| {
        let title = w.title();
        write_string_to_buffer(&TITLE_BUFFER, title)
    })
    .unwrap_or(ptr::null())
}

#[no_mangle]
pub extern "C" fn velox_window_is_fullscreen(window: *mut VeloxWindowHandle) -> bool {
    with_window(window, |w| w.fullscreen().is_some()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_is_focused(window: *mut VeloxWindowHandle) -> bool {
    with_window(window, |w| w.is_focused()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_cursor_position(
    window: *mut VeloxWindowHandle,
    point: *mut VeloxPoint,
) -> bool {
    if point.is_null() {
        return false;
    }

    with_window(window, |w| match w.cursor_position() {
        Ok(position) => {
            unsafe {
                (*point).x = position.x;
                (*point).y = position.y;
            }
            true
        }
        Err(_) => false,
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_current_monitor(window: *mut VeloxWindowHandle) -> *const c_char {
    with_window(window, |w| {
        if let Some(monitor) = w.current_monitor() {
            write_json_to_buffer(&MONITOR_BUFFER, monitor_to_json(&monitor))
        } else {
            ptr::null()
        }
    })
    .unwrap_or(ptr::null())
}

#[no_mangle]
pub extern "C" fn velox_window_primary_monitor(window: *mut VeloxWindowHandle) -> *const c_char {
    with_window(window, |w| {
        if let Some(monitor) = w.primary_monitor() {
            write_json_to_buffer(&MONITOR_BUFFER, monitor_to_json(&monitor))
        } else {
            ptr::null()
        }
    })
    .unwrap_or(ptr::null())
}

#[no_mangle]
pub extern "C" fn velox_window_available_monitors(window: *mut VeloxWindowHandle) -> *const c_char {
    with_window(window, |w| {
        let monitors: Vec<_> = w
            .available_monitors()
            .map(|monitor| monitor_to_json(&monitor))
            .collect();
        write_json_to_buffer(&MONITOR_LIST_BUFFER, serde_json::Value::Array(monitors))
    })
    .unwrap_or(ptr::null())
}

#[no_mangle]
pub extern "C" fn velox_window_monitor_from_point(
    window: *mut VeloxWindowHandle,
    point: VeloxPoint,
) -> *const c_char {
    with_window(window, |w| {
        if let Some(monitor) = w.monitor_from_point(point.x, point.y) {
            write_json_to_buffer(&MONITOR_BUFFER, monitor_to_json(&monitor))
        } else {
            ptr::null()
        }
    })
    .unwrap_or(ptr::null())
}

#[no_mangle]
pub extern "C" fn velox_window_set_theme(
    window: *mut VeloxWindowHandle,
    theme: VeloxWindowTheme,
) -> bool {
    let theme = theme_from_ffi(theme);
    with_window(window, |w| {
        w.set_theme(theme);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_focus(window: *mut VeloxWindowHandle) -> bool {
    with_window(window, |w| {
        w.set_focus();
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_focusable(
    window: *mut VeloxWindowHandle,
    focusable: bool,
) -> bool {
    with_window(window, |w| {
        w.set_focusable(focusable);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_request_redraw(window: *mut VeloxWindowHandle) -> bool {
    with_window(window, |w| {
        w.request_redraw();
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_size(
    window: *mut VeloxWindowHandle,
    width: f64,
    height: f64,
) -> bool {
    with_window(window, |w| {
        w.set_inner_size(LogicalSize::new(width, height));
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_position(
    window: *mut VeloxWindowHandle,
    x: f64,
    y: f64,
) -> bool {
    with_window(window, |w| {
        w.set_outer_position(LogicalPosition::new(x, y));
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_min_size(
    window: *mut VeloxWindowHandle,
    width: f64,
    height: f64,
) -> bool {
    with_window(window, |w| {
        let size: Option<Size> = if width > 0.0 && height > 0.0 {
            Some(Size::Logical(LogicalSize::new(width, height)))
        } else {
            None
        };
        w.set_min_inner_size(size);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_max_size(
    window: *mut VeloxWindowHandle,
    width: f64,
    height: f64,
) -> bool {
    with_window(window, |w| {
        let size: Option<Size> = if width > 0.0 && height > 0.0 {
            Some(Size::Logical(LogicalSize::new(width, height)))
        } else {
            None
        };
        w.set_max_inner_size(size);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_request_user_attention(
    window: *mut VeloxWindowHandle,
    attention_type: VeloxUserAttentionType,
) -> bool {
    let attention = tao_user_attention_from_ffi(attention_type);
    with_window(window, |w| {
        w.request_user_attention(Some(attention));
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_clear_user_attention(window: *mut VeloxWindowHandle) -> bool {
    with_window(window, |w| {
        w.request_user_attention(None);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_cursor_grab(window: *mut VeloxWindowHandle, grab: bool) -> bool {
    with_window(window, |w| w.set_cursor_grab(grab).is_ok()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_cursor_visible(
    window: *mut VeloxWindowHandle,
    visible: bool,
) -> bool {
    with_window(window, |w| {
        w.set_cursor_visible(visible);
        true
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_cursor_position(
    window: *mut VeloxWindowHandle,
    x: f64,
    y: f64,
) -> bool {
    with_window(window, |w| {
        w.set_cursor_position(LogicalPosition::new(x, y)).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_ignore_cursor_events(
    window: *mut VeloxWindowHandle,
    ignore: bool,
) -> bool {
    with_window(window, |w| w.set_ignore_cursor_events(ignore).is_ok()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_start_dragging(window: *mut VeloxWindowHandle) -> bool {
    with_window(window, |w| w.drag_window().is_ok()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_start_resize_dragging(
    window: *mut VeloxWindowHandle,
    direction: VeloxResizeDirection,
) -> bool {
    let tao_direction = tao_resize_direction_from_ffi(direction);
    with_window(window, |w| w.drag_resize_window(tao_direction).is_ok()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_webview_build(
    window: *mut VeloxWindowHandle,
    config: *const VeloxWebviewConfig,
) -> *mut VeloxWebviewHandle {
    if window.is_null() {
        return ptr::null_mut();
    }

    let cfg = unsafe { config.as_ref().copied().unwrap_or_default() };
    let url = opt_cstring(cfg.url);

    let ffi_protocols: Vec<(
        String,
        unsafe extern "C" fn(
            *const VeloxCustomProtocolRequest,
            *mut VeloxCustomProtocolResponse,
            *mut c_void,
        ) -> bool,
        *mut c_void,
    )> = if cfg.custom_protocols.count > 0 && !cfg.custom_protocols.protocols.is_null() {
        unsafe {
            std::slice::from_raw_parts(cfg.custom_protocols.protocols, cfg.custom_protocols.count)
        }
        .iter()
        .filter_map(|definition| {
            let handler = definition.handler?;
            let scheme = opt_cstring(definition.scheme)?;
            Some((scheme, handler, definition.user_data))
        })
        .collect()
    } else {
        Vec::new()
    };

    with_window(window, |w| {
        let mut builder = WebViewBuilder::new();

        if let Some(url) = url.as_ref() {
            builder = builder.with_url(url.clone());
        }

        for (scheme, handler, user_data) in ffi_protocols.iter().cloned() {
            builder = builder.with_asynchronous_custom_protocol(
                scheme.clone(),
                move |webview_id, request, responder| {
                    let (parts, body_vec) = request.into_parts();
                    let uri_string = parts.uri.to_string();
                    let method_string = parts.method.as_str().to_string();
                    let headers_map = parts.headers;

                    let url_cstring = match CString::new(uri_string) {
                        Ok(value) => value,
                        Err(_) => {
                            let _ = responder.respond(
                                WryHttpResponse::builder()
                                    .status(StatusCode::BAD_REQUEST)
                                    .body(Vec::new())
                                    .unwrap(),
                            );
                            return;
                        }
                    };

                    let method_cstring = match CString::new(method_string) {
                        Ok(value) => value,
                        Err(_) => {
                            let _ = responder.respond(
                                WryHttpResponse::builder()
                                    .status(StatusCode::BAD_REQUEST)
                                    .body(Vec::new())
                                    .unwrap(),
                            );
                            return;
                        }
                    };

                    let webview_id_string = format!("{webview_id:?}");
                    let webview_id_cstring = CString::new(webview_id_string)
                        .unwrap_or_else(|_| CString::new("").expect("empty string"));

                    let mut header_storage: Vec<CString> = Vec::new();
                    let mut header_pairs: Vec<VeloxCustomProtocolHeader> = Vec::new();
                    for (name, value) in headers_map.iter() {
                        let name_str = name.as_str();
                        let value_str = match value.to_str() {
                            Ok(v) => v,
                            Err(_) => continue,
                        };

                        let Ok(name_cstring) = CString::new(name_str) else {
                            continue;
                        };
                        let Ok(value_cstring) = CString::new(value_str) else {
                            continue;
                        };

                        header_pairs.push(VeloxCustomProtocolHeader {
                            name: name_cstring.as_ptr(),
                            value: value_cstring.as_ptr(),
                        });
                        header_storage.push(name_cstring);
                        header_storage.push(value_cstring);
                    }

                    let headers_list = VeloxCustomProtocolHeaderList {
                        headers: if header_pairs.is_empty() {
                            ptr::null()
                        } else {
                            header_pairs.as_ptr()
                        },
                        count: header_pairs.len(),
                    };

                    let body_buffer = VeloxCustomProtocolBuffer {
                        ptr: body_vec.as_ptr(),
                        len: body_vec.len(),
                    };

                    let ffi_request = VeloxCustomProtocolRequest {
                        url: url_cstring.as_ptr(),
                        method: method_cstring.as_ptr(),
                        headers: headers_list,
                        body: body_buffer,
                        webview_id: webview_id_cstring.as_ptr(),
                    };

                    let mut ffi_response = VeloxCustomProtocolResponse::default();
                    let handled = match catch_unwind(AssertUnwindSafe(|| unsafe {
                        handler(&ffi_request, &mut ffi_response, user_data)
                    })) {
                        Ok(result) => result,
                        Err(_) => false,
                    };

                    if !handled {
                        let _ = responder.respond(
                            WryHttpResponse::builder()
                                .status(StatusCode::NOT_FOUND)
                                .body(Vec::new())
                                .unwrap(),
                        );
                        return;
                    }

                    let status = if ffi_response.status == 0 {
                        StatusCode::OK
                    } else {
                        StatusCode::from_u16(ffi_response.status).unwrap_or(StatusCode::OK)
                    };

                    let mut builder = WryHttpResponse::builder().status(status);

                    if !ffi_response.mime_type.is_null() {
                        if let Ok(mime) = unsafe { CStr::from_ptr(ffi_response.mime_type) }.to_str()
                        {
                            if let Ok(value) = HeaderValue::from_str(mime) {
                                builder = builder.header(CONTENT_TYPE, value);
                            }
                        }
                    }

                    if ffi_response.headers.count > 0 && !ffi_response.headers.headers.is_null() {
                        let header_slice = unsafe {
                            std::slice::from_raw_parts(
                                ffi_response.headers.headers,
                                ffi_response.headers.count,
                            )
                        };
                        for header in header_slice {
                            if header.name.is_null() || header.value.is_null() {
                                continue;
                            }
                            let Ok(name_str) = unsafe { CStr::from_ptr(header.name) }.to_str()
                            else {
                                continue;
                            };
                            let Ok(value_str) = unsafe { CStr::from_ptr(header.value) }.to_str()
                            else {
                                continue;
                            };
                            let Ok(name) = HeaderName::from_bytes(name_str.as_bytes()) else {
                                continue;
                            };
                            let Ok(value) = HeaderValue::from_str(value_str) else {
                                continue;
                            };
                            builder = builder.header(name, value);
                        }
                    }

                    let body = if ffi_response.body.len > 0 && !ffi_response.body.ptr.is_null() {
                        unsafe {
                            std::slice::from_raw_parts(ffi_response.body.ptr, ffi_response.body.len)
                        }
                        .to_vec()
                    } else {
                        Vec::new()
                    };

                    let response = builder.body(body).unwrap_or_else(|_| {
                        WryHttpResponse::builder()
                            .status(StatusCode::INTERNAL_SERVER_ERROR)
                            .body(Vec::new())
                            .unwrap()
                    });

                    let _ = responder.respond(response);

                    if let Some(free) = ffi_response.free {
                        unsafe { free(ffi_response.user_data) };
                    }
                },
            );
        }

        // Build as child webview if requested, otherwise as full-window webview
        if cfg.is_child {
            let bounds = Rect {
                position: LogicalPosition::new(cfg.x, cfg.y).into(),
                size: LogicalSize::new(cfg.width, cfg.height).into(),
            };
            builder = builder.with_bounds(bounds);
            builder
                .build_as_child(w)
                .ok()
                .map(|webview| Box::into_raw(Box::new(VeloxWebviewHandle { webview })))
        } else {
            builder
                .build(w)
                .ok()
                .map(|webview| Box::into_raw(Box::new(VeloxWebviewHandle { webview })))
        }
    })
    .flatten()
    .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn velox_webview_free(webview: *mut VeloxWebviewHandle) {
    if !webview.is_null() {
        unsafe { drop(Box::from_raw(webview)) };
    }
}

#[no_mangle]
pub extern "C" fn velox_webview_navigate(
    webview: *mut VeloxWebviewHandle,
    url: *const c_char,
) -> bool {
    let Some(url_str) = opt_cstring(url) else {
        return false;
    };
    let Ok(parsed_url) = Url::parse(&url_str) else {
        return false;
    };
    with_webview(webview, |view| view.load_url(parsed_url.as_str()).is_ok()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_webview_reload(webview: *mut VeloxWebviewHandle) -> bool {
    with_webview(webview, |view| view.reload().is_ok()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_webview_evaluate_script(
    webview: *mut VeloxWebviewHandle,
    script: *const c_char,
) -> bool {
    let Some(script) = opt_cstring(script) else {
        return false;
    };
    with_webview(webview, |view| view.evaluate_script(&script).is_ok()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_webview_set_zoom(
    webview: *mut VeloxWebviewHandle,
    scale_factor: f64,
) -> bool {
    with_webview(webview, |view| view.zoom(scale_factor).is_ok()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_webview_show(webview: *mut VeloxWebviewHandle) -> bool {
    with_webview(webview, |view| view.set_visible(true).is_ok()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_webview_hide(webview: *mut VeloxWebviewHandle) -> bool {
    with_webview(webview, |view| view.set_visible(false).is_ok()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_webview_clear_browsing_data(webview: *mut VeloxWebviewHandle) -> bool {
    with_webview(webview, |view| view.clear_all_browsing_data().is_ok()).unwrap_or(false)
}

/// Set the bounds of a child webview
#[no_mangle]
pub extern "C" fn velox_webview_set_bounds(
    webview: *mut VeloxWebviewHandle,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
) -> bool {
    with_webview(webview, |view| {
        let bounds = Rect {
            position: LogicalPosition::new(x, y).into(),
            size: LogicalSize::new(width, height).into(),
        };
        view.set_bounds(bounds).is_ok()
    })
    .unwrap_or(false)
}

#[derive(Serialize)]
struct EventPosition {
    x: f64,
    y: f64,
}

#[derive(Serialize)]
struct EventSize {
    width: f64,
    height: f64,
}

#[derive(Serialize)]
struct EventModifiers {
    shift: bool,
    control: bool,
    alt: bool,
    super_key: bool,
}

fn modifiers_payload(modifiers: ModifiersState) -> EventModifiers {
    EventModifiers {
        shift: modifiers.shift_key(),
        control: modifiers.control_key(),
        alt: modifiers.alt_key(),
        super_key: modifiers.super_key(),
    }
}

fn serialize_event(event: &Event<VeloxUserEvent>) -> String {
    let value = match event {
        Event::NewEvents(cause) => json!({
            "type": "new-events",
            "cause": format!("{:?}", cause),
        }),
        Event::MainEventsCleared => json!({ "type": "main-events-cleared" }),
        Event::RedrawEventsCleared => json!({ "type": "redraw-events-cleared" }),
        Event::LoopDestroyed => json!({ "type": "loop-destroyed" }),
        Event::Suspended => json!({ "type": "suspended" }),
        Event::Resumed => json!({ "type": "resumed" }),
        Event::RedrawRequested(window_id) => json!({
            "type": "window-redraw-requested",
            "window_id": format!("{window_id:?}"),
        }),
        Event::UserEvent(VeloxUserEvent::Exit) => json!({ "type": "user-exit" }),
        Event::UserEvent(VeloxUserEvent::Custom(payload)) => json!({
            "type": "user-event",
            "payload": payload,
        }),
        #[cfg(target_os = "macos")]
        Event::UserEvent(VeloxUserEvent::Menu(menu_id)) => json!({
            "type": "menu-event",
            "menu_id": menu_id,
        }),
        #[cfg(target_os = "macos")]
        Event::UserEvent(VeloxUserEvent::Tray(event)) => {
            let mut payload = Map::new();
            payload.insert("type".into(), json!("tray-event"));
            payload.insert("tray_id".into(), json!(event.identifier));
            payload.insert(
                "event_type".into(),
                json!(match event.kind {
                    VeloxTrayEventKind::Click => "click",
                    VeloxTrayEventKind::DoubleClick => "double-click",
                    VeloxTrayEventKind::Enter => "enter",
                    VeloxTrayEventKind::Move => "move",
                    VeloxTrayEventKind::Leave => "leave",
                }),
            );
            if let Some((x, y)) = event.position {
                payload.insert("position".into(), json!({"x": x, "y": y}));
            }
            if let Some(rect) = event.rect {
                payload.insert(
                    "rect".into(),
                    json!({
                        "x": rect.origin_x,
                        "y": rect.origin_y,
                        "width": rect.width,
                        "height": rect.height,
                    }),
                );
            }
            if let Some(button) = &event.button {
                payload.insert("button".into(), json!(button));
            }
            if let Some(state) = &event.button_state {
                payload.insert("button_state".into(), json!(state));
            }
            serde_json::Value::Object(payload)
        }
        Event::DeviceEvent {
            device_id, event, ..
        } => json!({
            "type": "device-event",
            "device_id": format!("{device_id:?}"),
            "event": format!("{:?}", event),
        }),
        Event::Opened { urls } => json!({
            "type": "opened",
            "urls": urls.iter().map(|u| u.to_string()).collect::<Vec<_>>(),
        }),
        Event::Reopen {
            has_visible_windows,
            ..
        } => json!({
            "type": "reopen",
            "has_visible_windows": has_visible_windows,
        }),
        Event::WindowEvent {
            window_id, event, ..
        } => match event {
            TaoWindowEvent::CloseRequested => json!({
                "type": "window-close-requested",
                "window_id": format!("{window_id:?}"),
            }),
            TaoWindowEvent::Destroyed => json!({
                "type": "window-destroyed",
                "window_id": format!("{window_id:?}"),
            }),
            TaoWindowEvent::Resized(size) => json!({
                "type": "window-resized",
                "window_id": format!("{window_id:?}"),
                "size": EventSize {
                    width: size.width as f64,
                    height: size.height as f64,
                },
            }),
            TaoWindowEvent::Moved(position) => json!({
                "type": "window-moved",
                "window_id": format!("{window_id:?}"),
                "position": EventPosition {
                    x: position.x as f64,
                    y: position.y as f64,
                },
            }),
            TaoWindowEvent::Focused(focused) => json!({
                "type": "window-focused",
                "window_id": format!("{window_id:?}"),
                "isFocused": focused,
            }),
            TaoWindowEvent::ScaleFactorChanged {
                scale_factor,
                new_inner_size,
            } => json!({
                "type": "window-scale-factor-changed",
                "window_id": format!("{window_id:?}"),
                "scale_factor": scale_factor,
                "size": EventSize {
                    width: new_inner_size.width as f64,
                    height: new_inner_size.height as f64,
                },
            }),
            TaoWindowEvent::KeyboardInput {
                event: key_event,
                is_synthetic,
                ..
            } => json!({
                "type": "window-keyboard-input",
                "window_id": format!("{window_id:?}"),
                "state": format!("{:?}", key_event.state),
                "logical_key": format!("{:?}", key_event.logical_key),
                "physical_key": format!("{:?}", key_event.physical_key),
                "text": key_event.text.map(|s| s.to_string()),
                "repeat": key_event.repeat,
                "location": format!("{:?}", key_event.location),
                "is_synthetic": is_synthetic,
            }),
            TaoWindowEvent::ReceivedImeText(text) => json!({
                "type": "window-ime-text",
                "window_id": format!("{window_id:?}"),
                "text": text,
            }),
            TaoWindowEvent::ModifiersChanged(modifiers) => json!({
                "type": "window-modifiers-changed",
                "window_id": format!("{window_id:?}"),
                "modifiers": modifiers_payload(*modifiers),
            }),
            TaoWindowEvent::CursorMoved { position, .. } => json!({
                "type": "window-cursor-moved",
                "window_id": format!("{window_id:?}"),
                "position": EventPosition {
                    x: position.x,
                    y: position.y,
                },
            }),
            TaoWindowEvent::CursorEntered { device_id } => json!({
                "type": "window-cursor-entered",
                "window_id": format!("{window_id:?}"),
                "device_id": format!("{device_id:?}"),
            }),
            TaoWindowEvent::CursorLeft { device_id } => json!({
                "type": "window-cursor-left",
                "window_id": format!("{window_id:?}"),
                "device_id": format!("{device_id:?}"),
            }),
            TaoWindowEvent::MouseInput { state, button, .. } => {
                let state_str = match state {
                    ElementState::Pressed => "pressed",
                    ElementState::Released => "released",
                    _ => "unknown",
                };

                let button_str = match button {
                    MouseButton::Left => "left".to_string(),
                    MouseButton::Right => "right".to_string(),
                    MouseButton::Middle => "middle".to_string(),
                    MouseButton::Other(value) => format!("other:{value}"),
                    _ => "unknown".to_string(),
                };

                json!({
                    "type": "window-mouse-input",
                    "window_id": format!("{window_id:?}"),
                    "state": state_str,
                    "button": button_str,
                })
            }
            TaoWindowEvent::MouseWheel { delta, phase, .. } => {
                let delta_value = match delta {
                    MouseScrollDelta::LineDelta(x, y) => json!({
                        "unit": "line",
                        "x": x,
                        "y": y,
                    }),
                    MouseScrollDelta::PixelDelta(position) => json!({
                        "unit": "pixel",
                        "x": position.x,
                        "y": position.y,
                    }),
                    _ => json!({
                        "unit": "unknown",
                    }),
                };

                json!({
                    "type": "window-mouse-wheel",
                    "window_id": format!("{window_id:?}"),
                    "delta": delta_value,
                    "phase": format!("{:?}", phase),
                })
            }
            TaoWindowEvent::DroppedFile(path) => json!({
                "type": "window-dropped-file",
                "window_id": format!("{window_id:?}"),
                "path": path.to_string_lossy(),
            }),
            TaoWindowEvent::HoveredFile(path) => json!({
                "type": "window-hovered-file",
                "window_id": format!("{window_id:?}"),
                "path": path.to_string_lossy(),
            }),
            TaoWindowEvent::HoveredFileCancelled => json!({
                "type": "window-hovered-file-cancelled",
                "window_id": format!("{window_id:?}"),
            }),
            TaoWindowEvent::ThemeChanged(theme) => json!({
                "type": "window-theme-changed",
                "window_id": format!("{window_id:?}"),
                "theme": format!("{:?}", theme),
            }),
            other => json!({
                "type": "window-event",
                "window_id": format!("{window_id:?}"),
                "kind": format!("{:?}", other),
            }),
        },
        other => json!({
            "type": "raw",
            "debug": format!("{other:?}"),
        }),
    };

    serde_json::to_string(&value).unwrap_or_else(|_| "{}".into())
}
