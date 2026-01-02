import promptAction from '@ohos.promptAction';

import { mapCommon, map, MapComponent } from '@kit.MapKit';
import { AsyncCallback } from '@kit.BasicServicesKit';

import {
  deletePathRecursive,
  dirExists,
  displayNameFromDir,
  listOfflineMapDirs,
  sanitizeOfflineAreaName
} from '../common/OfflineMapUtils';
import { estimateDownloadKb, formatKb } from '../common/TileMathUtils';

import { DownloadJob, DownloadManager } from './index/DownloadManager';
import { LocationManager } from './index/LocationManager';
import { OfflineMapView } from './index/OfflineMapView';
import { TileOverlayManager } from './index/TileOverlayManager';
import { ViewportTracker, ViewportUpdate } from './index/ViewportTracker';
import { MapControllerCompat, MapInitError, ToastOptions, ZoomAndRange } from './index/Types';

interface HostContextCompat {
  filesDir?: string;
}

@Entry
@Component
struct OfflineMapDemo {
  private minZoomForOfflineDownload: number = 13;
  private maxZoomForOfflineDownload: number = 18;
  private tileDownloadTimeoutMs: number = 15000;
  private estimatedTileSizeKb: number = 20;
  private offlineMapPrefix: string = 'offline_map_';
  private mapOption?: mapCommon.MapOptions;
  private mapController?: map.MapComponentController;
  private callback?: AsyncCallback<map.MapComponentController>;
  private tileOverlay?: map.TileOverlay;
  private myLocationMarker?: map.Marker;
  @State progress: number = 0;
  @State isDownloading: boolean = false;
  @State isMenuOpen: boolean = false;
  @State showOfflineNameDialog: boolean = false;
  @State showDeleteDialog: boolean = false;
  @State offlineNameInput: string = '';
  @State activeOfflineAreaName: string = 'offline_map_default';
  @State offlineMapDirs: string[] = [];
  @State pendingDeleteDirName: string = '';
  @State detectedViewportZoom: number = -1;
  @State detectedViewportTiles: number = 0;
  @State hasMyLocation: boolean = false;
  @State myLocationLat: number = 0;
  @State myLocationLon: number = 0;
  @State estimatedDownloadText: string = '';
  private MAX_CONCURRENT: number = 4;
  private viewportTracker?: ViewportTracker;
  private tileOverlayManager?: TileOverlayManager;
  private locationManager: LocationManager = new LocationManager();
  private downloadManager?: DownloadManager;

  aboutToAppear(): void {
    this.viewportTracker = new ViewportTracker(
      this.minZoomForOfflineDownload,
      this.maxZoomForOfflineDownload,
      this.estimatedTileSizeKb
    );

    this.tileOverlayManager = new TileOverlayManager(this.viewportTracker, {
      getRootDir: (): string | null | undefined => this.getFilesDir(),
      getActiveOfflineAreaName: (): string => this.activeOfflineAreaName,
      onViewportUpdate: (update: ViewportUpdate): void => {
        this.detectedViewportZoom = update.detectedViewportZoom;
        this.detectedViewportTiles = update.detectedViewportTiles;
        this.estimatedDownloadText = update.estimatedDownloadText;
      }
    });

    this.downloadManager = new DownloadManager(this.MAX_CONCURRENT, this.tileDownloadTimeoutMs, {
      onProgress: (progress: number): void => {
        this.progress = progress;
      },
      onDownloadingChanged: (isDownloading: boolean): void => {
        this.isDownloading = isDownloading;
      },
      toast: (message: string): void => {
        this.toast(message);
      },
      onJobCompleted: (): void => {
        this.refreshOfflineMaps();
      }
    });
    this.downloadManager.startDefaultNetworkListener();

    this.mapOption = {
      mapType: 0,
      position: {
        target: { latitude: 31.98, longitude: 118.7 },
        zoom: 7
      },
      scaleControlsEnabled: true,
      maxZoom: this.maxZoomForOfflineDownload
    };

    this.callback =
      async (err: MapInitError | null | undefined, controller: map.MapComponentController): Promise<void> => {
        if (err) {
          console.error(`Map init failed: ${err.code} ${err.message}`);
          return;
        }

        this.mapController = controller;
        this.resetTileOverlay();

        if (this.hasMyLocation) {
          this.locationManager.removeMarker(this.myLocationMarker);
          this.myLocationMarker = await this.locationManager.showMyLocationMarker(
            controller,
            this.myLocationLat,
            this.myLocationLon
          );
        }
      };

    this.refreshOfflineMaps();
  }

