import { TileRange } from '../../common/TileStorageHelper';
import { boundsToTileRange, estimateDownloadKb, formatKb } from '../../common/TileMathUtils';
import {
  CameraContainer,
  MapControllerCompat,
  MaybePromise,
  ViewportTileStats,
  VisibleRegion,
  ZoomAndRange
} from './Types';

export interface ViewportUpdate {
  detectedViewportZoom: number;
  detectedViewportTiles: number;
  estimatedDownloadText: string;
}

export class ViewportTracker {
  private minZoomForOfflineDownload: number;
  private maxZoomForOfflineDownload: number;
  private estimatedTileSizeKb: number;
  private viewportTileStats: ViewportTileStats | null = null;
  private lastViewportUiUpdateMs: number = 0;
  private detectedViewportZoom: number = -1;
  private detectedViewportTiles: number = 0;
  private estimatedDownloadText: string = '';

  constructor(minZoomForOfflineDownload: number, maxZoomForOfflineDownload: number, estimatedTileSizeKb: number) {
    this.minZoomForOfflineDownload = minZoomForOfflineDownload;
    this.maxZoomForOfflineDownload = maxZoomForOfflineDownload;
    this.estimatedTileSizeKb = estimatedTileSizeKb;
  }

  public getOverlayViewportTileRange(): ZoomAndRange | null {
    const stats: ViewportTileStats | null = this.viewportTileStats;
    if (stats === null) {
      return null;
    }

    const zoom: number = stats.zoom;
    const range: TileRange = new TileRange(
      stats.xMin,
      stats.xMax,
      stats.yMin,
      stats.yMax
    );
    return { zoom, range };
  }

  public onTileRequested(x: number, y: number, z: number): ViewportUpdate | null {
    const now: number = Date.now();

    const stats: ViewportTileStats | null = this.viewportTileStats;
    if (stats === null || stats.zoom !== z || now - stats.updatedAtMs > 600) {
      this.viewportTileStats = {
        zoom: z,
        xMin: x,
        xMax: x,
        yMin: y,
        yMax: y,
        updatedAtMs: now
      };
      this.detectedViewportZoom = z;
      this.detectedViewportTiles = 1;
      this.estimatedDownloadText = this.estimateDownloadTextFromCurrentViewAscii();
      this.lastViewportUiUpdateMs = now;
      return this.getUpdate();
    }

    stats.xMin = Math.min(stats.xMin, x);
    stats.xMax = Math.max(stats.xMax, x);
    stats.yMin = Math.min(stats.yMin, y);
    stats.yMax = Math.max(stats.yMax, y);
    stats.updatedAtMs = now;

    if (now - this.lastViewportUiUpdateMs <= 500) {
      return null;
    }

    this.detectedViewportZoom = z;
    const tilesX: number = stats.xMax - stats.xMin + 1;
    const tilesY: number = stats.yMax - stats.yMin + 1;
    this.detectedViewportTiles = Math.max(0, tilesX * tilesY);
    this.estimatedDownloadText = this.estimateDownloadTextFromCurrentViewAscii();
    this.lastViewportUiUpdateMs = now;
    return this.getUpdate();
  }

  public async getControllerViewportTileRange(controller: MapControllerCompat | undefined):
    Promise<ZoomAndRange | null> {
    if (!controller) {
      return null;
    }
    const cameraCandidates: Array<() => MaybePromise<CameraContainer | null | undefined>> = [
      (): MaybePromise<CameraContainer | null | undefined> => controller.getCameraPosition?.(),
      (): MaybePromise<CameraContainer | null | undefined> => controller.getPosition?.(),
      (): MaybePromise<CameraContainer | null | undefined> => controller.getMapStatus?.(),
      (): MaybePromise<CameraContainer | null | undefined> => controller.getCurrentPosition?.()
    ];
    let zoom: number | null = null;
    for (const candidate of cameraCandidates) {
      try {
        const result: CameraContainer | null | undefined = await this.maybeAwait(candidate());
        if (!result) {
          continue;
        }
        const z: number | undefined = result.zoom ?? result.position?.zoom ?? result.camera?.zoom;
        if (typeof z === 'number') {
          zoom = z;
          break;
        }
      } catch {
        // ignore
      }
    }
    if (zoom === null) {
      return null;
    }

    const regionCandidates: Array<() => MaybePromise<VisibleRegion | null | undefined>> = [
      (): MaybePromise<VisibleRegion | null | undefined> => controller.getVisibleRegion?.(),
      (): MaybePromise<VisibleRegion | null | undefined> => controller.getRegion?.(),
      (): MaybePromise<VisibleRegion | null | undefined> => controller.getVisibleArea?.()
    ];

    for (const candidate of regionCandidates) {
      try {
        const region: VisibleRegion | null | undefined = await this.maybeAwait(candidate());
        if (!region) {
          continue;
        }

        const southwest = region.southwest ?? region.southWest ?? region.bounds?.southwest ?? region.bounds?.southWest;
        const northeast = region.northeast ?? region.northEast ?? region.bounds?.northeast ?? region.bounds?.northEast;
        if (!southwest || !northeast) {
          continue;
        }

        const south: number = southwest.latitude;
        const west: number = southwest.longitude;
        const north: number = northeast.latitude;
        const east: number = northeast.longitude;
        if ([south, west, north, east].every((v: number): boolean => typeof v === 'number')) {
          const zInt: number = Math.floor(zoom);
          const range: TileRange = boundsToTileRange(zInt, north, south, west, east);
          return { zoom: zInt, range };
        }
      } catch {
        // ignore
      }
    }

    return null;
  }

  private estimateDownloadTextFromCurrentViewAscii(): string {
    if (this.detectedViewportZoom < 0 || this.detectedViewportTiles <= 0) {
      return '';
    }
    if (this.detectedViewportZoom < this.minZoomForOfflineDownload) {
      return `Zoom in (>= z${this.minZoomForOfflineDownload}); area is too large.`;
    }
    const kb: number = estimateDownloadKb(
      this.detectedViewportTiles,
      this.detectedViewportZoom,
      this.maxZoomForOfflineDownload,
      this.estimatedTileSizeKb
    );
    return `Est. download: ${formatKb(kb)} (z${this.detectedViewportZoom} -> z${this.maxZoomForOfflineDownload})`;
  }

  private getUpdate(): ViewportUpdate {
    return {
      detectedViewportZoom: this.detectedViewportZoom,
      detectedViewportTiles: this.detectedViewportTiles,
      estimatedDownloadText: this.estimatedDownloadText
    };
  }

  private async maybeAwait<T>(value: MaybePromise<T>): Promise<T> {
    return await Promise.resolve(value);
  }
}
