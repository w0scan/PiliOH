import filePicker from '@ohos.file.picker';
import fileIo from '@ohos.file.fs';
import pasteboard from '@ohos.pasteboard';
import { util } from '@kit.ArkTS';
import { Log, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import type { BusinessError } from '@ohos.base';

const TAG = 'FilePickerOhos';

export default class FilePickerOhos {
  private constructor() {}

  /** Handle MethodChannel calls from Dart. */
  static handleCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'saveFile': {
        const fileName = call.argument('fileName') as string;
        const base64 = call.argument('base64') as string;
        FilePickerOhos.saveFile(fileName, base64, result);
        break;
      }
      case 'pickFile': {
        FilePickerOhos.pickFile(result);
        break;
      }
      case 'readClipboard': {
        FilePickerOhos.readClipboard(result);
        break;
      }
      default:
        result.notImplemented();
    }
  }

  /** Open system save dialog, write file, return result. */
  private static saveFile(fileName: string, base64: string, result: MethodResult): void {
    const documentSaveOptions = new filePicker.DocumentSaveOptions();
    documentSaveOptions.newFileNames = [fileName];

    try {
      const documentViewPicker = new filePicker.DocumentViewPicker();
      documentViewPicker.save(documentSaveOptions).then((uris: string[]) => {
        if (uris == null || uris.length == 0) {
          result.success(false);
          return;
        }
        const uri = uris[0];
        try {
          const bytes: Uint8Array = FilePickerOhos.base64ToBytes(base64);
          const file = fileIo.openSync(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE);
          try {
            fileIo.writeSync(file.fd, bytes.buffer);
          } finally {
            fileIo.closeSync(file);
          }
          Log.i(TAG, 'file saved: ' + uri);
          result.success(true);
        } catch (e) {
          Log.e(TAG, 'write failed: ' + JSON.stringify(e));
          result.success(false);
        }
      }).catch((err: BusinessError) => {
        Log.e(TAG, 'save dialog failed: ' + JSON.stringify(err));
        result.success(false);
      });
    } catch (e) {
      Log.e(TAG, 'saveFile exception: ' + JSON.stringify(e));
      result.success(false);
    }
  }

  /** Open system file picker, read content, return as base64 string. */
  private static pickFile(result: MethodResult): void {
    const documentSelectOptions = new filePicker.DocumentSelectOptions();
    documentSelectOptions.fileSuffixFilters = ['json', 'txt'];

    try {
      const documentViewPicker = new filePicker.DocumentViewPicker();
      documentViewPicker.select(documentSelectOptions).then((uris: string[]) => {
        if (uris == null || uris.length == 0) {
          result.success(null);
          return;
        }
        const uri = uris[0];
        try {
          const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
          const stat = fileIo.statSync(file.fd);
          const buf = new ArrayBuffer(stat.size);
          fileIo.readSync(file.fd, buf);
          fileIo.closeSync(file);
          const bytes = new Uint8Array(buf);
          const base64 = FilePickerOhos.bytesToBase64(bytes);
          Log.i(TAG, 'file picked: ' + uri + ' size=' + stat.size);
          result.success(base64);
        } catch (e) {
          Log.e(TAG, 'read failed: ' + JSON.stringify(e));
          result.success(null);
        }
      }).catch((err: BusinessError) => {
        Log.e(TAG, 'select dialog failed: ' + JSON.stringify(err));
        result.success(null);
      });
    } catch (e) {
      Log.e(TAG, 'pickFile exception: ' + JSON.stringify(e));
      result.success(null);
    }
  }

  /** Read plain text from the system pasteboard (foreground, no permission). */
  private static readClipboard(result: MethodResult): void {
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.getData().then((data: pasteboard.PasteData) => {
        try {
          const text = data.getPrimaryText();
          result.success(text == null ? '' : text);
        } catch (e) {
          Log.e(TAG, 'getPrimaryText failed: ' + JSON.stringify(e));
          result.success('');
        }
      }).catch((err: BusinessError) => {
        Log.e(TAG, 'getData failed: ' + JSON.stringify(err));
        result.success('');
      });
    } catch (e) {
      Log.e(TAG, 'readClipboard exception: ' + JSON.stringify(e));
      result.success('');
    }
  }

  private static base64ToBytes(base64: string): Uint8Array {
    const helper = new util.Base64Helper();
    return helper.decodeSync(base64);
  }

  private static bytesToBase64(bytes: Uint8Array): string {
    const helper = new util.Base64Helper();
    return helper.encodeToStringSync(bytes);
  }
}
