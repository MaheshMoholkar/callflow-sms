package service

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"os"
	"path/filepath"
	"strings"
	"time"

	"callflow/internal/domain/landing"
	"callflow/internal/domain/template"
)

const (
	uploadThingAPIRoot  = "https://api.uploadthing.com"
	uploadThingTokenEnv = "UPLOADTHING_TOKEN"
)

type uploadThingTokenPayload struct {
	APIKey string `json:"apiKey"`
	AppID  string `json:"appId"`
}

type prepareUploadRequest struct {
	FileName string `json:"fileName"`
	FileSize int    `json:"fileSize"`
	FileType string `json:"fileType,omitempty"`
}

type prepareUploadResponse struct {
	URL string `json:"url"`
	Key string `json:"key"`
}

type UploadThingImageStore struct {
	apiKey string
	appID  string
	client *http.Client
}

func NewUploadThingImageStoreFromEnv() (*UploadThingImageStore, error) {
	cfg, err := readUploadThingConfigFromEnv()
	if err != nil {
		return nil, err
	}
	return &UploadThingImageStore{
		apiKey: cfg.APIKey,
		appID:  cfg.AppID,
		client: &http.Client{Timeout: 30 * time.Second},
	}, nil
}

func (s *UploadThingImageStore) UploadTemplateImage(
	ctx context.Context,
	filename,
	contentType string,
	file []byte,
) (*template.UploadedImage, error) {
	url, key, err := s.uploadImage(ctx, filename, contentType, file)
	if err != nil {
		return nil, err
	}
	return &template.UploadedImage{
		URL: url,
		Key: key,
	}, nil
}

func (s *UploadThingImageStore) UploadLandingImage(
	ctx context.Context,
	filename,
	contentType string,
	file []byte,
) (*landing.UploadedImage, error) {
	url, key, err := s.uploadImage(ctx, filename, contentType, file)
	if err != nil {
		return nil, err
	}
	return &landing.UploadedImage{
		URL: url,
		Key: key,
	}, nil
}

func (s *UploadThingImageStore) uploadImage(
	ctx context.Context,
	filename,
	contentType string,
	file []byte,
) (string, string, error) {
	if len(file) == 0 {
		return "", "", errors.New("empty file")
	}

	fileName := sanitizeFileName(filename)
	if fileName == "" {
		fileName = "image.jpg"
	}

	uploadURL, fileKey, err := s.prepareUpload(ctx, fileName, contentType, len(file))
	if err != nil {
		return "", "", err
	}

	if err := s.putMultipartFile(ctx, uploadURL, fileName, contentType, file); err != nil {
		return "", "", err
	}

	return fmt.Sprintf("https://%s.ufs.sh/f/%s", s.appID, fileKey), fileKey, nil
}

func (s *UploadThingImageStore) DeleteTemplateImage(ctx context.Context, imageKey string) error {
	return s.deleteImage(ctx, imageKey)
}

func (s *UploadThingImageStore) DeleteLandingImage(ctx context.Context, imageKey string) error {
	return s.deleteImage(ctx, imageKey)
}

func (s *UploadThingImageStore) deleteImage(ctx context.Context, imageKey string) error {
	imageKey = strings.TrimSpace(imageKey)
	if imageKey == "" {
		return nil
	}

	payload := map[string]interface{}{
		"fileKeys": []string{imageKey},
		"keys":     []string{imageKey},
		"keyType":  "fileKey",
	}
	body, _ := json.Marshal(payload)

	paths := []string{"/v6/deleteFiles", "/v7/deleteFiles"}
	var lastErr error
	for _, path := range paths {
		req, err := http.NewRequestWithContext(
			ctx,
			http.MethodPost,
			uploadThingAPIRoot+path,
			bytes.NewReader(body),
		)
		if err != nil {
			lastErr = err
			continue
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("x-uploadthing-api-key", s.apiKey)

		resp, err := s.client.Do(req)
		if err != nil {
			lastErr = err
			continue
		}

		respBody, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			return nil
		}

		lastErr = fmt.Errorf("uploadthing delete failed (%s): %s", resp.Status, strings.TrimSpace(string(respBody)))
	}
	if lastErr != nil {
		return lastErr
	}
	return errors.New("uploadthing delete failed")
}

