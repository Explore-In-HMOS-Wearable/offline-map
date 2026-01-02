import fs from '@ohos.file.fs';

import { map, mapCommon } from '@kit.MapKit';

import { fileExists } from '../../common/OfflineMapUtils';
import { RemovableOverlay, TileOverlayLike } from './Types';
import { ViewportTracker, ViewportUpdate } from './ViewportTracker';

export interface TileOverlayManagerCallbacks {
  getRootDir: () => string | null | undefined;
  getActiveOfflineAreaName: () => string;
  onViewportUpdate: (update: ViewportUpdate) => void;
}

export class TileOverlayManager {
  private tracker: ViewportTracker;
  private callbacks: TileOverlayManagerCallbacks;

  constructor(tracker: ViewportTracker, callbacks: TileOverlayManagerCallbacks) {
    this.tracker = tracker;
    this.callbacks = callbacks;
  }

  public getTileOverlayOptions(): mapCommon.TileOverlayOptions {
    return {
      tileProvider: this.tileProvider,
      fadeIn: true,
      transparency: 0,
      visible: true
    };
  }

  public resetTileOverlay(
    mapController: map.MapComponentController | undefined,
    existingOverlay: map.TileOverlay | undefined
  ): map.TileOverlay | undefined {
    if (!mapController) {
      return existingOverlay;
    }

    const overlayLike: TileOverlayLike | undefined = existingOverlay as TileOverlayLike | undefined;
    try {
      overlayLike?.clearTileCache?.();
      overlayLike?.setVisible?.(false);
      overlayLike?.setVisible?.(true);
    } catch {
      // ignore
    }

    try {
      (existingOverlay as RemovableOverlay | undefined)?.remove?.();
    } catch {
      // ignore
    }

    try {
      return mapController.addTileOverlay(this.getTileOverlayOptions());
    } catch (e) {
      console.error('Failed to reset tile overlay', e);
      return undefined;
    }
  }

  public tileProvider = async (x: number, y: number, z: number): Promise<ArrayBuffer> => {
    const update: ViewportUpdate | null = this.tracker.onTileRequested(x, y, z);
    if (update) {
      this.callbacks.onViewportUpdate(update);
    }

    const rootDir: string | null | undefined = this.callbacks.getRootDir();
    if (!rootDir) {
      return new ArrayBuffer(0);
    }

    const areaName: string = this.callbacks.getActiveOfflineAreaName();
    return await this.loadTile(rootDir, areaName, x, y, z);
  };

  private async loadTile(
    rootDir: string,
    offlineAreaName: string,
    x: number,
    y: number,
    z: number
  ): Promise<ArrayBuffer> {
    const tilePath = `${rootDir}/${offlineAreaName}/${z}/${x}/${y}.png`;

    if (fileExists(tilePath)) {
      const file = fs.openSync(tilePath, fs.OpenMode.READ_ONLY);
      try {
        const stat = fs.statSync(tilePath);
        const buffer = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buffer);
        return buffer;
      } finally {
        try {
          fs.closeSync(file);
        } catch {
          // ignore
        }
      }
    }

    return new ArrayBuffer(0);
  }
}

