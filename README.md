# 织影（WeaveFlux）

织影 是一款面向 Android 的客户端本地 AI 视频生成应用。项目采用 BYO Key（Bring Your Own Key）模式：用户在应用内配置自己的 OpenAI 兼容接口 `Base URL` 与 `API Key`，应用直接从本地向用户指定的模型服务发起视频生成请求，不依赖自建远程服务器、云数据库或第三方托管鉴权服务。

当前仓库已完成 Flutter 前端 UI 的首次实现，包括创作工作台、任务队列、私密画廊与端点配置等核心页面，并根据设计交付文件完成深色主题与主要交互状态的落地。

## 项目概述

织影 的目标是在 Android 设备上提供一个轻量、私密、可自定义端点的 AI 视频创作工具。

核心设计原则：

- **纯客户端架构**：应用不维护自有后端，不引入 Firebase、Supabase 或其他云端数据库。
- **用户自带密钥**：Base URL 与 API Key 由用户自行提供，应用仅在本地保存和使用。
- **OpenAI 兼容接口**：视频生成请求面向 OpenAI 风格的接口规范，便于适配不同模型聚合服务或兼容端点。
- **本地隐私优先**：敏感配置通过 Android KeyStore/EncryptedSharedPreferences 进行加密存储。
- **Android 优先**：项目面向 Android 设备开发，目标 SDK 要求 34+。

## 功能

当前 UI 阶段已实现以下页面与交互原型：

- **创作工作台**
  - 文生视频 / 图生视频分段切换
  - Prompt 大文本输入框
  - 高级参数面板
  - 模型名、画面比例、动态幅度等参数控件
  - 底部主生成按钮

- **任务轨道**
  - 生成中任务卡片
  - 失败任务卡片
  - 原厂错误码详情展开/收起
  - 失败任务重试入口
  - 已完成任务状态展示

- **私密画廊**
  - 两列瀑布流作品列表
  - 视频封面占位与时长标签
  - 全屏沉浸播放页
  - 下载、删除、删除确认与 Toast 状态

- **端点配置**
  - Base URL 输入
  - API Key 密文输入与显隐切换
  - 可用模型下拉选择
  - 连接测试结果展示
  - 应用更新检测 UI
  - 安全与隐私说明

## 技术栈

- **Flutter**：跨平台 UI 层，目前主要面向 Android。
- **Dart**：Flutter 应用开发语言。
- **Material 3**：基础组件体系与主题定制。
- **flutter_secure_storage**：用于本地加密保存 Base URL、API Key 和默认模型配置。
- **flutter_staggered_grid_view**：用于私密画廊瀑布流布局。
- **path_provider**：用于后续访问应用私有目录与本地缓存目录。
- **video_player**：用于后续接入真实视频播放能力。
- **Go Mobile（规划）**：作为嵌入式本地核心，用于封装 OpenAI 兼容请求、任务轮询与本地业务逻辑。
- **Android MediaStore（规划）**：用于将生成视频导出至系统相册目录 `Movies/WeaveFlux`。

## 开发环境

推荐环境：

- Windows 11
- Flutter Stable 3.44.2 或更高兼容版本
- Dart 3.12.2 或随 Flutter SDK 提供的对应版本
- Android SDK 36
- Android Build Tools 28.0.3 及 34.0.0+
- JDK 17
- Android Studio 或 Android SDK Command-line Tools

本地配置示例：

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

由于 Windows 跨盘构建时 Kotlin 增量编译可能遇到缓存路径问题，项目已在 `android/gradle.properties` 中关闭 Kotlin incremental：

```properties
kotlin.incremental=false
```

## 运行环境

- Android 设备或模拟器
- Android 14 / Target SDK 34+ 方向适配
- 用户需要自行准备兼容 OpenAI 请求结构的视频生成服务端点
- 用户需要在应用设置页中配置：
  - `Base URL`
  - `API Key`
  - 默认生成模型

运行调试：

```powershell
flutter run
```

构建 Debug APK：

```powershell
flutter build apk --debug
```

生成产物路径：

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## 仓库结构

```text
lib/
  main.dart                 # Flutter 应用入口
  theme/                    # 全局设计令牌与主题
  screens/                  # 创作、任务、画廊、设置页面
android/                    # Android 原生工程壳
assets/                     # 后续静态资源目录（如需要）
docs/                       # 产品、架构与 UI/UX 文档
design_handoff/             # Open Design 导出的设计交付文件
test/                       # Flutter widget 测试
```

## 安全说明

- 不应将 API Key 写入明文配置文件。
- 不应提交 `android/local.properties`、keystore、签名配置或本地构建产物。
- 不应请求 `MANAGE_EXTERNAL_STORAGE` 等高风险外部存储权限。
- 生成视频的临时文件应优先保存在应用私有目录中；导出到系统相册时应使用 Android MediaStore。
