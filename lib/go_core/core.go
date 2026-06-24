package weavefluxcore

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

// GoStatusListener is implemented by the Android host through gomobile. Go
// invokes it from a background goroutine when a remote task reaches a terminal
// status or times out.
type GoStatusListener interface {
	OnStatusChanged(status string, videoURL string, errStr string)
}

var activePollingTasks sync.Map

type connectionResult struct {
	Success bool   `json:"success"`
	Error   string `json:"error"`
}

type modelsResult struct {
	Success     bool     `json:"success"`
	Models      []string `json:"models"`
	VideoModels []string `json:"video_models"`
	ImageModels []string `json:"image_models"`
	Error       string   `json:"error"`
	Debug       string   `json:"debug"`
}

type dispatchResult struct {
	TaskID    string `json:"task_id"`
	Status    string `json:"status"`
	ResultURL string `json:"result_url"`
	ResultB64 string `json:"result_b64"`
	Error     string `json:"error"`
}

type videoGenerationRequest struct {
	Model           string  `json:"model"`
	Prompt          string  `json:"prompt"`
	Size            string  `json:"size"`
	MotionScale     float64 `json:"motion_scale,omitempty"`
	Duration        int     `json:"duration,omitempty"`
	NegativePrompt  string  `json:"negative_prompt,omitempty"`
	PromptExtension *bool   `json:"prompt_extension,omitempty"`
	Watermark       *bool   `json:"watermark,omitempty"`
	Seed            string  `json:"seed,omitempty"`
	Template        string  `json:"template,omitempty"`
	Mode            string  `json:"mode,omitempty"`
	Image           string  `json:"image,omitempty"`
	LastFrameImage  string  `json:"last_frame_image,omitempty"`
	Video           string  `json:"video,omitempty"`
	Audio           string  `json:"audio,omitempty"`
	FirstFrameURL   string  `json:"first_frame_url,omitempty"`
	LastFrameURL    string  `json:"last_frame_url,omitempty"`
	ClipURL         string  `json:"clip_url,omitempty"`
	AudioURL        string  `json:"audio_url,omitempty"`
}

type chatCompletionRequest struct {
	Model       string        `json:"model"`
	Messages    []chatMessage `json:"messages"`
	Size        string        `json:"size,omitempty"`
	MotionScale float64       `json:"motion_scale,omitempty"`
}

type chatMessage struct {
	Role    string `json:"role"`
	Content any    `json:"content"`
}

type multimodalContent struct {
	Type     string    `json:"type"`
	Text     string    `json:"text,omitempty"`
	ImageURL *imageURL `json:"image_url,omitempty"`
}

type imageURL struct {
	URL string `json:"url"`
}

type dispatchAttempt struct {
	Path string
	Body any
}

const dispatchRequestTimeout = 25 * time.Second

type videoDispatchPayload struct {
	Model           string `json:"model"`
	Prompt          string `json:"prompt"`
	Size            string `json:"size"`
	MotionScale     string `json:"motion_scale"`
	Duration        string `json:"duration"`
	NegativePrompt  string `json:"negative_prompt"`
	PromptExtension string `json:"prompt_extension"`
	Watermark       string `json:"watermark"`
	Seed            string `json:"seed"`
	Template        string `json:"template"`
	Mode            string `json:"mode"`
	ImageBase64     string `json:"image_base64"`
	LastFrameBase64 string `json:"last_frame_base64"`
	ClipBase64      string `json:"clip_base64"`
	AudioBase64     string `json:"audio_base64"`
	FirstFrameURL   string `json:"first_frame_url"`
	LastFrameURL    string `json:"last_frame_url"`
	ClipURL         string `json:"clip_url"`
	AudioURL        string `json:"audio_url"`
}

type imageGenerationRequest struct {
	Model          string `json:"model"`
	Prompt         string `json:"prompt"`
	Size           string `json:"size,omitempty"`
	Quality        string `json:"quality,omitempty"`
	N              int    `json:"n,omitempty"`
	NegativePrompt string `json:"negative_prompt,omitempty"`
	Seed           string `json:"seed,omitempty"`
	Image          string `json:"image,omitempty"`
}

type imageDispatchPayload struct {
	Model          string `json:"model"`
	Prompt         string `json:"prompt"`
	Size           string `json:"size"`
	Quality        string `json:"quality"`
	Count          string `json:"count"`
	NegativePrompt string `json:"negative_prompt"`
	Seed           string `json:"seed"`
	ImageBase64    string `json:"image_base64"`
}

type taskStatusResult struct {
	Success   bool   `json:"success"`
	Status    string `json:"status"`
	ResultURL string `json:"result_url"`
	ResultB64 string `json:"result_b64"`
	Error     string `json:"error"`
}

type modelsResponse struct {
	Data []modelItem `json:"data"`
}

type modelItem struct {
	ID         string          `json:"id"`
	Categories json.RawMessage `json:"categories"`
}

type modelCollection struct {
	Models               []string
	VideoModels          []string
	ImageModels          []string
	Total                int
	Kept                 int
	KeptVideo            int
	KeptImage            int
	RejectedTextFamily   int
	RejectedNotVideoLike int
	RejectedNoMediaTag   int
	Duplicate            int
	EmptyID              int
	Samples              []string
}

// TestConnection checks the user-provided OpenAI-compatible /models endpoint.
//
// gomobile bind has limited support for multiple non-error return values, so
// this exported boundary returns a JSON string and lets Android/Dart decode it.
func TestConnection(baseURL, apiKey string) (result string) {
	defer recoverJSONResult(&result, func(err string) string {
		return encodeConnectionResult(false, err)
	})
	resp, errMsg := requestModels(baseURL, apiKey, 20*time.Second)
	if errMsg != "" {
		return encodeConnectionResult(false, errMsg)
	}
	resp.Body.Close()
	return encodeConnectionResult(true, "")
}

