import {
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodChannel,
  MethodResult,
  TextureRegistry,
} from '@ohos/flutter_ohos';
import type { SurfaceTextureEntry } from '@ohos/flutter_ohos';
import mpvVideo from 'libmedia_kit_ohos_video.so';

const TAG = 'MediaKitVideoPlugin';

// Per-player render target: the Flutter texture + the mpv core handle that
// media_kit's Dart Player owns. Keyed by the mpv handle (decimal string).
class VideoOutput {
  textureId: number;
  entry: SurfaceTextureEntry;
  handle: bigint;

  constructor(textureId: number, entry: SurfaceTextureEntry, handle: bigint) {
    this.textureId = textureId;
    this.entry = entry;
    this.handle = handle;
  }
}

// ArkTS counterpart of media_kit_video's native plugin, but for OpenHarmony.
//
// media_kit's Dart Player drives playback over dart:ffi to libmpv. Only video
// *output* needs platform glue: register a Flutter texture, hand its
// OHNativeWindow to the native render module, and resize/dispose on demand.
// Channel name matches the one the Dart [OhosVideoController] talks to.
export default class MediaKitVideoPlugin implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private textures: TextureRegistry | null = null;
  private outputs: Map<string, VideoOutput> = new Map();

  getUniqueClassName(): string {
    return 'MediaKitVideoPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.textures = binding.getTextureRegistry();
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      'com.alexmercerind/media_kit_video',
    );
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        this.handle(call, result);
      },
    });
    Log.i(TAG, 'attached');
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    for (const output of this.outputs.values()) {
      this.disposeOutput(output);
    }
    this.outputs.clear();
  }

  private handle(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case 'VideoOutputManager.Create':
          this.create(call.argument('handle') as string, result);
          break;
        case 'VideoOutputManager.SetSurfaceTextureSize':
          this.setSize(
            call.argument('handle') as string,
            call.argument('width') as string,
            call.argument('height') as string,
          );
          result.success(null);
          break;
        case 'VideoOutputManager.Dispose':
          this.dispose(call.argument('handle') as string);
          result.success(null);
          break;
        default:
          result.notImplemented();
      }
    } catch (e) {
      Log.e(TAG, 'method ' + call.method + ' failed: ' + JSON.stringify(e));
      result.error('media_kit_ohos', JSON.stringify(e), null);
    }
  }

  private create(handleStr: string, result: MethodResult): void {
    if (this.textures == null) {
      result.error('media_kit_ohos', 'no TextureRegistry', null);
      return;
    }
    const existing = this.outputs.get(handleStr);
    if (existing != undefined) {
      const reply: Map<string, number> = new Map();
      reply.set('id', existing.textureId);
      result.success(reply);
      return;
    }

    const handle: bigint = BigInt(handleStr);
    const textureId: number = this.textures.getTextureId();
    const entry: SurfaceTextureEntry = this.textures.registerTexture(textureId);
    const window: number = entry.getNativeWindowId();

    // Start the native render thread + mpv render context. Size 0 until the
    // first video-params arrive (the render loop idles while size is 0).
    mpvVideo.create(handle, window, 0, 0);

    this.outputs.set(handleStr, new VideoOutput(textureId, entry, handle));
    Log.i(TAG, 'created texture ' + textureId + ' for handle ' + handleStr);

    const reply: Map<string, number> = new Map();
    reply.set('id', textureId);
    result.success(reply);
  }

  private setSize(handleStr: string, widthStr: string, heightStr: string): void {
    const output = this.outputs.get(handleStr);
    if (output == undefined) {
      return;
    }
    const width: number = parseInt(widthStr, 10);
    const height: number = parseInt(heightStr, 10);
    if (width <= 0 || height <= 0) {
      return;
    }
    this.textures?.setTextureBufferSize(output.textureId, width, height);
    mpvVideo.setSize(output.handle, width, height);
  }

  private dispose(handleStr: string): void {
    const output = this.outputs.get(handleStr);
    if (output == undefined) {
      return;
    }
    this.disposeOutput(output);
    this.outputs.delete(handleStr);
  }

  private disposeOutput(output: VideoOutput): void {
    // Stop native rendering (joins the render thread, frees EGL + render ctx)
    // before unregistering the texture so the OHNativeWindow stays valid until
    // the render thread has released it.
    mpvVideo.dispose(output.handle);
    this.textures?.unregisterTexture(output.textureId);
  }
}
