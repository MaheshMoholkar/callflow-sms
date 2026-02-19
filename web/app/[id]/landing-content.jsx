'use client';

import { useI18n } from '../i18n-context';

function buildMapUrl(user) {
  if (!user) return '';
  if (user.location_url) return user.location_url;
  const address = [user.address, user.city].filter(Boolean).join(', ');
  if (!address) return '';
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(address)}`;
}

function descriptionToPoints(description) {
  if (!description || typeof description !== 'string') return [];
  return description
    .split(/\r?\n/)
    .map((line) => line.trim())
    .map((line) => line.replace(/^[-*\u2022]\s+/, '').replace(/^\d+[.)]\s+/, ''))
    .filter(Boolean);
}

export default function LandingContent({ user = {}, landing = {} }) {
  const { t } = useI18n();

  const headline =
    landing.headline || user.business_name || user.name || t('landing.fallbackTitle');
  const descriptionPoints = descriptionToPoints(landing.description || '');
  const imageUrl = landing.image_url || '';
  const mapUrl = buildMapUrl(user);

  const actions = [
    user.phone ? { label: t('landing.actions.call'), href: `tel:${user.phone}` } : null,
    landing.facebook_url ? { label: t('landing.actions.facebook'), href: landing.facebook_url } : null,
    landing.instagram_url ? { label: t('landing.actions.instagram'), href: landing.instagram_url } : null,
    landing.youtube_url ? { label: t('landing.actions.youtube'), href: landing.youtube_url } : null,
    landing.email ? { label: t('landing.actions.email'), href: `mailto:${landing.email}` } : null,
    landing.website_url ? { label: t('landing.actions.website'), href: landing.website_url } : null,
    mapUrl ? { label: t('landing.actions.maps'), href: mapUrl } : null,
  ].filter(Boolean);

  return (
    <main className="container">
      <section className="hero">
        {imageUrl ? (
          <img src={imageUrl} alt={headline} />
        ) : (
          <div
            style={{
              width: '100%',
              height: '160px',
              borderRadius: '16px',
              background: 'linear-gradient(135deg, #f1d6e3, #e7e0f4)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: '#6b5d70',
              fontWeight: 600,
            }}
          >
            {t('landing.noImage')}
          </div>
        )}
        <div>
          <p className="label">{t('landing.partnerLabel')}</p>
          <h1>{headline}</h1>
          {descriptionPoints.length ? (
            <ul className="hero-points">
              {descriptionPoints.map((point, index) => (
                <li key={`${point}-${index}`}>{point}</li>
              ))}
            </ul>
          ) : null}
          {actions.length ? (
            <div className="actions">
              {actions.map((action) => (
                <a key={action.label} className="action" href={action.href} target="_blank" rel="noreferrer">
                  {action.label}
                </a>
              ))}
            </div>
          ) : null}
        </div>
      </section>
    </main>
  );
}
