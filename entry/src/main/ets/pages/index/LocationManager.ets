import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import geoLocationManager from '@ohos.geoLocationManager';

import { map, mapCommon } from '@kit.MapKit';

import {
  AbilityAccessManager,
  GeoLocation,
  GeoLocationError,
  MarkerLike,
  PermissionRequestResult,
  RemovableOverlay
} from './Types';

export interface LocationManagerCallbacks {
  getAbilityContext: () => object | null | undefined;
  toast: (message: string) => void;
  setLocationState: (location: GeoLocation) => void;
  setMarker: (marker: map.Marker | undefined) => void;
}

export class LocationManager {
  public async centerOnMyLocation(
    mapController: map.MapComponentController | undefined,
    callbacks: LocationManagerCallbacks
  ): Promise<void> {
    if (!mapController) {
      callbacks.toast('Map not ready.');
      return;
    }

    const granted: boolean = await this.requestLocationPermission(callbacks.getAbilityContext, callbacks.toast);
    if (!granted) {
      return;
    }

    const location: GeoLocation | null = await this.getCurrentLocation(5000, callbacks.toast);
    if (!location) {
      callbacks.toast('Unable to get current location.');
      return;
    }

    callbacks.setLocationState(location);

    const marker: map.Marker | undefined =
      await this.showMyLocationMarker(mapController, location.latitude, location.longitude);
    callbacks.setMarker(marker);
    await this.moveMapTo(mapController, location.latitude, location.longitude, 16);
  }

  public async showMyLocationMarker(
    mapController: map.MapComponentController,
    latitude: number,
    longitude: number
  ): Promise<map.Marker | undefined> {
    const markerOptions: mapCommon.MarkerOptions = {
      position: { latitude, longitude },
      rotation: 0,
      visible: true,
      zIndex: 100,
      alpha: 1,
      anchorU: 0.5,
      anchorV: 1,
      clickable: false,
      draggable: false,
      flat: false
    };

    try {
      const marker: map.Marker = await mapController.addMarker(markerOptions);
      (marker as MarkerLike | undefined)?.setAnnotationVisible?.(false);
      return marker;
    } catch (e) {
      console.error('Failed to create my-location marker', e);
      return undefined;
    }
  }

  public removeMarker(marker: map.Marker | undefined): void {
    if (!marker) {
      return;
    }
    try {
      (marker as RemovableOverlay | undefined)?.remove?.();
    } catch {
      // ignore
    }
  }

  private async requestLocationPermission(
    getAbilityContext: () => object | null | undefined,
    toast: (message: string) => void
  ): Promise<boolean> {
    const context = getAbilityContext();
    if (!context) {
      toast('No ability context.');
      return false;
    }

    try {
      const atManager: AbilityAccessManager = (abilityAccessCtrl.createAtManager() as AbilityAccessManager);
      const result: PermissionRequestResult = await atManager.requestPermissionsFromUser(context, [
        'ohos.permission.LOCATION'
      ]);
      const granted: boolean = result.authResults.every((v: number): boolean => v === 0);
      if (!granted) {
        toast('Location permission denied.');
      }
      return granted;
    } catch (e) {
      console.error('requestPermissionsFromUser failed', e);
      toast('Failed to request location permission.');
      return false;
    }
  }

  private async getCurrentLocation(timeoutMs: number, toast: (message: string) => void): Promise<GeoLocation | null> {
    try {
      if (typeof geoLocationManager.isLocationEnabled === 'function' && !geoLocationManager.isLocationEnabled()) {
        toast('Location services are off.');
        return null;
      }
    } catch {
      // ignore
    }

    return await Promise.race([
      new Promise<GeoLocation | null>((resolve: (value: GeoLocation | null) => void): void => {
        try {
          if (typeof geoLocationManager.getCurrentLocation === 'function') {
            geoLocationManager.getCurrentLocation((err: GeoLocationError | null, location: GeoLocation | null) => {
              if (err) {
                console.error(`getCurrentLocation failed: ${err.code} ${err.message}`);
                resolve(null);
                return;
              }
              resolve(location);
            });
            return;
          }
        } catch (e) {
          console.error('getCurrentLocation call failed', e);
        }
        resolve(null);
      }),
      this.delay(timeoutMs).then((): GeoLocation | null => null)
    ]);
  }

  private async moveMapTo(
    mapController: map.MapComponentController,
    latitude: number,
    longitude: number,
    zoom: number
  ): Promise<void> {
    const target: mapCommon.LatLng = { latitude, longitude };

    const cameraPosition: mapCommon.CameraPosition = {
      target: target,
      zoom: zoom
    };

    const cameraUpdate: map.CameraUpdate = map.newCameraPosition(cameraPosition);
    mapController.animateCamera(cameraUpdate, 1000);
  }

  private delay(ms: number): Promise<void> {
    return new Promise((resolve: () => void): void => {
      setTimeout(resolve, ms);
    });
  }
}

