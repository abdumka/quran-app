import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/audio_service.dart';

/// Plays a finished «فيديو الآية» inside the share sheet: it starts on its
/// own, plays once and stops on the closing card. Tap to pause, play or
/// replay. Native on both phones with the same channel: Android's
/// AyahVideoPlayerView.kt (the app's own Media3 player) and iOS's
/// AyahVideoPlayerView.swift (AVPlayer).
class AyahVideoPlayer extends StatefulWidget {
  const AyahVideoPlayer({
    super.key,
    required this.file,
    required this.aspectRatio,
    required this.accent,
  });

  final File file;

  /// Width / height of the video as made (9:16, 1:1 or 16:9).
  final double aspectRatio;
  final Color accent;

  @override
  State<AyahVideoPlayer> createState() => _AyahVideoPlayerState();
}

class _AyahVideoPlayerState extends State<AyahVideoPlayer>
    with WidgetsBindingObserver {
  static const _viewType = 'com.mahfodqr.qalon_mushaf/ayah_video_player';

  MethodChannel? _channel;
  Timer? _poll;
  int _position = 0;
  int _duration = 0;
  bool _playing = true;
  bool _ended = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A recitation left playing would talk over the preview (Android takes
    // audio focus anyway; iOS lets two players run at once).
    if (AudioService.instance.isPlaying.value) AudioService.instance.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _channel = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app (or the share sheet of another app covering it) pauses
    // the preview; it never plays on unseen.
    if (state != AppLifecycleState.resumed) _call('pause');
  }

  void _created(int id) {
    _channel = MethodChannel('${_viewType}_$id');
    _poll = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _refresh(),
    );
  }

  Future<void> _call(String method) async {
    try {
      await _channel?.invokeMethod<void>(method);
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  Future<void> _refresh() async {
    final ch = _channel;
    if (ch == null) return;
    try {
      final m = await ch.invokeMapMethod<String, Object?>('state');
      if (!mounted || m == null) return;
      setState(() {
        _position = (m['position'] as num?)?.toInt() ?? 0;
        _duration = (m['duration'] as num?)?.toInt() ?? 0;
        _playing = m['playing'] == true;
        _ended = m['ended'] == true;
        _error = m['error'] == true;
      });
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  Future<void> _toggle() async {
    await _call(_playing ? 'pause' : 'play');
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.5;
    final progress = _duration > 0
        ? (_position / _duration).clamp(0.0, 1.0)
        : 0.0;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                if (defaultTargetPlatform == TargetPlatform.iOS)
                  UiKitView(
                    viewType: _viewType,
                    layoutDirection: TextDirection.ltr,
                    creationParams: {'path': widget.file.path},
                    creationParamsCodec: const StandardMessageCodec(),
                    onPlatformViewCreated: _created,
                  )
                else
                  AndroidView(
                    viewType: _viewType,
                    layoutDirection: TextDirection.ltr,
                    creationParams: {'path': widget.file.path},
                    creationParamsCodec: const StandardMessageCodec(),
                    onPlatformViewCreated: _created,
                  ),
                Positioned.fill(
                  child: Semantics(
                    button: true,
                    label: _playing ? 'إيقاف مؤقت' : 'تشغيل',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggle,
                      child: AnimatedOpacity(
                        opacity: _playing && !_error ? 0 : 1,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          color: Colors.black26,
                          alignment: Alignment.center,
                          child: _error
                              ? const Text(
                                  'تعذّر تشغيل الفيديو',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : Container(
                                  width: 58,
                                  height: 58,
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _ended
                                        ? Icons.replay_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: Colors.white24,
                    color: widget.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
