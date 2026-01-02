import { displayNameFromDir } from '../../common/OfflineMapUtils';

export interface OfflineMapViewCallbacks {
  onRefreshOfflineMaps: () => void;
  onCenterOnMyLocation: () => Promise<void>;
  onUseOfflineMap: (dirName: string) => void;
  onStartOfflineDownload: (offlineName: string) => Promise<void>;
  onDeleteOfflineMapDir: (dirName: string) => Promise<void>;
}

@Component
export struct OfflineMapView {
  @Prop offlineMapPrefix: string = 'offline_map_';

  @Link progress: number;
  @Link isDownloading: boolean;
  @Link isMenuOpen: boolean;
  @Link showOfflineNameDialog: boolean;
  @Link showDeleteDialog: boolean;
  @Link offlineNameInput: string;
  @Link activeOfflineAreaName: string;
  @Link offlineMapDirs: string[];
  @Link pendingDeleteDirName: string;
  @Link detectedViewportZoom: number;
  @Link detectedViewportTiles: number;
  @Link estimatedDownloadText: string;

  onRefreshOfflineMaps: () => void = (): void => {};
  onCenterOnMyLocation: () => Promise<void> = async (): Promise<void> => {};
  onUseOfflineMap: (dirName: string) => void = (_dirName: string): void => {};
  onStartOfflineDownload: (offlineName: string) => Promise<void> = async (_offlineName: string): Promise<void> => {};
  onDeleteOfflineMapDir: (dirName: string) => Promise<void> = async (_dirName: string): Promise<void> => {};

  build() {
    Stack() {
      Column() {
        Row() {
          Button(this.isMenuOpen ? 'Close' : 'Offline Maps')
            .onClick((): void => {
              this.isMenuOpen = !this.isMenuOpen;
              if (this.isMenuOpen) {
                this.onRefreshOfflineMaps();
              }
            })
            .fontSize(12)
            .margin({ right: 4 });

          Button('📍')
            .fontSize(12)
            .onClick(async (): Promise<void> => {
              await this.onCenterOnMyLocation();
            });
        }.justifyContent(FlexAlign.Start);

        if (this.isMenuOpen) {
          Column() {
            Scroll() {
              Column() {
                Text(`Active: ${displayNameFromDir(this.activeOfflineAreaName, this.offlineMapPrefix)}`)
                  .fontSize(12)
                  .fontColor(Color.Black)
                  .margin({ bottom: 3 });

                Text(this.detectedViewportZoom >= 0 ?
                  `Current view: z${this.detectedViewportZoom} (~${this.detectedViewportTiles} tiles)` :
                  'Current view: detecting...')
                  .fontSize(12)
                  .fontColor(Color.Black)
                  .margin({ bottom: 4 });

                if (this.estimatedDownloadText) {
                  Text(this.estimatedDownloadText)
                    .fontSize(11)
                    .fontColor(Color.Black)
                    .margin({ bottom: 4 });
                }

                Text(`Download Progress: ${this.progress.toFixed(1)}%`)
                  .fontSize(12)
                  .fontColor(Color.Black)
                  .margin({ bottom: 4 });

                Button(this.isDownloading ? 'Downloading...' : 'Download Current View')
                  .fontSize(12)
                  .enabled(!this.isDownloading)
                  .onClick((): void => {
                    this.offlineNameInput = displayNameFromDir(this.activeOfflineAreaName, this.offlineMapPrefix);
                    this.showOfflineNameDialog = true;
                  })
                  .margin({ bottom: 5 });

                Text('Downloaded offline maps')
                  .fontSize(12)
                  .fontColor(Color.Black)
                  .margin({ bottom: 3 });

                if (this.offlineMapDirs.length === 0) {
                  Text('No offline maps yet.')
                    .fontColor(Color.Black)
                    .fontSize(12);
                } else {
                  Column() {
                    ForEach(this.offlineMapDirs, (dirName: string) => {
                      Row() {
                        Text(displayNameFromDir(dirName, this.offlineMapPrefix))
                          .fontColor(Color.Black)
                          .fontSize(12)
                          .layoutWeight(1);
                        Button('Use')
                          .fontSize(12)
                          .onClick((): void => {
                            this.onUseOfflineMap(dirName);
                          });
                        Button('Remove')
                          .fontSize(12)
                          .onClick((): void => {
                            this.pendingDeleteDirName = dirName;
                            this.showDeleteDialog = true;
                          })
                          .margin({ left: 8 });
                      }
                      .padding({ top: 6, bottom: 6 });
                    }, (dirName: string) => dirName);
                  };
                }
              }
            }
            .width('100%')
            .height(120)
            .scrollBar(BarState.Auto);
          }
          .margin({ top: 10 });
        }
      }
      .padding(6)
      .backgroundColor('#CCFFFFFF')
      .borderRadius(12)
      .margin({ top: 12, left: 12, right: 12 })
      .zIndex(2);

      if (this.showOfflineNameDialog) {
        Stack() {
          Column() {
            Text('Save offline map')
              .fontColor(Color.Black)
              .fontSize(14)
              .margin({ bottom: 4 });

            TextInput({ placeholder: 'Offline map name', text: this.offlineNameInput })
              .onChange((value: string): void => {
                this.offlineNameInput = value;
              })
              .margin({ bottom: 6 });

            Row() {
              Button('Cancel')
                .onClick((): void => {
                  this.showOfflineNameDialog = false;
                })
                .fontSize(12)
                .margin({ right: 4 });

              Button(this.isDownloading ? 'Downloading...' : 'Download')
                .enabled(!this.isDownloading)
                .fontSize(12)
                .onClick(async (): Promise<void> => {
                  this.showOfflineNameDialog = false;
                  await this.onStartOfflineDownload(this.offlineNameInput);
                });
            }.justifyContent(FlexAlign.End);
          }
          .padding(8)
          .backgroundColor(Color.White)
          .borderRadius(12)
          .width('80%')
          .align(Alignment.Center);
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .zIndex(3);
      }

      if (this.showDeleteDialog) {
        Stack() {
          Column() {
            Text('Remove offline map?')
              .fontSize(18)
              .margin({ bottom: 8 });

            Text(`This will delete folder: ${this.pendingDeleteDirName}`)
              .fontSize(12)
              .fontColor(Color.Black)
              .margin({ bottom: 12 });

            Row() {
              Button('Cancel')
                .onClick((): void => {
                  this.showDeleteDialog = false;
                  this.pendingDeleteDirName = '';
                })
                .margin({ right: 8 });

              Button('Delete')
                .onClick(async (): Promise<void> => {
                  const dirName: string = this.pendingDeleteDirName;
                  this.showDeleteDialog = false;
                  this.pendingDeleteDirName = '';
                  await this.onDeleteOfflineMapDir(dirName);
                });
            }.justifyContent(FlexAlign.End);
          }
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(12)
          .width('90%')
          .align(Alignment.Center);
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .zIndex(3);
      }
    }
    .position({ y: 4 });
  }
}
