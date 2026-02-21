import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class StreetViewScreen extends StatefulWidget {
  final double latitude;
  final double longitude;

  const StreetViewScreen({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<StreetViewScreen> createState() => _StreetViewScreenState();
}

class _StreetViewScreenState extends State<StreetViewScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(
        Uri.parse(
          'https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=${widget.latitude},${widget.longitude}',
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Street View')),
      body: WebViewWidget(controller: _controller),
    );
  }
}

