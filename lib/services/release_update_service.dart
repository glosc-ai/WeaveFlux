import 'dart:io';
import 'dart:isolate';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ReleaseUpdateService {
  ReleaseUpdateService._() {
    _channel.setMethodCallHandler(_handleNativeCallback);
  }

  static final ReleaseUpdateService instance = ReleaseUpdateService._();

  static const _channel = MethodChannel('weaveflux/update');
  static const _defaultRepository = 'glosc-ai/WeaveFlux';
  static const _repository = String.fromEnvironment(
    'GITHUB_REPOSITORY',
    defaultValue: _defaultRepository,
  );
  static const _currentVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.1.0',
  );

  ValueChanged<double>? _activeDownloadProgress;

  Future<dynamic> _handleNativeCallback(MethodCall call) async {
    if (call.method != 'updateDownloadProgress') return null;
    final args = call.arguments;
    if (args is! Map) return null;
    final progress = args['progress'];
    if (progress is num) {
      _activeDownloadProgress?.call(progress.toDouble().clamp(0, 1));
    }
    return null;
  }

  Future<ReleaseCheckResult> checkLatest() async {
    final fetchResult = await Future.any<ReleaseFetchResult>([
      Isolate.run(() => _fetchLatestRelease(_repository)),
      Future<void>.delayed(const Duration(seconds: 15)).then(
        (_) => const ReleaseFetchResult.error(
          '\u68c0\u67e5\u66f4\u65b0\u8d85\u65f6\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5\u3002',
        ),
      ),
    ]);

    if (!fetchResult.success) {
      return ReleaseCheckResult.error(
        fetchResult.error,
        currentVersion: _currentVersion,
      );
    }

    try {
      final release = fetchResult.release;
      if (release == null || release.version.isEmpty) {
        return ReleaseCheckResult.error(
          '\u672a\u80fd\u89e3\u6790\u6700\u65b0\u7248\u672c\u53f7',
          currentVersion: _currentVersion,
        );
      }

      final hasUpdate = _compareVersions(release.version, _currentVersion) > 0;
      return ReleaseCheckResult(
        success: true,
        currentVersion: _currentVersion,
        release: release,
        hasUpdate: hasUpdate,
      );
    } catch (error, stack) {
      debugPrint('Release check failed: $error\nStack: $stack');
      return ReleaseCheckResult.error(
        error.toString(),
        currentVersion: _currentVersion,
      );
    }
  }

  Future<String> downloadApk(
    ReleaseInfo release, {
    ValueChanged<double>? onProgress,
  }) async {
    final apkUrl = release.apkDownloadUrl;
    if (apkUrl.isEmpty) {
      throw StateError(
          '\u8be5 Release \u6ca1\u6709\u53ef\u4e0b\u8f7d\u7684 APK \u9644\u4ef6');
    }

    final safeVersion =
        release.version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final displayName = 'weaveflux_$safeVersion.apk';
    _activeDownloadProgress = onProgress;
    try {
      onProgress?.call(0);
      final path = await _channel.invokeMethod<String>('downloadApk', {
        'url': apkUrl,
        'displayName': displayName,
      });
      if (path == null || path.isEmpty) {
        throw StateError('APK 下载完成但未返回本地路径');
      }
      onProgress?.call(1);
      return path;
    } on PlatformException catch (error, stack) {
      debugPrint('Download APK failed: $error\nStack: $stack');
      throw StateError(error.message ?? error.code);
    } finally {
      _activeDownloadProgress = null;
    }
  }

  Future<void> installApk(String apkPath) async {
    try {
      await _channel.invokeMethod<void>('installApk', {'apkPath': apkPath});
    } on PlatformException catch (error, stack) {
      debugPrint('Install APK failed: $error\nStack: $stack');
      throw StateError(error.message ?? error.code);
    }
  }

  int _compareVersions(String remote, String current) {
    final remoteParts = _versionParts(remote);
    final currentParts = _versionParts(current);
    final length = remoteParts.length > currentParts.length
        ? remoteParts.length
        : currentParts.length;
    for (var i = 0; i < length; i++) {
      final left = i < remoteParts.length ? remoteParts[i] : 0;
      final right = i < currentParts.length ? currentParts[i] : 0;
      if (left != right) return left.compareTo(right);
    }
    return 0;
  }

  List<int> _versionParts(String version) {
    final normalized = version.trim().replaceFirst(RegExp(r'^[vV]'), '');
    return normalized
        .split(RegExp(r'[.+-]'))
        .map((part) => int.tryParse(part.replaceAll(RegExp(r'\D'), '')) ?? 0)
        .toList();
  }
}

Future<ReleaseFetchResult> _fetchLatestRelease(String repository) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 8);
  try {
    final uri =
        Uri.https('api.github.com', '/repos/$repository/releases/latest');
    final request =
        await client.getUrl(uri).timeout(const Duration(seconds: 8));
    request.headers
        .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    request.headers.set('X-GitHub-Api-Version', '2022-11-28');
    request.headers.set(HttpHeaders.userAgentHeader, 'WeaveFlux');

    final response = await request.close().timeout(const Duration(seconds: 15));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return ReleaseFetchResult.error(
        'GitHub release request failed: HTTP ${response.statusCode}, $body',
      );
    }

    final payload = jsonDecode(body);
    if (payload is! Map<String, dynamic>) {
      return const ReleaseFetchResult.error('Invalid GitHub release response');
    }
    return ReleaseFetchResult.success(ReleaseInfo.fromJson(payload));
  } catch (error) {
    return ReleaseFetchResult.error(error.toString());
  } finally {
    client.close(force: true);
  }
}

class ReleaseFetchResult {
  const ReleaseFetchResult._({
    required this.success,
    this.release,
    this.error = '',
  });

  const ReleaseFetchResult.success(ReleaseInfo release)
      : this._(success: true, release: release);

  const ReleaseFetchResult.error(String error)
      : this._(success: false, error: error);

  final bool success;
  final ReleaseInfo? release;
  final String error;
}

class ReleaseCheckResult {
  const ReleaseCheckResult({
    required this.success,
    required this.currentVersion,
    required this.hasUpdate,
    this.release,
    this.error = '',
  });

  factory ReleaseCheckResult.error(String error, {String currentVersion = ''}) {
    return ReleaseCheckResult(
      success: false,
      currentVersion: currentVersion,
      hasUpdate: false,
      error: error,
    );
  }

  final bool success;
  final String currentVersion;
  final bool hasUpdate;
  final ReleaseInfo? release;
  final String error;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.name,
    required this.htmlUrl,
    required this.apkDownloadUrl,
    required this.publishedAt,
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final tagName = (json['tag_name'] as String? ?? '').trim();
    final assets = json['assets'] as List<dynamic>? ?? const [];
    var apkUrl = '';
    for (final asset in assets.whereType<Map<String, dynamic>>()) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String? ?? '';
        break;
      }
    }

    return ReleaseInfo(
      version: tagName.replaceFirst(RegExp(r'^[vV]'), ''),
      name: json['name'] as String? ?? tagName,
      htmlUrl: json['html_url'] as String? ?? '',
      apkDownloadUrl: apkUrl,
      publishedAt: json['published_at'] as String? ?? '',
    );
  }

  final String version;
  final String name;
  final String htmlUrl;
  final String apkDownloadUrl;
  final String publishedAt;
}
