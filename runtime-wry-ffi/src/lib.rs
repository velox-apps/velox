use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::sync::{
    atomic::{AtomicU32, Ordering},
    OnceLock,
};

use tao::{
    dpi::{LogicalPosition, LogicalSize, Size},
    event::{
        ElementState, Event, MouseButton, MouseScrollDelta, StartCause,
        WindowEvent as TaoWindowEvent,
    },
    event_loop::{ControlFlow, EventLoop, EventLoopBuilder, EventLoopProxy},
    keyboard::ModifiersState,
    platform::run_return::EventLoopExtRunReturn,
    window::{
        Fullscreen, ResizeDirection as TaoResizeDirection,
        UserAttentionType as TaoUserAttentionType, Window, WindowBuilder as TaoWindowBuilder,
    },
};
use wry::{WebView, WebViewBuilder};

use serde::Serialize;
use serde_json::json;
use tauri_runtime::{
    dpi::{
        LogicalPosition as RuntimeLogicalPosition, LogicalSize as RuntimeLogicalSize,
        Position as RuntimePosition, Size as RuntimeSize,
    },
    webview::{PendingWebview, WebviewAttributes},
    window::{PendingWindow, RawWindow, WindowBuilder, WindowId},
    ExitRequestedEventAction, ResizeDirection, RunEvent, Runtime, RuntimeHandle, RuntimeInitArgs,
    UserAttentionType,
};
use tauri_runtime::{WebviewDispatch, WindowDispatch};
use tauri_runtime_wry::{WindowBuilderWrapper, Wry, WryWebviewDispatcher, WryWindowDispatcher};
use tauri_utils::config::WebviewUrl;
use url::Url;

static LIBRARY_NAME: OnceLock<CString> = OnceLock::new();
static RUNTIME_VERSION: OnceLock<CString> = OnceLock::new();
static WEBVIEW_VERSION: OnceLock<CString> = OnceLock::new();
static NEXT_RUNTIME_WINDOW_LABEL: AtomicU32 = AtomicU32::new(0);
static NEXT_RUNTIME_WEBVIEW_LABEL: AtomicU32 = AtomicU32::new(0);

fn next_runtime_window_label() -> String {
    let id = NEXT_RUNTIME_WINDOW_LABEL.fetch_add(1, Ordering::SeqCst);
    format!("velox-runtime-window-{id}")
}

fn next_runtime_webview_label() -> String {
    let id = NEXT_RUNTIME_WEBVIEW_LABEL.fetch_add(1, Ordering::SeqCst);
    format!("velox-runtime-webview-{id}")
}

fn noop_raw_window<'a>(_: RawWindow<'a>) {}

#[derive(Debug, Clone)]
enum VeloxUserEvent {
    Exit,
}

pub struct VeloxEventLoop {
    event_loop: EventLoop<VeloxUserEvent>,
}

pub struct VeloxEventLoopProxyHandle {
    proxy: EventLoopProxy<VeloxUserEvent>,
}

enum WindowHandleInner {
    Direct(Window),
    Dispatcher {
        dispatcher: WryWindowDispatcher<VeloxUserEvent>,
        _id: WindowId,
    },
}

enum WebviewHandleInner {
    Direct(WebView),
    Dispatcher(WryWebviewDispatcher<VeloxUserEvent>),
}

pub struct VeloxWindowHandle {
    inner: WindowHandleInner,
}

pub struct VeloxWebviewHandle {
    inner: WebviewHandleInner,
}

pub struct VeloxRuntime {
    runtime: Wry<VeloxUserEvent>,
}