// FetchModels returns the available OpenAI-compatible model IDs as JSON.
func FetchModels(baseURL, apiKey string) (result string) {
	defer recoverJSONResult(&result, func(err string) string {
		return encodeModelsResult(false, nil, nil, err, "")
	})
	collection, errMsg := fetchModelIDs(baseURL, apiKey)
	if errMsg != "" {
		return encodeModelsResult(false, nil, nil, errMsg, "")
	}
	if len(collection.VideoModels) == 0 && len(collection.ImageModels) == 0 {
		return encodeModelsResult(false, nil, nil, "No video/image tagged models returned by /models", collection.Debug())
	}
	return encodeModelsResult(true, collection.VideoModels, collection.ImageModels, "", "plain request: "+collection.Debug())
}

// DispatchVideoTask sends a T2V/I2V video generation request.
func DispatchVideoTask(baseURL, apiKey, model, prompt, size, motionScale, imageBase64 string) (result string) {
	defer recoverJSONResult(&result, encodeDispatchPanic)
	payload := videoDispatchPayload{
		Model:       model,
		Prompt:      prompt,
		Size:        size,
		MotionScale: motionScale,
		ImageBase64: imageBase64,
	}
	data, err := json.Marshal(payload)
	if err != nil {
		return encodeDispatchResult("", "", "", "", "Failed to encode video payload")
	}
	return DispatchVideoTaskV2(baseURL, apiKey, string(data))
}

// DispatchVideoTaskV2 accepts a JSON payload so Dart and Go can exchange rich
// request data while keeping the gomobile boundary to primitive strings.
func DispatchVideoTaskV2(baseURL, apiKey, payloadJSON string) (result string) {
	defer recoverJSONResult(&result, encodeDispatchPanic)
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	apiKey = strings.TrimSpace(apiKey)

	var payload videoDispatchPayload
	if err := json.Unmarshal([]byte(payloadJSON), &payload); err != nil {
		return encodeDispatchResult("", "", "", "", fmt.Sprintf("Invalid video payload JSON: %v", err))
	}

	model := strings.TrimSpace(payload.Model)
	prompt := strings.TrimSpace(payload.Prompt)
	size := strings.TrimSpace(payload.Size)
	imageBase64 := strings.TrimSpace(payload.ImageBase64)
	lastFrameBase64 := strings.TrimSpace(payload.LastFrameBase64)
	clipBase64 := strings.TrimSpace(payload.ClipBase64)
	audioBase64 := strings.TrimSpace(payload.AudioBase64)

	if baseURL == "" {
		return encodeDispatchResult("", "", "", "", "Base URL is empty")
	}
	if apiKey == "" {
		return encodeDispatchResult("", "", "", "", "API Key is empty")
	}
	if model == "" {
		return encodeDispatchResult("", "", "", "", "Model is empty")
	}
	if prompt == "" {
		return encodeDispatchResult("", "", "", "", "Prompt is empty")
	}
	if size == "" {
		return encodeDispatchResult("", "", "", "", "Size is empty")
	}

	motion, err := strconv.ParseFloat(strings.TrimSpace(payload.MotionScale), 64)
	if err != nil {
		motion = 0
	}
	duration, _ := strconv.Atoi(strings.TrimSpace(payload.Duration))
	promptExtension, hasPromptExtension := parseOptionalBool(payload.PromptExtension)
	watermark, hasWatermark := parseOptionalBool(payload.Watermark)

	videoMode := normalizeVideoMode(payload.Mode)
	requestBody := videoGenerationRequest{
		Model:          model,
		Prompt:         prompt,
		Size:           size,
		MotionScale:    motion,
		Duration:       duration,
		NegativePrompt: strings.TrimSpace(payload.NegativePrompt),
		Seed:           strings.TrimSpace(payload.Seed),
		Template:       strings.TrimSpace(payload.Template),
		Mode:           videoMode,
		Image:          asDataURL(imageBase64, "image/jpeg"),
		LastFrameImage: asDataURL(lastFrameBase64, "image/jpeg"),
		Video:          asDataURL(clipBase64, "video/mp4"),
		Audio:          asDataURL(audioBase64, "audio/mpeg"),
		FirstFrameURL:  strings.TrimSpace(payload.FirstFrameURL),
		LastFrameURL:   strings.TrimSpace(payload.LastFrameURL),
		ClipURL:        strings.TrimSpace(payload.ClipURL),
		AudioURL:       strings.TrimSpace(payload.AudioURL),
	}
	if hasPromptExtension {
		requestBody.PromptExtension = &promptExtension
	}
	if hasWatermark {
		requestBody.Watermark = &watermark
	}

	attempts := videoDispatchAttempts(
		requestBody,
		buildChatCompletionRequest(model, videoPayloadPrompt(payload, videoMode), size, motion, imageBase64),
	)

	errors := make([]string, 0, len(attempts))
	for _, attempt := range attempts {
		taskID, resultURL, resultB64, unsupported, errMsg := dispatchToEndpoint(baseURL, apiKey, attempt)
		if errMsg == "" {
			status := "processing"
			if resultURL != "" || resultB64 != "" {
				status = "completed"
			}
			return encodeDispatchResult(taskID, status, resultURL, resultB64, "")
		}
		errors = append(errors, attempt.Path+": "+errMsg)
		if !unsupported {
			return encodeDispatchResult("", "", "", "", errMsg)
		}
	}

	return encodeDispatchResult("", "", "", "", strings.Join(errors, "; "))
}

