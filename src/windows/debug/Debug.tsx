import { invoke } from '@tauri-apps/api';
import { useState } from 'react';
import { Button } from '~/components/ui/button';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '~/components/ui/tabs';
import { Title } from '~/components/ui/title';
import { OverlayWindow } from '~/windows/main/OverlayWindow';
import { Permissions } from '~/windows/permissions/Permissions';
import { Settings } from '~/windows/settings/SettingsWindow';

export function Debug() {
  const urlParams = new URLSearchParams(window.location.search);
  const tabParam = urlParams.get('tab') ?? 'scratchpad';
  const [tab, setTab] = useState(tabParam);

  function handleTabChange(value: string) {
    setTab(value);
    urlParams.set('tab', value);
    window.history.replaceState({}, '', `${window.location.pathname}?${urlParams}`);
  }

  return (
    <div className="p-10 flex flex-col gap-6">
      <Tabs defaultValue={tab} className="" onValueChange={handleTabChange}>
        <TabsList>
          <TabsTrigger value="scratchpad">Scratchpad</TabsTrigger>
          <TabsTrigger value="components">Components</TabsTrigger>
          <TabsTrigger value="views">Views</TabsTrigger>
        </TabsList>
        <TabsContent value="components">
          <Title>Overlay</Title>
          <div className="flex flex-col gap-2 border p-3">
            <div className="border w-[140px] h-[40px] relative">
              <OverlayWindow />
            </div>
            <div className="border w-[140px] h-[40px] relative">
              <OverlayWindow />
            </div>
          </div>
        </TabsContent>
        <TabsContent value="views" className="flex gap-6 flex-col">
          <div>
            <Title>Settings</Title>
            <div className="border w-[500px]">
              <Settings />
            </div>
          </div>
          <div>
            <Title>Permissions</Title>
            <div className="border w-[580px]">
              <Permissions />
            </div>
          </div>
        </TabsContent>
        <TabsContent value="scratchpad" className="overflow-auto h-full flex-1">
          <div className="border">
            <div className="p-3">
              <Button onClick={() => invoke('start_recording')}>Start Recording</Button>
              <Button onClick={() => invoke('stop_recording')}>Stop Recording</Button>
            </div>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}
