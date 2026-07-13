import fileIo from '@ohos.file.fs';
import environment from '@ohos.file.environment';
import filePicker from '@ohos.file.picker';
import type common from '@ohos.app.ability.common';
import { Log } from '@ohos/flutter_ohos';

const TAG = 'OhosDownloadDirectory';

export default class OhosDownloadDirectory {
  private constructor() {}

  static async ensureAuthorized(context: common.UIAbilityContext): Promise<string> {
    const existing = OhosDownloadDirectory.resolve(context);
    if (existing.length > 0) {
      return existing;
    }
    try {
      const options = new filePicker.DocumentSaveOptions();
      options.pickerMode = filePicker.DocumentPickerMode.DOWNLOAD;
      const picker = new filePicker.DocumentViewPicker(context);
      await picker.save(options);
    } catch (e) {
      Log.w(TAG, 'download directory authorization cancelled: ' + JSON.stringify(e));
    }
    return OhosDownloadDirectory.resolve(context);
  }

  static resolve(context: common.UIAbilityContext): string {
    try {
      const base = environment.getUserDownloadDir();
      if (base.length === 0) {
        return '';
      }
      const directory = `${base}/${context.applicationInfo.name}`;
      if (!fileIo.accessSync(directory)) {
        fileIo.mkdirSync(directory, true);
      }
      const probePath = `${directory}/.probe`;
      const probe = fileIo.openSync(
        probePath,
        fileIo.OpenMode.READ_WRITE |
        fileIo.OpenMode.CREATE |
        fileIo.OpenMode.TRUNC,
      );
      try {
        fileIo.writeSync(probe.fd, new Uint8Array([1]).buffer);
      } finally {
        fileIo.closeSync(probe.fd);
      }
      fileIo.unlinkSync(probePath);
      return directory;
    } catch (e) {
      Log.w(TAG, 'public download directory unavailable: ' + JSON.stringify(e));
      return '';
    }
  }
}
