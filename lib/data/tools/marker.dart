import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:saber/data/tools/pen.dart';

/// A thick, fixed-width felt-tip marker.
///
/// Strokes are stored with the ballpoint tool id (no new stroke type), so
/// existing files and the canvas keep working unchanged.
class Marker extends Pen {
  new()
    : super(
        name: 'Marker',
        sizeMin: 4,
        sizeMax: 40,
        sizeStep: 2,
        icon: markerIcon,
        options: Pen.defaultOptions.copyWith(
          size: 12,
          smoothing: 0.5,
          streamline: 0.35,
        ),
        pressureEnabled: false,
        color: Colors.black,
        toolId: .ballpointPen,
      );

  static var currentMarker = Marker();

  static const markerIcon = FontAwesomeIcons.marker;
}
