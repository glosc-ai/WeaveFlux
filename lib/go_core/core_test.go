package weavefluxcore

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestCollectMediaModelIDsUsesMediaCategoryTags(t *testing.T) {
	items := []modelItem{
		{ID: "GPT5.5", Categories: rawJSON(t, `["video"]`)},
		{ID: "Claude-ops-4-8", Categories: rawJSON(t, `["video"]`)},
		{ID: "Agnes/agnes-1.5-flash", Categories: rawJSON(t, `["chat"]`)},
		{ID: "flux-image", Categories: rawJSON(t, `["image"]`)},
		{ID: "kling-v2", Categories: rawJSON(t, `["video"]`)},
		{ID: "wanx2.1-t2v-plus", Categories: rawJSON(t, `[]`)},
		{ID: "xai/grok-imagine-video", Categories: rawJSON(t, `["video"]`)},
	}

	collection := collectMediaModelIDs(items)
	gotVideo := collection.VideoModels
	wantVideo := []string{"GPT5.5", "Claude-ops-4-8", "kling-v2", "xai/grok-imagine-video"}

	if len(gotVideo) != len(wantVideo) {
		t.Fatalf("got %v, want %v", gotVideo, wantVideo)
	}
	for index := range wantVideo {
		if gotVideo[index] != wantVideo[index] {
			t.Fatalf("got %v, want %v", gotVideo, wantVideo)
		}
	}

	gotImage := collection.ImageModels
	wantImage := []string{"flux-image"}
	if len(gotImage) != len(wantImage) || gotImage[0] != wantImage[0] {
		t.Fatalf("got %v, want %v", gotImage, wantImage)
	}
}

func TestHasVideoCategoryParsesStructuredCategories(t *testing.T) {
	cases := []string{
		`["video"]`,
		`["text-to-video"]`,
		`{"video":true}`,
		`{"capabilities":["image-to-video"]}`,
	}

	for _, input := range cases {
		if !hasVideoCategory(rawJSON(t, input)) {
			t.Fatalf("expected video category for %s", input)
		}
	}

	if hasVideoCategory(rawJSON(t, `["chat","vision"]`)) {
		t.Fatal("did not expect video category for chat/vision")
	}
}

func TestHasImageCategoryParsesStructuredCategories(t *testing.T) {
	cases := []string{
		`["image"]`,
		`["text-to-image"]`,
		`{"image":true}`,
		`{"capabilities":["image-to-image"]}`,
	}

	for _, input := range cases {
		if !hasImageCategory(rawJSON(t, input)) {
			t.Fatalf("expected image category for %s", input)
		}
	}

	if hasImageCategory(rawJSON(t, `["chat","video"]`)) {
		t.Fatal("did not expect image category for chat/video")
	}
}

func TestMergeTypedModelsHonorsReturnedCategories(t *testing.T) {
	collection := modelCollection{}
	collection.mergeTypedModels([]modelItem{
		{ID: "video-model", Categories: rawJSON(t, `["video"]`)},
		{ID: "text-model", Categories: rawJSON(t, `["text"]`)},
		{ID: "image-model", Categories: rawJSON(t, `["image"]`)},
	}, "video")

	if len(collection.VideoModels) != 1 || collection.VideoModels[0] != "video-model" {
		t.Fatalf("got video models %v", collection.VideoModels)
	}
	if len(collection.Models) != 1 || collection.Models[0] != "video-model" {
		t.Fatalf("got models %v", collection.Models)
	}

	collection.mergeTypedModels([]modelItem{
		{ID: "video-model", Categories: rawJSON(t, `["video"]`)},
		{ID: "image-model", Categories: rawJSON(t, `["image"]`)},
	}, "image")

	if len(collection.ImageModels) != 1 || collection.ImageModels[0] != "image-model" {
		t.Fatalf("got image models %v", collection.ImageModels)
	}
}

func TestExtractChatTaskIDIgnoresTopLevelCompletionID(t *testing.T) {
	data := []byte(`{
		"id": "chatcmpl-not-a-video-task",
		"choices": [
			{
				"message": {
					"content": "{\"task_id\":\"video_task_123\"}"
				}
			}
		]
	}`)

	if got := extractChatTaskID(data); got != "video_task_123" {
		t.Fatalf("got %q, want video_task_123", got)
	}
}

func TestExtractChatTaskIDReturnsEmptyWithoutContentTask(t *testing.T) {
	data := []byte(`{
		"id": "chatcmpl-not-a-video-task",
		"choices": [
			{"message": {"content": "regular assistant text"}}
		]
	}`)

	if got := extractChatTaskID(data); got != "" {
		t.Fatalf("got %q, want empty task id", got)
	}
}

func TestExtractResultURLFindsURLInsideChatContent(t *testing.T) {
	data := []byte(`{
		"choices": [
			{"message": {"content": "{\"url\":\"https://example.com/out.png\"}"}}
		]
	}`)

	if got := extractResultURL(data); got != "https://example.com/out.png" {
		t.Fatalf("got %q, want result url", got)
	}
}

func TestDispatchErrorPreviewMentionsBodyWhenNoResultReturned(t *testing.T) {
	body := []byte(`{"created":123,"data":[{"revised_prompt":"ok"}]}`)
	if preview := responsePreview(body); !strings.Contains(preview, "revised_prompt") {
		t.Fatalf("preview did not include response body: %q", preview)
	}
}

func TestNormalizeVideoModeMapsFlutterModesToProviderModes(t *testing.T) {
	cases := map[string]string{
		"promptOnly":     "ti2vid",
		"firstFrame":     "ti2vid",
		"extendClip":     "ti2vid",
		"firstLastFrame": "keyframes",
		"keyframes":      "keyframes",
		"ti2vid":         "ti2vid",
	}
	for input, want := range cases {
		if got := normalizeVideoMode(input); got != want {
			t.Fatalf("normalizeVideoMode(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestVideoDispatchAttemptsPreferNewApiTaskRoute(t *testing.T) {
	attempts := videoDispatchAttempts(videoGenerationRequest{}, chatCompletionRequest{})
	if len(attempts) < 2 {
		t.Fatalf("expected multiple attempts")
	}
	if attempts[0].Path != "/video/generations" {
		t.Fatalf("first attempt = %s, want /video/generations", attempts[0].Path)
	}
}

func rawJSON(t *testing.T, value string) json.RawMessage {
	t.Helper()
	return json.RawMessage(value)
}
