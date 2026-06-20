import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MediaStoreExporter {
  MediaStoreExporter._();

  static final MediaStoreExporter instance = MediaStoreExporter._();

  static const MethodChannel _channel = MethodChannel('weaveflux/media_store');

  Future<void> exportVideo({
    required String localPath,
    required String displayName,
  }) async {
    try {
      await _channel.invokeMethod<void>(
        'exportVideoToGallery',
        <String, Object?>{
          'localPath': localPath,
          'displayName': displayName,
        },
      );
    } catch (e, stack) {
      debugPrint('❌ [MethodChannel Error]: $e \n Stack: $stack');
      rethrow;
    }
  }
}
