import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class ReleaseUpdateService {
  ReleaseUpdateService._();

  static final ReleaseUpdateService instance = ReleaseUpdateService._();

  static const _channel = MethodChannel('weaveflux/update');
  static const _defaultRepository = 'glosc-ai/WeaveFlux';
  static const _repository = String.fromEnvironment(
    'GITHUB_REPOSITORY',
    defaultValue: _defaultRepository,
  );

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    ),
  );

  Future<ReleaseCheckResult> checkLatest() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    const uri = 'https://api.github.com/repos/$_repository/releases/latest';

    try {
      final response = await _dio.get<Map<String, dynamic>>(uri);
      final payload = response.data;
      if (payload == null) {
        return ReleaseCheckResult.error(
            '\u672a\u80fd\u89e3\u6790\u6700\u65b0\u7248\u672c\u53f7');
      }

      final release = ReleaseInfo.fromJson(payload);
      if (release.version.isEmpty) {
        return ReleaseCheckResult.error(
            '\u672a\u80fd\u89e3\u6790\u6700\u65b0\u7248\u672c\u53f7');
      }

      final hasUpdate = _compareVersions(release.version, currentVersion) > 0;
      return ReleaseCheckResult(
        success: true,
        currentVersion: currentVersion,
        release: release,
        hasUpdate: hasUpdate,
      );
    } on DioException catch (error, stack) {
      debugPrint('Release check failed: $error\nStack: $stack');
      return ReleaseCheckResult.error(
        error.response?.data?.toString() ?? error.message ?? error.toString(),
        currentVersion: currentVersion,
      );
    } catch (error, stack) {
      debugPrint('Release check failed: $error\nStack: $stack');
      return ReleaseCheckResult.error(
        error.toString(),
        currentVersion: currentVersion,
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

    final directory = await getApplicationDocumentsDirectory();
    final updatesDir =
        Directory('${directory.path}${Platform.pathSeparator}updates');
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }

    final safeVersion =
        release.version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final targetPath =
        '${updatesDir.path}${Platform.pathSeparator}weaveflux_$safeVersion.apk';

    await _dio.download(
      apkUrl,
      targetPath,
      onReceiveProgress: (received, total) {
        if (total <= 0) return;
        onProgress?.call(received / total);
      },
      options: Options(headers: const {'Accept': 'application/octet-stream'}),
    );

    return targetPath;
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
