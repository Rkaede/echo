import { invoke } from '@tauri-apps/api';
import { listen } from '@tauri-apps/api/event';
import { isRegistered, register } from '@tauri-apps/api/globalShortcut';
import { useEffect } from 'react';
import { settingsStore, useSetting } from '~/store/settings';
import { log } from '~/util';
import useStore, { Status } from '../../store/store';
import { Overlay } from './Overlay';

export function OverlayWindow() {
  const status = useStore((state) => state.status);
  const setStatus = useStore((state) => state.setStatus);
  const [model] = useSetting<string>('model', 'base');

  useEffect(() => {
    let cleanup: () => void;

    async function statusChanges() {
      cleanup = await listen<{ status: Status }>('change_status', (event) => {
        log('listen: change_status');
        setStatus(event.payload.status);
      });
    }

    statusChanges();

    return () => {
      if (cleanup) {
        cleanup();
      }
    };
  }, [setStatus]);
  return <Overlay status={status} model={model} />;
}

isRegistered('Option+Space').then((registered) => {
  log(`registered ${registered.toString()}`);
  if (!registered) {
    register('Option+Space', async () => {
      log(`Option+Space ${useStore.getState().status}`);
      switch (useStore.getState().status) {
        case 'idle':
          settingsStore.get('model').then((model) => {
            log(`start recording: ${model} - ${Date.now()}`);
            invoke('start_recording', { model: model ?? 'base' });
          });

          break;
        case 'recording':
          log(`stop recording: ${Date.now()}`);
          invoke('stop_recording');
          break;
        case 'transcribing':
          log('do nothing');
          break;
      }
    });
  }
});
