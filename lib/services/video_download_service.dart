import 'dart:io';

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
  }) async {
    final uri = Uri.tryParse(videoUrl);
    if (uri == null || !uri.hasScheme) {
      throw ArgumentError('Invalid video URL: $videoUrl');
    }

    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}${Platform.pathSeparator}videos');
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final extension = _extensionFromUri(uri);
    final safeTaskId = taskId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final outputPath =
        '${directory.path}${Platform.pathSeparator}vid_$safeTaskId$extension';

    final output = File(outputPath);
    if (await output.exists() && await output.length() > 0) {
      return output.path;
    }

    final tempPath = '$outputPath.part';
    await _dio.download(
      videoUrl,
      tempPath,
      options: Options(responseType: ResponseType.bytes),
    );

    final tempFile = File(tempPath);
    if (!await tempFile.exists() || await tempFile.length() == 0) {
      throw StateError('Downloaded video is empty');
    }
    if (await output.exists()) {
      await output.delete();
    }
    await tempFile.rename(output.path);
    return output.path;
  }

  String _extensionFromUri(Uri uri) {
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dot = last.lastIndexOf('.');
    if (dot >= 0 && dot < last.length - 1) {
      final ext = last.substring(dot).toLowerCase();
      if (ext.length <= 8 && RegExp(r'^\.[a-z0-9]+$').hasMatch(ext)) {
        return ext;
      }
    }
    return '.mp4';
  }
}
