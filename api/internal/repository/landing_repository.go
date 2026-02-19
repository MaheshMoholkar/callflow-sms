package repository

import (
	"context"
	"errors"

	"callflow/internal/domain/landing"
	db "callflow/internal/sql/db"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

// LandingRepository implements landing.Repository
// for landing page persistence.
type LandingRepository struct {
	pool    *pgxpool.Pool
	queries *db.Queries
}

// NewLandingRepository creates a new landing repository.
func NewLandingRepository(pool *pgxpool.Pool) *LandingRepository {
	return &LandingRepository{
		pool:    pool,
		queries: db.New(pool),
	}
}

func (r *LandingRepository) GetByUserID(ctx context.Context, userID int64) (*landing.Landing, error) {
	row, err := r.queries.GetLandingByUserID(ctx, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, landing.ErrLandingNotFound
		}
		return nil, err
	}
	return dbLandingToModel(row), nil
}

func (r *LandingRepository) UpsertByUserID(ctx context.Context, userID int64, data landing.LandingUpsert) (*landing.Landing, error) {
	row, err := r.queries.UpsertLandingByUserID(ctx, db.UpsertLandingByUserIDParams{
		UserID:       userID,
		Headline:     nullableLandingText(data.Headline),
		Description:  nullableLandingText(data.Description),
		ImageUrl:     nullableLandingText(data.ImageURL),
		ImageKey:     nullableLandingText(data.ImageKey),
		WhatsappUrl:  nullableLandingText(data.WhatsappURL),
		FacebookUrl:  nullableLandingText(data.FacebookURL),
		InstagramUrl: nullableLandingText(data.InstagramURL),
		YoutubeUrl:   nullableLandingText(data.YoutubeURL),
		Email:        nullableLandingText(data.Email),
		WebsiteUrl:   nullableLandingText(data.WebsiteURL),
	})
	if err != nil {
		return nil, err
	}
	return dbLandingToModel(row), nil
}

func dbLandingToModel(row db.LandingPage) *landing.Landing {
	var headline *string
	var description *string
	var imageURL *string
	var imageKey *string
	var whatsappURL *string
	var facebookURL *string
	var instagramURL *string
	var youtubeURL *string
	var email *string
	var websiteURL *string

	if row.Headline.Valid {
		headline = &row.Headline.String
	}
	if row.Description.Valid {
		description = &row.Description.String
	}
	if row.ImageUrl.Valid {
		imageURL = &row.ImageUrl.String
	}
	if row.ImageKey.Valid {
		imageKey = &row.ImageKey.String
	}
	if row.WhatsappUrl.Valid {
		whatsappURL = &row.WhatsappUrl.String
	}
	if row.FacebookUrl.Valid {
		facebookURL = &row.FacebookUrl.String
	}
	if row.InstagramUrl.Valid {
		instagramURL = &row.InstagramUrl.String
	}
	if row.YoutubeUrl.Valid {
		youtubeURL = &row.YoutubeUrl.String
	}
	if row.Email.Valid {
		email = &row.Email.String
	}
	if row.WebsiteUrl.Valid {
		websiteURL = &row.WebsiteUrl.String
	}

	return &landing.Landing{
		ID:           row.ID,
		UserID:       row.UserID,
		Headline:     headline,
		Description:  description,
		ImageURL:     imageURL,
		ImageKey:     imageKey,
		WhatsappURL:  whatsappURL,
		FacebookURL:  facebookURL,
		InstagramURL: instagramURL,
		YoutubeURL:   youtubeURL,
		Email:        email,
		WebsiteURL:   websiteURL,
		CreatedAt:    row.CreatedAt.Time,
		UpdatedAt:    row.UpdatedAt.Time,
	}
}

func nullableLandingText(v *string) pgtype.Text {
	if v == nil {
		return pgtype.Text{Valid: false}
	}
	return pgtype.Text{String: *v, Valid: true}
}
