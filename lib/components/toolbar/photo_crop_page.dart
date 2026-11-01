import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Where a new photo comes from.
enum PhotoSource { camera, gallery }

/// Whether this device can take a picture with its camera.
bool get canTakePhotos =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// A small popup asking whether to take a photo or pick one from the gallery.
/// Returns null if it was dismissed.
Future<PhotoSource?> showPhotoSourceDialog(BuildContext context) {
  return showDialog<PhotoSource>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Add photo'),
      children: [
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Take a photo'),
          onTap: () => Navigator.pop(context, PhotoSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Choose from gallery'),
          onTap: () => Navigator.pop(context, PhotoSource.gallery),
        ),
      ],
    ),
  );
}

/// A full-screen page to cut a photo out with four freely placed corners.
/// The area between the corners is stretched into an upright rectangle.
///
/// Pops with the cropped image as PNG bytes, or null if cancelled.
class PhotoCropPage extends StatefulWidget {
  const PhotoCropPage({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  static Future<Uint8List?> show(BuildContext context, Uint8List imageBytes) {
    return Navigator.of(context, rootNavigator: true).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => PhotoCropPage(imageBytes: imageBytes),
      ),
    );
  }

  @override
  State<PhotoCropPage> createState() => _PhotoCropPageState();
}

class _PhotoCropPageState extends State<PhotoCropPage> {
  static const _initialCorners = [
    Offset(0.1, 0.1), // top left
    Offset(0.9, 0.1), // top right
    Offset(0.9, 0.9), // bottom right
    Offset(0.1, 0.9), // bottom left
  ];

  ui.Image? _image;
  Object? _loadError;
  bool _working = false;

