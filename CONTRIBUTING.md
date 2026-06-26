# 贡献指南

感谢你关注 WeaveFlux。这个项目面向 Android，本地优先，核心目标是让用户使用自己的 OpenAI 兼容端点完成图片与视频生成。

## 开发前准备

请先确认本地环境可用：

```powershell
flutter pub get
flutter analyze
flutter test
```

如果修改了 `lib/go_core/` 下的 Go 代码，需要重新生成 Go Mobile Android 绑定：

```powershell
cd lib/go_core
gomobile bind -target=android/arm64
```

## 架构约束

- 不引入自建远程后端。
- 不使用 Firebase Auth、Firestore、Realtime Database 或 Remote Config 存储用户数据。
- Firebase Analytics 仅用于基础使用分析，不记录敏感业务内容。
- 用户的 `Base URL` 与 `API Key` 必须通过 `flutter_secure_storage` 加密保存。
- 生成任务、状态、远端 URL 与本地文件路径应保存在本地数据库中。
- Android 公共相册导出必须使用 MediaStore，不要申请 `MANAGE_EXTERNAL_STORAGE`。

## 敏感文件

以下文件不应提交到 Git：

```text
android/local.properties
android/key.properties
*.jks
*.keystore
android/app/google-services.json
```

## 代码规范

- Dart 遵循 Effective Dart。
- 优先使用 `const` 构造。
- Go Mobile 暴露函数只使用基础类型，避免复杂结构跨语言传递。
- MethodChannel 调用必须有异常保护，避免 native 异常导致 Flutter 调试信息丢失。
- Kotlin 回调 Dart 时需要切回 Android 主线程。
- 不在 Widget `build()` 中触发状态变更、网络请求、数据库写入或下载任务。
- 避免高频 `notifyListeners()` 造成重绘风暴。

## 提交流程

提交前建议运行：

```powershell
flutter analyze
flutter test
```

涉及 Android 构建或依赖变更时，建议额外验证：

```powershell
flutter build apk --debug
```

提交信息使用 Conventional Commits 风格，并使用中文正文说明。例如：

```text
ci: 增加 Android 签名配置校验

- 优化 GitHub Actions 中 keystore 的 base64 解码流程，避免换行或空格污染签名文件
- 在 Release 构建前使用 keytool 校验 keystore 密码和 key alias
- 签名配置错误时提前在 Configure Android signing 步骤失败，减少无效构建等待时间
- 保持原有 key.properties 生成和 Release APK 构建流程不变
```

常用类型：

- `feat`: 新功能
- `fix`: 修复问题
- `chore`: 构建、脚本、依赖或维护工作
- `docs`: 文档更新
- `refactor`: 不改变行为的代码重构
- `test`: 测试相关变更

## 发布版本

发布前必须更新 `pubspec.yaml`：

```yaml
version: 0.1.7+8
```

规则：

- `0.1.7` 是用户可见版本名。
- `+8` 是 Android `versionCode`。
- 每次发布都必须递增 `versionCode`。

GitHub Actions 会在检测到版本号变更后自动执行 Android 构建。

## Pull Request 建议

PR 描述建议包含：

- 变更目的
- 主要实现点
- 涉及的页面或服务
- 已执行的验证命令
- 已知风险或后续事项

涉及网络请求、任务轮询、文件下载、MediaStore、Go Mobile 或 MethodChannel 的变更，请说明异常处理和线程切换策略。
