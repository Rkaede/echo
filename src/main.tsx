import ReactDOM from 'react-dom/client';
import './styles.css';
import { Debug } from './windows/debug/Debug';
import { OverlayWindow } from './windows/main/OverlayWindow';
import { Permissions } from './windows/permissions/Permissions';
import { Settings } from './windows/settings/SettingsWindow';

const routes = {
  settings: <Settings />,
  debug: <Debug />,
  app: <OverlayWindow />,
  permissions: <Permissions />,
};

type Routes = keyof typeof routes;

const urlParams = new URLSearchParams(window.location.search);
const route = urlParams.get('route') ?? 'app';
const RouteComponent = routes[route as Routes];

ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  RouteComponent
);
