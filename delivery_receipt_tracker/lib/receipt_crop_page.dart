import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Pure Flutter crop UI: no native cropper plugin, suitable for iOS builds.
/// Returns the path of a cropped JPEG, or null if the user cancels.
class ReceiptCropPage extends StatefulWidget {
  const ReceiptCropPage({super.key, required this.imagePath});
  final String imagePath;

  @override
  State<ReceiptCropPage> createState() => _ReceiptCropPageState();
}

class _ReceiptCropPageState extends State<ReceiptCropPage> {
  double left = .06, top = .08, right = .94, bottom = .92;
  bool processing = false;
  int turns = 0;
  img.Image? decoded;
  Uint8List? previewBytes;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final image = img.decodeImage(await File(widget.imagePath).readAsBytes());
      if (image == null) throw Exception('Unsupported image format');
      final upright = img.bakeOrientation(image);
      final preview = Uint8List.fromList(img.encodeJpg(upright, quality: 85));
      if (mounted) {
        setState(() {
          decoded = upright;
          previewBytes = preview;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    }
  }

  Future<void> _confirm() async {
    if (decoded == null || processing) return;
    setState(() => processing = true);
    try {
      img.Image source = decoded!;
      if (turns != 0) source = img.copyRotate(source, angle: turns * 90);
      final x = (left * source.width).round().clamp(0, source.width - 1);
      final y = (top * source.height).round().clamp(0, source.height - 1);
      final w = ((right - left) * source.width).round().clamp(1, source.width - x);
      final h = ((bottom - top) * source.height).round().clamp(1, source.height - y);
      final cropped = img.copyCrop(source, x: x, y: y, width: w, height: h);
      final path = '${Directory.systemTemp.path}/receiptly_crop_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(img.encodeJpg(cropped, quality: 95));
      if (mounted) Navigator.pop(context, path);
    } catch (e) {
      if (mounted) {
        setState(() => processing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not crop image: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = decoded;
    return Scaffold(
      backgroundColor: const Color(0xFF151515),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151515),
        foregroundColor: Colors.white,
        title: const Text('Crop receipt'),
        actions: [
          IconButton(
            tooltip: 'Rotate 90 degrees',
            onPressed: image == null ? null : () => setState(() {
              turns = (turns + 1) % 4;
              left = .06; top = .08; right = .94; bottom = .92;
            }),
            icon: const Icon(Icons.rotate_right),
          ),
        ],
      ),
      body: error != null
          ? Center(child: Text(error!, style: const TextStyle(color: Colors.white)))
          : image == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Expanded(child: LayoutBuilder(builder: (context, constraints) {
                    final rotated = turns.isOdd;
                    final iw = (rotated ? image.height : image.width).toDouble();
                    final ih = (rotated ? image.width : image.height).toDouble();
                    final scale = math.min(constraints.maxWidth / iw, constraints.maxHeight / ih);
                    final dw = iw * scale, dh = ih * scale;
                    return Center(child: SizedBox(width: dw, height: dh, child: Stack(children: [
                      Positioned.fill(child: RotatedBox(
                        quarterTurns: turns,
                        child: Image.memory(previewBytes!, fit: BoxFit.fill),
                      )),
                      Positioned.fill(child: CustomPaint(painter: _CropOverlay(left, top, right, bottom))),
                      ...List.generate(4, (index) {
                        final fx = index.isEven ? left : right;
                        final fy = index < 2 ? top : bottom;
                        return Positioned(
                          left: fx * dw - 24, top: fy * dh - 24,
                          width: 48, height: 48,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (details) => setState(() {
                              final dx = details.delta.dx / dw;
                              final dy = details.delta.dy / dh;
                              if (index.isEven) {
                                left = (left + dx).clamp(.0, right - .12).toDouble();
                              } else {
                                right = (right + dx).clamp(left + .12, 1.0).toDouble();
                              }
                              if (index < 2) {
                                top = (top + dy).clamp(.0, bottom - .12).toDouble();
                              } else {
                                bottom = (bottom + dy).clamp(top + .12, 1.0).toDouble();
                              }
                            }),
                            child: const Center(child: Icon(Icons.radio_button_unchecked,
                                size: 30, color: Colors.orangeAccent)),
                          ),
                        );
                      }),
                    ])));
                  })),
                  const Padding(padding: EdgeInsets.all(12), child: Text(
                    'Drag the four orange handles around the product table. Include DESCRIPTION and U. PRICE headers.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white70))),
                  Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE85014)),
                      onPressed: processing ? null : _confirm,
                      child: Text(processing ? 'Preparing image...' : 'Crop and scan'),
                    ),
                  )),
                ]),
    );
  }
}

class _CropOverlay extends CustomPainter {
  _CropOverlay(this.left, this.top, this.right, this.bottom);
  final double left, top, right, bottom;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(left * size.width, top * size.height,
        right * size.width, bottom * size.height);
    final shade = Paint()..color = Colors.black.withValues(alpha: .55);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, rect.top), shade);
    canvas.drawRect(Rect.fromLTWH(0, rect.bottom, size.width, size.height - rect.bottom), shade);
    canvas.drawRect(Rect.fromLTWH(0, rect.top, rect.left, rect.height), shade);
    canvas.drawRect(Rect.fromLTWH(rect.right, rect.top, size.width - rect.right, rect.height), shade);
    canvas.drawRect(rect, Paint()..color = Colors.orangeAccent..style = PaintingStyle.stroke..strokeWidth = 2);
  }
  @override
  bool shouldRepaint(covariant _CropOverlay old) =>
      left != old.left || top != old.top || right != old.right || bottom != old.bottom;
}