func (s *UploadThingImageStore) prepareUpload(
	ctx context.Context,
	fileName, contentType string,
	fileSize int,
) (string, string, error) {
	reqBody := prepareUploadRequest{
		FileName: fileName,
		FileSize: fileSize,
		FileType: strings.TrimSpace(contentType),
	}
	body, err := json.Marshal(reqBody)
	if err != nil {
		return "", "", err
	}

	req, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		uploadThingAPIRoot+"/v7/prepareUpload",
		bytes.NewReader(body),
	)
	if err != nil {
		return "", "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-uploadthing-api-key", s.apiKey)

	resp, err := s.client.Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", "", fmt.Errorf("uploadthing prepare failed (%s): %s", resp.Status, strings.TrimSpace(string(respBody)))
	}

	var prepared prepareUploadResponse
	if err := json.Unmarshal(respBody, &prepared); err != nil {
		return "", "", fmt.Errorf("uploadthing prepare parse failed: %w", err)
	}
	if prepared.URL == "" || prepared.Key == "" {
		return "", "", errors.New("uploadthing prepare returned missing url/key")
	}
	return prepared.URL, prepared.Key, nil
}

func (s *UploadThingImageStore) putMultipartFile(
	ctx context.Context,
	uploadURL,
	fileName string,
	contentType string,
	file []byte,
) error {
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	if strings.TrimSpace(contentType) == "" {
		contentType = "application/octet-stream"
	}

	header := make(textproto.MIMEHeader)
	header.Set("Content-Disposition", fmt.Sprintf(`form-data; name="file"; filename="%s"`, fileName))
	header.Set("Content-Type", contentType)

	part, err := writer.CreatePart(header)
	if err != nil {
		return err
	}
	if _, err := part.Write(file); err != nil {
		return err
	}
	if err := writer.Close(); err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPut, uploadURL, &body)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("x-uploadthing-api-key", s.apiKey)

	resp, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}
	respBody, _ := io.ReadAll(resp.Body)
	return fmt.Errorf("uploadthing upload failed (%s): %s", resp.Status, strings.TrimSpace(string(respBody)))
}

func readUploadThingConfigFromEnv() (*uploadThingTokenPayload, error) {
	token := strings.TrimSpace(os.Getenv(uploadThingTokenEnv))
	token = strings.Trim(token, `"'`)
	if token == "" {
		return nil, errors.New("UPLOADTHING_TOKEN is required")
	}

	decoded, err := decodeUploadThingToken(token)
	if err != nil {
		return nil, err
	}

	if decoded.APIKey == "" || decoded.AppID == "" {
		return nil, errors.New("missing UploadThing credentials (apiKey/appId)")
	}

	return decoded, nil
}

func decodeUploadThingToken(token string) (*uploadThingTokenPayload, error) {
	var payload uploadThingTokenPayload
	decodeFns := []func(string) ([]byte, error){
		base64.StdEncoding.DecodeString,
		base64.RawStdEncoding.DecodeString,
		base64.URLEncoding.DecodeString,
		base64.RawURLEncoding.DecodeString,
	}

	var lastErr error
	for _, decode := range decodeFns {
		decoded, err := decode(token)
		if err != nil {
			lastErr = err
			continue
		}
		if err := json.Unmarshal(decoded, &payload); err != nil {
			lastErr = err
			continue
		}
		return &payload, nil
	}

	return nil, fmt.Errorf("failed to decode UPLOADTHING_TOKEN: %w", lastErr)
}

func sanitizeFileName(name string) string {
	base := strings.TrimSpace(filepath.Base(name))
	if base == "" || base == "." || base == "/" {
		return ""
	}

	var b strings.Builder
	for _, ch := range base {
		if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
			(ch >= '0' && ch <= '9') || ch == '.' || ch == '_' || ch == '-' {
			b.WriteRune(ch)
		} else {
			b.WriteRune('_')
		}
	}
	out := strings.Trim(b.String(), "._-")
	if out == "" {
		return ""
	}
	return out
}