  aboutToDisappear(): void {
    this.downloadManager?.stopDefaultNetworkListener();
    this.downloadManager?.cancelActiveDownload();
    this.locationManager.removeMarker(this.myLocationMarker);
  }

  private getFilesDir(): string | null {
    const host: HostContextCompat | null | undefined =
      this.getUIContext().getHostContext() as HostContextCompat | null | undefined;
    return host?.filesDir ?? null;
  }

  private resetTileOverlay(): void {
    if (!this.tileOverlayManager) {
      return;
    }

    this.tileOverlay = this.tileOverlayManager.resetTileOverlay(this.mapController, this.tileOverlay);
  }

  private async centerOnMyLocation(): Promise<void> {
    await this.locationManager.centerOnMyLocation(this.mapController, {
      getAbilityContext: (): object | null | undefined => this.getUIContext()
        .getHostContext() as object | null | undefined,
      toast: (message: string): void => this.toast(message),
      setLocationState: (location): void => {
        this.hasMyLocation = true;
        this.myLocationLat = location.latitude;
        this.myLocationLon = location.longitude;
      },
      setMarker: (marker: map.Marker | undefined): void => {
        this.locationManager.removeMarker(this.myLocationMarker);
        this.myLocationMarker = marker;
      }
    });
  }

  private refreshOfflineMaps(): void {
    const rootDir: string | null = this.getFilesDir();
    if (!rootDir) {
      this.offlineMapDirs = [];
      return;
    }
    this.offlineMapDirs = listOfflineMapDirs(rootDir, this.offlineMapPrefix);
  }

  private dirNameFromDisplayName(name: string): string {
    return `${this.offlineMapPrefix}${name}`;
  }

  private async deleteOfflineMapDir(dirName: string): Promise<void> {
    if (!dirName || !dirName.startsWith(this.offlineMapPrefix)) {
      this.toast('Invalid offline map folder.');
      return;
    }

    if (this.isDownloading) {
      this.toast('Stop downloading before deleting.');
      return;
    }

    const rootDir: string | null = this.getFilesDir();
    if (!rootDir) {
      this.toast('Cannot access app storage.');
      return;
    }

    const fullPath: string = `${rootDir}/${dirName}`;
    if (!dirExists(fullPath)) {
      this.refreshOfflineMaps();
      return;
    }

    if (this.activeOfflineAreaName === dirName) {
      this.activeOfflineAreaName = 'offline_map_default';
      this.resetTileOverlay();
    }

    try {
      deletePathRecursive(fullPath);
      this.refreshOfflineMaps();
      if (dirExists(fullPath)) {
        this.toast('Delete failed (folder still exists).');
        return;
      }
      this.resetTileOverlay();
      this.toast(`Deleted ${displayNameFromDir(dirName, this.offlineMapPrefix)}`);
    } catch {
      this.toast('Delete failed.');
    }
  }

  private toast(message: string): void {
    try {
      const options: ToastOptions = { message };
      promptAction.openToast(options);
    } catch {
      console.warn(message);
    }
  }

