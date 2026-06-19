package weavefluxcore

import (
	"encoding/json"
	"testing"
)

func TestCollectVideoModelIDsExcludesTextModels(t *testing.T) {
	items := []modelItem{
		{ID: "GPT5.5", Categories: rawJSON(t, `["video"]`)},
		{ID: "Claude-ops-4-8", Categories: rawJSON(t, `["video"]`)},
		{ID: "Agnes/agnes-1.5-flash", Categories: rawJSON(t, `["chat"]`)},
		{ID: "kling-v2", Categories: rawJSON(t, `["video"]`)},
		{ID: "wanx2.1-t2v-plus", Categories: rawJSON(t, `[]`)},
		{ID: "xai/grok-imagine-video", Categories: rawJSON(t, `["video"]`)},
	}

	got := collectVideoModelIDs(items).Models
	want := []string{"kling-v2", "wanx2.1-t2v-plus", "xai/grok-imagine-video"}

	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for index := range want {
		if got[index] != want[index] {
			t.Fatalf("got %v, want %v", got, want)
		}
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

func rawJSON(t *testing.T, value string) json.RawMessage {
	t.Helper()
	return json.RawMessage(value)
}
