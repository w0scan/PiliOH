#include <cstdint>

#include <hilog/log.h>
#include <napi/native_api.h>

#include "media_kit_ohos_video.h"

#undef LOG_TAG
#undef LOG_DOMAIN
#define LOG_DOMAIN 0x3200
#define LOG_TAG "mediakit_ohos"

namespace {

uint64_t GetBigIntArg(napi_env env, napi_value value) {
  uint64_t out = 0;
  bool lossless = false;
  napi_get_value_bigint_uint64(env, value, &out, &lossless);
  return out;
}

int GetIntArg(napi_env env, napi_value value) {
  int32_t out = 0;
  napi_get_value_int32(env, value, &out);
  return out;
}

int64_t GetInt64Arg(napi_env env, napi_value value) {
  int64_t out = 0;
  napi_get_value_int64(env, value, &out);
  return out;
}

// create(handle: bigint, window: number, width: number, height: number): void
// `window` is the OHNativeWindow* returned by SurfaceTextureEntry.getNativeWindowId(),
// which flutter_ohos exposes as a JS number.
napi_value JsCreate(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value args[4] = {nullptr, nullptr, nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  auto* mpv = reinterpret_cast<mpv_handle*>(GetBigIntArg(env, args[0]));
  void* window = reinterpret_cast<void*>(GetInt64Arg(env, args[1]));
  int width = argc > 2 ? GetIntArg(env, args[2]) : 0;
  int height = argc > 3 ? GetIntArg(env, args[3]) : 0;

  if (mpv == nullptr || window == nullptr) {
    OH_LOG_ERROR(LOG_APP, "mediakit_ohos: create with null mpv/window");
    return nullptr;
  }
  MediaKitOhosVideo::Create(mpv, window, width, height);
  OH_LOG_INFO(LOG_APP, "mediakit_ohos: created %{public}dx%{public}d", width,
              height);
  return nullptr;
}

// setSize(handle: bigint, width: number, height: number): void
napi_value JsSetSize(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3] = {nullptr, nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  auto* mpv = reinterpret_cast<mpv_handle*>(GetBigIntArg(env, args[0]));
  int width = argc > 1 ? GetIntArg(env, args[1]) : 0;
  int height = argc > 2 ? GetIntArg(env, args[2]) : 0;

  if (auto* video = MediaKitOhosVideo::Get(mpv)) {
    video->SetSize(width, height);
  }
  return nullptr;
}

// dispose(handle: bigint): void
napi_value JsDispose(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  auto* mpv = reinterpret_cast<mpv_handle*>(GetBigIntArg(env, args[0]));
  MediaKitOhosVideo::Destroy(mpv);
  return nullptr;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"create", nullptr, JsCreate, nullptr, nullptr, nullptr, napi_default,
       nullptr},
      {"setSize", nullptr, JsSetSize, nullptr, nullptr, nullptr, napi_default,
       nullptr},
      {"dispose", nullptr, JsDispose, nullptr, nullptr, nullptr, napi_default,
       nullptr},
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  return exports;
}

}  // namespace

static napi_module g_mediaKitModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "media_kit_ohos_video",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterMediaKitModule(void) {
  napi_module_register(&g_mediaKitModule);
}
