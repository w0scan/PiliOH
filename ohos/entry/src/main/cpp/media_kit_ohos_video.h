#ifndef MEDIA_KIT_OHOS_VIDEO_H
#define MEDIA_KIT_OHOS_VIDEO_H

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <thread>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>

#include <mpv/client.h>
#include <mpv/render_gl.h>

struct NativeWindow;  // OHNativeWindow (opaque)

// Renders an existing libmpv core (created by media_kit's Dart Player) into a
// Flutter texture surface on OpenHarmony.
//
// Unlike the standalone demo, this class does NOT create its own mpv core: the
// media_kit Dart Player owns the mpv_handle (via dart:ffi) and drives all
// playback control. Here we only attach the libmpv Render API (OpenGL backend)
// on top of an EGL context bound to the OHNativeWindow that Flutter's
// TextureRegistry hands us, and pump frames as mpv produces them.
//
// One instance per mpv core. Instances are tracked by MediaKitOhosVideo::Get /
// Create / Destroy keyed by the mpv_handle pointer.
class MediaKitOhosVideo {
 public:
  // Registry keyed by the mpv core handle.
  static MediaKitOhosVideo* Create(mpv_handle* mpv, void* window, int width,
                                   int height);
  static MediaKitOhosVideo* Get(mpv_handle* mpv);
  static void Destroy(mpv_handle* mpv);

  void SetSize(int width, int height);

 private:
  explicit MediaKitOhosVideo(mpv_handle* mpv, void* window, int width,
                             int height);
  ~MediaKitOhosVideo();

  MediaKitOhosVideo(const MediaKitOhosVideo&) = delete;
  MediaKitOhosVideo& operator=(const MediaKitOhosVideo&) = delete;

  bool InitEgl();
  void DestroyEgl();

  void StartRenderThread();
  void StopRenderThread();
  void RenderLoop();
  void RequestRedraw();

  static void* GetProcAddress(void* ctx, const char* name);
  static void OnMpvRenderUpdate(void* ctx);

  // EGL state (owned by the render thread).
  EGLDisplay display_ = EGL_NO_DISPLAY;
  EGLContext context_ = EGL_NO_CONTEXT;
  EGLSurface surface_ = EGL_NO_SURFACE;
  EGLConfig config_ = nullptr;
  NativeWindow* window_ = nullptr;
  std::atomic<int> width_{0};
  std::atomic<int> height_{0};

  // mpv state. mpv_ is owned by the Dart Player, NOT by us.
  mpv_handle* mpv_ = nullptr;
  mpv_render_context* renderCtx_ = nullptr;

  // Render thread synchronisation.
  std::thread renderThread_;
  std::mutex renderMutex_;
  std::condition_variable renderCond_;
  std::atomic<bool> renderRunning_{false};
  std::atomic<bool> wantRedraw_{false};
  std::atomic<bool> wantResize_{false};
};

#endif  // MEDIA_KIT_OHOS_VIDEO_H
