package service

import (
	"context"
	"errors"
	"log"
	"net/url"
	"strings"

	"callflow/internal/domain/landing"
)

type LandingImageStore interface {
	UploadLandingImage(ctx context.Context, filename, contentType string, file []byte) (*landing.UploadedImage, error)
	DeleteLandingImage(ctx context.Context, imageKey string) error
}

// LandingService provides landing page business logic.
type LandingService struct {
	landingRepo landing.Repository
	imageStore  LandingImageStore
}

// NewLandingService creates a new landing service instance.
func NewLandingService(landingRepo landing.Repository, imageStore LandingImageStore) *LandingService {
	return &LandingService{
		landingRepo: landingRepo,
		imageStore:  imageStore,
	}
}

func (s *LandingService) GetByUserID(ctx context.Context, userID int64) (*landing.Landing, error) {
	return s.landingRepo.GetByUserID(ctx, userID)
}

func (s *LandingService) UpsertByUserID(ctx context.Context, userID int64, data landing.LandingUpsert) (*landing.Landing, error) {
	existing, err := s.landingRepo.GetByUserID(ctx, userID)
	if err != nil && !errorsIsLandingNotFound(err) {
		return nil, err
	}

	// Normalize inputs
	data.Headline = normalizeStringPtr(data.Headline)
	data.Description = normalizeStringPtr(data.Description)
	data.ImageURL = normalizeURL(data.ImageURL)
	data.ImageKey = normalizeStringPtr(data.ImageKey)
	data.WhatsappURL = normalizeStringPtr(data.WhatsappURL)
	data.FacebookURL = normalizeStringPtr(data.FacebookURL)
	data.InstagramURL = normalizeStringPtr(data.InstagramURL)
	data.YoutubeURL = normalizeStringPtr(data.YoutubeURL)
	data.Email = normalizeStringPtr(data.Email)
	data.WebsiteURL = normalizeStringPtr(data.WebsiteURL)

	// Preserve image key when URL is unchanged and client does not resend key.
	if existing != nil && data.ImageURL != nil && existing.ImageURL != nil &&
		*data.ImageURL == *existing.ImageURL && data.ImageKey == nil {
		data.ImageKey = existing.ImageKey
	}

	if data.ImageURL == nil {
		data.ImageKey = nil
	}

	requiresImageKey := data.ImageURL != nil && (existing == nil || existing.ImageURL == nil || *data.ImageURL != *existing.ImageURL)
	if err := validateLandingImageFields(data.ImageURL, data.ImageKey, requiresImageKey); err != nil {
		return nil, err
	}

	updated, err := s.landingRepo.UpsertByUserID(ctx, userID, data)
	if err != nil {
		return nil, err
	}

	if existing != nil && shouldDeleteOldImage(existing.ImageKey, updated.ImageKey) {
		s.deleteImageKeyAsync(existing.ImageKey)
	}

	return updated, nil
}

func (s *LandingService) UploadImage(ctx context.Context, _ int64, filename, contentType string, file []byte) (*landing.UploadedImage, error) {
	if s.imageStore == nil {
		return nil, landing.ErrUploadDisabled
	}
	return s.imageStore.UploadLandingImage(ctx, filename, contentType, file)
}

func validateLandingImageFields(imageURL, imageKey *string, requireImageKey bool) error {
	if imageURL == nil {
		return nil
	}
	parsed, err := url.Parse(*imageURL)
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
		return landing.ErrInvalidImageURL
	}
	if requireImageKey && imageKey == nil {
		return landing.ErrMissingImageKey
	}
	return nil
}

func normalizeURL(v *string) *string {
	value := normalizeStringPtr(v)
	if value == nil {
		return nil
	}
	trimmed := strings.TrimSpace(*value)
	if trimmed == "" {
		return nil
	}
	return &trimmed
}

func normalizeStringPtr(v *string) *string {
	if v == nil {
		return nil
	}
	trimmed := strings.TrimSpace(*v)
	if trimmed == "" {
		return nil
	}
	return &trimmed
}

func shouldDeleteOldImage(oldKey, newKey *string) bool {
	if oldKey == nil || *oldKey == "" {
		return false
	}
	if newKey == nil || *newKey == "" {
		return true
	}
	return *oldKey != *newKey
}

func (s *LandingService) deleteImageKeyAsync(imageKey *string) {
	if imageKey == nil || s.imageStore == nil {
		return
	}
	if err := s.imageStore.DeleteLandingImage(context.Background(), *imageKey); err != nil {
		log.Printf("failed to delete landing image key %s: %v", *imageKey, err)
	}
}

func errorsIsLandingNotFound(err error) bool {
	return errors.Is(err, landing.ErrLandingNotFound)
}
