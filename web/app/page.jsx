export default function Home() {
  const highlights = [
    {
      title: 'Instant follow-up',
      text: 'Respond to missed calls in seconds with personalized SMS and WhatsApp messaging.',
    },
    {
      title: 'Smart automation',
      text: 'Use rule-based triggers, templates, and scheduling to keep engagement consistent.',
    },
    {
      title: 'Shareable landing links',
      text: 'Every business gets a clean public page to convert conversations into actions.',
    },
  ];

  const steps = [
    'Set your business profile, response rules, and templates.',
    'AdFlow detects incoming and missed calls automatically.',
    'Customers receive follow-up messages and your landing link instantly.',
    'They can call, message, map, or contact your business from one page.',
  ];

  return (
    <main className="container site-home">
      <section className="site-hero">
        <div>
          <p className="label">AdFlow</p>
          <h1>Convert missed calls into booked customers.</h1>
          <p className="site-subtitle">
            AdFlow automates your call follow-up workflow and routes customers to a focused landing page with one tap.
          </p>
          <div className="site-hero-actions">
            <a className="action" href="https://adflow.up.railway.app/admin" target="_blank" rel="noreferrer">
              Open Admin Console
            </a>
            <a className="action action-ghost" href="#how-it-works">
              How It Works
            </a>
          </div>
        </div>

        <div className="site-stat-grid">
          <div className="site-stat-card">
            <p className="site-stat-value">24/7</p>
            <p className="site-stat-label">Automated call follow-up</p>
          </div>
          <div className="site-stat-card">
            <p className="site-stat-value">SMS + WhatsApp</p>
            <p className="site-stat-label">Multi-channel outreach</p>
          </div>
          <div className="site-stat-card">
            <p className="site-stat-value">Public page</p>
            <p className="site-stat-label">One shareable business URL</p>
          </div>
        </div>
      </section>

      <section className="section">
        <p className="label">Why AdFlow</p>
        <h2 className="site-section-title">Everything needed for fast customer response</h2>
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
        <p className="label">Workflow</p>
        <h2 className="site-section-title">How your landing flow works</h2>
        <ol className="site-steps">
          {steps.map((step) => (
            <li key={step}>{step}</li>
          ))}
        </ol>
      </section>

      <section className="section site-cta">
        <h2 className="site-section-title">Customer pages are published at:</h2>
        <p className="site-url">https://adflowapp.vercel.app/&lt;customer-id&gt;</p>
        <p className="description">
          Use your assigned customer ID URL to open a specific business landing page.
        </p>
      </section>
    </main>
  );
}
