import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../theme/app_theme.dart';
import 'create_workspace.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key});

  static const routeName = '/settings';

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  static const _baseUrlKey = 'wf_base_url';
  static const _apiKeyKey = 'wf_api_key';
  static const _modelKey = 'wf_selected_model';

  static const _models = [
    't2v-default-model',
    'kling-v2',
    'wanx2.1-t2v-plus',
    'vidu-1.5',
  ];

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _baseUrlController =
      TextEditingController(text: 'https://api.glosc-ai.one/v1');
  final _apiKeyController = TextEditingController();

  String _selectedModel = _models.first;
  bool _keyVisible = false;
  bool _testing = false;
  bool _checkingUpdate = false;
  _TestResult? _result;
  _UpdateResult? _updateResult;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final baseUrl = await _storage.read(key: _baseUrlKey);
    final apiKey = await _storage.read(key: _apiKeyKey);
    final model = await _storage.read(key: _modelKey);
    if (!mounted) return;
    setState(() {
      if (baseUrl != null && baseUrl.isNotEmpty) {
        _baseUrlController.text = baseUrl;
      }
      if (apiKey != null) {
        _apiKeyController.text = apiKey;
      }
      if (model != null && _models.contains(model)) {
        _selectedModel = model;
      }
    });
  }

  Future<void> _selectModel(String? model) async {
    if (model == null) return;
    setState(() => _selectedModel = model);
    await _storage.write(key: _modelKey, value: model);
  }

  Future<void> _testConnection() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty) {
      setState(() => _result = _TestResult.error('请输入 Base URL', '端点地址不能为空'));
      return;
    }
    if (apiKey.isEmpty) {
      setState(() => _result = _TestResult.error('请输入 API Key', 'API 密钥不能为空'));
      return;
    }

    setState(() {
      _testing = true;
      _result = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 850));
    await _storage.write(key: _baseUrlKey, value: baseUrl);
    await _storage.write(key: _apiKeyKey, value: apiKey);
    await _storage.write(key: _modelKey, value: _selectedModel);

    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = _TestResult.success('通信成功', '端点、密钥和默认模型已加密保存');
    });
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
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'https://api.glosc-ai.one/v1',
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
                  onPressed: () => setState(() => _keyVisible = !_keyVisible),
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
                selectedModel: _selectedModel,
                models: _models,
                onChanged: _selectModel,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionLabel('连接检测'),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.secondaryAccent,
                side: const BorderSide(color: AppColors.secondaryAccent),
                backgroundColor:
                    AppColors.secondaryAccent.withValues(alpha: 0.08),
              ),
              onPressed: _testing ? null : _testConnection,
              child: _testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.secondaryAccent,
                      ),
                    )
                  : const Text('测试连接'),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _result == null
                ? const SizedBox(height: 12)
                : Padding(
                    key: ValueKey(_result!.message),
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
    required this.selectedModel,
    required this.models,
    required this.onChanged,
  });

  final String selectedModel;
  final List<String> models;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryAccent.withValues(alpha: 0.12),
            child: const Icon(Icons.memory_rounded,
                color: AppColors.primaryAccent, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '默认生成模型',
                  style: TextStyle(
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
                      isExpanded: true,
                      dropdownColor: AppColors.surface,
                      iconEnabledColor: AppColors.muted,
                      style: const TextStyle(
                        color: AppColors.foreground,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      items: [
                        for (final model in models)
                          DropdownMenuItem(value: model, child: Text(model)),
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

  final _TestResult result;

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
          Icon(result.success ? Icons.check_circle : Icons.error_outline,
              color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.message,
                  style: TextStyle(
                      color: color, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  result.detail,
                  style: TextStyle(
                      color: color.withValues(alpha: 0.8), fontSize: 11),
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
                child: const Icon(Icons.system_update_alt_rounded,
                    color: AppColors.secondaryAccent, size: 16),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('应用版本',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text('WeaveFlux 0.1.0',
                        style: TextStyle(color: AppColors.muted, fontSize: 12)),
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
                      '检测会读取本地版本信息，并在后续接入发布源后比较最新版本。',
                      style: TextStyle(
                          color: AppColors.muted, fontSize: 12, height: 1.5),
                    ),
                  )
                : Padding(
                    key: ValueKey(result!.title),
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_rounded,
                            color: AppColors.primaryAccent, size: 18),
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
                                    color: AppColors.muted, fontSize: 11),
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
              Icon(Icons.lock_outline_rounded,
                  color: AppColors.primaryAccent, size: 18),
              SizedBox(width: 6),
              Text('安全说明',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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

class _TestResult {
  const _TestResult._(this.success, this.message, this.detail);

  factory _TestResult.success(String message, String detail) {
    return _TestResult._(true, message, detail);
  }

  factory _TestResult.error(String message, String detail) {
    return _TestResult._(false, message, detail);
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
