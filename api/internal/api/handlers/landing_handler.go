package handler

import (
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"

	"callflow/internal/api/response"
	"callflow/internal/domain/landing"
	"callflow/internal/domain/user"

	"github.com/gin-gonic/gin"
)

// LandingHandler handles HTTP requests related to landing pages.
type LandingHandler struct {
	landingService landing.Service
	userService    user.Service
}

const maxLandingImageBytes = 5 * 1024 * 1024

var allowedLandingImageContentTypes = map[string]struct{}{
	"image/jpeg": {},
	"image/png":  {},
	"image/webp": {},
}

// NewLandingHandler creates a new landing handler instance.
func NewLandingHandler(landingService landing.Service, userService user.Service) *LandingHandler {
	return &LandingHandler{
		landingService: landingService,
		userService:    userService,
	}
}

// RegisterRoutes registers authenticated landing routes.
func (h *LandingHandler) RegisterRoutes(rg *gin.RouterGroup) {
	landingGroup := rg.Group("/landing")
	{
		landingGroup.GET("", h.Get)
		landingGroup.PUT("", h.Upsert)
		landingGroup.POST("/upload-image", h.UploadImage)
	}
}

// RegisterPublicRoutes registers public landing routes.
func (h *LandingHandler) RegisterPublicRoutes(rg *gin.RouterGroup) {
	public := rg.Group("/public")
	{
		public.GET("/landing/:id", h.GetPublic)
	}
}

// Get returns the authenticated user's landing page.
func (h *LandingHandler) Get(c *gin.Context) {
	userID, ok := getUserID(c)
	if !ok {
		return
	}

	u, err := h.userService.GetUser(c.Request.Context(), userID)
	if err != nil {
		internalError(c, response.ErrGetFailed, "Failed to get user", err)
		return
	}

	l, err := h.landingService.GetByUserID(c.Request.Context(), userID)
	if err != nil {
		if errors.Is(err, landing.ErrLandingNotFound) {
			l = &landing.Landing{UserID: userID}
		} else {
			internalError(c, response.ErrGetFailed, "Failed to get landing page", err)
			return
		}
	}

	response.Success(c, gin.H{
		"landing":      l,
		"location_url": u.LocationURL,
	})
}

type landingUpsertRequest struct {
	landing.LandingUpsert
	LocationURL *string `json:"location_url,omitempty"`
}

// Upsert creates or updates the authenticated user's landing page.
func (h *LandingHandler) Upsert(c *gin.Context) {
	userID, ok := getUserID(c)
	if !ok {
		return
	}

	var req landingUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, response.ErrInvalidRequest, "Invalid request body", err.Error())
		return
	}

	l, err := h.landingService.UpsertByUserID(c.Request.Context(), userID, req.LandingUpsert)
	if err != nil {
		if errors.Is(err, landing.ErrInvalidImageURL) || errors.Is(err, landing.ErrMissingImageKey) {
			response.BadRequest(c, response.ErrValidationFailed, "Invalid image data", err.Error())
			return
		}
		internalError(c, response.ErrUpdateFailed, "Failed to update landing page", err)
		return
	}

	if req.LocationURL != nil {
		if _, err := h.userService.UpdateUser(c.Request.Context(), userID, user.UserUpdate{
			LocationURL: req.LocationURL,
		}); err != nil {
			internalError(c, response.ErrUpdateFailed, "Failed to update location URL", err)
			return
		}
	}

	loc := ""
	if req.LocationURL != nil {
		loc = *req.LocationURL
	} else {
		if u, err := h.userService.GetUser(c.Request.Context(), userID); err == nil {
			loc = u.LocationURL
		}
	}

	response.Success(c, gin.H{
		"landing":      l,
		"location_url": loc,
	})
}

// UploadImage uploads a landing image and returns a public URL and storage key.
func (h *LandingHandler) UploadImage(c *gin.Context) {
	userID, ok := getUserID(c)
	if !ok {
		return
	}

	fileHeader, err := c.FormFile("image")
	if err != nil {
		response.BadRequest(c, response.ErrInvalidRequest, "image file is required", err.Error())
		return
	}
	if fileHeader.Size <= 0 {
		response.BadRequest(c, response.ErrInvalidRequest, "image file is empty", "")
		return
	}
	if fileHeader.Size > maxLandingImageBytes {
		response.BadRequest(c, response.ErrValidationFailed, "image file exceeds 5MB limit", "")
		return
	}

	file, err := fileHeader.Open()
	if err != nil {
		internalError(c, response.ErrCreateFailed, "Failed to open upload", err)
		return
	}
	defer file.Close()

	content, err := io.ReadAll(io.LimitReader(file, maxLandingImageBytes+1))
	if err != nil {
		internalError(c, response.ErrCreateFailed, "Failed to read upload", err)
		return
	}
	if len(content) > maxLandingImageBytes {
		response.BadRequest(c, response.ErrValidationFailed, "image file exceeds 5MB limit", "")
		return
	}

	contentType := detectLandingImageContentType(fileHeader.Header.Get("Content-Type"), content)
	if _, ok := allowedLandingImageContentTypes[contentType]; !ok {
		response.BadRequest(c, response.ErrValidationFailed, "Only JPEG, PNG, and WebP images are allowed", "")
		return
	}

	uploaded, err := h.landingService.UploadImage(
		c.Request.Context(),
		userID,
		fileHeader.Filename,
		contentType,
		content,
	)
	if err != nil {
		if errors.Is(err, landing.ErrUploadDisabled) {
			internalError(c, response.ErrCreateFailed, "Image upload is not configured", err)
			return
		}
		internalError(c, response.ErrCreateFailed, "Failed to upload image", err)
		return
	}

	response.Success(c, uploaded)
}

// GetPublic returns the public landing page for a user.
func (h *LandingHandler) GetPublic(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, response.ErrInvalidID, "Invalid user ID", err.Error())
		return
	}

	u, err := h.userService.GetUser(c.Request.Context(), id)
	if err != nil {
		response.NotFound(c, response.ErrNotFound, "User not found", "")
		return
	}

	if u.Status != user.StatusActive || u.Plan != user.PlanSMS {
		response.NotFound(c, response.ErrNotFound, "Landing page not found", "")
		return
	}

	l, err := h.landingService.GetByUserID(c.Request.Context(), id)
	if err != nil {
		if errors.Is(err, landing.ErrLandingNotFound) {
			l = &landing.Landing{UserID: id}
		} else {
			internalError(c, response.ErrGetFailed, "Failed to get landing page", err)
			return
		}
	}

	response.Success(c, gin.H{
		"user": gin.H{
			"id":            u.ID,
			"name":          u.Name,
			"business_name": u.BusinessName,
			"phone":         u.Phone,
			"address":       u.Address,
			"city":          u.City,
			"location_url":  u.LocationURL,
		},
		"landing": l,
	})
}

func detectLandingImageContentType(headerValue string, file []byte) string {
	headerType := strings.TrimSpace(strings.Split(headerValue, ";")[0])
	if _, ok := allowedLandingImageContentTypes[headerType]; ok {
		return headerType
	}
	return http.DetectContentType(file)
}