// DispatchImageTask sends an OpenAI-compatible image generation request.
func DispatchImageTask(baseURL, apiKey, payloadJSON string) (result string) {
	defer recoverJSONResult(&result, encodeDispatchPanic)
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	apiKey = strings.TrimSpace(apiKey)

	var payload imageDispatchPayload
	if err := json.Unmarshal([]byte(payloadJSON), &payload); err != nil {
		return encodeDispatchResult("", "", "", "", fmt.Sprintf("Invalid image payload JSON: %v", err))
	}

	model := strings.TrimSpace(payload.Model)
	prompt := strings.TrimSpace(payload.Prompt)
	if baseURL == "" {
		return encodeDispatchResult("", "", "", "", "Base URL is empty")
	}
	if apiKey == "" {
		return encodeDispatchResult("", "", "", "", "API Key is empty")
	}
	if model == "" {
		return encodeDispatchResult("", "", "", "", "Model is empty")
	}
	if prompt == "" {
		return encodeDispatchResult("", "", "", "", "Prompt is empty")
	}

	count, _ := strconv.Atoi(strings.TrimSpace(payload.Count))
	if count <= 0 {
		count = 1
	}

	body := imageGenerationRequest{
		Model:          model,
		Prompt:         prompt,
		Size:           strings.TrimSpace(payload.Size),
		Quality:        strings.TrimSpace(payload.Quality),
		N:              count,
		NegativePrompt: strings.TrimSpace(payload.NegativePrompt),
		Seed:           strings.TrimSpace(payload.Seed),
		Image:          asDataURL(strings.TrimSpace(payload.ImageBase64), "image/jpeg"),
	}

	attempts := []dispatchAttempt{
		{
			Path: "/images/generations",
			Body: body,
		},
		{
			Path: "/images/generations/",
			Body: body,
		},
	}

	errors := make([]string, 0, len(attempts))
	for _, attempt := range attempts {
		taskID, resultURL, resultB64, unsupported, errMsg := dispatchToEndpoint(baseURL, apiKey, attempt)
		if errMsg == "" {
			status := "processing"
			if resultURL != "" || resultB64 != "" {
				status = "completed"
			}
			return encodeDispatchResult(taskID, status, resultURL, resultB64, "")
		}
		errors = append(errors, attempt.Path+": "+errMsg)
		if !unsupported {
			return encodeDispatchResult("", "", "", "", errMsg)
		}
	}

	return encodeDispatchResult("", "", "", "", strings.Join(errors, "; "))
}

func videoDispatchAttempts(videoBody videoGenerationRequest, chatBody chatCompletionRequest) []dispatchAttempt {
	return []dispatchAttempt{
		{
			Path: "/video/generations",
			Body: videoBody,
		},
		{
			Path: "/videos/generations",
			Body: videoBody,
		},
		{
			Path: "/videos",
			Body: videoBody,
		},
		{
			Path: "/chat/completions",
			Body: chatBody,
		},
	}
}

// QueryTask checks a remote async generation task. It intentionally tries a
// small set of common OpenAI-compatible provider paths.
func QueryTask(baseURL, apiKey, taskID string) (result string) {
	defer recoverJSONResult(&result, func(err string) string {
		return encodeTaskStatusResult(false, "", "", "", err)
	})
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	apiKey = strings.TrimSpace(apiKey)
	taskID = strings.TrimSpace(taskID)
	if baseURL == "" {
		return encodeTaskStatusResult(false, "", "", "", "Base URL is empty")
	}
	if apiKey == "" {
		return encodeTaskStatusResult(false, "", "", "", "API Key is empty")
	}
	if taskID == "" {
		return encodeTaskStatusResult(false, "", "", "", "Task ID is empty")
	}

	paths := []string{
		"/video/generations/" + taskID,
		"/videos/generations/" + taskID,
		"/videos/" + taskID,
		"/videos/tasks/" + taskID,
		"/videos/" + taskID + "/content",
		"/tasks/" + taskID,
	}
	errors := make([]string, 0, len(paths))
	for _, path := range paths {
		status, resultURL, resultB64, unsupported, errMsg := queryTaskEndpoint(baseURL, apiKey, path)
		if errMsg == "" {
			return encodeTaskStatusResult(true, status, resultURL, resultB64, "")
		}
		errors = append(errors, path+": "+errMsg)
		if !unsupported {
			return encodeTaskStatusResult(false, "", "", "", errMsg)
		}
	}
	return encodeTaskStatusResult(false, "", "", "", strings.Join(errors, "; "))
}