#[repr(C)]
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum VeloxControlFlow {
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
    extern "C" fn(event_description: *const c_char, user_data: *mut c_void) -> VeloxControlFlow,
>;

pub type VeloxRuntimeCallback =
    Option<extern "C" fn(event_description: *const c_char, user_data: *mut c_void)>;

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

fn with_runtime<R>(
    runtime: *mut VeloxRuntime,
    f: impl FnOnce(&mut Wry<VeloxUserEvent>) -> R,
) -> Option<R> {
    if runtime.is_null() {
        None
    } else {
        let runtime = unsafe { &mut *runtime };
        Some(f(&mut runtime.runtime))
    }
}

fn with_window<R>(window: *mut VeloxWindowHandle, f: impl FnOnce(&Window) -> R) -> Option<R> {
    unsafe { window.as_ref() }.and_then(|handle| match &handle.inner {
        WindowHandleInner::Direct(window) => Some(f(window)),
        _ => None,
    })
}

fn with_webview<R>(webview: *mut VeloxWebviewHandle, f: impl FnOnce(&WebView) -> R) -> Option<R> {
    unsafe { webview.as_ref() }.and_then(|handle| match &handle.inner {
        WebviewHandleInner::Direct(webview) => Some(f(webview)),
        _ => None,
    })
}

fn with_window_dispatcher<R>(
    window: *mut VeloxWindowHandle,
    f: impl FnOnce(&mut WryWindowDispatcher<VeloxUserEvent>) -> R,
) -> Option<R> {
    unsafe { window.as_mut() }.and_then(|handle| match &mut handle.inner {
        WindowHandleInner::Dispatcher { dispatcher, .. } => Some(f(dispatcher)),
        _ => None,
    })
}

fn with_webview_dispatcher<R>(
    webview: *mut VeloxWebviewHandle,
    f: impl FnOnce(&mut WryWebviewDispatcher<VeloxUserEvent>) -> R,
) -> Option<R> {
    unsafe { webview.as_mut() }.and_then(|handle| match &mut handle.inner {
        WebviewHandleInner::Dispatcher(dispatcher) => Some(f(dispatcher)),
        _ => None,
    })
}

fn runtime_user_attention_from_ffi(kind: VeloxUserAttentionType) -> UserAttentionType {
    match kind {
        VeloxUserAttentionType::Informational => UserAttentionType::Informational,
        VeloxUserAttentionType::Critical => UserAttentionType::Critical,
    }
}

fn tao_user_attention_from_ffi(kind: VeloxUserAttentionType) -> TaoUserAttentionType {
    match kind {
        VeloxUserAttentionType::Informational => TaoUserAttentionType::Informational,
        VeloxUserAttentionType::Critical => TaoUserAttentionType::Critical,
    }
}

fn runtime_resize_direction_from_ffi(direction: VeloxResizeDirection) -> ResizeDirection {
    match direction {
        VeloxResizeDirection::East => ResizeDirection::East,
        VeloxResizeDirection::North => ResizeDirection::North,
        VeloxResizeDirection::NorthEast => ResizeDirection::NorthEast,
        VeloxResizeDirection::NorthWest => ResizeDirection::NorthWest,
        VeloxResizeDirection::South => ResizeDirection::South,
        VeloxResizeDirection::SouthEast => ResizeDirection::SouthEast,
        VeloxResizeDirection::SouthWest => ResizeDirection::SouthWest,
        VeloxResizeDirection::West => ResizeDirection::West,
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
        tauri_runtime_wry::webview_version().unwrap_or_default()
    })
}

#[no_mangle]
pub extern "C" fn velox_event_loop_new() -> *mut VeloxEventLoop {
    Box::into_raw(Box::new(VeloxEventLoop {
        event_loop: EventLoopBuilder::<VeloxUserEvent>::with_user_event().build(),
    }))
}

#[no_mangle]
pub extern "C" fn velox_event_loop_free(event_loop: *mut VeloxEventLoop) {
    if !event_loop.is_null() {
        unsafe { drop(Box::from_raw(event_loop)) };
    }
}

