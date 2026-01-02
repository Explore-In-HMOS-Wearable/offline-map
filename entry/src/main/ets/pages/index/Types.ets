import { TileRange } from '../../common/TileStorageHelper';

export interface ToastOptions {
  message: string;
}

export interface ZoomAndRange {
  zoom: number;
  range: TileRange;
}

export interface MapInitError {
  code: number;
  message: string;
}

export interface ViewportTileStats {
  zoom: number;
  xMin: number;
  xMax: number;
  yMin: number;
  yMax: number;
  updatedAtMs: number;
}

export interface RemovableOverlay {
  remove?: () => void;
}

export interface TileOverlayLike extends RemovableOverlay {
  clearTileCache?: () => void;
  setVisible?: (visible: boolean) => void;
}

export interface PermissionRequestResult {
  authResults: number[];
  permissions: string[];
}

export interface AbilityAccessManager {
  requestPermissionsFromUser: (context: object, permissions: string[]) => Promise<PermissionRequestResult>;
}

export interface GeoLocation {
  latitude: number;
  longitude: number;
}

export interface GeoLocationError {
  code: number;
  message: string;
}

export interface MarkerLike extends RemovableOverlay {
  setAnnotationVisible?: (visible: boolean) => void;
}

export interface LatLng {
  latitude: number;
  longitude: number;
}

export interface CameraContainer {
  zoom?: number;
  target?: LatLng;
  position?: CameraContainer;
  camera?: CameraContainer;
  center?: LatLng;
}

export interface VisibleBounds {
  southwest?: LatLng;
  southWest?: LatLng;
  northeast?: LatLng;
  northEast?: LatLng;
}

export interface VisibleRegion {
  southwest?: LatLng;
  southWest?: LatLng;
  northeast?: LatLng;
  northEast?: LatLng;
  bounds?: VisibleBounds;
}

export type MaybePromise<T> = T | Promise<T>;

export interface MapControllerCompat {
  getCameraPosition?: () => MaybePromise<CameraContainer | null | undefined>;
  getPosition?: () => MaybePromise<CameraContainer | null | undefined>;
  getMapStatus?: () => MaybePromise<CameraContainer | null | undefined>;
  getCurrentPosition?: () => MaybePromise<CameraContainer | null | undefined>;
  getVisibleRegion?: () => MaybePromise<VisibleRegion | null | undefined>;
  getRegion?: () => MaybePromise<VisibleRegion | null | undefined>;
  getVisibleArea?: () => MaybePromise<VisibleRegion | null | undefined>;
}