// StartPollingTask starts a non-blocking background poller for a single remote
// video task. It uses the new-api task fetch route requested by the Android
// bridge and reports terminal states through GoStatusListener.
func StartPollingTask(baseURL, apiKey, taskID string, listener GoStatusListener) {
	defer func() {
		if recovered := recover(); recovered != nil {
			errMsg := fmt.Sprintf("Go Native Panic: %v", recovered)
			log.Printf("[Go Native Panic Caught]: %s", errMsg)
			safeNotify(listener, "failed", "", errMsg)
		}
	}()
	go func() {
		baseURL := strings.TrimRight(strings.TrimSpace(baseURL), "/")
		apiKey := strings.TrimSpace(apiKey)
		taskID := strings.TrimSpace(taskID)

		if listener == nil {
			return
		}
		if baseURL == "" || apiKey == "" || taskID == "" {
			safeNotify(listener, "failed", "", "Missing polling parameters")
			return
		}
		if _, loaded := activePollingTasks.LoadOrStore(taskID, true); loaded {
			return
		}
		defer activePollingTasks.Delete(taskID)
		defer func() {
			if recovered := recover(); recovered != nil {
				errMsg := fmt.Sprintf("Go Native Panic: %v", recovered)
				log.Printf("[Go Native Panic Caught]: %s", errMsg)
				safeNotify(listener, "failed", "", errMsg)
			}
		}()

		ticker := time.NewTicker(7 * time.Second)
		defer ticker.Stop()

		const maxAttempts = 60
		var lastErr string
		for attempt := 1; attempt <= maxAttempts; attempt++ {
			status, videoURL, errMsg := queryTaskWithFallback(baseURL, apiKey, taskID)
			if errMsg != "" {
				lastErr = errMsg
			} else {
				status = normalizeRemoteStatus(status)
				switch status {
				case "completed":
					safeNotify(listener, "success", videoURL, "")
					return
				case "failed":
					safeNotify(listener, "failed", videoURL, "Remote task failed")
					return
				}
			}

			if attempt < maxAttempts {
				<-ticker.C
			}
		}

		if lastErr == "" {
			lastErr = "Polling timed out"
		} else {
			lastErr = "Polling timed out: " + lastErr
		}
		safeNotify(listener, "failed", "", lastErr)
	}()
}

func queryTaskWithFallback(baseURL, apiKey, taskID string) (string, string, string) {
	paths := []string{
		"/videos/tasks/" + taskID,
		"/videos/generations/" + taskID,
		"/video/generations/" + taskID,
		"/videos/" + taskID,
		"/videos/" + taskID + "/content",
		"/tasks/" + taskID,
	}

	errors := make([]string, 0, len(paths))
	for _, path := range paths {
		status, resultURL, _, unsupported, errMsg := queryTaskEndpoint(baseURL, apiKey, path)
		if errMsg == "" {
			return status, resultURL, ""
		}
		errors = append(errors, path+": "+errMsg)
		if !unsupported {
			return "", "", errMsg
		}
	}
	return "", "", strings.Join(errors, "; ")
}

func normalizeRemoteStatus(status string) string {
	switch strings.TrimSpace(strings.ToLower(status)) {
	case "completed", "succeeded", "success", "finished", "complete":
		return "completed"
	case "failed", "error", "cancelled", "canceled":
		return "failed"
	default:
		return "processing"
	}
}

func recoverJSONResult(result *string, encoder func(string) string) {
	if recovered := recover(); recovered != nil {
		errMsg := fmt.Sprintf("Go Native Panic: %v", recovered)
		log.Printf("[Go Native Panic Caught]: %s", errMsg)
		*result = encoder(errMsg)
	}
}

func encodeDispatchPanic(err string) string {
	return encodeDispatchResult("", "", "", "", err)
}

func safeNotify(listener GoStatusListener, status, videoURL, errStr string) {
	if listener == nil {
		return
	}
	defer func() {
		if recovered := recover(); recovered != nil {
			log.Printf("[Go Native Panic Caught]: listener callback failed: %v", recovered)
		}
	}()
	listener.OnStatusChanged(status, videoURL, errStr)
}

func fetchModelIDs(baseURL, apiKey string) (modelCollection, string) {
	resp, errMsg := requestModelsWithRetry(baseURL, apiKey, 180*time.Second, 2)
	if errMsg != "" {
		return modelCollection{}, errMsg
	}
	defer resp.Body.Close()

	var payload modelsResponse
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return modelCollection{}, fmt.Sprintf("Invalid /models response: %v", err)
	}

	collection := collectMediaModelIDs(payload.Data)

	if items, queryErr := fetchModelItems(baseURL, apiKey, "/models?categories=video"); queryErr == "" {
		collection.mergeTypedModels(items, "video")
	}
	if items, queryErr := fetchModelItems(baseURL, apiKey, "/models?categories=image"); queryErr == "" {
		collection.mergeTypedModels(items, "image")
	}

	return collection, ""
}

func fetchModelItems(baseURL, apiKey, path string) ([]modelItem, string) {
	resp, errMsg := requestModelsPathWithRetry(baseURL, apiKey, path, 60*time.Second, 1)
	if errMsg != "" {
		return nil, errMsg
	}
	defer resp.Body.Close()

	var payload modelsResponse
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil, fmt.Sprintf("Invalid %s response: %v", path, err)
	}
	return payload.Data, ""
}

func extractTaskID(data []byte) string {
	var payload map[string]any
	if err := json.Unmarshal(data, &payload); err != nil {
		return extractTaskIDFromText(string(data))
	}
	if taskID := findTaskID(payload); taskID != "" {
		return taskID
	}
	return extractTaskIDFromText(string(data))
}

func extractResultURL(data []byte) string {
	var payload any
	if err := json.Unmarshal(data, &payload); err != nil {
		return extractResultURLFromText(string(data))
	}
	if value := findStringByKeys(payload, []string{"url", "video_url", "output_url", "result_url", "image_url"}); value != "" {
		return value
	}
	return extractResultURLFromText(string(data))
}

func extractResultB64(data []byte) string {
	var payload any
	if err := json.Unmarshal(data, &payload); err != nil {
		return extractResultB64FromText(string(data))
	}
	if value := findStringByKeys(payload, []string{"b64_json", "base64", "image_base64", "video_base64"}); value != "" {
		return value
	}
	return extractResultB64FromText(string(data))
}

func extractStatus(data []byte) string {
	var payload any
	if err := json.Unmarshal(data, &payload); err != nil {
		return ""
	}
	status := strings.ToLower(findStringByKeys(payload, []string{"status", "state"}))
	switch status {
	case "succeeded", "success", "finished", "complete":
		return "completed"
	case "failed", "error", "cancelled", "canceled":
		return "failed"
	case "queued", "pending", "running", "processing", "in_progress", "submitted":
		return "processing"
	default:
		return status
	}
}

