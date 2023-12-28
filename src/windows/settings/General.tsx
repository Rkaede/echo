import { Checkbox } from '~/components/ui/checkbox';
import { Label } from '~/components/ui/label';
import { ReactNode, useEffect, useState } from 'react';
import { Textarea } from '~/components/ui/textarea';
import { SettingTitle } from './components/SettingTitle';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '~/components/ui/select';
import { enable, isEnabled, disable } from 'tauri-plugin-autostart-api';
import { CheckedState } from '@radix-ui/react-checkbox';
import { useSetting } from '~/store/settings';
import { Slider } from '~/components/ui/slider';
import { Separator } from '~/components/ui/separator';

// placeholders for future features
const showPlaceholders = false;

function Description({ children }: { children: ReactNode }) {
  return <p className="text-sm mb-2">{children}</p>;
}

function LayoutGrid({ children }: { children: ReactNode }) {
  return (
    <div className="grid grid-cols-[160px_1fr] items-center gap-y-2 gap-x-4 auto-rows-fr">
      {children}
    </div>
  );
}

export function General() {
  const [sounds, setSounds] = useSetting<boolean>('sound-effects', true);
  const [volume, setVolume] = useSetting<number>('sound-volume', 1);

  function handleToggleSounds(value: CheckedState) {
    setSounds(value === true);
  }

  function handleVolumeChange(value: number[]) {
    setVolume(value[0]);
  }

  return (
    <div className="flex flex-col gap-8">
      <section>
        <LayoutGrid>
          <div className="text-sm justify-self-end items-center">Startup:</div>
          <StartupSetting />
        </LayoutGrid>
      </section>
      <Separator />
      <section>
        <div className="flex flex-col gap-5">
          <LayoutGrid>
            <>
              <Label className="col-start-2 flex items-center justify-self-start">
                <Checkbox
                  className="mr-2"
                  checked={sounds}
                  onCheckedChange={handleToggleSounds}
                />
                <div className="text-sm justify-self-end">Sound effects</div>
              </Label>
            </>
            <>
              <div className="text-sm justify-self-end">Volume:</div>
              <Slider
                className="max-w-[200px]"
                defaultValue={[volume]}
                onValueCommit={handleVolumeChange}
                disabled={!sounds}
                min={0}
                max={1}
                step={0.01}
              />
            </>
            <>
              <SoundSelect
                label="Start recording:"
                soundEvent="sound-start"
                disabled={!sounds}
              />
            </>
            <>
              <SoundSelect
                label="Stop recording:"
                soundEvent="sound-stop"
                disabled={!sounds}
              />
            </>
            <>
              <SoundSelect
                label="Transcription complete:"
                soundEvent="sound-complete"
                disabled={!sounds}
              />
            </>
            <>
              <div className="text-xs col-start-2">
                More sounds coming soon!
              </div>
            </>
          </LayoutGrid>
        </div>
      </section>
      {showPlaceholders && (
        <section>
          <SettingTitle>Overlay</SettingTitle>
          <div className="flex items-center">
            <Label className="flex items-center">
              <Checkbox className="mr-2" />
              <span>Overlay Position</span>
            </Label>
          </div>
        </section>
      )}
      {showPlaceholders && (
        <section>
          <SettingTitle>Prompt</SettingTitle>
          <Description>
            The prompt to provide the model. This is typically used to correct
            spelling. Limit of 250 characters.
          </Description>
          <div className="flex items-center">
            <Textarea className="max-w-lg h-[100px] resize-none" />
          </div>
        </section>
      )}
      {showPlaceholders && (
        <section>
          <SettingTitle>Audio Device</SettingTitle>
          <Description>
            The prompt to provide the model. This is typically used to correct
            spelling. Limit of 250 characters.
          </Description>
          <Select>
            <SelectTrigger className="w-[180px]">
              <SelectValue placeholder="Theme" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="light">Default</SelectItem>
            </SelectContent>
          </Select>
        </section>
      )}
    </div>
  );
}

function StartupSetting() {
  const [startupEnabled, setStartupEnabled] = useState(false);

  useEffect(() => {
    isEnabled().then((enabled) => {
      setStartupEnabled(enabled);
    });
  }, []);

  function handleStartupEnabledChange(value: CheckedState) {
    if (typeof value !== 'string') {
      if (value === true) {
        enable();
      } else {
        disable();
      }
      setStartupEnabled(value);
    }
  }

  return (
    <div className="flex items-center">
      <Label className="flex items-center">
        <Checkbox
          className="mr-2"
          checked={startupEnabled}
          onCheckedChange={handleStartupEnabledChange}
        />
        <span>Start at login</span>
      </Label>
    </div>
  );
}

type SoundSelectProps = {
  label: string;
  soundEvent: string;
  disabled: boolean;
};

function SoundSelect({
  label,
  soundEvent,
  disabled = false,
}: SoundSelectProps) {
  const [soundSetting, setSoundSetting] = useSetting<string>(
    soundEvent,
    'none'
  );

  function handleChange(value: string) {
    setSoundSetting(value);
  }

  return (
    <>
      <div className="justify-self-end text-sm">{label}</div>
      <Select
        value={soundSetting ?? 'none'}
        onValueChange={handleChange}
        disabled={disabled}
      >
        <SelectTrigger className="w-[180px] h-8">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="none">
            <span className="text-slate-600">None</span>
          </SelectItem>
          <SelectItem value="tick.mp3">Tick</SelectItem>
        </SelectContent>
      </Select>
    </>
  );
}
