// One-shot icon generator for Rest Thermostat.
//
// Produces three PNG assets:
//   - assets/icon/icon.png             (1024x1024, app icon source)
//   - assets/icon/icon_foreground.png  (1024x1024, Android adaptive foreground)
//   - assets/splash/splash.png         (512x512, transparent bg splash logo)
//
// Design rationale (see docs/DESIGN.md §10.4 and the issue body for #24):
//
//   * Abstract geometric mark: three concentric arc segments forming a partial
//     ring. Outer arc warms toward Ember orange; inner arc cools toward Ember
//     blue. The middle arc interpolates.
//   * No fan blades, no leaves, no flame imagery (legal posture, DESIGN §1).
//   * A small solid dot at the geometric center reads as the focal point of
//     the (implicit) thermostat dial without referencing Nest's continuous
//     ring proportions.
//
// Drawing approach: the `image` package has no thick-arc primitive, so each
// pixel is tested directly against (radius band, angle band) for every arc.
// Anti-aliasing comes from per-pixel alpha falloff at the inner/outer radial
// edges and at the angular tips.
//
// Run from repo root:
//   dart run tool/generate_icon.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const int _canvasSize = 1024;
const int _splashSize = 512;

// Ember palette (matches DESIGN.md tokens):
//   Background     #050108  (near-black with a faint purple cast)
//   Orange warm    #FF6432  (outer arc)
//   Orange hot     #FF4516
//   Blue cool      #3070D0  (inner arc)
//   Blue bright    #50AAFF
//   Center dot     #FF8A50
const int _bgR = 0x05, _bgG = 0x01, _bgB = 0x08;

// Angular sweep: 195° to 345° (measured clockwise from the 3-o'clock axis in
// screen coordinates, where +y points DOWN). 195° starts in the lower-left
// quadrant and sweeps clockwise up through 270° (top) and down to 345°.
// Net effect: an open partial ring with the gap facing the bottom.
const double _arcStartDeg = 195;
const double _arcEndDeg = 345;

class _Arc {
  const _Arc({
    required this.radius,
    required this.strokeWidth,
    required this.startColor,
    required this.endColor,
  });

  final double radius;
  final double strokeWidth;
  // The arc's color is interpolated linearly from startColor (at the sweep's
  // start angle) to endColor (at the sweep's end angle).
  final (int, int, int) startColor;
  final (int, int, int) endColor;
}

const List<_Arc> _arcs = [
  _Arc(
    radius: 360,
    strokeWidth: 56,
    startColor: (0xFF, 0x64, 0x32), // outer: orange warm
    endColor: (0xFF, 0x45, 0x16), // outer: orange hot
  ),
  _Arc(
    radius: 280,
    strokeWidth: 44,
    startColor: (0xFF, 0x8A, 0x50), // middle: peach
    endColor: (0x70, 0x80, 0xE0), // middle: warm-to-cool transition
  ),
  _Arc(
    radius: 200,
    strokeWidth: 32,
    startColor: (0x30, 0x70, 0xD0), // inner: blue cool
    endColor: (0x50, 0xAA, 0xFF), // inner: blue bright
  ),
];

// Center accent dot.
const double _dotRadius = 32;
const (int, int, int) _dotColor = (0xFF, 0x8A, 0x50);

double _deg2rad(double deg) => deg * math.pi / 180.0;

/// Returns the angle in radians (0..2π) of a vector (dx, dy) from origin.
double _angleOf(double dx, double dy) {
  final a = math.atan2(dy, dx);
  return a < 0 ? a + 2 * math.pi : a;
}

/// Linear interpolation of an int channel.
int _lerpChan(int a, int b, double t) {
  return (a + (b - a) * t).round().clamp(0, 255);
}

/// Smooth alpha falloff: 1.0 inside [0, edge-aa], 0.0 outside [0, edge].
double _aaAlpha(double distance, double halfWidth, {double aa = 1.0}) {
  final outside = distance - halfWidth;
  if (outside <= -aa) return 1.0;
  if (outside >= 0) return 0.0;
  // Smoothstep between -aa..0.
  final t = (-outside) / aa;
  return t * t * (3 - 2 * t);
}

