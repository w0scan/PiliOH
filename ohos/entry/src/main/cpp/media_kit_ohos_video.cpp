#include "media_kit_ohos_video.h"

#include <dlfcn.h>

#include <map>

#include <hilog/log.h>
#include <native_window/external_window.h>

#undef LOG_TAG
#undef LOG_DOMAIN
#define LOG_DOMAIN 0x3200
#define LOG_TAG "mediakit_ohos"

namespace {
constexpr char kTag[] = "mediakit_ohos";

std::mutex g_registryMutex;
std::map<mpv_handle*, MediaKitOhosVideo*>& Registry() {
  static std::map<mpv_handle*, MediaKitOhosVideo*> registry;
  return registry;
}
}  // namespace

// --------------------------------------------------------------------------
// Registry
// --------------------------------------------------------------------------
MediaKitOhosVideo* MediaKitOhosVideo::Create(mpv_handle* mpv, void* window,
                                             int width, int height) {
  std::lock_guard<std::mutex> lock(g_registryMutex);
  auto& reg = Registry();
  auto it = reg.find(mpv);
  if (it != reg.end()) {
    // Already exists: just (re)bind the new surface size.
    it->second->SetSize(width, height);
    return it->second;
  }
  auto* video = new MediaKitOhosVideo(mpv, window, width, height);
  reg[mpv] = video;
  return video;
}

MediaKitOhosVideo* MediaKitOhosVideo::Get(mpv_handle* mpv) {
  std::lock_guard<std::mutex> lock(g_registryMutex);
  auto& reg = Registry();
  auto it = reg.find(mpv);
  return it == reg.end() ? nullptr : it->second;
}

void MediaKitOhosVideo::Destroy(mpv_handle* mpv) {
  MediaKitOhosVideo* video = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_registryMutex);
    auto& reg = Registry();
    auto it = reg.find(mpv);
    if (it == reg.end()) {
      return;
    }
    video = it->second;
    reg.erase(it);
  }
  delete video;  // joins the render thread, frees render context + EGL.
}

// --------------------------------------------------------------------------
// Lifecycle
// --------------------------------------------------------------------------
MediaKitOhosVideo::MediaKitOhosVideo(mpv_handle* mpv, void* window, int width,
                                     int height)
    : mpv_(mpv),
      window_(static_cast<NativeWindow*>(window)) {
  width_ = width;
  height_ = height;
  if (window_ != nullptr && width > 0 && height > 0) {
    OH_NativeWindow_NativeWindowHandleOpt(
        reinterpret_cast<OHNativeWindow*>(window_), SET_BUFFER_GEOMETRY, width,
        height);
  }
  StartRenderThread();
}

MediaKitOhosVideo::~MediaKitOhosVideo() {
  StopRenderThread();
  window_ = nullptr;
}

void MediaKitOhosVideo::SetSize(int width, int height) {
  if (width <= 0 || height <= 0) {
    return;
  }
  width_ = width;
  height_ = height;
  if (window_ != nullptr) {
    OH_NativeWindow_NativeWindowHandleOpt(
        reinterpret_cast<OHNativeWindow*>(window_), SET_BUFFER_GEOMETRY, width,
        height);
  }
  wantResize_ = true;
  RequestRedraw();
}

// --------------------------------------------------------------------------
// GL function resolver for the mpv OpenGL backend.
// eglGetProcAddress on OHOS does not reliably return pointers for core GLES
// functions, so we fall back to dlsym() on the GLES/EGL shared objects.
// --------------------------------------------------------------------------
void* MediaKitOhosVideo::GetProcAddress(void* /*ctx*/, const char* name) {
  static void* glesv3 = dlopen("libGLESv3.so", RTLD_NOW | RTLD_GLOBAL);
  static void* glesv2 = dlopen("libGLESv2.so", RTLD_NOW | RTLD_GLOBAL);
  static void* egl = dlopen("libEGL.so", RTLD_NOW | RTLD_GLOBAL);

  if (auto p = reinterpret_cast<void*>(eglGetProcAddress(name))) {
    return p;
  }
  for (void* handle : {glesv3, glesv2, egl}) {
    if (handle != nullptr) {
      if (void* p = dlsym(handle, name)) {
        return p;
      }
    }
  }
  return nullptr;
}

void MediaKitOhosVideo::OnMpvRenderUpdate(void* ctx) {
  static_cast<MediaKitOhosVideo*>(ctx)->RequestRedraw();
}

