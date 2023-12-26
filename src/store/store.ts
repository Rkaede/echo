/* eslint-disable @typescript-eslint/no-explicit-any */
import { listen } from '@tauri-apps/api/event';
import { exists } from '@tauri-apps/api/fs';
import { share } from 'shared-zustand';
import { create } from 'zustand';
import { subscribeWithSelector } from 'zustand/middleware';
import { immer } from 'zustand/middleware/immer';
import { Model, ModelStatus } from '~/types';
import { download, getModelDir, log } from '~/util';
import { models } from './models';

export type Status = 'recording' | 'idle' | 'transcribing';

interface State {
  status: Status;
  models: Model[];
  setStatus: (status: Status) => void;
  updateModelStatus: (modelId: string, status: ModelStatus) => void;
  updateDownloadProgress: (modelId: string, progress: number | null) => void;
  downloadModel: (modelId: string) => void;
  deleteModel: (modelId: string) => void;
}

export const useStore = create(
  subscribeWithSelector(
    immer<State>((set) => ({
      status: 'idle',
      models: models,
      setStatus: (status: Status) => {
        set((state) => {
          state.status = status;
        });
      },
      downloadModel: async (modelId: string) => {
        set((state) => {
          const models = state.models;
          const model = models.find((m) => m.id === modelId);

          if (model && model.status !== 'downloading') {
            model.downloadProgress = 0;
            model.status = 'downloading';
            download(model);
          }
        });
      },
      deleteModel: async (modelId: string) => {
        set((state) => {
          const models = state.models;
          const model = models.find((m) => m.id === modelId);

          if (model && model.status === 'available') {
            model.downloadProgress = null;
            model.status = 'unavailable';
          }
        });
      },
      updateModelStatus: (modelId: string, status: ModelStatus) => {
        set((state) => {
          const model = state.models.find((m) => m.id === modelId);
          if (model) {
            model.status = status;
          }
        });
      },
      updateDownloadProgress: (modelId: string, progress: number | null) => {
        set((state) => {
          const model = state.models.find((m) => m.id === modelId);
          if (model) {
            model.downloadProgress = progress;
          }
        });
      },
    })),
  ),
);

share('model', useStore);
share('status', useStore);

export async function refreshModels() {
  const MODEL_DIR = await getModelDir();
  const models = useStore.getState().models;
  models.map(async (model) => {
    const path = `${MODEL_DIR}${model.filename}`;
    console.log(`model path: ${path}`);
    const modelExists = await exists(path);
    console.log(`model exists: ${modelExists}`);

    if (model.status !== 'downloading') {
      useStore
        .getState()
        .updateModelStatus(model.id, modelExists ? 'available' : 'unavailable');
    }
  });
}

interface DownloadProgressPayload {
  model_id: string;
  progress: number;
}

async function startup() {
  await listen<DownloadProgressPayload>('download-progress', (event) => {
    const models = useStore.getState().models;
    const model = models.find((m) => m.id === event.payload.model_id);
    if (model) {
      log(`download progress: ${event.payload.progress}`);
      useStore
        .getState()
        .updateDownloadProgress(event.payload.model_id, event.payload.progress);
      if (event.payload.progress === 100) {
        log('model downloaded');
        useStore.getState().updateModelStatus(event.payload.model_id, 'available');
        useStore.getState().updateDownloadProgress(event.payload.model_id, null);
      }
    } else {
      log(`model not found: ${event.payload.model_id}`);
    }
  });

  refreshModels();
}

startup();

export default useStore;
