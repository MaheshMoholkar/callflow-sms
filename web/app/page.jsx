'use client';

import { useI18n } from './i18n-context';
import LanguageToggle from './language-toggle';

export default function Home() {
  const { t } = useI18n();
  const highlights = t('home.highlights');
  const steps = t('home.steps');

  return (
    <>
      <LanguageToggle />
      <main className="container site-home">
        <section className="site-hero">
          <div>
            <p className="label">{t('home.brandLabel')}</p>
            <h1>{t('home.heroTitle')}</h1>
            <p className="site-subtitle">{t('home.heroSubtitle')}</p>
            <div className="site-hero-actions">
              <a className="action" href="#how-it-works">
                {t('home.howItWorks')}
              </a>
            </div>
          </div>

          <div className="site-stat-grid">
            <div className="site-stat-card">
              <p className="site-stat-value">{t('home.stats.alwaysOnValue')}</p>
              <p className="site-stat-label">{t('home.stats.alwaysOnLabel')}</p>
            </div>
            <div className="site-stat-card">
              <p className="site-stat-value">{t('home.stats.smsValue')}</p>
              <p className="site-stat-label">{t('home.stats.smsLabel')}</p>
            </div>
            <div className="site-stat-card">
              <p className="site-stat-value">{t('home.stats.pageValue')}</p>
              <p className="site-stat-label">{t('home.stats.pageLabel')}</p>
            </div>
          </div>
        </section>

        <section className="section">
          <p className="label">{t('home.whyLabel')}</p>
          <h2 className="site-section-title">{t('home.whyTitle')}</h2>
          <div className="site-grid">
            {highlights.map((item) => (
              <article key={item.title} className="site-card">
                <h3>{item.title}</h3>
                <p>{item.text}</p>
              </article>
            ))}
          </div>
        </section>

        <section id="how-it-works" className="section">
          <p className="label">{t('home.workflowLabel')}</p>
          <h2 className="site-section-title">{t('home.workflowTitle')}</h2>
          <ol className="site-steps">
            {steps.map((step) => (
              <li key={step}>{step}</li>
            ))}
          </ol>
        </section>

        <section className="section site-cta">
          <h2 className="site-section-title">{t('home.customerPageTitle')}</h2>
          <p className="site-url">https://adflowapp.vercel.app/&lt;customer-id&gt;</p>
          <p className="description">{t('home.customerPageHint')}</p>
        </section>

        <section className="section">
          <p className="label">{t('home.advertisingLabel')}</p>
          <h2 className="site-section-title">{t('home.advertisingTitle')}</h2>
          <div className="site-hero-actions">
            <a className="action" href="mailto:mahesh.moholkar.dev@gmail.com">
              mahesh.moholkar.dev@gmail.com
            </a>
            <a className="action action-ghost" href="tel:+919579047391">
              +91 95790 47391
            </a>
          </div>
        </section>
      </main>
    </>
  );
}
