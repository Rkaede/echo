import { useEffect, useState } from 'react';
import { Store } from 'tauri-plugin-store-api';

export const settingsStore = new Store('.settings.dat');

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
    settingsStore.set(key, value).then(() => {
      settingsStore.save();
    });
    setValue(value);
  };

  return [value, set];
}