/// Draws the concentric-arcs glyph onto `image`. If `withBackground` is true,
/// fills the canvas with the Ember-deep color first; otherwise the canvas is
/// left transparent (used for the splash logo and Android adaptive foreground).
/// `scale` lets the caller render the glyph smaller within a larger canvas
/// (used for the foreground's safe-zone padding).
void _drawGlyph(
  img.Image image, {
  required bool withBackground,
  double scale = 1.0,
}) {
  final w = image.width;
  final h = image.height;

  if (withBackground) {
    img.fill(image, color: img.ColorRgba8(_bgR, _bgG, _bgB, 255));
  }

  // Recenter the composition (arcs + dot) on the canvas. With the chosen
  // sweep (195°→345°, screen coords +y down), arcs occupy the half-plane
  // ABOVE the geometric center; the dot sits at center. So the composition's
  // vertical bbox goes from cy - outerRadius to cy + dotRadius. To center
  // that bbox vertically: cy = h/2 + (outerRadius - dotRadius) / 2.
  // The reference geometry assumes a 1024×1024 canvas; for other sizes or
  // scaled-down draws we re-anchor to the canvas center.
  final geometryScale = (w / 1024.0) * scale;
  final outerR = _arcs.first.radius * geometryScale;
  final dotR = _dotRadius * geometryScale;
  final cx = w / 2.0;
  final cy = h / 2.0 + (outerR - dotR) / 2.0;

  final startA = _deg2rad(_arcStartDeg);
  final endA = _deg2rad(_arcEndDeg);
  // Angular AA in radians, scaled with the canvas so tip falloff stays ~1px.
  final angularAa = 2.5 / (200 * geometryScale);

  for (var arc in _arcs) {
    final r = arc.radius * geometryScale;
    final halfStroke = arc.strokeWidth * geometryScale / 2.0;
    final rMin = r - halfStroke - 2;
    final rMax = r + halfStroke + 2;

    // Iterate the bounding box of the arc only.
    final xMin = (cx - rMax).floor().clamp(0, w - 1);
    final xMax = (cx + rMax).ceil().clamp(0, w - 1);
    final yMin = (cy - rMax).floor().clamp(0, h - 1);
    final yMax = (cy + rMax).ceil().clamp(0, h - 1);

    for (var y = yMin; y <= yMax; y++) {
      for (var x = xMin; x <= xMax; x++) {
        final dx = x + 0.5 - cx;
        final dy = y + 0.5 - cy;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < rMin || dist > rMax) continue;

        // Radial alpha: full inside [r-halfStroke, r+halfStroke], smoothstep
        // out over ~1.5px.
        final radial = _aaAlpha((dist - r).abs(), halfStroke, aa: 1.5);
        if (radial <= 0) continue;

        // Rotate the frame so the sweep starts at angle 0 and ends at
        // `sweep`. `aRel` is the pixel's angle in that rotated frame.
        final sweep = endA - startA;
        var aRel = _angleOf(dx, dy) - startA;
        if (aRel < 0) aRel += 2 * math.pi;

        // Distance (in radians) from `aRel` to the nearest point in [0, sweep].
        // Inside the sweep this is 0; outside it's the gap to the closer tip.
        // Outside-distance wraps around 2π — the start tip is also reachable
        // by going clockwise from aRel through 2π back to 0.
        final double tipGap;
        if (aRel <= sweep) {
          tipGap = -math.min(aRel, sweep - aRel); // negative = inside
        } else {
          tipGap = math.min(aRel - sweep, 2 * math.pi - aRel);
        }

        // Smoothstep across the AA band centered on the tip: full coverage
        // at gap = -angularAa, zero at gap = +angularAa.
        final double angularAlpha;
        if (tipGap <= -angularAa) {
          angularAlpha = 1.0;
        } else if (tipGap >= angularAa) {
          continue;
        } else {
          final t = (angularAa - tipGap) / (2 * angularAa);
          angularAlpha = t * t * (3 - 2 * t);
        }

        // Color: interpolate startColor → endColor along the sweep. Pixels
        // outside the band borrow the nearer tip's color so the AA falloff
        // matches the band's color at that tip.
        final t = (aRel.clamp(0, sweep)) / sweep;
        final r0 = _lerpChan(arc.startColor.$1, arc.endColor.$1, t);
        final g0 = _lerpChan(arc.startColor.$2, arc.endColor.$2, t);
        final b0 = _lerpChan(arc.startColor.$3, arc.endColor.$3, t);

        final coverage = radial * angularAlpha;
        final alpha = (255 * coverage).round().clamp(0, 255);
        _compositePixel(image, x, y, r0, g0, b0, alpha);
      }
    }
  }

  // Center accent dot (filled circle).
  final dotRMax = dotR + 2;
  final dxMin = (cx - dotRMax).floor().clamp(0, w - 1);
  final dxMax = (cx + dotRMax).ceil().clamp(0, w - 1);
  final dyMin = (cy - dotRMax).floor().clamp(0, h - 1);
  final dyMax = (cy + dotRMax).ceil().clamp(0, h - 1);
  for (var y = dyMin; y <= dyMax; y++) {
    for (var x = dxMin; x <= dxMax; x++) {
      final dx = x + 0.5 - cx;
      final dy = y + 0.5 - cy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist > dotRMax) continue;
      final radial = _aaAlpha(dist, dotR, aa: 1.5);
      if (radial <= 0) continue;
      final alpha = (255 * radial).round().clamp(0, 255);
      _compositePixel(
        image,
        x,
        y,
        _dotColor.$1,
        _dotColor.$2,
        _dotColor.$3,
        alpha,
      );
    }
  }
}

