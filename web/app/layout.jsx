import './globals.css';

export const metadata = {
  title: 'AdFlow Landing',
  description: 'AdFlow customer landing page',
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
