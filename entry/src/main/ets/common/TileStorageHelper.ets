import fs from '@ohos.file.fs';
import { OpenStreetMapAPI, TileServiceOutput } from './OpenStreetMapAPI';

export class TileRange {
  public xMin: number = 0;
  public xMax: number = 0;
  public yMin: number = 0;
  public yMax: number = 0;

  constructor(xMin: number, xMax: number, yMin: number, yMax: number) {
    this.xMin = xMin;
    this.xMax = xMax;
    this.yMin = yMin;
    this.yMax = yMax;
  }

  public doubleIt() {
    this.xMin *= 2;
    this.xMax = this.xMax * 2 + 1;
    this.yMin *= 2;
    this.yMax = this.yMax * 2 + 1;
  }
}

export class TileDownloader {
  private cancelled: boolean = false;
  private api: OpenStreetMapAPI = new OpenStreetMapAPI();

  cancel(): void {
    this.cancelled = true;
    try {
      this.api.destroy();
    } catch {
      // ignore
    }
  }

  async saveTile(
    rootDir: string,
    offlineAreaName: string,
    zoom: number,
    x: number,
    y: number
  ): Promise<void> {
    if (this.cancelled) {
      return;
    }

    const tile: TileServiceOutput = await this.api.downloadTile(zoom, x, y);
    if (this.cancelled) {
      return;
    }

    if (tile.success === true) {
      const areaDir = `${rootDir}/${offlineAreaName}`;
      const filePath: string = `${areaDir}/${zoom}/${x}/${y}.png`;
      await saveTileImage(filePath, tile.response);
    } else {
      // handle download problem
    }
  }
}

export function createTileDownloader(): TileDownloader {
  return new TileDownloader();
}

async function saveTileImage(
  filePath: string,
  data: Uint8Array
): Promise<void> {
  ensureDirSync(filePath.substring(0, filePath.lastIndexOf('/')));

  const file = fs.openSync(
    filePath,
    fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC
  );

  try {
    fs.writeSync(file.fd, data);
    console.info(`Tile saved to: ${filePath}`);
  } catch (error) {
    console.error(`Tile cannot save to ${filePath}`);
  } finally {
    fs.closeSync(file);
  }
}

export async function saveTile(
  rootDir: string,
  offlineAreaName: string,
  zoom: number,
  x: number,
  y: number
): Promise<void> {
  const downloader: TileDownloader = createTileDownloader();
  try {
    await downloader.saveTile(rootDir, offlineAreaName, zoom, x, y);
  } finally {
    downloader.cancel();
  }
}


function ensureDirSync(dirPath: string): void {
  const parts = dirPath.split('/');
  let current = '';

  for (const part of parts) {
    if (!part) {
      continue;
    }
    current += `/${part}`;
    try {
      fs.mkdirSync(current);
    } catch (e) {
      // Ignore if already exists
    }
  }
}
