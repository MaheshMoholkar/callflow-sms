package main

import (
	"log"
	"os"

	"callflow/config"
	"callflow/internal/api"
	handler "callflow/internal/api/handlers"
	"callflow/internal/api/middleware"
	"callflow/internal/repository"
	"callflow/internal/service"

	"github.com/joho/godotenv"
)

func main() {
	if _, err := os.Stat(".env"); err == nil {
		_ = godotenv.Load(".env")
	}

	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		log.Fatal("JWT_SECRET environment variable is required")
	}

	// Initialize database connection
	dbPool, err := config.InitDBPool()
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer dbPool.Close()

	// Ensure rate limiter cleanup goroutine is stopped on shutdown
	defer middleware.AuthRateLimiter.Stop()

	// Get port from environment
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Repositories
	userRepo := repository.NewUserRepository(dbPool)
	templateRepo := repository.NewTemplateRepository(dbPool)
	landingRepo := repository.NewLandingRepository(dbPool)
	ruleRepo := repository.NewRuleRepository(dbPool)
	contactRepo := repository.NewContactRepository(dbPool)

	// Services
	authService := service.NewAuthService(userRepo, jwtSecret)
	userService := service.NewUserService(userRepo)
	uploadThingStore, uploadThingErr := service.NewUploadThingImageStoreFromEnv()
	if uploadThingErr != nil {
		log.Printf("UploadThing not configured: %v", uploadThingErr)
	}
	templateService := service.NewTemplateService(templateRepo, uploadThingStore)
	landingService := service.NewLandingService(landingRepo, uploadThingStore)
	ruleService := service.NewRuleService(ruleRepo)
	contactService := service.NewContactService(contactRepo)

	// Handlers
	authHandler := handler.NewAuthHandler(authService)
	userHandler := handler.NewUserHandler(userService)
	templateHandler := handler.NewTemplateHandler(templateService)
	landingHandler := handler.NewLandingHandler(landingService, userService)
	ruleHandler := handler.NewRuleHandler(ruleService)
	syncHandler := handler.NewSyncHandler(userService, templateService, ruleService)
	contactHandler := handler.NewContactHandler(contactService)
	adminHandler := handler.NewAdminHandler(userService)

	// Setup router
	router := api.SetupRouter(
		authService,
		authHandler,
		userHandler,
		templateHandler,
		landingHandler,
		ruleHandler,
		syncHandler,
		contactHandler,
		adminHandler,
	)

	if router == nil {
		log.Fatal("Failed to setup router")
	}

	// Create and start server
	server := api.NewServer(router, port)
	if server == nil {
		log.Fatal("Failed to create server")
	}

	server.Start()
}
