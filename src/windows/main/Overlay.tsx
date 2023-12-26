import { VariantProps, cva } from 'cva';
import { AnimatePresence, motion } from 'framer-motion';
import { appWindow } from '@tauri-apps/api/window';

const overlay = cva(
  [
    'p-1',
    'h-[40px] w-[190px]',
    'flex',
    'flex-col',
    'justify-center',
    'items-center',
    'rounded-b-2xl',
    'cap',
    'font-medium',
  ],
  {
    variants: {
      status: {
        idle: 'text-slate-100',
        recording: 'text-slate-100',
        transcribing: 'text-slate-100',
      },
    },
    defaultVariants: {
      status: 'idle',
    },
  }
);

const variants = {
  recording: {
    backgroundColor: '#EF4444',
    y: '-3%',
    transition: { type: 'spring', damping: 15, bounce: 0.1, delay: 0.1 },
  },
  transcribing: {
    backgroundColor: '#6366f1',
    y: '-3%',
  },
  idle: {
    backgroundColor: '#090A0C',
    y: '-100%',
    transition: { type: 'spring', damping: 15, bounce: 0.1, delay: 0.1 },
  },
};

export function Overlay({ status, model }: OverlayProps) {
  const activeStatus = status ?? 'idle';

  function handleAnimationComplete(definition: string) {
    if (definition === 'idle') {
      appWindow.hide();
    }
  }

  return (
    <AnimatePresence>
      {status !== 'idle' && (
        <div className="flex flex-col justify-center items-center">
          <motion.div
            initial="idle"
            animate={variants[activeStatus]}
            onAnimationComplete={handleAnimationComplete}
            exit="idle"
            variants={variants}
            className={overlay({ status })}
          >
            <div>{status}</div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
}

export type OverlayProps = VariantProps<typeof overlay> & {
  model: string;
};
