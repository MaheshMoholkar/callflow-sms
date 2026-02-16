package landing

import "time"

// Landing represents a user's public landing page content
// ImageKey is stored but not exposed in JSON responses.
type Landing struct {
	ID           int64     `json:"id"`
	UserID       int64     `json:"user_id"`
	Headline     *string   `json:"headline,omitempty"`
	Description  *string   `json:"description,omitempty"`
	ImageURL     *string   `json:"image_url,omitempty"`
	ImageKey     *string   `json:"-"`
	WhatsappURL  *string   `json:"whatsapp_url,omitempty"`
	FacebookURL  *string   `json:"facebook_url,omitempty"`
	InstagramURL *string   `json:"instagram_url,omitempty"`
	YoutubeURL   *string   `json:"youtube_url,omitempty"`
	Email        *string   `json:"email,omitempty"`
	WebsiteURL   *string   `json:"website_url,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// LandingUpsert contains data for creating or updating landing content.
type LandingUpsert struct {
	Headline     *string `json:"headline,omitempty"`
	Description  *string `json:"description,omitempty"`
	ImageURL     *string `json:"image_url,omitempty"`
	ImageKey     *string `json:"image_key,omitempty"`
	WhatsappURL  *string `json:"whatsapp_url,omitempty"`
	FacebookURL  *string `json:"facebook_url,omitempty"`
	InstagramURL *string `json:"instagram_url,omitempty"`
	YoutubeURL   *string `json:"youtube_url,omitempty"`
	Email        *string `json:"email,omitempty"`
	WebsiteURL   *string `json:"website_url,omitempty"`
}

// UploadedImage represents an uploaded landing image.
type UploadedImage struct {
	URL string `json:"image_url"`
	Key string `json:"image_key"`
}
