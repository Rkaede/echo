import * as RadioGroup from '@radix-ui/react-radio-group';
import { BaseDirectory, removeFile } from '@tauri-apps/api/fs';
import { VariantProps, cva } from 'cva';
import { CheckCircle2, DownloadCloudIcon, Trash2 } from 'lucide-react';
import { Button } from '~/components/ui/button';
import { Progress } from '~/components/ui/progress';
import { useSetting } from '~/store/settings';
import useStore from '~/store/store';
import { Model } from '~/types';
import { cn } from '~/util';
import { Rating } from './components/Rating';
import { SettingTitle } from './components/SettingTitle';
import { useEffect } from 'react';

const modelRadio = cva(
  ['flex flex-col gap-2 items-center px-4 py-2 rounded-lg border relative'],
  {
    variants: {
      selected: {
        true: 'outline outline-green-600 border-green-600 outline-2',
        false: '',
      },
      disabled: {
        true: ' bg-slate-50 cursor-default',
        false: 'cursor-pointer',
      },
    },
    defaultVariants: {
      selected: false,
    },
  },
);

export type ModelProps = VariantProps<typeof modelRadio> & {
  model: Model;
  disabled?: boolean;
  onClick?: () => void;
};

export function SelectModel() {
  const deleteModel = useStore((state) => state.deleteModel);
  const allModels = useStore((state) => state.models);
  const models = allModels.filter((model) => model.status === 'available');

  const [selectedModel, setModel] = useSetting<string>('model', 'base');

  useEffect(() => {
    const model = models.find((model) => model.id === selectedModel);
    if (!model) {
      setModel('base');
    }
  }, [models, selectedModel, setModel]);

  async function handleDelete(model: Model) {
    deleteModel(model.id);
    await removeFile(`resources/models/${model.filename}`, {
      dir: BaseDirectory.Resource,
    });
  }

  return (
    <div>
      <SettingTitle>Active Model</SettingTitle>
      <RadioGroup.Root
        className="flex flex-col gap-2"
        onValueChange={(value) => setModel(value)}
        value={selectedModel}
      >
        {models.map((model: Model) => (
          <RadioGroup.Item
            key={model.id}
            className={cn(
              'border rounded-lg px-0 py-2 w-full grid grid-cols-[46px_1fr_120px_120px_52px] items-center hover:bg-slate-50',
              model.id === selectedModel && 'outline outline-2 outline-indigo-500',
            )}
            value={model.id}
          >
            <div className="min-w-8 px-3 flex justify-center">
              {model.id === selectedModel ? (
                <CheckCircle2 className="h-6 w-6 text-indigo-500" />
              ) : (
                <div className="h-6 w-6" />
              )}
            </div>
            <div className="flex flex-col items-start">
              <div className="text-base font-medium leading-none">{model.label}</div>
              <div className="text-xs font-normal text-left">{model.description}</div>
            </div>
            <div className="flex items-start flex-col gap-1">
              <div className="text-xs font-medium leading-none">Speed:</div>
              <Rating rating={model.ratings.speed} />
            </div>
            <div className="flex items-start flex-col gap-1">
              <div className="text-xs font-medium leading-none">Accuracy:</div>
              <Rating rating={model.ratings.accuracy} />
            </div>
            <div className="flex items-start flex-col gap-1">
              {model.id !== 'base' && (
                <Button size="sm" variant="ghost" onClick={() => handleDelete(model)} asChild>
                  {/* we need to use a div here because the button is a radio button */}
                  <div role="button">
                    <Trash2 className="w-6 h-6" />
                  </div>
                </Button>
              )}
            </div>
          </RadioGroup.Item>
        ))}
      </RadioGroup.Root>
    </div>
  );
}

export function DownloadModels() {
  const allModels = useStore((state) => state.models);
  const models = allModels.filter((model) => model.status !== 'available');
  const downloadModel = useStore((state) => state.downloadModel);

  return (
    <div>
      <SettingTitle>Download Models</SettingTitle>
      <div className="flex flex-col gap-2">
        {models.map((model: Model) => (
          <div
            key={model.id}
            className={cn(
              'border-b px-0 py-2 w-full grid grid-cols-[46px_1fr_120px_120px_52px] items-center',
              model.id === models[0].id && 'border-t',
            )}
          >
            <div className="min-w-8 px-3 flex justify-center" />
            <div className="flex flex-col items-start">
              <div className="text-base font-medium leading-none">{model.label}</div>
              <div className="text-xs font-normal text-left">{model.description}</div>
            </div>
            <div className="flex items-start flex-col gap-1">
              <div className="text-xs font-medium leading-none">Speed:</div>
              <Rating rating={model.ratings.speed} />
            </div>
            <div className="flex items-start flex-col gap-1">
              <div className="text-xs font-medium leading-none">Accuracy:</div>
              <Rating rating={model.ratings.accuracy} />
            </div>
            <div className="flex items-start flex-col gap-1">
              {model.downloadProgress !== null && <Progress value={model.downloadProgress} />}
              {model.downloadProgress === null && model.status !== 'available' && (
                <Button size="sm" variant="ghost" onClick={() => downloadModel(model.id)}>
                  <DownloadCloudIcon />
                </Button>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