func findStringByKeys(value any, keys []string) string {
	switch typed := value.(type) {
	case map[string]any:
		for _, key := range keys {
			if raw, ok := typed[key].(string); ok && strings.TrimSpace(raw) != "" {
				return strings.TrimSpace(raw)
			}
		}
		for _, item := range typed {
			if value := findStringByKeys(item, keys); value != "" {
				return value
			}
		}
	case []any:
		for _, item := range typed {
			if value := findStringByKeys(item, keys); value != "" {
				return value
			}
		}
	case string:
		var nested any
		if err := json.Unmarshal([]byte(typed), &nested); err == nil {
			if value := findStringByKeys(nested, keys); value != "" {
				return value
			}
		}
	}
	return ""
}

func extractResultURLFromText(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`data:(?:image|video)/[A-Za-z0-9.+-]+;base64,[A-Za-z0-9+/=_-]+`),
		regexp.MustCompile(`https?://[^\s"'<>，。)）]+`),
	}
	for _, pattern := range patterns {
		if match := pattern.FindString(value); match != "" {
			return strings.TrimRight(match, ".,;")
		}
	}
	return ""
}

func extractResultB64FromText(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	pattern := regexp.MustCompile(`(?i)(?:b64_json|base64|image_base64|video_base64)\s*[:=]\s*"?(data:[^,"\s]+|[A-Za-z0-9+/=_-]{80,})"?`)
	matches := pattern.FindStringSubmatch(value)
	if len(matches) > 1 {
		return strings.TrimSpace(matches[1])
	}
	return ""
}

func findTaskID(value any) string {
	switch typed := value.(type) {
	case map[string]any:
		for _, key := range []string{"task_id", "taskId", "taskID", "id"} {
			if value, ok := typed[key].(string); ok && strings.TrimSpace(value) != "" {
				return strings.TrimSpace(value)
			}
		}
		for _, item := range typed {
			if taskID := findTaskID(item); taskID != "" {
				return taskID
			}
		}
	case []any:
		for _, item := range typed {
			if taskID := findTaskID(item); taskID != "" {
				return taskID
			}
		}
	case string:
		return extractTaskIDFromText(typed)
	}
	return ""
}

func extractTaskIDFromText(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	var nested any
	if err := json.Unmarshal([]byte(value), &nested); err == nil {
		if taskID := findTaskID(nested); taskID != "" {
			return taskID
		}
	}
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`(?i)"(?:task_id|taskId|taskID|id)"\s*:\s*"([^"]+)"`),
		regexp.MustCompile(`(?i)(?:task_id|taskId|taskID)\s*[:=]\s*([A-Za-z0-9._:-]+)`),
	}
	for _, pattern := range patterns {
		matches := pattern.FindStringSubmatch(value)
		if len(matches) > 1 && strings.TrimSpace(matches[1]) != "" {
			return strings.TrimSpace(matches[1])
		}
	}
	return ""
}

