import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/go_core_bridge.dart';
import '../services/model_catalog.dart';
import '../services/release_update_service.dart';
import '../theme/app_theme.dart';
import 'create_workspace.dart';

List<String> _dedupeModels(List<String> models) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in models) {
    final model = raw.trim();
    if (model.isEmpty || !seen.add(model)) continue;
    result.add(model);
  }
  return result;
}

String? _validSelectedModel(String? selected, List<String> models) {
  if (selected == null) return null;
  return models.where((model) => model == selected).length == 1
      ? selected
      : null;
}

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key});

  static const routeName = '/settings';

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  static const _baseUrlKey = ModelCatalog.baseUrlKey;
  static const _apiKeyKey = ModelCatalog.apiKeyKey;

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _baseUrlController =
      TextEditingController(text: 'https://one.gloscai.com/v1');
  final _apiKeyController = TextEditingController();

  List<String> _videoModels = <String>[];
  List<String> _imageModels = <String>[];
  String? _selectedVideoModel;
  String? _selectedImageModel;
  String? _lastFetchedCredentialKey;
  bool _keyVisible = false;
  bool _saving = false;
  bool _fetchingModels = false;
  bool _testing = false;
  bool _checkingUpdate = false;
  bool _downloadingUpdate = false;
  double _downloadProgress = 0;
  _PanelResult? _result;
  _UpdateResult? _updateResult;
  ReleaseInfo? _availableRelease;

  @override
  void initState() {
    super.initState();
    ModelCatalog.instance.videoModels.addListener(_syncModelCatalog);
    ModelCatalog.instance.imageModels.addListener(_syncModelCatalog);
    ModelCatalog.instance.selectedVideoModel.addListener(_syncModelCatalog);
    ModelCatalog.instance.selectedImageModel.addListener(_syncModelCatalog);
    _loadSettings();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    ModelCatalog.instance.videoModels.removeListener(_syncModelCatalog);
    ModelCatalog.instance.imageModels.removeListener(_syncModelCatalog);
    ModelCatalog.instance.selectedVideoModel.removeListener(_syncModelCatalog);
    ModelCatalog.instance.selectedImageModel.removeListener(_syncModelCatalog);
    super.dispose();
  }

  void _syncModelCatalog() {
    if (!mounted) return;
    final videoModels = _dedupeModels(ModelCatalog.instance.videoModels.value);
    final imageModels = _dedupeModels(ModelCatalog.instance.imageModels.value);
    setState(() {
      _videoModels = videoModels;
      _imageModels = imageModels;
      _selectedVideoModel = _validSelectedModel(
        ModelCatalog.instance.selectedVideoModel.value,
        videoModels,
      );
      _selectedImageModel = _validSelectedModel(
        ModelCatalog.instance.selectedImageModel.value,
        imageModels,
      );
    });
  }

  Future<void> _loadSettings() async {
    final baseUrl = await _storage.read(key: _baseUrlKey);
    final apiKey = await _storage.read(key: _apiKeyKey);
    await ModelCatalog.instance.load();
    if (!mounted) return;

    setState(() {
      _videoModels = _dedupeModels(ModelCatalog.instance.videoModels.value);
      _imageModels = _dedupeModels(ModelCatalog.instance.imageModels.value);
      if (baseUrl != null && baseUrl.isNotEmpty) {
        _baseUrlController.text = baseUrl;
      }
      if (apiKey != null) {
        _apiKeyController.text = apiKey;
      }
      if ((baseUrl ?? '').isNotEmpty && (apiKey ?? '').isNotEmpty) {
        _lastFetchedCredentialKey = _CredentialInput(
          baseUrl:
              _baseUrlController.text.trim().replaceAll(RegExp(r'/+$'), ''),
          apiKey: _apiKeyController.text.trim(),
        ).cacheKey;
      }
      _selectedVideoModel = _validSelectedModel(
        ModelCatalog.instance.selectedVideoModel.value,
        _videoModels,
      );
      _selectedImageModel = _validSelectedModel(
        ModelCatalog.instance.selectedImageModel.value,
        _imageModels,
      );
    });
  }

  Future<void> _selectVideoModel(String? model) async {
    if (model == null) return;
    setState(() => _selectedVideoModel = model);
    await ModelCatalog.instance.setSelectedVideoModel(model);
  }

  Future<void> _selectImageModel(String? model) async {
    if (model == null) return;
    setState(() => _selectedImageModel = model);
    await ModelCatalog.instance.setSelectedImageModel(model);
  }

  Future<void> _fetchModels() async {
    final values = _readCredentialInputs(requireModel: false);
    if (values == null) return;

    setState(() {
      _fetchingModels = true;
      _result = null;
    });

    try {
      final modelsResult = await ModelCatalog.instance.refresh(
        baseUrl: values.baseUrl,
        apiKey: values.apiKey,
      );

      if (!mounted) return;
      if (modelsResult.success) {
        final videoModels = _dedupeModels(modelsResult.videoModels);
        final imageModels = _dedupeModels(modelsResult.imageModels);
        final selectedVideo = videoModels.contains(_selectedVideoModel)
            ? _selectedVideoModel
            : videoModels.isNotEmpty
                ? videoModels.first
                : null;
        final selectedImage = imageModels.contains(_selectedImageModel)
            ? _selectedImageModel
            : imageModels.isNotEmpty
                ? imageModels.first
                : null;
        setState(() {
          _videoModels = videoModels;
          _imageModels = imageModels;
          _selectedVideoModel = selectedVideo;
          _selectedImageModel = selectedImage;
          _lastFetchedCredentialKey = values.cacheKey;
          _result = _PanelResult.success(
            '\u6a21\u578b\u83b7\u53d6\u6210\u529f',
            '\u5df2\u83b7\u53d6 ${videoModels.length} \u4e2a\u89c6\u9891\u6a21\u578b\u3001'
                '${imageModels.length} \u4e2a\u56fe\u7247\u6a21\u578b\uff0c'
                '\u8bf7\u9009\u62e9\u540e\u6d4b\u8bd5\u8fde\u63a5\u3002',
          );
        });
        if (selectedVideo != null) {
          await ModelCatalog.instance.setSelectedVideoModel(selectedVideo);
        }
        if (selectedImage != null) {
          await ModelCatalog.instance.setSelectedImageModel(selectedImage);
        }
      } else {
        setState(() {
          _result = _PanelResult.error(
            '\u6a21\u578b\u83b7\u53d6\u5931\u8d25',
            modelsResult.error,
          );
        });
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _result = _PanelResult.error('\u6a21\u578b\u83b7\u53d6\u5931\u8d25',
            error.message ?? error.code);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _result = _PanelResult.error(
            '\u6a21\u578b\u83b7\u53d6\u5931\u8d25', error.toString());
      });
    } finally {
      if (mounted) {
        setState(() => _fetchingModels = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    final values = _readCredentialInputs();
    if (values == null) return;

    setState(() {
      _saving = true;
      _result = null;
    });

    try {
      await _persistSettings(values);
      if (!mounted) return;
      setState(() {
        _result = _PanelResult.success(
          '\u914d\u7f6e\u5df2\u52a0\u5bc6\u4fdd\u5b58',
          'Base URL\u3001API Key \u548c\u9ed8\u8ba4\u6a21\u578b\u5df2\u4fdd\u5b58\u81f3\u672c\u5730\u3002',
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _result =
            _PanelResult.error('\u4fdd\u5b58\u5931\u8d25', error.toString());
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _testConnection() async {
    final values = _readCredentialInputs();
    if (values == null) return;

    setState(() {
      _testing = true;
      _result = null;
    });

    try {
      final testResult = await GoCoreBridge.testConnection(
        baseUrl: values.baseUrl,
        apiKey: values.apiKey,
      );

      if (!mounted) return;
      if (testResult.success) {
        await _persistSettings(values);
        if (!mounted) return;
        setState(() {
          _result = _PanelResult.success(
            '\u901a\u4fe1\u6210\u529f',
            '\u6a21\u578b\u54cd\u5e94\u6b63\u5e38\uff0c\u914d\u7f6e\u5df2\u52a0\u5bc6\u4fdd\u5b58\u3002',
          );
        });
      } else {
        setState(() {
          _result =
              _PanelResult.error('\u901a\u4fe1\u5931\u8d25', testResult.error);
        });
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _result = _PanelResult.error(
          '\u901a\u4fe1\u5931\u8d25',
          error.message ?? error.code,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _result =
            _PanelResult.error('\u901a\u4fe1\u5931\u8d25', error.toString());
      });
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  _CredentialInput? _readCredentialInputs({bool requireModel = true}) {
    final baseUrl =
        _baseUrlController.text.trim().replaceAll(RegExp(r'/+$'), '');
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty) {
      setState(() => _result = _PanelResult.error('\u8bf7\u8f93\u5165 Base URL',
          '\u7aef\u70b9\u5730\u5740\u4e0d\u80fd\u4e3a\u7a7a\u3002'));
      return null;
    }
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() => _result = _PanelResult.error(
          'Base URL \u683c\u5f0f\u9519\u8bef',
          '\u8bf7\u8f93\u5165\u5b8c\u6574\u7684 HTTPS OpenAI \u517c\u5bb9\u7aef\u70b9\u3002'));
      return null;
    }
    if (apiKey.isEmpty) {
      setState(() => _result = _PanelResult.error('\u8bf7\u8f93\u5165 API Key',
          'API \u5bc6\u94a5\u4e0d\u80fd\u4e3a\u7a7a\u3002'));
      return null;
    }
    if (requireModel && _selectedVideoModel == null) {
      setState(() => _result = _PanelResult.error(
          '\u8bf7\u9009\u62e9\u6a21\u578b',
          '\u8bf7\u5148\u83b7\u53d6\u53ef\u7528\u6a21\u578b\u5e76\u9009\u62e9\u4e00\u4e2a\u6a21\u578b\u3002'));
      return null;
    }

    final values = _CredentialInput(baseUrl: baseUrl, apiKey: apiKey);
    if (requireModel && _lastFetchedCredentialKey != values.cacheKey) {
      setState(() => _result = _PanelResult.error(
          '\u8bf7\u5148\u83b7\u53d6\u6a21\u578b',
          'Base URL \u6216 API Key \u5df2\u53d8\u66f4\uff0c\u8bf7\u91cd\u65b0\u83b7\u53d6\u53ef\u7528\u6a21\u578b\u540e\u518d\u7ee7\u7eed\u3002'));
      return null;
    }

    return values;
  }

  Future<void> _persistSettings(_CredentialInput values) async {
    await _storage.write(key: _baseUrlKey, value: values.baseUrl);
    await _storage.write(key: _apiKeyKey, value: values.apiKey);
    final videoModel = _selectedVideoModel;
    if (videoModel != null) {
      await ModelCatalog.instance.setSelectedVideoModel(videoModel);
    }
    final imageModel = _selectedImageModel;
    if (imageModel != null) {
      await ModelCatalog.instance.setSelectedImageModel(imageModel);
    }
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate || _downloadingUpdate) return;
    setState(() {
      _checkingUpdate = true;
      _updateResult = null;
      _availableRelease = null;
    });

    final result = await ReleaseUpdateService.instance.checkLatest();
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _checkingUpdate = false;
        _updateResult = _UpdateResult(
          title: '\u68c0\u67e5\u66f4\u65b0\u5931\u8d25',
          detail: result.error,
          success: false,
        );
      });
      return;
    }

    final release = result.release;
    setState(() {
      _checkingUpdate = false;
      _availableRelease = result.hasUpdate ? release : null;
      _updateResult = result.hasUpdate && release != null
          ? _UpdateResult(
              title: '\u53d1\u73b0\u65b0\u7248\u672c ${release.version}',
              detail: release.apkDownloadUrl.isEmpty
                  ? 'Release \u4e2d\u6ca1\u6709 APK \u9644\u4ef6\uff0c\u8bf7\u524d\u5f80 GitHub \u9875\u9762\u67e5\u770b\u3002'
                  : '\u5f53\u524d\u7248\u672c ${result.currentVersion}\uff0c'
                      '\u53ef\u4e0b\u8f7d\u6700\u65b0\u5b89\u88c5\u5305\u3002',
            )
          : _UpdateResult(
              title: '\u5f53\u524d\u5df2\u662f\u6700\u65b0\u7248\u672c',
              detail: 'WeaveFlux ${result.currentVersion}',
            );
    });
  }

  Future<void> _downloadAndInstallUpdate() async {
    if (_checkingUpdate || _downloadingUpdate) return;
    final release = _availableRelease;
    if (release == null) return;
    var lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    var lastProgressPercent = -1;

    setState(() {
      _downloadingUpdate = true;
      _downloadProgress = 0;
      _updateResult = _UpdateResult(
        title: '\u6b63\u5728\u4e0b\u8f7d ${release.version}',
        detail: '\u4e0b\u8f7d\u8fdb\u5ea6 0%',
      );
    });

    try {
      final apkPath = await ReleaseUpdateService.instance.downloadApk(
        release,
        onProgress: (progress) {
          if (!mounted) return;
          final percent = (progress.clamp(0, 1) * 100).round();
          final now = DateTime.now();
          if (percent == lastProgressPercent &&
              now.difference(lastProgressUpdate) <
                  const Duration(milliseconds: 300)) {
            return;
          }
          lastProgressPercent = percent;
          lastProgressUpdate = now;
          setState(() {
            _downloadProgress = progress.clamp(0, 1);
            _updateResult = _UpdateResult(
              title: '\u6b63\u5728\u4e0b\u8f7d ${release.version}',
              detail: '\u4e0b\u8f7d\u8fdb\u5ea6 $percent%',
            );
          });
        },
      );
      await ReleaseUpdateService.instance.installApk(apkPath);
      if (!mounted) return;
      setState(() {
        _downloadingUpdate = false;
        _updateResult = const _UpdateResult(
          title: '\u5b89\u88c5\u5668\u5df2\u6253\u5f00',
          detail:
              '\u8bf7\u5728\u7cfb\u7edf\u5b89\u88c5\u754c\u9762\u786e\u8ba4\u66f4\u65b0\u3002',
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloadingUpdate = false;
        _updateResult = _UpdateResult(
          title: '\u4e0b\u8f7d\u5b89\u88c5\u5931\u8d25',
          detail: error.toString(),
          success: false,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _fetchingModels || _testing || _downloadingUpdate;

    return WeaveScaffold(
      activeRoute: SettingsPanel.routeName,
      header: const _SettingsHeader(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        children: [
          const _SectionLabel('\u0041\u0050\u0049 \u7aef\u70b9'),
          _SettingsCard(
            children: [
              _CredentialRow(
                icon: Icons.link_rounded,
                iconColor: AppColors.secondaryAccent,
                label: 'Base URL',
                child: TextField(
                  controller: _baseUrlController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  enabled: !busy,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'https://one.gloscai.com/v1',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              const Divider(height: 1),
              _CredentialRow(
                icon: Icons.key_rounded,
                iconColor: AppColors.primaryAccent,
                label: 'API Key',
                trailing: IconButton(
                  tooltip: _keyVisible
                      ? '\u9690\u85cf API Key'
                      : '\u663e\u793a API Key',
                  onPressed: busy
                      ? null
                      : () => setState(() => _keyVisible = !_keyVisible),
                  icon: Icon(
                    _keyVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.muted,
                  ),
                ),
                child: TextField(
                  controller: _apiKeyController,
                  obscureText: !_keyVisible,
                  textInputAction: TextInputAction.done,
                  enabled: !busy,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'sk-xxxxxxxxxxxxxxxxxxxxxxxx',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _ApiKeyHelpLink(),
          const SizedBox(height: 20),
          const _SectionLabel('\u53ef\u7528\u6a21\u578b'),
          _SettingsCard(
            children: [
              _DropdownRow(
                label: '\u9ed8\u8ba4\u89c6\u9891\u6a21\u578b',
                selectedModel: _selectedVideoModel,
                models: _videoModels,
                onChanged: busy ? null : _selectVideoModel,
              ),
              const Divider(height: 1),
              _DropdownRow(
                label: '\u9ed8\u8ba4\u56fe\u7247\u6a21\u578b',
                selectedModel: _selectedImageModel,
                models: _imageModels,
                onChanged: busy ? null : _selectImageModel,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryAccent,
                side: const BorderSide(color: AppColors.primaryAccent),
                backgroundColor:
                    AppColors.primaryAccent.withValues(alpha: 0.08),
              ),
              onPressed: busy ? null : _fetchModels,
              icon: _fetchingModels
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryAccent,
                      ),
                    )
                  : const Icon(Icons.cloud_sync_outlined, size: 18),
              label: const Text('\u83b7\u53d6\u53ef\u7528\u6a21\u578b'),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('\u8fde\u63a5\u68c0\u6d4b'),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryAccent,
                      side: const BorderSide(color: AppColors.primaryAccent),
                      backgroundColor:
                          AppColors.primaryAccent.withValues(alpha: 0.08),
                    ),
                    onPressed: busy ? null : _saveSettings,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryAccent,
                            ),
                          )
                        : const Icon(Icons.lock_outline_rounded, size: 18),
                    label: const Text('\u4fdd\u5b58\u914d\u7f6e'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondaryAccent,
                      side: const BorderSide(color: AppColors.secondaryAccent),
                      backgroundColor:
                          AppColors.secondaryAccent.withValues(alpha: 0.08),
                    ),
                    onPressed: busy ? null : _testConnection,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.secondaryAccent,
                            ),
                          )
                        : const Icon(Icons.wifi_tethering_rounded, size: 18),
                    label: const Text('\u6d4b\u8bd5\u8fde\u63a5'),
                  ),
                ),
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _result == null
                ? const SizedBox(height: 12)
                : Padding(
                    key: ValueKey('${_result!.message}:${_result!.detail}'),
                    padding: const EdgeInsets.only(top: 12),
                    child: _ResultBanner(result: _result!),
                  ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('\u5e94\u7528\u66f4\u65b0'),
          _UpdateCard(
            checking: _checkingUpdate,
            downloading: _downloadingUpdate,
            progress: _downloadProgress,
            result: _updateResult,
            onCheck: _checkingUpdate ? null : _checkUpdate,
            onDownload: _availableRelease?.apkDownloadUrl.isEmpty ?? true
                ? null
                : _downloadAndInstallUpdate,
            releaseUrl: _availableRelease?.htmlUrl ?? '',
          ),
          const SizedBox(height: 20),
          const _SectionLabel('\u5b89\u5168\u4e0e\u9690\u79c1'),
          const _SecurityCard(),
        ],
      ),
    );
  }
}

class _ApiKeyHelpLink extends StatelessWidget {
  const _ApiKeyHelpLink();

  static final Uri _portalUri = Uri.parse('https://one.gloscai.com/');

  Future<void> _openPortal() async {
    final opened = await launchUrl(
      _portalUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      throw StateError('无法打开 $_portalUri');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.secondaryAccent,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: _openPortal,
        icon: const Icon(Icons.open_in_new_rounded, size: 16),
        label: const Text('\u4ece glosc ai one \u83b7\u53d6 API \u79d8\u94a5'),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '\u7aef\u70b9\u914d\u7f6e',
              textAlign: TextAlign.left,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 2),
            Text(
              '\u517c\u5bb9 OpenAI \u89c4\u8303 · \u672c\u5730 KeyStore \u52a0\u5bc6\u5b58\u50a8',
              textAlign: TextAlign.left,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.secondaryAccent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: children),
    );
  }
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: iconColor.withValues(alpha: 0.12),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child,
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.selectedModel,
    required this.models,
    required this.onChanged,
  });

  final String label;
  final String? selectedModel;
  final List<String> models;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final models = _dedupeModels(this.models);
    final value = _validSelectedModel(selectedModel, models);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryAccent.withValues(alpha: 0.12),
            child: const Icon(
              Icons.memory_rounded,
              color: AppColors.primaryAccent,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: AppRadii.inputRadius,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: value,
                      hint: const Text(
                          '\u8bf7\u5148\u83b7\u53d6\u53ef\u7528\u6a21\u578b'),
                      isExpanded: true,
                      menuMaxHeight: 260,
                      borderRadius: AppRadii.inputRadius,
                      dropdownColor: AppColors.surface,
                      iconEnabledColor: AppColors.muted,
                      style: const TextStyle(
                        color: AppColors.foreground,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      items: [
                        for (final model in models)
                          DropdownMenuItem(
                            value: model,
                            child: Text(
                              model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: models.isEmpty ? null : onChanged,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result});

  final _PanelResult result;

  @override
  Widget build(BuildContext context) {
    final color = result.success ? AppColors.primaryAccent : AppColors.danger;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadii.inputRadius,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            result.success ? Icons.check_circle : Icons.error_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.message,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  result.detail,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({
    required this.checking,
    required this.downloading,
    required this.progress,
    required this.result,
    required this.onCheck,
    required this.onDownload,
    required this.releaseUrl,
  });

  final bool checking;
  final bool downloading;
  final double progress;
  final _UpdateResult? result;
  final VoidCallback? onCheck;
  final VoidCallback? onDownload;
  final String releaseUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor:
                    AppColors.secondaryAccent.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.system_update_alt_rounded,
                  color: AppColors.secondaryAccent,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '\u5e94\u7528\u7248\u672c',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'WeaveFlux',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 36,
                child: OutlinedButton(
                  onPressed: downloading ? null : onCheck,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondaryAccent,
                    side: const BorderSide(color: AppColors.secondaryAccent),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.secondaryAccent,
                          ),
                        )
                      : const Text('\u68c0\u67e5\u66f4\u65b0'),
                ),
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: result == null
                ? const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      '\u5c06\u4ece GitHub Release \u8bfb\u53d6\u6700\u65b0\u7248\u672c\uff0c\u5e76\u4e0b\u8f7d APK \u5b89\u88c5\u5305\u3002',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  )
                : Padding(
                    key: ValueKey(result!.title),
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              result!.success
                                  ? Icons.verified_rounded
                                  : Icons.error_outline_rounded,
                              color: result!.success
                                  ? AppColors.primaryAccent
                                  : AppColors.danger,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    result!.title,
                                    style: TextStyle(
                                      color: result!.success
                                          ? AppColors.primaryAccent
                                          : AppColors.danger,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    result!.detail,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (downloading) ...[
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: progress <= 0 ? null : progress,
                            color: AppColors.primaryAccent,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.08),
                          ),
                        ],
                        if (!downloading &&
                            result!.success &&
                            onDownload != null) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: onDownload,
                              icon: const Icon(
                                Icons.download_for_offline_outlined,
                                size: 18,
                              ),
                              label: const Text(
                                  '\u4e0b\u8f7d\u5e76\u5b89\u88c5\u66f4\u65b0'),
                            ),
                          ),
                        ] else if (!downloading &&
                            result!.success &&
                            releaseUrl.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: () => launchUrl(
                              Uri.parse(releaseUrl),
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: const Text('\u6253\u5f00 GitHub Release'),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard();

  @override
  Widget build(BuildContext context) {
    const badges = [
      'Android KeyStore',
      'AES-256',
      '\u96f6\u4e0a\u4f20',
      '\u5b8c\u5168\u672c\u5730'
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: AppColors.primaryAccent,
                size: 18,
              ),
              SizedBox(width: 6),
              Text(
                '\u5b89\u5168\u8bf4\u660e',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '\u4f60\u7684 API \u51ed\u8bc1\u4ec5\u5b58\u50a8\u5728\u672c\u5730 Android KeyStore \u4e2d\u3002WeaveFlux \u4e0d\u4f1a\u5c06\u4efb\u4f55\u51ed\u8bc1\u4e0a\u4f20\u81f3\u8fdc\u7a0b\u670d\u52a1\u5668\u3002',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final badge in badges)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: AppColors.primaryAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CredentialInput {
  const _CredentialInput({
    required this.baseUrl,
    required this.apiKey,
  });

  final String baseUrl;
  final String apiKey;

  String get cacheKey => '$baseUrl\n$apiKey';
}

class _PanelResult {
  const _PanelResult._(this.success, this.message, this.detail);

  factory _PanelResult.success(String message, String detail) {
    return _PanelResult._(true, message, detail);
  }

  factory _PanelResult.error(String message, String detail) {
    return _PanelResult._(false, message, detail);
  }

  final bool success;
  final String message;
  final String detail;
}

class _UpdateResult {
  const _UpdateResult({
    required this.title,
    required this.detail,
    this.success = true,
  });

  final String title;
  final String detail;
  final bool success;
}
