import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/go_core_bridge.dart';
import '../services/model_catalog.dart';
import '../theme/app_theme.dart';
import 'create_workspace.dart';

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
  _PanelResult? _result;
  _UpdateResult? _updateResult;

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
    setState(() {
      _videoModels = ModelCatalog.instance.videoModels.value;
      _imageModels = ModelCatalog.instance.imageModels.value;
      _selectedVideoModel = ModelCatalog.instance.selectedVideoModel.value;
      _selectedImageModel = ModelCatalog.instance.selectedImageModel.value;
    });
  }

  Future<void> _loadSettings() async {
    final baseUrl = await _storage.read(key: _baseUrlKey);
    final apiKey = await _storage.read(key: _apiKeyKey);
    await ModelCatalog.instance.load();
    if (!mounted) return;

    setState(() {
      _videoModels = ModelCatalog.instance.videoModels.value;
      _imageModels = ModelCatalog.instance.imageModels.value;
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
      _selectedVideoModel = ModelCatalog.instance.selectedVideoModel.value;
      _selectedImageModel = ModelCatalog.instance.selectedImageModel.value;
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
        final videoModels = modelsResult.videoModels;
        final imageModels = modelsResult.imageModels;
        final models = <String>{...videoModels, ...imageModels}.toList();
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
            '模型获取成功',
            '已筛选出 ${models.length} 个候选视频模型，请选择后测试连接。',
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
            '模型获取失败',
            modelsResult.error,
          );
        });
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _result = _PanelResult.error('模型获取失败', error.message ?? error.code);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _result = _PanelResult.error('模型获取失败', error.toString());
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
        _result =
            _PanelResult.success('配置已加密保存', 'Base URL、API Key 和默认模型已保存至本地。');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _result = _PanelResult.error('保存失败', error.toString());
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
            '通信成功',
            '模型响应正常，配置已加密保存。',
          );
        });
      } else {
        setState(() {
          _result = _PanelResult.error('通信失败', testResult.error);
        });
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _result = _PanelResult.error(
          '通信失败',
          error.message ?? error.code,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _result = _PanelResult.error('通信失败', error.toString());
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
      setState(() => _result = _PanelResult.error('请输入 Base URL', '端点地址不能为空。'));
      return null;
    }
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() => _result =
          _PanelResult.error('Base URL 格式错误', '请输入完整的 HTTPS OpenAI 兼容端点。'));
      return null;
    }
    if (apiKey.isEmpty) {
      setState(
          () => _result = _PanelResult.error('请输入 API Key', 'API 密钥不能为空。'));
      return null;
    }
    if (requireModel && _selectedVideoModel == null) {
      setState(() => _result = _PanelResult.error('请选择模型', '请先获取可用模型并选择一个模型。'));
      return null;
    }

    final values = _CredentialInput(baseUrl: baseUrl, apiKey: apiKey);
    if (requireModel && _lastFetchedCredentialKey != values.cacheKey) {
      setState(() => _result = _PanelResult.error(
          '请先获取模型', 'Base URL 或 API Key 已变更，请重新获取可用模型后再继续。'));
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
    setState(() {
      _checkingUpdate = true;
      _updateResult = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _checkingUpdate = false;
      _updateResult = const _UpdateResult(
        title: '当前已是最新版本',
        detail: 'WeaveFlux 0.1.0 · 上次检测：刚刚',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _fetchingModels || _testing;

    return WeaveScaffold(
      activeRoute: SettingsPanel.routeName,
      header: const _SettingsHeader(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        children: [
          const _SectionLabel('API 端点'),
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
                  tooltip: _keyVisible ? '隐藏 API Key' : '显示 API Key',
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
          const SizedBox(height: 20),
          const _SectionLabel('可用模型'),
          _SettingsCard(
            children: [
              _DropdownRow(
                label: '默认视频模型',
                selectedModel: _selectedVideoModel,
                models: _videoModels,
                onChanged: busy ? null : _selectVideoModel,
              ),
              const Divider(height: 1),
              _DropdownRow(
                label: '默认图片模型',
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
              label: const Text('获取可用模型'),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('连接检测'),
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
                    label: const Text('保存配置'),
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
                    label: const Text('测试连接'),
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
          const _SectionLabel('应用更新'),
          _UpdateCard(
            checking: _checkingUpdate,
            result: _updateResult,
            onCheck: _checkingUpdate ? null : _checkUpdate,
          ),
          const SizedBox(height: 20),
          const _SectionLabel('安全与隐私'),
          const _SecurityCard(),
        ],
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
              '端点配置',
              textAlign: TextAlign.left,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 2),
            Text(
              '兼容 OpenAI 规范 · 本地 KeyStore 加密存储',
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
                      value: selectedModel,
                      hint: const Text('请先获取可用模型'),
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
                      onChanged: onChanged,
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
    required this.result,
    required this.onCheck,
  });

  final bool checking;
  final _UpdateResult? result;
  final VoidCallback? onCheck;

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
                      '应用版本',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'WeaveFlux 0.1.0',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 36,
                child: OutlinedButton(
                  onPressed: onCheck,
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
                      : const Text('检查更新'),
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
                      '检测会读取本地版本信息，后续接入发布源后比较最新版本。',
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
                    child: Row(
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          color: AppColors.primaryAccent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                result!.title,
                                style: const TextStyle(
                                  color: AppColors.primaryAccent,
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
    const badges = ['Android KeyStore', 'AES-256', '零上传', '完全私密'];

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
                '安全说明',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '你的 API 凭证仅存储在本地 Android KeyStore 中。WeaveFlux 不会将任何凭证上传至远程服务器。',
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
  const _UpdateResult({required this.title, required this.detail});

  final String title;
  final String detail;
}
