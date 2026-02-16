import { notFound } from 'next/navigation';

async function fetchLanding(id) {
  const base = process.env.NEXT_PUBLIC_API_BASE || 'http://localhost:8080/api/v1';
  const res = await fetch(`${base}/public/landing/${id}`, { cache: 'no-store' });
  if (!res.ok) {
    return null;
  }
  const body = await res.json();
  if (!body || !body.success || !body.data) {
    return null;
  }
  return body.data;
}

function buildMapUrl(user) {
  if (!user) return '';
  if (user.location_url) return user.location_url;
  const address = [user.address, user.city].filter(Boolean).join(', ');
  if (!address) return '';
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(address)}`;
}

export default async function LandingPage({ params }) {
  const data = await fetchLanding(params.id);
  if (!data) {
    notFound();
  }

  const user = data.user || {};
  const landing = data.landing || {};
  const headline = landing.headline || user.business_name || user.name || 'Welcome';
  const description = landing.description || '';
  const imageUrl = landing.image_url || '';
  const mapUrl = buildMapUrl(user);

  const actions = [
    user.phone ? { label: 'Call', href: `tel:${user.phone}` } : null,
    landing.whatsapp_url ? { label: 'WhatsApp', href: landing.whatsapp_url } : null,
    landing.facebook_url ? { label: 'Facebook', href: landing.facebook_url } : null,
    landing.instagram_url ? { label: 'Instagram', href: landing.instagram_url } : null,
    landing.youtube_url ? { label: 'YouTube', href: landing.youtube_url } : null,
    landing.email ? { label: 'Email', href: `mailto:${landing.email}` } : null,
    landing.website_url ? { label: 'Website', href: landing.website_url } : null,
    mapUrl ? { label: 'Maps', href: mapUrl } : null,
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
            No image
          </div>
        )}
        <div>
          <p className="label">AdFlow Partner</p>
          <h1>{headline}</h1>
          {description ? <p>{description.slice(0, 140)}</p> : null}
          <div className="meta">
            {user.phone ? <span>{user.phone}</span> : null}
            {user.address || user.city ? (
              <span>{[user.address, user.city].filter(Boolean).join(', ')}</span>
            ) : null}
          </div>
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

      <section className="section">
        {imageUrl ? <img src={imageUrl} alt={headline} /> : null}
        {description ? <div className="description">{description}</div> : null}
      </section>
    </main>
  );
}
