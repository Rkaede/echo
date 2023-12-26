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

// placeholders for future features
const showPlaceholders = false;

function Description({ children }: { children: ReactNode }) {
  return <p className="text-sm mb-2">{children}</p>;
}

export function General() {
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
    <div className="flex flex-col gap-6">
      <div>
        <SettingTitle>Startup</SettingTitle>
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
      </div>
      {showPlaceholders && (
        <div>
          <SettingTitle>Overlay</SettingTitle>
          <div className="flex items-center">
            <Label className="flex items-center">
              <Checkbox className="mr-2" />
              <span>Overlay Position</span>
            </Label>
          </div>
        </div>
      )}
      {showPlaceholders && (
        <div>
          <SettingTitle>Prompt</SettingTitle>
          <Description>
            The prompt to provide the model. This is typically used to correct
            spelling. Limit of 250 characters.
          </Description>
          <div className="flex items-center">
            <Textarea className="max-w-lg h-[100px] resize-none" />
          </div>
        </div>
      )}
      {showPlaceholders && (
        <div>
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
        </div>
      )}
    </div>
  );
}
