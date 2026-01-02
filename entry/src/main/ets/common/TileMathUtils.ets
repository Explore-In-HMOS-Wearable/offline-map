import { TileRange } from './TileStorageHelper';

export function normalizeLongitude(longitude: number): number {
  let normalized = longitude;
  while (normalized < -180) {
    normalized += 360;
  }
  while (normalized >= 180) {
    normalized -= 360;
  }
  return normalized;
}

export function clampLatitude(latitude: number): number {
  return Math.max(-85.05112878, Math.min(85.05112878, latitude));
}

export function boundsToTileRange(
  zoom: number,
  north: number,
  south: number,
  west: number,
  east: number
): TileRange {
  const z = Math.max(0, Math.floor(zoom));
  const n = Math.pow(2, z);

  const xFromLon = (lon: number): number => Math.floor((normalizeLongitude(lon) + 180) / 360 * n);
  const yFromLat = (lat: number): number => {
    const clampedLat = clampLatitude(lat);
    const latRad = clampedLat * Math.PI / 180;
    const y = (1 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI) / 2 * n;
    return Math.floor(y);
  };

  let xMin = xFromLon(west);
  let xMax = xFromLon(east);
  const yMin = yFromLat(north);
  const yMax = yFromLat(south);

  xMin = Math.max(0, Math.min(n - 1, xMin));
  xMax = Math.max(0, Math.min(n - 1, xMax));

  const yyMin = Math.max(0, Math.min(n - 1, Math.min(yMin, yMax)));
  const yyMax = Math.max(0, Math.min(n - 1, Math.max(yMin, yMax)));

  if (xMax < xMin) {
    return new TileRange(0, n - 1, yyMin, yyMax);
  }
  return new TileRange(xMin, xMax, yyMin, yyMax);
}

export function estimateDownloadKb(
  baseTileCount: number,
  zoomMin: number,
  zoomMax: number,
  estimatedTileSizeKb: number
): number {
  if (baseTileCount <= 0) {
    return 0;
  }
  if (zoomMax < zoomMin) {
    return 0;
  }

  const levels: number = zoomMax - zoomMin;
  let totalTiles: number = 0;
  let multiplier: number = 1;
  for (let i = 0; i <= levels; i++) {
    totalTiles += baseTileCount * multiplier;
    multiplier *= 4;
  }
  return totalTiles * estimatedTileSizeKb;
}

export function formatKb(kb: number): string {
  if (!Number.isFinite(kb) || kb <= 0) {
    return '0 KB';
  }
  if (kb >= 1024 * 1024) {
    return `${(kb / (1024 * 1024)).toFixed(2)} GB`;
  }
  if (kb >= 1024) {
    return `${(kb / 1024).toFixed(1)} MB`;
  }
  return `${Math.round(kb)} KB`;
}
