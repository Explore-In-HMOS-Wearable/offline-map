import connection from '@ohos.net.connection';

import { createTileDownloader, TileDownloader, TileRange } from '../../common/TileStorageHelper';

export interface DownloadJob {
  rootDir: string;
  offlineAreaName: string;
  zoomMin: number;
  zoomMax: number;
  range: TileRange;
}

export interface DownloadManagerCallbacks {
  onProgress: (progress: number) => void;
  onDownloadingChanged: (isDownloading: boolean) => void;
  toast: (message: string) => void;
  onJobCompleted: () => void;
}

interface DownloadController {
  cancelled: boolean;
  downloader: TileDownloader;
  cancel: () => void;
}

interface NetCapCompat {
  bearerTypes?: number[];
}

interface NetCapabilityInfoCompat {
  netCap?: NetCapCompat;
  bearerTypes?: number[];
}

type NetCapabilitiesChangeCallback = (netCap: connection.NetCapabilityInfo) => void;

export class DownloadManager {
  private maxConcurrent: number;
  private tileDownloadTimeoutMs: number;
  private callbacks: DownloadManagerCallbacks;

  private netConnection?: connection.NetConnection;
  private defaultBearerTypesKey: string = '';
  private networkRestartInProgress: boolean = false;

  private activeDownloadController: DownloadController | null = null;
  private activeDownloadJob: DownloadJob | null = null;

  private onNetCapabilitiesChange: NetCapabilitiesChangeCallback = (netCap: connection.NetCapabilityInfo): void => {
    const netCapCompat: NetCapabilityInfoCompat = netCap as NetCapabilityInfoCompat;
    const bearers: number[] | undefined = netCapCompat.netCap?.bearerTypes ?? netCapCompat.bearerTypes;

    const nextKey: string = this.bearerTypesKey(bearers);
    if (nextKey === this.defaultBearerTypesKey) {
      return;
    }

    this.defaultBearerTypesKey = nextKey;
    this.onDefaultNetworkChanged();
  };

  constructor(maxConcurrent: number, tileDownloadTimeoutMs: number, callbacks: DownloadManagerCallbacks) {
    this.maxConcurrent = maxConcurrent;
    this.tileDownloadTimeoutMs = tileDownloadTimeoutMs;
    this.callbacks = callbacks;
  }

  startDefaultNetworkListener(): void {
    try {
      const defaultNet = connection.getDefaultNetSync();
      const netCapabilities = connection.getNetCapabilitiesSync(defaultNet);
      this.defaultBearerTypesKey = this.bearerTypesKey(netCapabilities.bearerTypes);

      this.netConnection = connection.createNetConnection();
      this.netConnection.on('netCapabilitiesChange', this.onNetCapabilitiesChange);
    } catch (e) {
      console.warn('Failed to start default network listener', e);
    }
  }

  stopDefaultNetworkListener(): void {
    const netConnection: connection.NetConnection | undefined = this.netConnection;
    this.netConnection = undefined;

    try {
      netConnection?.unregister((err: object | null, _data?: void): void => {
        if (err) {
          console.warn('netConnection.unregister failed', err);
        }
      });
    } catch {
      // ignore
    }
  }

  cancelActiveDownload(): void {
    const controller: DownloadController | null = this.activeDownloadController;
    if (!controller) {
      return;
    }
    controller.cancel();
  }

  async startJob(job: DownloadJob): Promise<void> {
    this.activeDownloadJob = job;
    await this.runDownloadJob(job);
  }

  private onDefaultNetworkChanged(): void {
    if (!this.activeDownloadController || !this.activeDownloadJob) {
      return;
    }

    if (this.networkRestartInProgress) {
      return;
    }

    void this.restartDownloadForNetworkChange();
  }

  private async restartDownloadForNetworkChange(): Promise<void> {
    if (!this.activeDownloadJob) {
      return;
    }

    this.networkRestartInProgress = true;
    try {
      this.callbacks.toast('Network changed. Restarting downloads...');
      const job: DownloadJob = this.activeDownloadJob;
      this.cancelActiveDownload();
      await this.delay(200);
      await this.runDownloadJob(job);
    } finally {
      this.networkRestartInProgress = false;
    }
  }

