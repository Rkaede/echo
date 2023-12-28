import { useEffect, useState } from 'react';
import { Store } from 'tauri-plugin-store-api';
import { log } from '~/util';

export const settingsStore = new Store('config.json');

export function useSetting<T>(key: string, defaultValue: T): [T, (value: T) => void] {
  const [value, setValue] = useState<T>(defaultValue);

  useEffect(() => {
    settingsStore.get<T>(key).then((value: T | null) => {
      if (value !== null) {
        setValue(value);
      } else {
        setValue(defaultValue);
        settingsStore.set(key, defaultValue);
      }
    });
  }, [key, defaultValue]);

  const set = (value: T) => {
    if (value === undefined) {
      log(`deleting ${key}`);
      settingsStore.delete(key);
      settingsStore.save();
    } else {
      settingsStore.set(key, value).then(() => {
        settingsStore.save();
      });
    }
    setValue(value);
  };

  return [value, set];
}
