use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::sync::OnceLock;

use tao::{
    dpi::LogicalSize,
    event::{Event, StartCause},
    event_loop::{ControlFlow, EventLoop, EventLoopBuilder, EventLoopProxy},
    platform::run_return::EventLoopExtRunReturn,
    window::{Window, WindowBuilder},
};
use wry::{WebView, WebViewBuilder};

use serde::Serialize;
use serde_json::json;

static LIBRARY_NAME: OnceLock<CString> = OnceLock::new();
static RUNTIME_VERSION: OnceLock<CString> = OnceLock::new();
static WEBVIEW_VERSION: OnceLock<CString> = OnceLock::new();

#[derive(Debug)]
enum VeloxUserEvent {
    Exit,
}

pub struct VeloxEventLoop {
    event_loop: EventLoop<VeloxUserEvent>,
}

pub struct VeloxEventLoopProxyHandle {
    proxy: EventLoopProxy<VeloxUserEvent>,
}

pub struct VeloxWindowHandle {
    window: Window,
}

pub struct VeloxWebviewHandle {
    _webview: WebView,
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

pub type VeloxEventLoopCallback = Option<
    extern "C" fn(event_description: *const c_char, user_data: *mut c_void) -> VeloxControlFlow,
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

fn serialize_event(event: &Event<VeloxUserEvent>) -> String {
    use tao::event::{Event as TaoEvent, WindowEvent as TaoWindowEvent};

    let value = match event {
        TaoEvent::NewEvents(cause) => json!({
          "type": "new-events",
          "cause": format!("{:?}", cause),
        }),
        TaoEvent::MainEventsCleared => json!({ "type": "main-events-cleared" }),
        TaoEvent::RedrawEventsCleared => json!({ "type": "redraw-events-cleared" }),
        TaoEvent::LoopDestroyed => json!({ "type": "loop-destroyed" }),
        TaoEvent::UserEvent(VeloxUserEvent::Exit) => json!({ "type": "user-exit" }),
        TaoEvent::WindowEvent {
            window_id, event, ..
        } => match event {
            TaoWindowEvent::CloseRequested => json!({
              "type": "window-close-requested",
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
            TaoWindowEvent::ScaleFactorChanged { scale_factor, .. } => json!({
              "type": "window-scale-factor-changed",
              "window_id": format!("{window_id:?}"),
              "scale_factor": scale_factor,
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
                let mut builder = WindowBuilder::new();

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
        Some(Ok(window)) => Box::into_raw(Box::new(VeloxWindowHandle { window })),
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
pub extern "C" fn velox_webview_build(
    window: *mut VeloxWindowHandle,
    config: *const VeloxWebviewConfig,
) -> *mut VeloxWebviewHandle {
    if window.is_null() {
        return std::ptr::null_mut();
    }

    let window = unsafe { &mut *window };
    let cfg = unsafe { config.as_ref().copied().unwrap_or_default() };

    let mut builder = WebViewBuilder::new();

    if let Some(url) = opt_cstring(cfg.url) {
        builder = builder.with_url(url);
    }

    match builder.build(&window.window) {
        Ok(webview) => Box::into_raw(Box::new(VeloxWebviewHandle { _webview: webview })),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn velox_webview_free(webview: *mut VeloxWebviewHandle) {
    if !webview.is_null() {
        unsafe { drop(Box::from_raw(webview)) };
    }
}
