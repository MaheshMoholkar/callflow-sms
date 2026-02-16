package landing

import "context"

// Repository defines the interface for landing data access.
type Repository interface {
	GetByUserID(ctx context.Context, userID int64) (*Landing, error)
	UpsertByUserID(ctx context.Context, userID int64, data LandingUpsert) (*Landing, error)
}
