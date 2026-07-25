import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/router/fly_router.dart';

enum PreviewImageType { network, asset, file }

class ImagePreviewRouteModule extends FlyRouteModule {
  @override
  List<AppRoute> get routes => [
        AppRoute(
          name: ImagePreviewPage.routeName,
          builder: (_, settings) {
            final args = settings.arguments;
            return ImagePreviewPage(
              image: args is ImagePreviewArgs ? args : const ImagePreviewArgs(source: ''),
            );
          },
        ),
      ];
}

class ImagePreviewArgs {
  const ImagePreviewArgs({
    required this.source,
    this.type = PreviewImageType.network,
    this.title,
  });

  final String source;
  final PreviewImageType type;
  final String? title;
}

class AppImage {
  AppImage._();

  static Future<void> previewNetwork(String url, {String? title}) {
    return FlyRouter().push<void>(
      ImagePreviewPage.routeName,
      arguments: ImagePreviewArgs(source: url, title: title),
    );
  }

  static Future<void> previewAsset(String asset, {String? title}) {
    return FlyRouter().push<void>(
      ImagePreviewPage.routeName,
      arguments: ImagePreviewArgs(
        source: asset,
        type: PreviewImageType.asset,
        title: title,
      ),
    );
  }

  static Future<void> previewFile(String path, {String? title}) {
    return FlyRouter().push<void>(
      ImagePreviewPage.routeName,
      arguments: ImagePreviewArgs(
        source: path,
        type: PreviewImageType.file,
        title: title,
      ),
    );
  }
}

class ImagePreviewPage extends StatelessWidget {
  const ImagePreviewPage({
    required this.image,
    super.key,
  });

  static const routeName = '/image-preview';

  final ImagePreviewArgs image;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(image.title ?? '图片预览'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5,
            child: _buildImage(),
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (image.source.isEmpty) {
      return const Text('图片地址为空', style: TextStyle(color: Colors.white));
    }

    return switch (image.type) {
      PreviewImageType.asset => Image.asset(image.source, fit: BoxFit.contain),
      PreviewImageType.file => Image.file(File(image.source), fit: BoxFit.contain),
      PreviewImageType.network => Image.network(image.source, fit: BoxFit.contain),
    };
  }
}
