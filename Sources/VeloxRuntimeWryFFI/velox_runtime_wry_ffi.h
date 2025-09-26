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

VeloxWebviewHandle *velox_webview_build(VeloxWindowHandle *window, const VeloxWebviewConfig *config);
void velox_webview_free(VeloxWebviewHandle *webview);

#ifdef __cplusplus
}
#endif

#endif /* VELOX_RUNTIME_WRY_FFI_H */
