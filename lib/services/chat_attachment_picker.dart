import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import 'chat_service.dart';

/// What came back from a pick. Both fields null means the user cancelled.
class ChatPickResult {
  final ChatDraftFile? file;
  final String? error;
  const ChatPickResult({this.file, this.error});
}

/// Picks and prepares a file for the chat. Nothing is asked for at launch: the
/// system pickers open only when the user taps attach, and they hand over only
/// the chosen file, so the app holds no photo or storage permission.
class ChatAttachmentPicker {
  ChatAttachmentPicker._();

  static const int maxBytes = 5 * 1024 * 1024;
  static const int _maxSide = 1600;
  static const int _quality = 80;
  static const String tooLargeMessage = 'الملف أكبر من 5 MB. اختر ملفًا أصغر.';

  /// `requestFullMetadata: false` is what keeps iOS from showing a photo
  /// library permission prompt; its picker gives us the one chosen photo.
  static Future<ChatPickResult> pickPhoto() async {
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
    } catch (error) {
      debugPrint('[Chat] photo pick failed: $error');
      return const ChatPickResult(error: 'تعذّر فتح معرض الصور.');
    }
    if (picked == null) return const ChatPickResult();
    final original = await picked.readAsBytes();
    final shrunk = await _shrink(original);
    if (shrunk.length > maxBytes) {
      return const ChatPickResult(error: tooLargeMessage);
    }
    return ChatPickResult(
      file: ChatDraftFile(
        name: _jpegName(picked.name),
        kind: 'image',
        bytes: shrunk,
        originalSize: original.length,
      ),
    );
  }

  static Future<ChatPickResult> pickPdf() async {
    final XFile? picked;
    try {
      picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'PDF',
            extensions: ['pdf'],
            mimeTypes: ['application/pdf'],
            uniformTypeIdentifiers: ['com.adobe.pdf'],
          ),
        ],
      );
    } catch (error) {
      debugPrint('[Chat] pdf pick failed: $error');
      return const ChatPickResult(error: 'تعذّر فتح الملفات.');
    }
    if (picked == null) return const ChatPickResult();
    final size = await picked.length();
    if (size > maxBytes) return const ChatPickResult(error: tooLargeMessage);
    final bytes = await picked.readAsBytes();
    return ChatPickResult(
      file: ChatDraftFile(
        name: picked.name,
        kind: 'pdf',
        bytes: bytes,
        originalSize: size,
      ),
    );
  }

  /// Re-encodes as JPEG at no more than [_maxSide] on the long edge, which also
  /// drops EXIF, including any GPS location. If that fails the original goes
  /// through unchanged and the server decides whether to accept it.
  static Future<Uint8List> _shrink(Uint8List original) async {
    try {
      final target = await _targetSize(original);
      final result = await FlutterImageCompress.compressWithList(
        original,
        minWidth: target.$1,
        minHeight: target.$2,
        quality: _quality,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      return result.isEmpty ? original : result;
    } catch (error) {
      debugPrint('[Chat] shrink failed: $error');
      return original;
    }
  }

  /// flutter_image_compress scales until the image just covers the size asked
  /// for, so asking for the exact scaled size is what bounds the long edge.
  static Future<(int, int)> _targetSize(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    descriptor.dispose();
    buffer.dispose();
    return scaledSize(width, height, _maxSide);
  }

  @visibleForTesting
  static (int, int) scaledSize(int width, int height, int maxSide) {
    final longest = width > height ? width : height;
    if (longest <= maxSide) return (width, height);
    final scale = maxSide / longest;
    return ((width * scale).round(), (height * scale).round());
  }

  static String _jpegName(String name) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return '${base.isEmpty ? 'photo' : base}.jpg';
  }
}
