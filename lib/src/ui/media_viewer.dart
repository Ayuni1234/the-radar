import 'package:flutter/material.dart';

import '../data/device_video_surface.dart';
import 'radar_theme.dart';

/// Opens the full-screen media viewer for a post's photo or device-video
/// poster frame. Pushes a dark fade-through route; pops on tap, Escape or
/// the close button.
Future<void> showMediaViewer(
  BuildContext context, {
  required String imageUrl,
  String? heroTag,
  String? authorName,
}) {
  return Navigator.of(context, rootNavigator: true).push(_MediaViewerRoute(
    imageUrl: imageUrl,
    heroTag: heroTag,
    authorName: authorName,
  ));
}

/// Fade-through route so the zoomed hero lands smoothly without the
/// material slide; the barrier is opaque black for focus.
class _MediaViewerRoute extends PageRouteBuilder<void> {
  _MediaViewerRoute({
    required String imageUrl,
    String? heroTag,
    String? authorName,
  }) : super(
          transitionDuration: const Duration(milliseconds: 240),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (_, _, _) => MediaViewer(
            imageUrl: imageUrl,
            heroTag: heroTag,
            authorName: authorName,
          ),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
          opaque: false,
          barrierColor: Colors.black,
        );
}

/// Full-screen media viewer: pinch to zoom, double-tap to toggle 1x/2.5x,
/// drag to pan while zoomed, and swipe-down to dismiss — pulling the image
/// away with a scale/opacity fade, exactly like the photo viewers in the
/// major social apps.
///
/// Gestures are handled with one custom scale handler rather than an
/// [InteractiveViewer]: an active scale recognizer in the tree would win
/// the arena for one-finger drags and kill swipe-to-dismiss at 1x.
class MediaViewer extends StatefulWidget {
  const MediaViewer({
    super.key,
    required this.imageUrl,
    this.heroTag,
    this.authorName,
  });

  /// Public CDN URL of the image (device photo or persisted video poster).
  final String imageUrl;

  /// Hero tag shared with the card's hero image for the zoom-in landing.
  final String? heroTag;

  /// Shown as the byline in the top chrome.
  final String? authorName;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer>
    with TickerProviderStateMixin {
  static const double _maxScale = 5.0;
  static const double _doubleTapScale = 2.5;
  static const double _dismissThreshold = 110;
  static const double _dismissVelocity = 900;

  final ValueNotifier<Matrix4> _transform =
      ValueNotifier<Matrix4>(Matrix4.identity());
  TapDownDetails? _lastDoubleTapDown;
  AnimationController? _animation;

  // Gesture-start snapshot: the matrix, focal point and scale the active
  // pinch/pan began from (composition base for incremental updates).
  Matrix4 _startMatrix = Matrix4.identity();
  Offset _startFocal = Offset.zero;
  double _startScale = 1.0;

  // Swipe-to-dismiss pull: the one-finger drag at 1x pulls the image away
  // with a fading backdrop; past the threshold a release closes.
  bool _isPulling = false;
  Offset _pullOffset = Offset.zero;
  double _pullScale = 1.0;

  @override
  void initState() {
    super.initState();
    // Platform views composite above the Flutter canvas on web, so any
    // cached video slot must be hidden DOM-side while this route is open.
    setDeviceVideosVisible(false);
  }

  @override
  void dispose() {
    setDeviceVideosVisible(true);
    _animation?.dispose();
    _transform.dispose();
    super.dispose();
  }

  bool get _isZoomed => _transform.value.getMaxScaleOnAxis() > 1.05;

  void _onDoubleTapDown(TapDownDetails details) {
    _lastDoubleTapDown = details;
  }

  void _onDoubleTap() {
    if (_isZoomed) {
      _animateTo(Matrix4.identity());
      return;
    }
    const scale = _doubleTapScale;
    final position =
        _lastDoubleTapDown?.localPosition ?? (context.size?.center(Offset.zero) ?? Offset.zero);
    // Zoom into the tapped point: scale about that point in local coords.
    _animateTo(Matrix4.identity() *
        Matrix4.translationValues(position.dx, position.dy, 0) *
        Matrix4.diagonal3Values(scale, scale, 1) *
        Matrix4.translationValues(-position.dx, -position.dy, 0));
  }

  void _animateTo(Matrix4 target) {
    _animation?.dispose();
    final controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    final Animation<Matrix4> anim = Matrix4Tween(
      begin: _transform.value,
      end: target,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutCubic));
    void listener() => _transform.value = anim.value;
    anim.addListener(listener);
    controller.addStatusListener((status) {
      if (status != AnimationStatus.forward) {
        anim.removeListener(listener);
        controller.dispose();
        if (identical(_animation, controller)) _animation = null;
      }
    });
    _animation = controller;
    controller.forward();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _animation?.stop();
    _startMatrix = _transform.value.clone();
    _startFocal = details.localFocalPoint;
    _startScale = _startMatrix.getMaxScaleOnAxis();
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final zoomGesture = _startScale > 1.05 || details.pointerCount >= 2;
    if (zoomGesture) {
      if (_isPulling) {
        setState(() {
          _isPulling = false;
          _pullOffset = Offset.zero;
          _pullScale = 1.0;
        });
      }
      // Compose on the gesture-start matrix: scale about the start focal
      // point, then pan by the focal delta. One finger while zoomed
      // (details.scale == 1) degenerates to pure panning.
      final newScale = (_startScale * details.scale).clamp(1.0, _maxScale);
      final matrix = _startMatrix *
          Matrix4.translationValues(_startFocal.dx, _startFocal.dy, 0) *
          Matrix4.diagonal3Values(newScale / _startScale, newScale / _startScale, 1) *
          Matrix4.translationValues(-_startFocal.dx, -_startFocal.dy, 0) *
          Matrix4.translationValues(
              details.localFocalPoint.dx - _startFocal.dx,
              details.localFocalPoint.dy - _startFocal.dy,
              0);
      _transform.value = _clampPan(matrix, newScale);
      return;
    }
    // One finger at 1x: the swipe-to-dismiss pull. Only downward pulls
    // travel (no bounce-up); horizontal movement is damped.
    final dy = details.focalPointDelta.dy;
    if (!_isPulling && dy <= 0) return;
    setState(() {
      _isPulling = true;
      _pullOffset = Offset(_pullOffset.dx + details.focalPointDelta.dx * 0.5,
          _pullOffset.dy + dy);
      final t = (_pullOffset.distance / 480).clamp(0.0, 0.55);
      _pullScale = 1.0 - t;
    });
  }