/// Alpha-composite a single source pixel onto the target image at (x, y).
/// Uses straight-alpha source-over compositing.
void _compositePixel(
  img.Image image,
  int x,
  int y,
  int r,
  int g,
  int b,
  int a,
) {
  if (a <= 0) return;
  final existing = image.getPixel(x, y);
  final dstA = existing.a.toInt();
  if (dstA == 0 || a == 255) {
    image.setPixelRgba(x, y, r, g, b, a);
    return;
  }
  final srcA = a / 255.0;
  final dstAf = dstA / 255.0;
  final outA = srcA + dstAf * (1 - srcA);
  final outR = (r * srcA + existing.r.toInt() * dstAf * (1 - srcA)) / outA;
  final outG = (g * srcA + existing.g.toInt() * dstAf * (1 - srcA)) / outA;
  final outB = (b * srcA + existing.b.toInt() * dstAf * (1 - srcA)) / outA;
  image.setPixelRgba(
    x,
    y,
    outR.round().clamp(0, 255),
    outG.round().clamp(0, 255),
    outB.round().clamp(0, 255),
    (outA * 255).round().clamp(0, 255),
  );
}

Future<void> _writePng(img.Image image, String path) async {
  final bytes = img.encodePng(image);
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  stdout.writeln(
    '  wrote $path (${bytes.length} bytes, ${image.width}x${image.height})',
  );
}

Future<void> main() async {
  stdout.writeln('Generating Rest Thermostat icon assets...');

  // 1) App icon — full canvas, Ember-deep background.
  final icon = img.Image(
    width: _canvasSize,
    height: _canvasSize,
    numChannels: 4,
  );
  _drawGlyph(icon, withBackground: true);
  await _writePng(icon, 'assets/icon/icon.png');

  // 2) Android adaptive foreground — same glyph, no background, centered with
  //    safe-zone padding. Android crops the outer ~25% of an adaptive icon, so
  //    the visible content must fit inside the inner 66% of the canvas. We
  //    scale the glyph to ~0.66 to land inside the safe zone with margin.
  final foreground = img.Image(
    width: _canvasSize,
    height: _canvasSize,
    numChannels: 4,
  );
  _drawGlyph(foreground, withBackground: false, scale: 0.66);
  await _writePng(foreground, 'assets/icon/icon_foreground.png');

  // 3) Splash logo — transparent background, scaled down. flutter_native_splash
  //    overlays this on the configured solid color (#000000 per the issue).
  final splash = img.Image(
    width: _splashSize,
    height: _splashSize,
    numChannels: 4,
  );
  _drawGlyph(splash, withBackground: false);
  await _writePng(splash, 'assets/splash/splash.png');

  stdout.writeln('Done.');
}
