import { CheckCircle, HelpCircle, Keyboard, Mic } from 'lucide-react';
import { useState } from 'react';
import {
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '~/components/ui/card';
import { Button } from '~/components/ui/button';

type PermissionStatus = 'none' | 'pending' | 'granted';

export function Permissions() {
  const [micPermission, setMicPermission] = useState<PermissionStatus>('none');
  const [pastePermission, setPastePermission] =
    useState<PermissionStatus>('none');

  return (
    <>
      <div>
        <CardHeader>
          <CardTitle>App Permissions</CardTitle>
          <CardDescription>
            Enable the following permissions to get started
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-6">
          <div className="flex items-center justify-between space-x-4 bg-slate-50 px-4 py-3 rounded-lg">
            <div className="flex items-center space-x-4">
              <Mic />
              <div>
                <p className="text-sm font-medium leading-none">Microphone</p>
                <p className="text-sm text-muted-foreground">
                  Required to record audio
                </p>
              </div>
            </div>
            <div>
              {micPermission === 'none' && (
                <Button
                  className="ml-auto"
                  variant="outline"
                  onClick={() => setMicPermission('granted')}
                >
                  Enable
                </Button>
              )}
              {micPermission === 'pending' && <HelpCircle />}
              {micPermission === 'granted' && (
                <CheckCircle className="text-green-500 h-10 mr-6" />
              )}
            </div>
          </div>
          <div className="flex items-center justify-between space-x-4  bg-slate-50 px-4 py-3 rounded-lg">
            <div className="flex items-center space-x-4">
              <Keyboard />
              <div>
                <p className="text-sm font-medium leading-none">
                  Accessibility
                </p>
                <p className="text-sm text-muted-foreground">
                  Required to paste the transcription into other apps
                </p>
              </div>
            </div>
            <div>
              {pastePermission === 'none' && (
                <Button
                  className="ml-auto"
                  variant="outline"
                  onClick={() => setPastePermission('granted')}
                >
                  Enable
                </Button>
              )}
              {pastePermission === 'pending' && <HelpCircle />}
              {pastePermission === 'granted' && (
                <CheckCircle className="text-green-500 h-10 mr-6" />
              )}
            </div>
          </div>
        </CardContent>
      </div>
    </>
  );
}