  /// Keeps the scaled image roughly on screen: the translation column of
  /// the composed matrix is clamped to the scaled overflow of the viewport.
  Matrix4 _clampPan(Matrix4 matrix, double scale) {
    final size = context.size;
    if (size == null) return matrix;
    final maxX = (scale - 1) * size.width / 2;
    final maxY = (scale - 1) * size.height / 2;
    final tx = matrix.getTranslation().x;
    final ty = matrix.getTranslation().y;
    final clampedTx = tx.clamp(-maxX, maxX);
    final clampedTy = ty.clamp(-maxY, maxY);
    // Post-multiplied translate happens in scaled space — divide the
    // correction by the scale so the visual offset lands exactly.
    return matrix *
        Matrix4.translationValues(
            (clampedTx - tx) / scale, (clampedTy - ty) / scale, 0);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_isPulling) {
      final shouldDismiss = _pullOffset.dy > _dismissThreshold ||
          details.velocity.pixelsPerSecond.dy > _dismissVelocity;
      if (shouldDismiss) {
        Navigator.of(context).pop();
        return; // the route's dispose resets the visuals
      }
      setState(() {
        _isPulling = false;
        _pullOffset = Offset.zero;
        _pullScale = 1.0;
      });
      return;
    }
    // A pinch that ended back at ~1x snaps the translation away.
    if (_transform.value.getMaxScaleOnAxis() <= 1.001) {
      _animateTo(Matrix4.identity());
    }
  }

  @override
  Widget build(BuildContext context) {
    final hero = Hero(
      tag: widget.heroTag ?? '',
      child: Image.network(
        widget.imageUrl,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        // A failed CDN fetch shows a quiet error state, never a crash —
        // and keeps widget tests free of unhandled image exceptions. The
        // FittedBox scales it into whatever constraints the hero flight
        // passes through (they can be arbitrarily small mid-animation).
        errorBuilder: (_, _, _) => FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_not_supported_outlined,
                  size: 44, color: Colors.white.withValues(alpha: 0.5)),
              const SizedBox(height: 10),
              Text(
                'Media could not be loaded',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black
          .withValues(alpha: (_isPulling ? 0.96 * _pullScale : 1.0)),
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        onDoubleTapDown: _onDoubleTapDown,
        onDoubleTap: _onDoubleTap,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: Stack(
          children: [
            // The media: transformed when zoomed, pulled away while
            // dismissing — never both.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _transform,
                builder: (context, _) {
                  return Transform.translate(
                    offset: _pullOffset,
                    child: Transform.scale(
                      scale: _pullScale,
                      child: Transform(
                        transform: _transform.value,
                        child: Center(child: hero),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Top chrome: byline + close.
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Row(
                  children: [
                    if (widget.authorName != null)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(
                            widget.authorName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: RadarTheme.textPrimary
                                  .withValues(alpha: 0.92),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _ViewerIconButton(
                        icon: Icons.close,
                        tooltip: 'Close viewer',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Bottom hint.
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Text(
                    _isZoomed
                        ? 'Pinch or drag to move · double-tap to reset'
                        : 'Pinch to zoom · double-tap · swipe down to close',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11.5,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerIconButton extends StatelessWidget {
  const _ViewerIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, size: 19, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
