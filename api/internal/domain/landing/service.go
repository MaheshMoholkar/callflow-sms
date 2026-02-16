package landing

import "context"

// Service defines the interface for landing business logic.
type Service interface {
	GetByUserID(ctx context.Context, userID int64) (*Landing, error)
	UpsertByUserID(ctx context.Context, userID int64, data LandingUpsert) (*Landing, error)
	UploadImage(ctx context.Context, userID int64, filename, contentType string, file []byte) (*UploadedImage, error)
}
