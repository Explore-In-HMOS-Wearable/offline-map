import http from '@ohos.net.http';

export class TileServiceOutput {
  public success: boolean = false;
  public response: Uint8Array = new Uint8Array(0);

  public constructor(success: boolean, response: Uint8Array) {
    this.success = success
    this.response = response
  }
}

export class OpenStreetMapAPI {
  private httpRequest = http.createHttp();

  async downloadTile(
    zoom: number,
    x: number,
    y: number
  ): Promise<TileServiceOutput> {

    const url = `https://tile.openstreetmap.org/${zoom}/${x}/${y}.png`;

    try {
      const response = await this.httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 15000,
        header: {
          'Accept': 'image/png',
          'User-Agent': 'MyArkUIApp/1.0'
        }
      });

      if (response.resultType !== http.HttpDataType.ARRAY_BUFFER) {
        console.error('Unexpected resultType:', response.resultType);
        return new TileServiceOutput(false, new Uint8Array());
      }

      return new TileServiceOutput(true, response.result as Uint8Array);
    } catch (error) {
      console.error('(getTile) Request failed:', error);
      return new TileServiceOutput(false, new Uint8Array());
    }
  }

  destroy() {
    this.httpRequest.destroy();
  }
}