#[no_mangle]
pub extern "C" fn velox_event_loop_create_proxy(
    event_loop: *mut VeloxEventLoop,
) -> *mut VeloxEventLoopProxyHandle {
    if event_loop.is_null() {
        return std::ptr::null_mut();
    }

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
pub extern "C" fn velox_event_loop_proxy_free(proxy: *mut VeloxEventLoopProxyHandle) {
    if !proxy.is_null() {
        unsafe { drop(Box::from_raw(proxy)) };
    }
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
                        VeloxControlFlow::Poll => *control_flow = ControlFlow::Poll,
                        VeloxControlFlow::Wait => *control_flow = ControlFlow::Wait,
                        VeloxControlFlow::Exit => *control_flow = ControlFlow::Exit,
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
                "focused": focused,
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

fn serialize_run_event(event: &RunEvent<VeloxUserEvent>) -> String {
    let value = match event {
        RunEvent::Ready => json!({ "type": "ready" }),
        RunEvent::Exit => json!({ "type": "exit" }),
        RunEvent::ExitRequested { code, tx } => {
            let _ = tx.send(ExitRequestedEventAction::Prevent);
            json!({ "type": "exit-requested", "code": code })
        }
        RunEvent::WindowEvent { label, event } => json!({
            "type": "window-event",
            "label": label,
            "event": format!("{:?}", event),
        }),
        RunEvent::WebviewEvent { label, event } => json!({
            "type": "webview-event",
            "label": label,
            "event": format!("{:?}", event),
        }),
        RunEvent::MainEventsCleared => json!({ "type": "main-events-cleared" }),
        RunEvent::Resumed => json!({ "type": "resumed" }),
        RunEvent::UserEvent(evt) => json!({
            "type": "user-event",
            "event": format!("{:?}", evt),
        }),
        #[cfg(any(target_os = "macos", target_os = "ios"))]
        RunEvent::Opened { urls } => json!({
            "type": "opened",
            "urls": urls.iter().map(|u| u.to_string()).collect::<Vec<_>>(),
        }),
        #[cfg(target_os = "macos")]
        RunEvent::Reopen {
            has_visible_windows,
        } => json!({
            "type": "reopen",
            "has_visible_windows": has_visible_windows,
        }),
        _ => json!({
            "type": "run-event",
            "debug": format!("{:?}", event),
        }),
    };

    serde_json::to_string(&value).unwrap_or_else(|_| "{}".into())
}

#[no_mangle]
pub extern "C" fn velox_window_build(
    event_loop: *mut VeloxEventLoop,
    config: *const VeloxWindowConfig,
) -> *mut VeloxWindowHandle {
    if event_loop.is_null() {
        return std::ptr::null_mut();
    }

    let event_loop = unsafe { &mut *event_loop };
    let cfg = unsafe { config.as_ref().copied().unwrap_or_default() };

    let mut result = None;
    event_loop
        .event_loop
        .run_return(|event, target, control_flow| {
            if let Event::NewEvents(StartCause::Init) = event {
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

            *control_flow = ControlFlow::Exit;
        });

    match result {
        Some(Ok(window)) => Box::into_raw(Box::new(VeloxWindowHandle {
            inner: WindowHandleInner::Direct(window),
        })),
        _ => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn velox_window_free(window: *mut VeloxWindowHandle) {
    if !window.is_null() {
        unsafe { drop(Box::from_raw(window)) };
    }
}

#[no_mangle]
pub extern "C" fn velox_window_set_title(
    window: *mut VeloxWindowHandle,
    title: *const c_char,
) -> bool {
    let Some(title) = opt_cstring(title) else {
        return false;
    };
    if let Some(result) = with_window(window, |w| {
        w.set_title(&title);
        true
    }) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| {
        dispatcher.set_title(title.clone()).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_fullscreen(
    window: *mut VeloxWindowHandle,
    fullscreen: bool,
) -> bool {
    if let Some(result) = with_window(window, |w| {
        if fullscreen {
            w.set_fullscreen(Some(Fullscreen::Borderless(None)));
        } else {
            w.set_fullscreen(None);
        }
        true
    }) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| {
        dispatcher.set_fullscreen(fullscreen).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_decorations(
    window: *mut VeloxWindowHandle,
    decorations: bool,
) -> bool {
    if let Some(result) = with_window(window, |w| {
        w.set_decorations(decorations);
        true
    }) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| {
        dispatcher.set_decorations(decorations).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_always_on_bottom(
    window: *mut VeloxWindowHandle,
    on_bottom: bool,
) -> bool {
    if let Some(result) = with_window(window, |w| {
        w.set_always_on_bottom(on_bottom);
        true
    }) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| {
        dispatcher.set_always_on_bottom(on_bottom).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_visible_on_all_workspaces(
    window: *mut VeloxWindowHandle,
    visible_on_all_workspaces: bool,
) -> bool {
    if let Some(result) = with_window(window, |w| {
        w.set_visible_on_all_workspaces(visible_on_all_workspaces);
        true
    }) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| {
        dispatcher
            .set_visible_on_all_workspaces(visible_on_all_workspaces)
            .is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_content_protected(
    window: *mut VeloxWindowHandle,
    protected: bool,
) -> bool {
    if let Some(result) = with_window(window, |w| {
        w.set_content_protection(protected);
        true
    }) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| {
        dispatcher.set_content_protected(protected).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_request_user_attention(
    window: *mut VeloxWindowHandle,
    attention_type: VeloxUserAttentionType,
) -> bool {
    let runtime_attention = runtime_user_attention_from_ffi(attention_type);

    if let Some(result) = with_window(window, |w| {
        let tao_attention = tao_user_attention_from_ffi(attention_type);
        w.request_user_attention(Some(tao_attention));
        true
    }) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| {
        dispatcher
            .request_user_attention(Some(runtime_attention))
            .is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_clear_user_attention(window: *mut VeloxWindowHandle) -> bool {
    if let Some(result) = with_window(window, |w| {
        w.request_user_attention(None);
        true
    }) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| {
        dispatcher.request_user_attention(None).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_focus(window: *mut VeloxWindowHandle) -> bool {
    if let Some(result) = with_window(window, |w| {
        w.set_focus();
        true
    }) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| dispatcher.set_focus().is_ok()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_focusable(
    window: *mut VeloxWindowHandle,
    focusable: bool,
) -> bool {
    if let Some(result) = with_window(window, |w| {
        w.set_focusable(focusable);
        true
    }) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| {
        dispatcher.set_focusable(focusable).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_skip_taskbar(
    window: *mut VeloxWindowHandle,
    skip: bool,
) -> bool {
    with_window_dispatcher(window, |dispatcher| {
        dispatcher.set_skip_taskbar(skip).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_cursor_grab(window: *mut VeloxWindowHandle, grab: bool) -> bool {
    if let Some(result) = with_window(window, |w| w.set_cursor_grab(grab).is_ok()) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| {
        dispatcher.set_cursor_grab(grab).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_cursor_visible(
    window: *mut VeloxWindowHandle,
    visible: bool,
) -> bool {
    if let Some(result) = with_window(window, |w| {
        w.set_cursor_visible(visible);
        true
    }) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| {
        dispatcher.set_cursor_visible(visible).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_cursor_position(
    window: *mut VeloxWindowHandle,
    x: f64,
    y: f64,
) -> bool {
    if let Some(result) = with_window(window, |w| {
        w.set_cursor_position(LogicalPosition::new(x, y)).is_ok()
    }) {
        return result;
    }

    let position = RuntimePosition::Logical(RuntimeLogicalPosition::new(x, y));
    with_window_dispatcher(window, |dispatcher| {
        dispatcher.set_cursor_position(position).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_ignore_cursor_events(
    window: *mut VeloxWindowHandle,
    ignore: bool,
) -> bool {
    if let Some(result) = with_window(window, |w| w.set_ignore_cursor_events(ignore).is_ok()) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| {
        dispatcher.set_ignore_cursor_events(ignore).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_resizable(
    window: *mut VeloxWindowHandle,
    resizable: bool,
) -> bool {
    if let Some(result) = with_window(window, |w| {
        w.set_resizable(resizable);
        true
    }) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| {
        dispatcher.set_resizable(resizable).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_always_on_top(
    window: *mut VeloxWindowHandle,
    on_top: bool,
) -> bool {
    if let Some(result) = with_window(window, |w| {
        w.set_always_on_top(on_top);
        true
    }) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| {
        dispatcher.set_always_on_top(on_top).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_visible(window: *mut VeloxWindowHandle, visible: bool) -> bool {
    if let Some(result) = with_window(window, |w| {
        w.set_visible(visible);
        true
    }) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| {
        if visible {
            dispatcher.show().is_ok()
        } else {
            dispatcher.hide().is_ok()
        }
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_request_redraw(window: *mut VeloxWindowHandle) -> bool {
    if let Some(result) = with_window(window, |w| {
        w.request_redraw();
        true
    }) {
        return result;
    }

    with_window_dispatcher(window, |_| false).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_size(
    window: *mut VeloxWindowHandle,
    width: f64,
    height: f64,
) -> bool {
    if let Some(result) = with_window(window, |w| {
        w.set_inner_size(LogicalSize::new(width, height));
        true
    }) {
        return result;
    }

    let size = RuntimeSize::Logical(RuntimeLogicalSize::new(width, height));
    with_window_dispatcher(window, |dispatcher| dispatcher.set_size(size).is_ok()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_position(
    window: *mut VeloxWindowHandle,
    x: f64,
    y: f64,
) -> bool {
    if let Some(result) = with_window(window, |w| {
        w.set_outer_position(LogicalPosition::new(x, y));
        true
    }) {
        return result;
    }

    let position = RuntimePosition::Logical(RuntimeLogicalPosition::new(x, y));
    with_window_dispatcher(window, |dispatcher| {
        dispatcher.set_position(position).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_min_size(
    window: *mut VeloxWindowHandle,
    width: f64,
    height: f64,
) -> bool {
    if let Some(result) = with_window(window, |w| {
        let size: Option<Size> = if width > 0.0 && height > 0.0 {
            Some(Size::Logical(LogicalSize::new(width, height)))
        } else {
            None
        };
        w.set_min_inner_size(size);
        true
    }) {
        return result;
    }

    let size: Option<RuntimeSize> = if width > 0.0 && height > 0.0 {
        Some(RuntimeSize::Logical(RuntimeLogicalSize::new(width, height)))
    } else {
        None
    };

    with_window_dispatcher(window, |dispatcher| dispatcher.set_min_size(size).is_ok())
        .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_set_max_size(
    window: *mut VeloxWindowHandle,
    width: f64,
    height: f64,
) -> bool {
    if let Some(result) = with_window(window, |w| {
        let size: Option<Size> = if width > 0.0 && height > 0.0 {
            Some(Size::Logical(LogicalSize::new(width, height)))
        } else {
            None
        };
        w.set_max_inner_size(size);
        true
    }) {
        return result;
    }

    let size: Option<RuntimeSize> = if width > 0.0 && height > 0.0 {
        Some(RuntimeSize::Logical(RuntimeLogicalSize::new(width, height)))
    } else {
        None
    };

    with_window_dispatcher(window, |dispatcher| dispatcher.set_max_size(size).is_ok())
        .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_start_dragging(window: *mut VeloxWindowHandle) -> bool {
    if let Some(result) = with_window(window, |w| w.drag_window().is_ok()) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| dispatcher.start_dragging().is_ok())
        .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_window_start_resize_dragging(
    window: *mut VeloxWindowHandle,
    direction: VeloxResizeDirection,
) -> bool {
    let runtime_direction = runtime_resize_direction_from_ffi(direction);

    if let Some(result) = with_window(window, |w| {
        let tao_direction = tao_resize_direction_from_ffi(direction);
        w.drag_resize_window(tao_direction).is_ok()
    }) {
        return result;
    }

    with_window_dispatcher(window, |dispatcher| {
        dispatcher.start_resize_dragging(runtime_direction).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_webview_build(
    window: *mut VeloxWindowHandle,
    config: *const VeloxWebviewConfig,
) -> *mut VeloxWebviewHandle {
    if window.is_null() {
        return std::ptr::null_mut();
    }

    let cfg = unsafe { config.as_ref().copied().unwrap_or_default() };
    let url = opt_cstring(cfg.url);

    if let Some(handle) = with_window(window, |w| {
        let mut builder = WebViewBuilder::new();
        if let Some(url) = url.as_ref() {
            builder = builder.with_url(url.clone());
        }
        builder.build(w).ok().map(|webview| {
            Box::into_raw(Box::new(VeloxWebviewHandle {
                inner: WebviewHandleInner::Direct(webview),
            }))
        })
    }) {
        if let Some(ptr) = handle {
            return ptr;
        }
    }

    with_window_dispatcher(window, |dispatcher| {
        let (attributes_url, resolved_url) = match url.as_ref() {
            Some(value) => match Url::parse(value) {
                Ok(parsed) if parsed.scheme() == "http" || parsed.scheme() == "https" => {
                    (WebviewUrl::External(parsed), Some(value.clone()))
                }
                Ok(parsed) => (WebviewUrl::CustomProtocol(parsed), Some(value.clone())),
                Err(_) => (
                    WebviewUrl::App(PathBuf::from(value.clone())),
                    Some(value.clone()),
                ),
            },
            None => (WebviewUrl::default(), None),
        };

        let label = next_runtime_webview_label();
        let mut pending = match PendingWebview::new(WebviewAttributes::new(attributes_url), label) {
            Ok(pending) => pending,
            Err(_) => return None,
        };

        if let Some(resolved) = resolved_url {
            pending.url = resolved;
        }

        dispatcher.create_webview(pending).ok().map(|detached| {
            Box::into_raw(Box::new(VeloxWebviewHandle {
                inner: WebviewHandleInner::Dispatcher(detached.dispatcher),
            }))
        })
    })
    .flatten()
    .unwrap_or(std::ptr::null_mut())
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
    if let Some(result) = with_webview(webview, |view| view.load_url(&url_str).is_ok()) {
        return result;
    }

    with_webview_dispatcher(webview, |dispatcher| {
        dispatcher.navigate(parsed_url.clone()).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_webview_reload(webview: *mut VeloxWebviewHandle) -> bool {
    if let Some(result) = with_webview(webview, |view| view.reload().is_ok()) {
        return result;
    }

    with_webview_dispatcher(webview, |dispatcher| dispatcher.reload().is_ok()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_webview_evaluate_script(
    webview: *mut VeloxWebviewHandle,
    script: *const c_char,
) -> bool {
    let Some(script) = opt_cstring(script) else {
        return false;
    };
    if let Some(result) = with_webview(webview, |view| view.evaluate_script(&script).is_ok()) {
        return result;
    }

    with_webview_dispatcher(webview, |dispatcher| {
        dispatcher.eval_script(script.clone()).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_webview_set_zoom(
    webview: *mut VeloxWebviewHandle,
    scale_factor: f64,
) -> bool {
    if let Some(result) = with_webview(webview, |view| view.zoom(scale_factor).is_ok()) {
        return result;
    }

    with_webview_dispatcher(webview, |dispatcher| {
        dispatcher.set_zoom(scale_factor).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_webview_show(webview: *mut VeloxWebviewHandle) -> bool {
    if let Some(result) = with_webview(webview, |view| view.set_visible(true).is_ok()) {
        return result;
    }

    with_webview_dispatcher(webview, |dispatcher| dispatcher.show().is_ok()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_webview_hide(webview: *mut VeloxWebviewHandle) -> bool {
    if let Some(result) = with_webview(webview, |view| view.set_visible(false).is_ok()) {
        return result;
    }

    with_webview_dispatcher(webview, |dispatcher| dispatcher.hide().is_ok()).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_webview_clear_browsing_data(webview: *mut VeloxWebviewHandle) -> bool {
    if let Some(result) = with_webview(webview, |view| view.clear_all_browsing_data().is_ok()) {
        return result;
    }

    with_webview_dispatcher(webview, |dispatcher| {
        dispatcher.clear_all_browsing_data().is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn velox_runtime_new() -> *mut VeloxRuntime {
    match catch_unwind(AssertUnwindSafe(|| {
        Wry::<VeloxUserEvent>::new(RuntimeInitArgs::default())
    })) {
        Ok(Ok(runtime)) => Box::into_raw(Box::new(VeloxRuntime { runtime })),
        _ => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn velox_runtime_create_window(
    runtime: *mut VeloxRuntime,
    config: *const VeloxWindowConfig,
) -> *mut VeloxWindowHandle {
    if runtime.is_null() {
        return std::ptr::null_mut();
    }

    let cfg = unsafe { config.as_ref().copied().unwrap_or_default() };
    let title = opt_cstring(cfg.title);

    with_runtime(runtime, |rt| {
        let mut builder = WindowBuilderWrapper::new();

        if let Some(title) = title.as_ref() {
            builder = builder.title(title.clone());
        }

        if cfg.width > 0 && cfg.height > 0 {
            builder = builder.inner_size(cfg.width as f64, cfg.height as f64);
        }

        let label = next_runtime_window_label();

        let pending = match PendingWindow::new(builder, label) {
            Ok(pending) => pending,
            Err(_) => return None,
        };

        rt.create_window(pending, Some(noop_raw_window))
            .ok()
            .map(|detached| {
                Box::into_raw(Box::new(VeloxWindowHandle {
                    inner: WindowHandleInner::Dispatcher {
                        dispatcher: detached.dispatcher,
                        _id: detached.id,
                    },
                }))
            })
    })
    .flatten()
    .unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn velox_runtime_free(runtime: *mut VeloxRuntime) {
    if !runtime.is_null() {
        unsafe { drop(Box::from_raw(runtime)) };
    }
}

#[no_mangle]
pub extern "C" fn velox_runtime_run_iteration(
    runtime: *mut VeloxRuntime,
    callback: VeloxRuntimeCallback,
    user_data: *mut c_void,
) {
    let cb = callback;
    let data = user_data;
    let _ = with_runtime(runtime, |rt| {
        let _ = catch_unwind(AssertUnwindSafe(|| {
            rt.run_iteration(move |event| {
                if let Some(callback) = cb {
                    let json = serialize_run_event(&event);
                    if let Ok(c_json) = CString::new(json) {
                        callback(c_json.as_ptr(), data);
                    }
                }
            });
        }));
    });
}

#[no_mangle]
pub extern "C" fn velox_runtime_request_exit(runtime: *mut VeloxRuntime, code: i32) -> bool {
    with_runtime(runtime, |rt| {
        match catch_unwind(AssertUnwindSafe(|| rt.handle().request_exit(code))) {
            Ok(Ok(())) => true,
            _ => false,
        }
    })
    .unwrap_or(false)
}
