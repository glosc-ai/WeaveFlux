# 织影（WeaveFlux）

织影 是一款面向 Android 的客户端本地 AI 视频与图片生成应用。项目采用 BYO Key（Bring Your Own Key）模式：用户在应用内配置自己的 OpenAI 兼容接口 `Base URL` 与 `API Key`，应用直接从本地向用户指定的模型服务发起生成请求，不依赖自建远程服务器、云数据库或托管鉴权服务。

项目由 Flutter UI、Android 原生能力与 Go Mobile 本地核心组成，重点覆盖创作工作台、任务队列、私密画廊、端点配置、模型拉取、异步任务轮询、本地资产下载、系统相册导出与应用更新。

## 项目原则

- **客户端优先**：应用不维护自有后端，不使用云数据库保存用户任务或密钥。
- **用户自带密钥**：`Base URL` 与 `API Key` 由用户自行提供，并通过 `flutter_secure_storage` 加密保存。
- **OpenAI 兼容接口**：生成请求面向 OpenAI 风格端点，并针对不同服务商视频路由做兼容处理。
- **本地数据闭环**：任务状态、生成记录与本地文件路径保存在设备本地。
- **Android 分区存储合规**：私有资产保存在应用沙盒，导出相册使用 Android MediaStore。
- **可观测性有限接入**：项目接入 Firebase Analytics 用于基础使用分析，不接入 Firebase Auth、Firestore、Realtime Database 或 Remote Config。

## 功能

- **创作工作台**
  - 文生视频、图生视频与图片生成入口
  - Prompt 输入与高级参数配置
  - 视频模型、图片模型按 `categories=video` / `categories=image` 分类拉取
  - 画面比例、尺寸、动态幅度等参数组装
  - 生成任务提交到本地任务队列后台处理

- **任务轨道**
  - 展示 `processing`、`success`、`failed` 等状态
  - Go Mobile 后台轮询任务状态并回调 Dart
  - 成功任务写入远端 URL 与本地沙盒文件路径
  - 失败任务保留错误信息，便于重试和排查

- **私密画廊**
  - 展示已完成图片和视频资产
  - 支持本地图片查看与视频播放
  - 支持删除沙盒内本地资产
  - 删除本地资产不会影响已经导出到系统相册的文件

- **系统相册导出**
  - Android 原生层通过 `MediaStore.Video.Media` 写入公共媒体库
  - 导出目录为 `Movies/WeaveFlux`
  - 不申请 `MANAGE_EXTERNAL_STORAGE`

- **端点与设置**
  - Base URL 与 API Key 加密保存
  - 可用模型拉取与连接测试
  - GitHub Release 更新检测、下载与安装
  - Firebase Analytics 初始化与页面访问分析

## 技术栈

- **Flutter / Dart**：应用 UI 与状态管理。
- **Go Mobile**：本地核心请求封装、任务分发与状态轮询。
- **Kotlin / Android MethodChannel**：Go Mobile 桥接、APK 安装、MediaStore 导出等原生能力。
- **Hive**：本地任务与生成资产记录。
- **flutter_secure_storage**：加密保存 API 凭证与端点配置。
- **dio**：HTTP 请求与文件下载。
- **path_provider**：访问应用私有目录。
- **video_player**：本地视频预览。
- **Firebase Analytics**：基础应用使用分析。

## 开发环境

推荐环境：

- Windows 11
- Flutter Stable 3.44.2 或更高兼容版本
- Dart 3.12.2 或随 Flutter SDK 提供的对应版本
- Android SDK 36
- Android Build Tools 34.0.0+
- JDK 17
- Android Studio 或 Android SDK Command-line Tools
- Go 与 gomobile（修改 `lib/go_core/` 后需要重新绑定）

本地 `android/local.properties` 示例：

```properties
sdk.dir=D:\\Android\\SDK
flutter.sdk=D:\\Flutter SDK
```

常用命令：

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

修改 Go Mobile 核心后，在 `lib/go_core/` 内重新生成 Android 绑定：

```powershell
gomobile bind -target=android/arm64
```

## 构建与发布

Debug APK：

```powershell
flutter build apk --debug
```

Release APK：

```powershell
flutter build apk --release
```

生成产物路径：

```text
build/app/outputs/flutter-apk/
```

GitHub Actions 会根据项目版本构建 Release 安装包。发布前请先更新 `pubspec.yaml` 中的版本号：

```yaml
version: 0.1.7+7
```

其中 `0.1.7` 是用户可见版本名，`+7` 是 Android `versionCode`，每次发布都必须递增。

## 仓库结构

```text
lib/
  main.dart                 # Flutter 应用入口
  go_core/                  # Go Mobile 本地核心
  models/                   # 本地数据模型
  screens/                  # 创作、任务、画廊、设置页面
  services/                 # 桥接、任务、下载、更新等服务
  theme/                    # 全局设计令牌与主题
android/                    # Android 原生工程与 MethodChannel
scripts/                    # 本地调试脚本
test/                       # Flutter 测试
.github/workflows/          # GitHub Actions 构建发布流程
```

## 安全说明

- 不要将 API Key 写入源码、脚本默认值或明文配置文件。
- 不要提交 `android/local.properties`、keystore、签名密码。
- 不要请求 `MANAGE_EXTERNAL_STORAGE` 等高风险外部存储权限。
- 沙盒视频和图片可由用户删除；导出到系统相册的文件由系统媒体库管理。
- Firebase Analytics 仅用于基础分析，不应用于记录 Prompt、API Key、Base URL、远端生成 URL 等敏感内容。