  private async startOfflineDownload(offlineAreaName: string): Promise<void> {
    if (this.isDownloading) {
      return;
    }

    const downloadManager: DownloadManager | undefined = this.downloadManager;
    const viewportTracker: ViewportTracker | undefined = this.viewportTracker;
    if (!downloadManager || !viewportTracker) {
      this.toast('Download subsystem not ready yet.');
      return;
    }

    const rootDir: string | null = this.getFilesDir();
    if (!rootDir) {
      this.toast('Cannot access app storage.');
      return;
    }

    let overlayView: ZoomAndRange | null = viewportTracker.getOverlayViewportTileRange();
    if (!overlayView) {
      overlayView =
        await viewportTracker.getControllerViewportTileRange(this.mapController as MapControllerCompat | undefined);
    }
    if (!overlayView) {
      this.toast('Map view not detected yet. Pan or zoom once, then try again.');
      return;
    }

    if (overlayView.zoom < this.minZoomForOfflineDownload) {
      this.toast(`Zoom in to at least ${this.minZoomForOfflineDownload} to download offline tiles.`);
      return;
    }

    if (overlayView.zoom > this.maxZoomForOfflineDownload) {
      this.toast(`Zoom out to at most ${this.maxZoomForOfflineDownload} for offline download.`);
      return;
    }

    const safeName: string = sanitizeOfflineAreaName(offlineAreaName);
    if (!safeName) {
      this.toast('Please enter a valid offline map name.');
      return;
    }

    const displayName: string = safeName.startsWith(this.offlineMapPrefix) ?
      safeName.slice(this.offlineMapPrefix.length) :
      safeName;
    const folderName: string = this.dirNameFromDisplayName(displayName);
    this.activeOfflineAreaName = folderName;
    this.progress = 0;

    const baseTileCount: number =
      (overlayView.range.xMax - overlayView.range.xMin + 1) *
        (overlayView.range.yMax - overlayView.range.yMin + 1);
    const estimatedKb: number = estimateDownloadKb(
      baseTileCount,
      overlayView.zoom,
      this.maxZoomForOfflineDownload,
      this.estimatedTileSizeKb
    );
    if (estimatedKb > 0) {
      this.toast(`Estimated download size: ${formatKb(estimatedKb)}`);
    }

    const job: DownloadJob = {
      rootDir,
      offlineAreaName: folderName,
      zoomMin: overlayView.zoom,
      zoomMax: this.maxZoomForOfflineDownload,
      range: overlayView.range
    };

    await downloadManager.startJob(job);
  }

  build() {
    Stack() {
      MapComponent({
        mapOptions: this.mapOption,
        mapCallback: this.callback
      })
        .width('100%')
        .height('100%');

      OfflineMapView({
        offlineMapPrefix: this.offlineMapPrefix,
        progress: $progress,
        isDownloading: $isDownloading,
        isMenuOpen: $isMenuOpen,
        showOfflineNameDialog: $showOfflineNameDialog,
        showDeleteDialog: $showDeleteDialog,
        offlineNameInput: $offlineNameInput,
        activeOfflineAreaName: $activeOfflineAreaName,
        offlineMapDirs: $offlineMapDirs,
        pendingDeleteDirName: $pendingDeleteDirName,
        detectedViewportZoom: $detectedViewportZoom,
        detectedViewportTiles: $detectedViewportTiles,
        estimatedDownloadText: $estimatedDownloadText,
        onRefreshOfflineMaps: (): void => this.refreshOfflineMaps(),
        onCenterOnMyLocation: async (): Promise<void> => await this.centerOnMyLocation(),
        onUseOfflineMap: (dirName: string): void => {
          this.activeOfflineAreaName = dirName;
          this.resetTileOverlay();
          this.toast(`Switched to ${displayNameFromDir(dirName, this.offlineMapPrefix)}`);
        },
        onStartOfflineDownload: async (name: string): Promise<void> => await this.startOfflineDownload(name),
        onDeleteOfflineMapDir: async (dirName: string): Promise<void> => await this.deleteOfflineMapDir(dirName)
      });
    }
    .width('100%')
    .height('100%');
  }
}
