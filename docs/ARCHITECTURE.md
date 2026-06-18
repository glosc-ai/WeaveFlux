## 系统架构与开发文档

### 1. 技术架构拓扑 (Architecture Topology)

本项目采用 **Flutter + Go Mobile 嵌入式核心** 架构。Go 代码被编译为 Android 原生动态链接库 (`.so`)，通过 Flutter 的 `MethodChannel` 实现本地进程内通信。

```
+-----------------------------------------------------------+
|                      Flutter UI 层                        |
|   (界面渲染 / 状态管理 Bloc / 本地视频播放器 / MediaStore API) |
+-----------------------------------------------------------+
                             |
                      Platform Channel 
                             |
+-----------------------------------------------------------+
|                    Go Mobile 核心逻辑层                    |
|  (API Key硬件解密映射 / OpenAI 规范客户端 / 异步轮询调度器)   |
+-----------------------------------------------------------+
                             |
                       本地环回网络
                             |
+-----------------------------------------------------------+
|              外部大模型聚合端点 (glosc ai one)              |
+-----------------------------------------------------------+

```

### 2. 本地持久化与密钥安全存储

1. **配置类敏感信息 (API 凭证)：** 使用 `flutter_secure_storage` 插件。在 Android 端，该插件会自动调用 `EncryptedSharedPreferences`，将密钥托管给 Android Keystore 系统进行硬件级安全隔离。
2. **结构化业务数据 (任务历史与画廊元数据)：** 采用本地高性能 NoSQL 数据库 `Isar` 或 `Hive`。任务本地数据模型示例如下：

```json
{
  "id": "uuid_v4_string",
  "prompt": "A futuristic cinematic drone shot of Neo-Tokyo...",
  "negative_prompt": "blurry, low quality",
  "model_used": "kling-v2",
  "aspect_ratio": "16:9",
  "local_video_path": "/storage/emulated/0/Android/data/com.weaveflux.app/files/videos/vid_001.mp4",
  "status": "success", 
  "error_message": "",
  "created_at": 1781293400000
}

```

### 3. Go Mobile 核心业务逻辑实现 (Go Core Implementation)

Go 核心代码负责处理符合 OpenAI 规范的请求封装与状态机管理。以下为核心业务的 Go 源码架构：

```go
package weavefluxcore

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// VideoTaskRequest 定义了符合 OpenAI 图像/视频生成扩展规范的本地请求体
type VideoTaskRequest struct {
	Model  string `json:"model"`
	Prompt string `json:"prompt"`
	Size   string `json:"size"` // e.g. "1024x576"
}

type OpenAIResponse struct {
	ID        string `json:"id"` // Task ID
	Status    string `json:"status"`
	VideoURL  string `json:"video_url"`
}

// DispatchVideoTask 由 Flutter 端通过 PlatformChannel 传入解密后的 key 直接调用
func DispatchVideoTask(baseURL, apiKey, model, prompt, size string) (string, error) {
	reqBody := VideoTaskRequest{
		Model:  model,
		Prompt: prompt,
		Size:   size,
	}
	
	jsonData, _ := json.Marshal(reqBody)
	
	// 对接 glosc ai one 的标准 OpenAI 兼容视频端点
	req, err := http.NewRequest("POST", baseURL+"/videos/generations", bytes.NewBuffer(jsonData))
	if err != nil {
		return "", err
	}
	
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", apiKey))
	
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	
	var openAIResp OpenAIResponse
	if err := json.NewDecoder(resp.Body).Decode(&openAIResp); err != nil {
		return "", err
	}
	
	return openAIResp.ID, nil
}

// StartPollingTask 启动本地 Goroutine 进行状态轮询，通过 callback 递交状态给 Dart 层
func StartPollingTask(baseURL, apiKey, taskID string, statusCallback func(status string, url string, errStr string)) {
	go func() {
		ticker := time.NewTicker(7 * time.Second)
		defer ticker.Stop()
		
		maxRetries := 60 // 约 7 分钟总超时
		for i := 0; i < maxRetries; i++ {
			<-ticker.C
			
			req, _ := http.NewRequest("GET", fmt.Sprintf("%s/videos/tasks/%s", baseURL, taskID), nil)
			req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", apiKey))
			
			client := &http.Client{Timeout: 10 * time.Second}
			resp, err := client.Do(req)
			if err != nil {
				continue // 网络抖动，忽略并等待下次轮询
			}
			
			var pollResp OpenAIResponse
			json.NewDecoder(resp.Body).Decode(&pollResp)
			resp.Body.Close()
			
			if pollResp.Status == "completed" || pollResp.Status == "success" {
				statusCallback("success", pollResp.VideoURL, "")
				return
			} else if pollResp.Status == "failed" {
				statusCallback("failed", "", "Upstream model generation failed")
				return
			}
		}
		statusCallback("failed", "", "Polling timeout")
	}()
}

```

### 4. Android 存储适配 (Scoped Storage & MediaStore)

应用完全在 Android 单端运行，且 Target SDK 设定在 34+（Android 14），必须严格遵守**分区存储 (Scoped Storage)** 规范，严禁申请危险的全局 `MANAGE_EXTERNAL_STORAGE` 权限。

* **沙盒暂存：** 当 Go 核心轮询成功拿到视频 URL 后，由 Flutter 的 `dio` 库将视频数据流下载至应用私有目录 `/storage/emulated/0/Android/data/com.weaveflux.app/files/videos/`。该目录写入无需任何权限申请。
* **公共相册导出：** 当用户在画廊详情点击“下载到系统相册”时，Flutter 端通过原生桥接调用 Android **MediaStore API**，将视频安全移入公共存储区：

```java
// Android 原生 / Flutter 插件内部逻辑示意
ContentValues values = new ContentValues();
values.put(MediaStore.Video.Media.DISPLAY_NAME, "WeaveFlux_" + System.currentTimeMillis() + ".mp4");
values.put(MediaStore.Video.Media.MIME_TYPE, "video/mp4");
values.put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/WeaveFlux"); // 创建公共二级专有目录

Uri collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY);
Uri videoUri = context.getContentResolver().insert(collection, values);
// 随后通过存储流将沙盒私有文件内容 copy 写入该 videoUri 中，无需动态申请 READ/WRITE_EXTERNAL_STORAGE 权限。

```