import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { errText } from '../common/Util';
import { FloatWindowManager } from '../service/FloatWindowManager';
import { SettingsStore } from '../service/SettingsStore';

const TAG: string = 'AiTranslator';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    SettingsStore.init(this.context);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'loadContent failed: %{public}s', errText(err));
      }
    });
  }

  onDestroy(): void {
    FloatWindowManager.close();
  }
}
