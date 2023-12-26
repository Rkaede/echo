export type ModelStatus = 'downloading' | 'available' | 'unavailable';

export type Model = {
  id: string;
  label: string;
  description: string;
  status: ModelStatus;
  downloadProgress: number | null;
  size: string;
  memory: string;
  url: string;
  filename: string;
  ratings: {
    speed: number;
    accuracy: number;
  };
};
