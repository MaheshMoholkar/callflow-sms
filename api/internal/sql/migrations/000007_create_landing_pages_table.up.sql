CREATE TABLE landing_pages (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    headline TEXT,
    description TEXT,
    image_url TEXT,
    image_key TEXT,
    whatsapp_url TEXT,
    facebook_url TEXT,
    instagram_url TEXT,
    youtube_url TEXT,
    email TEXT,
    website_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_landing_pages_user_id ON landing_pages(user_id);
