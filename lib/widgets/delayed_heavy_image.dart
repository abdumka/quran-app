import 'package:flutter/material.dart';

/// A wrapper that loads a lightweight asset image instantly,
/// then delays the loading of the heavy image by one frame.
/// This prevents heavy decoding tasks from blocking the UI thread
/// and completely eliminates blank screens on startup or scroll.
class DelayedHeavyImage extends StatefulWidget {
  final String assetPath;
  final ImageProvider heavyProvider;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final bool gaplessPlayback;
  final FilterQuality filterQuality;

  const DelayedHeavyImage({
    super.key,
    required this.assetPath,
    required this.heavyProvider,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.gaplessPlayback = true,
    this.filterQuality = FilterQuality.low,
  });

  @override
  State<DelayedHeavyImage> createState() => _DelayedHeavyImageState();
}

class _DelayedHeavyImageState extends State<DelayedHeavyImage> {
  bool _loadHeavy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _loadHeavy = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Lightweight image loads instantly
        Image(
          image: AssetImage(widget.assetPath),
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          alignment: widget.alignment,
          filterQuality: widget.filterQuality,
        ),
        // Heavy image loads after the UI has already rendered the first frame
        if (_loadHeavy)
          Image(
            image: widget.heavyProvider,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            alignment: widget.alignment,
            gaplessPlayback: widget.gaplessPlayback,
            filterQuality: widget.filterQuality,
          ),
      ],
    );
  }
}
