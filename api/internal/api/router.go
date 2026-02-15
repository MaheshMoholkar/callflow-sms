package api

import (
	"net/http"
	"os"
	"runtime"
	"time"

	handler "callflow/internal/api/handlers"
	"callflow/internal/api/middleware"
	"callflow/internal/api/response"
	"callflow/internal/domain/auth"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

// HealthCheckResponse represents the structure of the health check response
type HealthCheckResponse struct {
	Status      string `json:"status"`
	Timestamp   int64  `json:"timestamp"`
	Version     string `json:"version"`
	Uptime      string `json:"uptime"`
	GoVersion   string `json:"go_version"`
	CPUCount    int    `json:"cpu_count"`
	MemoryStats struct {
		Alloc      uint64 `json:"alloc_bytes"`
		TotalAlloc uint64 `json:"total_alloc_bytes"`
		Sys        uint64 `json:"sys_bytes"`
		NumGC      uint32 `json:"num_gc"`
	} `json:"memory_stats"`
}

var startTime = time.Now()

func getHealthCheck() HealthCheckResponse {
	var memStats runtime.MemStats
	runtime.ReadMemStats(&memStats)

	return HealthCheckResponse{
		Status:    "healthy",
		Timestamp: time.Now().Unix(),
		Version:   "1.0.0",
		Uptime:    time.Since(startTime).String(),
		GoVersion: runtime.Version(),
		CPUCount:  runtime.NumCPU(),
		MemoryStats: struct {
			Alloc      uint64 `json:"alloc_bytes"`
			TotalAlloc uint64 `json:"total_alloc_bytes"`
			Sys        uint64 `json:"sys_bytes"`
			NumGC      uint32 `json:"num_gc"`
		}{
			Alloc:      memStats.Alloc,
			TotalAlloc: memStats.TotalAlloc,
			Sys:        memStats.Sys,
			NumGC:      memStats.NumGC,
		},
	}
}

// SetupRouter configures and returns the Gin router
func SetupRouter(
	authService auth.Service,
	authHandler *handler.AuthHandler,
	userHandler *handler.UserHandler,
	templateHandler *handler.TemplateHandler,
	ruleHandler *handler.RuleHandler,
	syncHandler *handler.SyncHandler,
	contactHandler *handler.ContactHandler,
	adminHandler *handler.AdminHandler,
) *gin.Engine {
	router := gin.Default()

	// CORS
	corsConfig := cors.DefaultConfig()
	corsConfig.AllowAllOrigins = true
	corsConfig.AllowHeaders = append(corsConfig.AllowHeaders, "Authorization")
	router.Use(cors.New(corsConfig))

	// API v1
	v1 := router.Group("/api/v1")

	// Public routes
	v1.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, getHealthCheck())
	})

	// App version check (public — for in-app update prompts)
	v1.GET("/app/version", func(c *gin.Context) {
		forceUpdate := os.Getenv("APP_FORCE_UPDATE") == "true"
		response.Success(c, gin.H{
			"version":       os.Getenv("APP_VERSION"),
			"version_code":  os.Getenv("APP_VERSION_CODE"),
			"download_url":  os.Getenv("APP_DOWNLOAD_URL"),
			"release_notes": os.Getenv("APP_RELEASE_NOTES"),
			"force_update":  forceUpdate,
		})
	})

	// Auth routes (public)
	authHandler.RegisterRoutes(v1)

	// Protected routes
	mf := middleware.NewMiddlewareFactory(authService)
	protected := v1.Group("")
	protected.Use(mf.AuthChain())
	{
		// User routes
		userHandler.RegisterRoutes(protected)

		// Template routes
		templateHandler.RegisterRoutes(protected)

		// Rule routes
		ruleHandler.RegisterRoutes(protected)

		// Contact routes
		contactHandler.RegisterRoutes(protected)

		// Sync routes
		syncHandler.RegisterRoutes(protected)

	}

	// Admin routes (no auth — local use only)
	adminHandler.RegisterRoutes(v1)

	// Serve admin UI at /admin
	serveAdmin(router)

	return router
}
