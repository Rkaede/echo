import { invoke } from '@tauri-apps/api';
import { resourceDir } from '@tauri-apps/api/path';
import { type ClassValue, clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { Model } from '~/types';

export async function log(message: string) {
  console.info(message);
  invoke('log', { text: message });
}

export const IS_DEV = process.env.NODE_ENV === 'development';

// run once and resolve
export const modelDirBase = resourceDir();

export async function getModelDir() {
  return `${await modelDirBase}resources/models/`;
}

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export async function download(model: Model) {
  const { url, filename, id } = model;
  const basePath = await getModelDir();
  const destination = `${basePath}${filename}`;
  log(`downloading: ${id}, from: ${url}, to: ${destination}`);
  invoke('download_model', { src: url, target: destination, model: id });
}
