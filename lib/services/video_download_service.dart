import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class VideoDownloadService {
  VideoDownloadService._();

  static final VideoDownloadService instance = VideoDownloadService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),
      followRedirects: true,
    ),
  );

  Future<String> downloadToSandbox({
    required String taskId,
    required String videoUrl,
    bool isImage = false,
  }) async {
    final uri = Uri.tryParse(videoUrl);
    if (uri == null || !uri.hasScheme) {
      throw ArgumentError('Invalid asset URL: $videoUrl');
    }

    final directory = await _assetDirectory(isImage: isImage);

    final extension = _extensionFromUri(uri, isImage: isImage);
    final safeTaskId = taskId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final prefix = isImage ? 'img' : 'vid';
    final outputPath =
        '${directory.path}${Platform.pathSeparator}${prefix}_$safeTaskId$extension';

    final output = File(outputPath);
    if (await output.exists() && await output.length() > 0) {
      return output.path;
    }

    final tempPath = '$outputPath.part';
    final tempFile = File(tempPath);
    try {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      await _dio.download(
        videoUrl,
        tempPath,
        options: Options(responseType: ResponseType.bytes),
      );

      if (!await tempFile.exists() || await tempFile.length() == 0) {
        throw StateError('Downloaded asset is empty');
      }
      if (await output.exists()) {
        await output.delete();
      }
      await tempFile.rename(output.path);
      return output.path;
    } catch (error) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      throw StateError('Failed to download asset: $error');
    }
  }

  Future<String> saveBase64ToSandbox({
    required String taskId,
    required String base64Data,
    bool isImage = false,
  }) async {
    final directory = await _assetDirectory(isImage: isImage);
    final safeTaskId = taskId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final normalized = _stripDataUrlPrefix(base64Data);
    try {
      final bytes = base64Decode(normalized);
      if (bytes.isEmpty) {
        throw StateError('Generated asset Base64 is empty');
      }

      final extension = _extensionFromDataUrl(base64Data, isImage: isImage);
      final prefix = isImage ? 'img' : 'vid';
      final output = File(
        '${directory.path}${Platform.pathSeparator}${prefix}_$safeTaskId$extension',
      );
      await output.writeAsBytes(bytes, flush: true);
      return output.path;
    } catch (error) {
      throw StateError('Failed to save Base64 asset: $error');
    }
  }

  Future<Directory> _assetDirectory({required bool isImage}) async {
    final documents = await getApplicationDocumentsDirectory();
    final folder = isImage ? 'images' : 'videos';
    final directory =
        Directory('${documents.path}${Platform.pathSeparator}$folder');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  String _extensionFromUri(Uri uri, {required bool isImage}) {
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dot = last.lastIndexOf('.');
    if (dot >= 0 && dot < last.length - 1) {
      final ext = last.substring(dot).toLowerCase();
      if (ext.length <= 8 && RegExp(r'^\.[a-z0-9]+$').hasMatch(ext)) {
        return ext;
      }
    }
    return isImage ? '.png' : '.mp4';
  }

  String _extensionFromDataUrl(String value, {required bool isImage}) {
    if (value.startsWith('data:image/jpeg') || value.startsWith('data:image/jpg')) {
      return '.jpg';
    }
    if (value.startsWith('data:image/webp')) {
      return '.webp';
    }
    if (value.startsWith('data:video/')) {
      return '.mp4';
    }
    return isImage ? '.png' : '.mp4';
  }

  String _stripDataUrlPrefix(String value) {
    final comma = value.indexOf(',');
    if (value.startsWith('data:') && comma >= 0) {
      return value.substring(comma + 1);
    }
    return value.trim();
  }
}
