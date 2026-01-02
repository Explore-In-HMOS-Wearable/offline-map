import { AbilityConstant, ConfigurationConstant, UIAbility, Want, abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import prompt from '@system.prompt';


const permissions: Array<Permissions> = ['ohos.permission.LOCATION', 'ohos.permission.APPROXIMATELY_LOCATION'];

// Use UIExtensionAbility: Replace common.UIAbilityContext with common.UIExtensionContext.
function reqPermissionsFromUser(permissions: Array<Permissions>, context: common.UIAbilityContext): void {

  const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
  // The return value of requestPermissionsFromUser determines
  // whether to display a dialog box to request user authorization.
  atManager.requestPermissionsFromUser(context, permissions).then((data) => {
    const grantStatus: Array<number> = data.authResults;
    const length: number = grantStatus.length;
    for (let i = 0; i < length; i++) {
      if (grantStatus[i] !== 0) {
        prompt.showToast({
          message: 'Location permission is required to show current location. ' +
            'Please enable it in Settings > App permissions.'
        });
        return;
      }
    }
  }).catch((err: BusinessError) => {
    console.error(`Failed to request permissions from user. Code is ${err.code}, message is ${err.message}`);
  })
}

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      reqPermissionsFromUser(permissions, this.context);
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}