func dispatchToEndpoint(baseURL, apiKey string, attempt dispatchAttempt) (string, string, string, bool, string) {
	body, err := json.Marshal(attempt.Body)
	if err != nil {
		return "", "", "", false, fmt.Sprintf("Failed to encode request: %v", err)
	}

	req, err := http.NewRequest(http.MethodPost, baseURL+attempt.Path, bytes.NewReader(body))
	if err != nil {
		return "", "", "", false, fmt.Sprintf("Invalid request: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: dispatchRequestTimeout}
	resp, err := client.Do(req)
	if err != nil {
		return "", "", "", false, fmt.Sprintf("Network error: %v", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 1024*1024))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		message := strings.TrimSpace(string(respBody))
		if message == "" {
			message = http.StatusText(resp.StatusCode)
		}
		errMsg := fmt.Sprintf("HTTP %d: %s", resp.StatusCode, message)
		return "", "", "", isUnsupportedEndpoint(resp.StatusCode, message), errMsg
	}

	taskID := extractTaskID(respBody)
	if attempt.Path == "/chat/completions" {
		taskID = extractChatTaskID(respBody)
	}
	resultURL := extractResultURL(respBody)
	resultB64 := extractResultB64(respBody)
	if taskID == "" && resultURL != "" {
		taskID = resultURL
	}
	if taskID == "" && resultB64 != "" {
		taskID = "inline_base64_result"
	}
	if taskID == "" {
		return "", "", "", false, "No task_id/url/b64_json returned by " + attempt.Path + ": " + responsePreview(respBody)
	}
	return taskID, resultURL, resultB64, false, ""
}

func responsePreview(data []byte) string {
	value := strings.TrimSpace(string(data))
	if value == "" {
		return "<empty response body>"
	}
	const limit = 1200
	if len(value) > limit {
		return value[:limit] + "...<truncated>"
	}
	return value
}

func queryTaskEndpoint(baseURL, apiKey, path string) (string, string, string, bool, string) {
	req, err := http.NewRequest(http.MethodGet, baseURL+path, nil)
	if err != nil {
		return "", "", "", false, fmt.Sprintf("Invalid request: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)

	client := &http.Client{Timeout: 45 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", "", "", false, fmt.Sprintf("Network error: %v", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 1024*1024))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		message := strings.TrimSpace(string(respBody))
		if message == "" {
			message = http.StatusText(resp.StatusCode)
		}
		return "", "", "", isUnsupportedEndpoint(resp.StatusCode, message), fmt.Sprintf("HTTP %d: %s", resp.StatusCode, message)
	}

	status := extractStatus(respBody)
	resultURL := extractResultURL(respBody)
	resultB64 := extractResultB64(respBody)
	if status == "" {
		if resultURL != "" || resultB64 != "" {
			status = "completed"
		} else {
			status = "processing"
		}
	}
	return status, resultURL, resultB64, false, ""
}

func extractChatTaskID(data []byte) string {
	var payload map[string]any
	if err := json.Unmarshal(data, &payload); err != nil {
		return extractTaskIDFromText(string(data))
	}
	choices, ok := payload["choices"].([]any)
	if !ok {
		return ""
	}
	for _, choice := range choices {
		choiceMap, ok := choice.(map[string]any)
		if !ok {
			continue
		}
		for _, messageKey := range []string{"message", "delta"} {
			message, ok := choiceMap[messageKey].(map[string]any)
			if !ok {
				continue
			}
			content, ok := message["content"].(string)
			if ok {
				if taskID := extractTaskIDFromText(content); taskID != "" {
					return taskID
				}
			}
		}
	}
	return ""
}

func buildChatCompletionRequest(model, prompt, size string, motion float64, imageBase64 string) chatCompletionRequest {
	text := fmt.Sprintf("%s\n\nVideo generation parameters:\nsize: %s\nmotion_scale: %.3f", prompt, size, motion)
	message := chatMessage{Role: "user", Content: text}
	if imageBase64 != "" {
		message.Content = []multimodalContent{
			{Type: "text", Text: text},
			{Type: "image_url", ImageURL: &imageURL{URL: "data:image/jpeg;base64," + imageBase64}},
		}
	}
	return chatCompletionRequest{
		Model:       model,
		Messages:    []chatMessage{message},
		Size:        size,
		MotionScale: motion,
	}
}

func buildImageChatCompletionRequest(payload imageDispatchPayload, body imageGenerationRequest) chatCompletionRequest {
	text := strings.Join([]string{
		strings.TrimSpace(payload.Prompt),
		"",
		"Image generation parameters:",
		"size: " + strings.TrimSpace(payload.Size),
		"quality: " + strings.TrimSpace(payload.Quality),
		"n: " + strings.TrimSpace(payload.Count),
		"negative_prompt: " + strings.TrimSpace(payload.NegativePrompt),
		"seed: " + strings.TrimSpace(payload.Seed),
		"",
		"Return either a JSON object containing task_id, url, or b64_json.",
	}, "\n")
	message := chatMessage{
		Role: "user",
		Content: []multimodalContent{
			{Type: "text", Text: text},
		},
	}
	if body.Image != "" {
		message.Content = []multimodalContent{
			{Type: "text", Text: text},
			{Type: "image_url", ImageURL: &imageURL{URL: body.Image}},
		}
	}
	return chatCompletionRequest{
		Model:    strings.TrimSpace(payload.Model),
		Messages: []chatMessage{message},
		Size:     strings.TrimSpace(payload.Size),
	}
}

func videoPayloadPrompt(payload videoDispatchPayload, videoMode string) string {
	parts := []string{strings.TrimSpace(payload.Prompt), "", "Video generation parameters:"}
	addPromptPart := func(label, value string) {
		value = strings.TrimSpace(value)
		if value != "" {
			parts = append(parts, label+": "+value)
		}
	}
	addPromptPart("mode", videoMode)
	addPromptPart("size", payload.Size)
	addPromptPart("duration", payload.Duration)
	addPromptPart("motion_scale", payload.MotionScale)
	addPromptPart("negative_prompt", payload.NegativePrompt)
	addPromptPart("prompt_extension", payload.PromptExtension)
	addPromptPart("watermark", payload.Watermark)
	addPromptPart("seed", payload.Seed)
	addPromptPart("template", payload.Template)
	addPromptPart("first_frame_url", payload.FirstFrameURL)
	addPromptPart("last_frame_url", payload.LastFrameURL)
	addPromptPart("clip_url", payload.ClipURL)
	addPromptPart("audio_url", payload.AudioURL)
	if payload.LastFrameBase64 != "" {
		parts = append(parts, "last_frame_image: attached as base64 payload")
	}
	if payload.ClipBase64 != "" {
		parts = append(parts, "clip: attached as base64 payload")
	}
	if payload.AudioBase64 != "" {
		parts = append(parts, "audio: attached as base64 payload")
	}
	return strings.Join(parts, "\n")
}

func parseOptionalBool(value string) (bool, bool) {
	value = strings.ToLower(strings.TrimSpace(value))
	if value == "" {
		return false, false
	}
	switch value {
	case "true", "1", "yes", "on":
		return true, true
	case "false", "0", "no", "off":
		return false, true
	default:
		return false, false
	}
}

func normalizeVideoMode(value string) string {
	switch strings.ToLower(strings.ReplaceAll(strings.TrimSpace(value), "_", "")) {
	case "keyframes", "firstlastframe", "firstlast", "lastframe":
		return "keyframes"
	case "ti2vid", "t2v", "i2v", "promptonly", "prompt", "firstframe", "extendclip", "extend":
		return "ti2vid"
	default:
		if strings.TrimSpace(value) == "" {
			return "ti2vid"
		}
		return strings.TrimSpace(value)
	}
}

func asDataURL(value, mimeType string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	if strings.HasPrefix(value, "data:") || strings.HasPrefix(value, "http://") || strings.HasPrefix(value, "https://") {
		return value
	}
	return "data:" + mimeType + ";base64," + value
}

func isUnsupportedEndpoint(statusCode int, body string) bool {
	if statusCode == http.StatusNotFound || statusCode == http.StatusMethodNotAllowed {
		return true
	}
	body = strings.ToLower(body)
	return strings.Contains(body, "invalid url") ||
		strings.Contains(body, "not_found_error") ||
		strings.Contains(body, "requested resource was not found") ||
		strings.Contains(body, "/v1/videos") ||
		strings.Contains(body, "not found") ||
		strings.Contains(body, "unsupported endpoint")
}

func collectMediaModelIDs(items []modelItem) modelCollection {
	collection := modelCollection{
		Models:  make([]string, 0, len(items)),
		Total:   len(items),
		Samples: make([]string, 0, 8),
	}
	models := make([]string, 0, len(items))
	videoModels := make([]string, 0, len(items))
	imageModels := make([]string, 0, len(items))
	seen := make(map[string]bool, len(items))
	for _, item := range items {
		id := strings.TrimSpace(item.ID)
		if id == "" {
			collection.EmptyID++
			continue
		}
		if seen[id] {
			collection.Duplicate++
			continue
		}
		hasVideo := hasVideoCategory(item.Categories)
		hasImage := hasImageCategory(item.Categories)
		if !hasVideo && !hasImage {
			collection.RejectedNoMediaTag++
			collection.addSample("no-media-tag", id, item.Categories)
			continue
		}
		seen[id] = true
		models = append(models, id)
		if hasVideo {
			videoModels = append(videoModels, id)
		}
		if hasImage {
			imageModels = append(imageModels, id)
		}
	}
	collection.Models = models
	collection.VideoModels = videoModels
	collection.ImageModels = imageModels
	collection.Kept = len(models)
	collection.KeptVideo = len(videoModels)
	collection.KeptImage = len(imageModels)
	return collection
}

func (c *modelCollection) addSample(reason, id string, raw json.RawMessage) {
	if len(c.Samples) >= 8 {
		return
	}
	categories := strings.TrimSpace(string(raw))
	if len(categories) > 80 {
		categories = categories[:80] + "..."
	}
	c.Samples = append(c.Samples, fmt.Sprintf("%s: %s categories=%s", reason, id, categories))
}

func (c *modelCollection) mergeTypedModels(items []modelItem, mediaType string) {
	for _, item := range items {
		id := strings.TrimSpace(item.ID)
		if id == "" {
			continue
		}
		hasVideo := hasVideoCategory(item.Categories)
		hasImage := hasImageCategory(item.Categories)
		switch mediaType {
		case "video":
			if !hasVideo {
				continue
			}
		case "image":
			if !hasImage {
				continue
			}
		}
		c.addModel(id)
		switch mediaType {
		case "video":
			if addUnique(&c.VideoModels, id) {
				c.KeptVideo = len(c.VideoModels)
			}
		case "image":
			if addUnique(&c.ImageModels, id) {
				c.KeptImage = len(c.ImageModels)
			}
		}
	}
	c.Kept = len(c.Models)
}

func (c *modelCollection) addModel(id string) {
	if addUnique(&c.Models, id) {
		c.Kept = len(c.Models)
	}
}

func addUnique(values *[]string, value string) bool {
	for _, existing := range *values {
		if existing == value {
			return false
		}
	}
	*values = append(*values, value)
	return true
}

func (c modelCollection) Debug() string {
	parts := []string{
		fmt.Sprintf("total=%d", c.Total),
		fmt.Sprintf("kept=%d", c.Kept),
		fmt.Sprintf("video=%d", c.KeptVideo),
		fmt.Sprintf("image=%d", c.KeptImage),
		fmt.Sprintf("rejected_text_family=%d", c.RejectedTextFamily),
		fmt.Sprintf("rejected_not_video_like=%d", c.RejectedNotVideoLike),
		fmt.Sprintf("rejected_no_media_tag=%d", c.RejectedNoMediaTag),
		fmt.Sprintf("duplicate=%d", c.Duplicate),
		fmt.Sprintf("empty_id=%d", c.EmptyID),
	}
	if len(c.Samples) > 0 {
		parts = append(parts, "samples=["+strings.Join(c.Samples, " | ")+"]")
	}
	return strings.Join(parts, "; ")
}

func hasVideoCategory(raw json.RawMessage) bool {
	for _, token := range categoryTokens(raw) {
		if isVideoToken(token) {
			return true
		}
	}
	return false
}

func hasImageCategory(raw json.RawMessage) bool {
	for _, token := range categoryTokens(raw) {
		if isImageToken(token) {
			return true
		}
	}
	return false
}

func categoryTokens(raw json.RawMessage) []string {
	if len(raw) == 0 || string(raw) == "null" {
		return nil
	}

	var value any
	if err := json.Unmarshal(raw, &value); err != nil {
		return splitCategoryText(string(raw))
	}

	tokens := make([]string, 0)
	var walk func(any)
	walk = func(v any) {
		switch typed := v.(type) {
		case string:
			tokens = append(tokens, splitCategoryText(typed)...)
		case []any:
			for _, item := range typed {
				walk(item)
			}
		case map[string]any:
			for key, val := range typed {
				if enabled, ok := val.(bool); ok && enabled {
					tokens = append(tokens, splitCategoryText(key)...)
					continue
				}
				walk(val)
			}
		}
	}
	walk(value)
	return tokens
}

func splitCategoryText(value string) []string {
	value = strings.ToLower(strings.TrimSpace(value))
	value = strings.Trim(value, `"'[]{} `)
	if value == "" {
		return nil
	}

	separators := []string{",", ";", "|", "/", "\\", " "}
	parts := []string{value}
	for _, separator := range separators {
		next := make([]string, 0, len(parts))
		for _, part := range parts {
			next = append(next, strings.Split(part, separator)...)
		}
		parts = next
	}

	tokens := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.Trim(part, `"'[]{}() `)
		if part != "" {
			tokens = append(tokens, part)
		}
	}
	return tokens
}

func isVideoToken(token string) bool {
	switch strings.ToLower(strings.TrimSpace(token)) {
	case "video", "videos", "video-generation", "video_generation", "text-to-video", "image-to-video", "t2v", "i2v":
		return true
	default:
		return false
	}
}

func isImageToken(token string) bool {
	switch strings.ToLower(strings.TrimSpace(token)) {
	case "image", "images", "image-generation", "image_generation", "text-to-image", "image-to-image", "t2i", "i2i":
		return true
	default:
		return false
	}
}

func isLikelyVideoModel(id string) bool {
	value := strings.ToLower(id)
	keywords := []string{
		"video", "t2v", "i2v", "kling", "veo", "vidu", "wan", "hailuo",
		"minimax", "runway", "gen-2", "gen-3", "gen-4", "luma", "ray",
		"dream-machine", "pika", "pixverse", "seedance", "sora", "cogvideo",
		"stable-video", "svd", "hunyuanvideo", "skyreels", "ltx-video",
	}
	for _, keyword := range keywords {
		if strings.Contains(value, keyword) {
			return true
		}
	}
	return false
}

func isLikelyNonVideoModel(id string) bool {
	value := strings.ToLower(id)
	keywords := []string{
		"gpt", "claude", "deepseek", "qwen", "llama", "gemini", "o1", "o3",
		"o4", "mistral", "mixtral", "grok", "glm", "yi-", "chat", "rerank",
		"embedding", "embed", "whisper", "tts", "text-", "coder", "reason",
		"search", "moderation", "vision", "vl", "ocr", "flux", "sdxl",
		"stable-diffusion", "midjourney", "dall-e", "imagen",
	}
	for _, keyword := range keywords {
		if strings.Contains(value, keyword) {
			return true
		}
	}
	return false
}

func requestModelsWithRetry(baseURL, apiKey string, timeout time.Duration, retries int) (*http.Response, string) {
	return requestModelsPathWithRetry(baseURL, apiKey, "/models", timeout, retries)
}

func requestModelsPathWithRetry(baseURL, apiKey, path string, timeout time.Duration, retries int) (*http.Response, string) {
	var lastErr string
	for attempt := 0; attempt <= retries; attempt++ {
		resp, errMsg := requestModelsPath(baseURL, apiKey, path, timeout)
		if errMsg == "" {
			return resp, ""
		}
		lastErr = errMsg
		if attempt < retries {
			time.Sleep(time.Duration(attempt+1) * 700 * time.Millisecond)
		}
	}
	return nil, lastErr
}

func requestModels(baseURL, apiKey string, timeout time.Duration) (*http.Response, string) {
	return requestModelsPath(baseURL, apiKey, "/models", timeout)
}

func requestModelsPath(baseURL, apiKey, path string, timeout time.Duration) (*http.Response, string) {
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	apiKey = strings.TrimSpace(apiKey)
	path = strings.TrimSpace(path)

	if baseURL == "" {
		return nil, "Base URL is empty"
	}
	if apiKey == "" {
		return nil, "API Key is empty"
	}
	if path == "" {
		path = "/models"
	}
	if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}

	modelsURL := baseURL + path
	req, err := http.NewRequest(http.MethodGet, modelsURL, nil)
	if err != nil {
		return nil, fmt.Sprintf("Invalid request: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)

	client := &http.Client{Timeout: timeout}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Sprintf("Network error: %v", err)
	}

	if resp.StatusCode == http.StatusOK {
		return resp, ""
	}

	body, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
	resp.Body.Close()
	message := strings.TrimSpace(string(body))
	if message == "" {
		message = http.StatusText(resp.StatusCode)
	}
	return nil, fmt.Sprintf("HTTP %d: %s", resp.StatusCode, message)
}

func encodeConnectionResult(success bool, errMsg string) string {
	data, err := json.Marshal(connectionResult{Success: success, Error: errMsg})
	if err != nil {
		return `{"success":false,"error":"Failed to encode connection result"}`
	}
	return string(data)
}

func encodeModelsResult(success bool, videoModels, imageModels []string, errMsg, debug string) string {
	models := append([]string{}, videoModels...)
	seen := make(map[string]bool, len(models)+len(imageModels))
	for _, model := range models {
		seen[model] = true
	}
	for _, model := range imageModels {
		if !seen[model] {
			models = append(models, model)
			seen[model] = true
		}
	}
	if models == nil {
		models = []string{}
	}
	if videoModels == nil {
		videoModels = []string{}
	}
	if imageModels == nil {
		imageModels = []string{}
	}
	data, err := json.Marshal(modelsResult{Success: success, Models: models, VideoModels: videoModels, ImageModels: imageModels, Error: errMsg, Debug: debug})
	if err != nil {
		return `{"success":false,"models":[],"video_models":[],"image_models":[],"error":"Failed to encode models result"}`
	}
	return string(data)
}

func encodeDispatchResult(taskID, status, resultURL, resultB64, errMsg string) string {
	data, err := json.Marshal(dispatchResult{TaskID: taskID, Status: status, ResultURL: resultURL, ResultB64: resultB64, Error: errMsg})
	if err != nil {
		return `{"task_id":"","error":"Failed to encode dispatch result"}`
	}
	return string(data)
}

func encodeTaskStatusResult(success bool, status, resultURL, resultB64, errMsg string) string {
	data, err := json.Marshal(taskStatusResult{Success: success, Status: status, ResultURL: resultURL, ResultB64: resultB64, Error: errMsg})
	if err != nil {
		return `{"success":false,"error":"Failed to encode task status result"}`
	}
	return string(data)
}