// --------------------------------------------------------------------------
// EGL
// --------------------------------------------------------------------------
bool MediaKitOhosVideo::InitEgl() {
  display_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  if (display_ == EGL_NO_DISPLAY) {
    OH_LOG_ERROR(LOG_APP, "%{public}s: eglGetDisplay failed", kTag);
    return false;
  }
  EGLint major = 0, minor = 0;
  if (!eglInitialize(display_, &major, &minor)) {
    OH_LOG_ERROR(LOG_APP, "%{public}s: eglInitialize failed", kTag);
    return false;
  }
  OH_LOG_INFO(LOG_APP, "%{public}s: EGL %{public}d.%{public}d", kTag, major,
              minor);

  const EGLint configAttribs[] = {EGL_SURFACE_TYPE,
                                  EGL_WINDOW_BIT,
                                  EGL_RENDERABLE_TYPE,
                                  EGL_OPENGL_ES2_BIT,
                                  EGL_RED_SIZE,
                                  8,
                                  EGL_GREEN_SIZE,
                                  8,
                                  EGL_BLUE_SIZE,
                                  8,
                                  EGL_ALPHA_SIZE,
                                  8,
                                  EGL_DEPTH_SIZE,
                                  0,
                                  EGL_STENCIL_SIZE,
                                  0,
                                  EGL_NONE};
  EGLint numConfigs = 0;
  if (!eglChooseConfig(display_, configAttribs, &config_, 1, &numConfigs) ||
      numConfigs < 1) {
    OH_LOG_ERROR(LOG_APP, "%{public}s: eglChooseConfig failed", kTag);
    return false;
  }

  surface_ = eglCreateWindowSurface(
      display_, config_, reinterpret_cast<EGLNativeWindowType>(window_),
      nullptr);
  if (surface_ == EGL_NO_SURFACE) {
    OH_LOG_ERROR(LOG_APP, "%{public}s: eglCreateWindowSurface failed: 0x%{public}x",
                 kTag, eglGetError());
    return false;
  }

  const EGLint contextAttribs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  context_ = eglCreateContext(display_, config_, EGL_NO_CONTEXT, contextAttribs);
  if (context_ == EGL_NO_CONTEXT) {
    OH_LOG_ERROR(LOG_APP, "%{public}s: eglCreateContext failed", kTag);
    return false;
  }
  return true;
}

void MediaKitOhosVideo::DestroyEgl() {
  if (display_ != EGL_NO_DISPLAY) {
    eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (context_ != EGL_NO_CONTEXT) {
      eglDestroyContext(display_, context_);
      context_ = EGL_NO_CONTEXT;
    }
    if (surface_ != EGL_NO_SURFACE) {
      eglDestroySurface(display_, surface_);
      surface_ = EGL_NO_SURFACE;
    }
    eglTerminate(display_);
    display_ = EGL_NO_DISPLAY;
  }
}

// --------------------------------------------------------------------------
// Render thread
// --------------------------------------------------------------------------
void MediaKitOhosVideo::RequestRedraw() {
  {
    std::lock_guard<std::mutex> lock(renderMutex_);
    wantRedraw_ = true;
  }
  renderCond_.notify_one();
}

void MediaKitOhosVideo::StartRenderThread() {
  renderRunning_ = true;
  renderThread_ = std::thread(&MediaKitOhosVideo::RenderLoop, this);
}

void MediaKitOhosVideo::StopRenderThread() {
  {
    std::lock_guard<std::mutex> lock(renderMutex_);
    renderRunning_ = false;
  }
  renderCond_.notify_one();
  if (renderThread_.joinable()) {
    renderThread_.join();
  }
}

void MediaKitOhosVideo::RenderLoop() {
  if (!InitEgl()) {
    OH_LOG_ERROR(LOG_APP, "%{public}s: InitEgl failed", kTag);
    return;
  }
  if (!eglMakeCurrent(display_, surface_, surface_, context_)) {
    OH_LOG_ERROR(LOG_APP, "%{public}s: eglMakeCurrent failed", kTag);
    DestroyEgl();
    return;
  }

  // The render context must be created on the thread that owns the GL context.
  mpv_opengl_init_params glInit{};
  glInit.get_proc_address = &MediaKitOhosVideo::GetProcAddress;
  glInit.get_proc_address_ctx = this;

  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_API_TYPE,
       const_cast<char*>(MPV_RENDER_API_TYPE_OPENGL)},
      {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glInit},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  if (int err = mpv_render_context_create(&renderCtx_, mpv_, params); err < 0) {
    OH_LOG_ERROR(LOG_APP, "%{public}s: mpv_render_context_create failed: %{public}s",
                 kTag, mpv_error_string(err));
    DestroyEgl();
    return;
  }
  mpv_render_context_set_update_callback(
      renderCtx_, &MediaKitOhosVideo::OnMpvRenderUpdate, this);
  OH_LOG_INFO(LOG_APP, "%{public}s: render context created", kTag);

  while (renderRunning_) {
    {
      std::unique_lock<std::mutex> lock(renderMutex_);
      renderCond_.wait(lock, [this] {
        return wantRedraw_.load() || wantResize_.load() ||
               !renderRunning_.load();
      });
      wantRedraw_ = false;
    }
    if (!renderRunning_) {
      break;
    }

    bool resized = wantResize_.exchange(false);

    int w = width_.load();
    int h = height_.load();
    if (w <= 0 || h <= 0) {
      continue;
    }

    uint64_t flags = mpv_render_context_update(renderCtx_);
    if (!resized && !(flags & MPV_RENDER_UPDATE_FRAME)) {
      continue;
    }

    mpv_opengl_fbo fbo{};
    fbo.fbo = 0;  // default framebuffer of the window surface
    fbo.w = w;
    fbo.h = h;

    int flipY = 1;
    mpv_render_param renderParams[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &fbo},
        {MPV_RENDER_PARAM_FLIP_Y, &flipY},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    mpv_render_context_render(renderCtx_, renderParams);
    eglSwapBuffers(display_, surface_);
  }

  if (renderCtx_ != nullptr) {
    // Stop callbacks before freeing so no redraw is requested mid-teardown.
    mpv_render_context_set_update_callback(renderCtx_, nullptr, nullptr);
    mpv_render_context_free(renderCtx_);
    renderCtx_ = nullptr;
  }
  DestroyEgl();
  OH_LOG_INFO(LOG_APP, "%{public}s: render loop exited", kTag);
}
