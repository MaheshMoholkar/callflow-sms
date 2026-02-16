-- name: GetLandingByUserID :one
SELECT * FROM landing_pages WHERE user_id = $1;

-- name: UpsertLandingByUserID :one
INSERT INTO landing_pages (
  user_id,
  headline,
  description,
  image_url,
  image_key,
  whatsapp_url,
  facebook_url,
  instagram_url,
  youtube_url,
  email,
  website_url
) VALUES (
  $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11
)
ON CONFLICT (user_id) DO UPDATE
SET headline = EXCLUDED.headline,
    description = EXCLUDED.description,
    image_url = EXCLUDED.image_url,
    image_key = EXCLUDED.image_key,
    whatsapp_url = EXCLUDED.whatsapp_url,
    facebook_url = EXCLUDED.facebook_url,
    instagram_url = EXCLUDED.instagram_url,
    youtube_url = EXCLUDED.youtube_url,
    email = EXCLUDED.email,
    website_url = EXCLUDED.website_url,
    updated_at = NOW()
RETURNING *;
