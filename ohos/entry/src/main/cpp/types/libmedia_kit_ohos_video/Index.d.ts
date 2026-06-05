// Native module that renders an existing libmpv core (owned by media_kit's
// Dart Player) into a Flutter texture surface via the libmpv Render API.
//
// `handle` is the mpv_handle* address (bigint, full 64-bit precision). `window`
// is the OHNativeWindow* from SurfaceTextureEntry.getNativeWindowId(), which
// flutter_ohos exposes as a JS number.
export const create: (handle: bigint, window: number, width: number, height: number) => void;
export const setSize: (handle: bigint, width: number, height: number) => void;
export const dispose: (handle: bigint) => void;
// Move the live render output onto a Picture-in-Picture XComponent surface
// (identified by its OHOS surface id) or back to the Flutter texture window.
export const rebind: (handle: bigint, surfaceId: bigint) => void;
export const rebindToFlutter: (handle: bigint) => void;
