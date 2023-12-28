import { Model } from '~/types';

const BASE_URL = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/';

export const models = [
  {
    description: 'Ideal for low powered devices.',
    downloadProgress: null,
    filename: 'ggml-tiny.bin',
    id: 'tiny',
    label: 'Tiny',
    memory: '390Mb',
    ratings: { speed: 90, accuracy: 50 },
    size: '75Mb',
    status: 'unavailable',
    url: `${BASE_URL}ggml-tiny.bin`,
  },
  {
    description: 'For applications where speed is important and accuracy is not critical.',
    downloadProgress: null,
    filename: 'ggml-base.bin',
    id: 'base',
    label: 'Base',
    memory: '500Mb',
    ratings: { speed: 80, accuracy: 60 },
    size: '142Mb',
    status: 'unavailable',
    url: `${BASE_URL}ggml-base.bin`,
  },
  {
    description: 'A balance between performance and speed, ideal for most applications.',
    downloadProgress: null,
    filename: 'ggml-small.bin',
    id: 'small',
    label: 'Small',
    memory: '1.0Gb',
    ratings: { speed: 70, accuracy: 60 },
    size: '466Mb',
    status: 'unavailable',
    url: `${BASE_URL}ggml-small.bin`,
  },
  {
    description: 'For when higher precision is important.',
    downloadProgress: null,
    filename: 'ggml-medium.bin',
    id: 'medium',
    label: 'Medium',
    memory: '2.6Gb',
    ratings: { speed: 40, accuracy: 80 },
    size: '1.5Gb',
    status: 'unavailable',
    url: `${BASE_URL}ggml-medium.bin`,
  },
  {
    description: 'For scenarios where transcription accuracy is paramount.',
    downloadProgress: null,
    filename: 'ggml-large-v3.bin',
    id: 'large',
    label: 'Large V3',
    memory: '4.7Gb',
    ratings: { speed: 30, accuracy: 90 },
    size: '2.9Gb',
    status: 'unavailable',
    url: `${BASE_URL}ggml-large.bin`,
  },
] satisfies Model[];