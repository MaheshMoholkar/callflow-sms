package landing

import "errors"

var (
	ErrLandingNotFound = errors.New("landing page not found")
	ErrInvalidImageURL = errors.New("image_url must be a valid https URL")
	ErrMissingImageKey = errors.New("image_key is required when image_url is set")
	ErrUploadDisabled  = errors.New("image upload is not configured")
)
