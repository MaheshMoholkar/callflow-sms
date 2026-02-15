package api

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
)

func serveAdmin(router *gin.Engine) {
	adminDistDir := os.Getenv("ADMIN_DIST_DIR")
	if adminDistDir == "" {
		adminDistDir = "/app/admin/dist"
	}

	if stat, err := os.Stat(adminDistDir); err == nil && stat.IsDir() {
		router.GET("/admin", func(c *gin.Context) {
			c.File(filepath.Join(adminDistDir, "index.html"))
		})
		router.GET("/admin/*path", func(c *gin.Context) {
			requestedPath := c.Param("path")
			cleanPath := filepath.Clean(strings.TrimPrefix(requestedPath, "/"))
			filePath := filepath.Join(adminDistDir, cleanPath)

			adminDirAbs, _ := filepath.Abs(adminDistDir)
			filePathAbs, _ := filepath.Abs(filePath)
			if strings.HasPrefix(filePathAbs, adminDirAbs) {
				if stat, err := os.Stat(filePath); err == nil && !stat.IsDir() {
					c.File(filePath)
					return
				}
			}
			c.File(filepath.Join(adminDistDir, "index.html"))
		})
	}
}
