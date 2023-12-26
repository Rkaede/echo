import { DownloadModels, SelectModel } from './Models';
import { useEffect, useState } from 'react';
import { refreshModels } from '~/store/store';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '~/components/ui/tabs';
import { General } from './General';

export function Settings() {
  useEffect(() => {
    refreshModels();
  }, []);

  const [tab, setTab] = useState('general');

  return (
    <div className="p-4 flex flex-col gap-8 h-full">
      <Tabs defaultValue={tab} className="" onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="general">General</TabsTrigger>
          <TabsTrigger value="models">Models</TabsTrigger>
        </TabsList>
        <TabsContent value="general" className="p-4">
          <General />
        </TabsContent>
        <TabsContent value="models" className="flex flex-col gap-12 p-4">
          <SelectModel />
          <DownloadModels />
        </TabsContent>
      </Tabs>
    </div>
  );
}
