import 'package:flutter/material.dart';
import 'utils/responsive_helper.dart';

class QuranViewer extends StatefulWidget {
  final int startPage;

  const QuranViewer({super.key, required this.startPage});

  @override
  State<QuranViewer> createState() => _QuranViewerState();
}

class _QuranViewerState extends State<QuranViewer> {
  late PageController controller;

  final List<String> pages = [
    for (int i = 1; i <= 602; i++) 'assets/images/page_$i.webp'
  ];

  @override
  void initState() {
    super.initState();

    controller = PageController(
      initialPage: widget.startPage,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Widget _buildResponsivePage(String imagePath) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = ResponsiveHelper.isTablet(context);
        final padding = ResponsiveHelper.pageHorizontalPadding(context);

        return Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: Image.asset(
              imagePath,
              width: isTablet
                  ? constraints.maxWidth * 0.82
                  : constraints.maxWidth,
              height: constraints.maxHeight,
              fit: BoxFit.contain,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("المصحف"),
      ),
      body: PageView.builder(
        controller: controller,
        itemCount: pages.length,
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: _buildResponsivePage(pages[index]),
          );
        },
      ),
    );
  }
}