  /// The four corners as fractions (0 to 1) of the image's width and height,
  /// in the order top left, top right, bottom right, bottom left.
  List<Offset> _corners = List.of(_initialCorners);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _image = frame.image);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  /// Whether the corners form a proper four-sided shape that doesn't cross
  /// itself (otherwise it can't be stretched into a rectangle).
  bool get _isValid {
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final a = _corners[i];
      final b = _corners[(i + 1) % 4];
      final c = _corners[(i + 2) % 4];
      final cross =
          (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (cross.abs() < 1e-5) return false;
      final s = cross > 0 ? 1 : -1;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }

  Future<void> _done() async {
    final image = _image;
    if (image == null || _working) return;
    if (!_isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("The corners can't cross over each other"),
        ),
      );
      return;
    }

    setState(() => _working = true);
    try {
      final width = image.width;
      final height = image.height;
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!.buffer.asUint8List();

      final quad = [
        for (final corner in _corners) ...[
          corner.dx * width,
          corner.dy * height,
        ],
      ];
      Offset point(int i) => Offset(quad[i * 2], quad[i * 2 + 1]);

      // the rectangle is as wide / tall as the longer of the two matching sides
      var outWidth = max(
        (point(1) - point(0)).distance,
        (point(2) - point(3)).distance,
      );
      var outHeight = max(
        (point(3) - point(0)).distance,
        (point(2) - point(1)).distance,
      );
      const longestSide = 2048.0;
      final tooBig = max(outWidth, outHeight) / longestSide;
      if (tooBig > 1) {
        outWidth /= tooBig;
        outHeight /= tooBig;
      }
      final outW = max(1, outWidth.round());
      final outH = max(1, outHeight.round());

      final warped = await _warpInBackground(
        pixels,
        width,
        height,
        quad,
        outW,
        outH,
      );
      final png = await _encodePng(warped, outW, outH);

      if (!mounted) return;
      Navigator.pop(context, png);
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Couldn't crop the photo: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final image = _image;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Crop'),
        actions: [
          TextButton(
            onPressed: _working
                ? null
                : () => setState(() => _corners = List.of(_initialCorners)),
            child: const Text('Reset'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton(
              onPressed: image == null || _working ? null : _done,
              child: _working
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Done'),
            ),
          ),
        ],
      ),
      body: _loadError != null
          ? Center(
              child: Text(
                "Couldn't open this photo.\n$_loadError",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            )
          : image == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final available = constraints.biggest;
                final scale = min(
                  (available.width - 48) / image.width,
                  (available.height - 48) / image.height,
                );
                final size = Size(image.width * scale, image.height * scale);
                final rect = Rect.fromLTWH(
                  (available.width - size.width) / 2,
                  (available.height - size.height) / 2,
                  size.width,
                  size.height,
                );
                final points = [
                  for (final corner in _corners)
                    rect.topLeft +
                        Offset(corner.dx * rect.width, corner.dy * rect.height),
                ];

                return Stack(
                  children: [
                    Positioned.fromRect(
                      rect: rect,
                      child: RawImage(image: image, fit: BoxFit.fill),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _CropOutlinePainter(
                            points: points,
                            imageRect: rect,
                            color: _isValid
                                ? colorScheme.primary
                                : colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                    for (var i = 0; i < 4; i++)
                      Positioned(
                        left: points[i].dx - 28,
                        top: points[i].dy - 28,
                        width: 56,
                        height: 56,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (details) => setState(() {
                            final moved =
                                _corners[i] +
                                Offset(
                                  details.delta.dx / rect.width,
                                  details.delta.dy / rect.height,
                                );
                            _corners[i] = Offset(
                              moved.dx.clamp(0.0, 1.0),
                              moved.dy.clamp(0.0, 1.0),
                            );
                          }),
                          child: Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isValid
                                      ? colorScheme.primary
                                      : colorScheme.error,
                                  width: 3,
                                ),
                              ),
                              child: const SizedBox.square(dimension: 22),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _CropOutlinePainter extends CustomPainter {
  const _CropOutlinePainter({
    required this.points,
    required this.imageRect,
    required this.color,
  });

  final List<Offset> points;
  final Rect imageRect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // darken everything outside the shape
    final outside = Path()
      ..addRect(imageRect)
      ..addPolygon(points, true)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = Colors.black.withAlpha(140));

    canvas.drawPath(
      Path()..addPolygon(points, true),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_CropOutlinePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.imageRect != imageRect ||
      oldDelegate.color != color;
}

/// Runs [_warpPerspective] on another isolate.
///
/// This is a top-level function on purpose: the closure given to
/// [Isolate.run] captures everything in the scope it is written in, and inside
/// the crop page's State that includes the decoded `ui.Image`, which can't be
/// sent to another isolate.
Future<Uint8List> _warpInBackground(
  Uint8List pixels,
  int width,
  int height,
  List<double> quad,
  int outW,
  int outH,
) {
  return Isolate.run(
    () => _warpPerspective(pixels, width, height, quad, outW, outH),
  );
}

/// Stretches the four-sided area [quad] (x, y of top left, top right, bottom
/// right, bottom left, in source pixels) into a [outW] x [outH] rectangle.
/// [src] and the result are straight (non-premultiplied) RGBA bytes.
Uint8List _warpPerspective(
  Uint8List src,
  int srcW,
  int srcH,
  List<double> quad,
  int outW,
  int outH,
) {
  final x0 = quad[0], y0 = quad[1];
  final x1 = quad[2], y1 = quad[3];
  final x2 = quad[4], y2 = quad[5];
  final x3 = quad[6], y3 = quad[7];

  // the transform that maps the unit square onto the quad
  final sx = x0 - x1 + x2 - x3;
  final sy = y0 - y1 + y2 - y3;
  final dx1 = x1 - x2, dx2 = x3 - x2;
  final dy1 = y1 - y2, dy2 = y3 - y2;
  double g = 0, h = 0;
  if (sx.abs() > 1e-9 || sy.abs() > 1e-9) {
    final den = dx1 * dy2 - dx2 * dy1;
    g = (sx * dy2 - dx2 * sy) / den;
    h = (dx1 * sy - sx * dy1) / den;
  }
  final a = x1 - x0 + g * x1;
  final b = x3 - x0 + h * x3;
  final c = x0;
  final d = y1 - y0 + g * y1;
  final e = y3 - y0 + h * y3;
  final f = y0;

  final out = Uint8List(outW * outH * 4);
  var o = 0;
  for (var j = 0; j < outH; j++) {
    final v = (j + 0.5) / outH;
    for (var i = 0; i < outW; i++) {
      final u = (i + 0.5) / outW;
      final w = g * u + h * v + 1;
      // pixel centers sit half a pixel in
      final px = (a * u + b * v + c) / w - 0.5;
      final py = (d * u + e * v + f) / w - 0.5;

      final ix = px.floor();
      final iy = py.floor();
      final fx = px - ix;
      final fy = py - iy;
      final xa = ix.clamp(0, srcW - 1);
      final xb = (ix + 1).clamp(0, srcW - 1);
      final ya = iy.clamp(0, srcH - 1);
      final yb = (iy + 1).clamp(0, srcH - 1);

      final p00 = (ya * srcW + xa) * 4;
      final p10 = (ya * srcW + xb) * 4;
      final p01 = (yb * srcW + xa) * 4;
      final p11 = (yb * srcW + xb) * 4;
      final w00 = (1 - fx) * (1 - fy);
      final w10 = fx * (1 - fy);
      final w01 = (1 - fx) * fy;
      final w11 = fx * fy;

      for (var ch = 0; ch < 4; ch++) {
        out[o++] =
            (src[p00 + ch] * w00 +
                    src[p10 + ch] * w10 +
                    src[p01 + ch] * w01 +
                    src[p11 + ch] * w11)
                .round();
      }
    }
  }
  return out;
}

Future<Uint8List> _encodePng(Uint8List rgba, int width, int height) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return data!.buffer.asUint8List();
}
