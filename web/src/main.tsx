import { createRoot } from 'react-dom/client';
import App from './App';
import { Tooltips } from './Tooltip';
import './styles.css';
import './app-brand.css';
import './admin.css';
import './manolo-bay.css';
import './dropdown.css';
createRoot(document.getElementById('root')!).render(
  <>
    <App />
    <Tooltips />
  </>,
);
