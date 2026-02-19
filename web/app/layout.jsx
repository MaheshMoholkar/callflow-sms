import './globals.css';
import { I18nProvider } from './i18n-context';

export const metadata = {
  title: 'AdFlow Landing',
  description: 'AdFlow customer landing page',
};

export default function RootLayout({ children }) {
  return (
    <html lang="mr">
      <body>
        <I18nProvider>
          {children}
        </I18nProvider>
      </body>
    </html>
  );
}