  private async runDownloadJob(job: DownloadJob): Promise<void> {
    this.cancelActiveDownload();

    const downloader: TileDownloader = createTileDownloader();
    const controller: DownloadController = {
      cancelled: false,
      downloader,
      cancel: (): void => {
        if (controller.cancelled) {
          return;
        }
        controller.cancelled = true;
        controller.downloader.cancel();
      }
    };

    this.activeDownloadController = controller;
    this.callbacks.onProgress(0);
    this.callbacks.onDownloadingChanged(true);

    try {
      await this.downloadArea(job, controller);
      if (!controller.cancelled) {
        this.callbacks.onJobCompleted();
      }
    } finally {
      controller.cancel();
      if (this.activeDownloadController === controller) {
        this.activeDownloadController = null;
        this.callbacks.onDownloadingChanged(false);
      }
    }
  }

  private async downloadArea(job: DownloadJob, controller: DownloadController): Promise<void> {
    let tileRange = new TileRange(
      job.range.xMin,
      job.range.xMax,
      job.range.yMin,
      job.range.yMax
    );

    let totalTiles = 0;
    let tempRange = new TileRange(
      tileRange.xMin,
      tileRange.xMax,
      tileRange.yMin,
      tileRange.yMax
    );

    for (let z = job.zoomMin; z <= job.zoomMax; z++) {
      totalTiles +=
      (tempRange.xMax - tempRange.xMin + 1) *
        (tempRange.yMax - tempRange.yMin + 1);

      tempRange = new TileRange(
        tempRange.xMin * 2,
        tempRange.xMax * 2 + 1,
        tempRange.yMin * 2,
        tempRange.yMax * 2 + 1
      );
    }

    if (totalTiles <= 0) {
      this.callbacks.onProgress(0);
      this.callbacks.toast('Nothing to download for the current view.');
      return;
    }

    let downloadedTiles = 0;
    const queue: Promise<void>[] = [];
    let latestProgress: number = 0;
    let lastProgressPushed: number = -1;
    let progressTimerId: number = -1;

    try {
      progressTimerId = setInterval((): void => {
        if (controller.cancelled) {
          return;
        }
        if (latestProgress === lastProgressPushed) {
          return;
        }
        lastProgressPushed = latestProgress;
        this.callbacks.onProgress(latestProgress);
      }, 200) as number;

      for (let z = job.zoomMin; z <= job.zoomMax; z++) {
        for (let x = tileRange.xMin; x <= tileRange.xMax; x++) {
          for (let y = tileRange.yMin; y <= tileRange.yMax; y++) {
            if (controller.cancelled) {
              await Promise.allSettled(queue);
              return;
            }

            queue.push(this.saveTileBestEffort(controller, job.rootDir, job.offlineAreaName, z, x, y)
              .finally((): void => {
                downloadedTiles++;
                latestProgress = downloadedTiles / totalTiles * 100;
              }));

            if (queue.length >= this.maxConcurrent) {
              await Promise.all(queue);
              queue.length = 0;
              if (controller.cancelled) {
                return;
              }
            }
          }
        }

        tileRange = new TileRange(
          tileRange.xMin * 2,
          tileRange.xMax * 2 + 1,
          tileRange.yMin * 2,
          tileRange.yMax * 2 + 1
        );
      }

      if (queue.length > 0) {
        await Promise.all(queue);
      }
    } finally {
      if (progressTimerId !== -1) {
        clearInterval(progressTimerId);
      }
      this.callbacks.onProgress(latestProgress);
    }
  }

  private async saveTileBestEffort(
    controller: DownloadController,
    rootDir: string,
    offlineAreaName: string,
    zoom: number,
    x: number,
    y: number
  ): Promise<void> {
    if (controller.cancelled) {
      return;
    }
    try {
      await Promise.race([
        controller.downloader.saveTile(rootDir, offlineAreaName, zoom, x, y),
        this.delay(this.tileDownloadTimeoutMs)
      ]);
    } catch (e) {
      console.warn('Tile download failed', e);
    }
  }

  private bearerTypesKey(bearerTypes: number[] | undefined): string {
    if (!Array.isArray(bearerTypes) || bearerTypes.length === 0) {
      return '';
    }
    return bearerTypes.slice().sort().join(',');
  }

  private delay(ms: number): Promise<void> {
    return new Promise((resolve: () => void): void => {
      setTimeout(resolve, ms);
    });
  }
}
