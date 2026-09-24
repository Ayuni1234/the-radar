import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/device_video_surface.dart';
import 'radar_theme.dart';

/// One viewable item in the full-screen media gallery: a device photo or
/// a device video's persisted poster frame.
class ViewerMedia {
  const ViewerMedia({
    required this.imageUrl,
    this.authorName,
    this.postId,
  });

  /// Public CDN URL of the image.
  final String imageUrl;

  /// Byline shown in the top chrome for this item.
  final String? authorName;

  /// Owning post id — used to locate the tapped post inside the gallery.
  final String? postId;
}

/// Opens the full-screen media gallery. [media] holds every viewable item
/// of the surrounding feed (or just one); [initialIndex] selects the tapped
/// post and [heroTag] wires its zoom-in flight. Swipe left/right browses,
/// swipe down dismisses, pinch zooms, arrows/Escape work on desktop.
Future<void> showMediaViewer(
  BuildContext context, {
  required List<ViewerMedia> media,
  int initialIndex = 0,
  String? heroTag,
}) {
  return Navigator.of(context, rootNavigator: true).push(_MediaViewerRoute(
    media: media,
    initialIndex: initialIndex.clamp(0, media.isEmpty ? 0 : media.length - 1),
    heroTag: heroTag,
  ));
}

/// Fade-through route so the zoomed hero lands smoothly without the
/// material slide; the barrier is opaque black for focus.
class _MediaViewerRoute extends PageRouteBuilder<void> {
  _MediaViewerRoute({
    required List<ViewerMedia> media,
    required int initialIndex,
    String? heroTag,
  }) : super(
          transitionDuration: const Duration(milliseconds: 240),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (_, _, _) => MediaViewer(
            media: media,
            initialIndex: initialIndex,
            heroTag: heroTag,
          ),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
          opaque: false,
          barrierColor: Colors.black,
        );
}

/// Full-screen media gallery: pinch to zoom, double-tap to toggle 1x/2.5x,
/// drag to pan while zoomed, swipe left/right between the feed's media and
/// swipe down to dismiss — pulling the image away with a scale/opacity
/// fade, exactly like the photo viewers in the major social apps.
///
/// Desktop keyboard support: Escape closes, ←/→ browse, Home/End jump to
/// the gallery ends, and Tab still reaches the chrome buttons (key events
/// bubble to this listener from focused descendants). Opening steals focus
/// from whatever sat behind the route and closing restores it, so keys
/// never leak into the app underneath and desktop users land back where
/// they were.
///
/// All gestures live in one custom scale handler (no [InteractiveViewer],
/// no [PageView]): an active recognizer elsewhere in the tree would win
/// one-finger drags and break either paging or swipe-to-dismiss. The
/// handler axis-locks on the first significant movement — horizontal
/// drags page through the gallery (with neighbor previews and edge
/// rubber-banding), vertical drags pull the viewer away.
class MediaViewer extends StatefulWidget {
  const MediaViewer({
    super.key,
    required this.media,
    this.initialIndex = 0,
    this.heroTag,
  });

  /// Every viewable media item of the surrounding feed.
  final List<ViewerMedia> media;

  /// Index of the item the viewer opened on (the hero-flight target).
  final int initialIndex;

  /// Hero tag shared with the card's hero image for the zoom-in landing.
  /// Only applies to the item at [initialIndex].
  final String? heroTag;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

enum _DragMode { none, paging, pulling }

class _MediaViewerState extends State<MediaViewer>
    with TickerProviderStateMixin {
  static const double _maxScale = 5.0;
  static const double _doubleTapScale = 2.5;
  static const double _dismissThreshold = 110;
  static const double _dismissVelocity = 900;
  static const double _pageSwitchRatio = 0.25;
  static const double _pageSwitchVelocity = 500;
  static const double _axisLockSlop = 8;

  final ValueNotifier<Matrix4> _transform =
      ValueNotifier<Matrix4>(Matrix4.identity());
  final ValueNotifier<double> _pageDx = ValueNotifier<double>(0);
  TapDownDetails? _lastDoubleTapDown;
  AnimationController? _animation;
  AnimationController? _pageAnimation;
  final FocusNode _focus = FocusNode();

  /// Whatever held keyboard focus when the viewer opened (typically a
  /// composer text field behind the route). Keys must not leak into it
  /// while the viewer is up, and focus returns to it on close.
  FocusNode? _previousFocus;

  late int _index = widget.initialIndex.clamp(0, widget.media.length - 1);
  _DragMode _mode = _DragMode.none;

  // Gesture-start snapshot: the matrix, focal point and scale the active
  // pinch/pan began from (composition base for incremental updates).
  Matrix4 _startMatrix = Matrix4.identity();
  Offset _startFocal = Offset.zero;
  double _startScale = 1.0;

  // Swipe-to-dismiss pull: the vertical drag at 1x pulls the image away
  // with a fading backdrop; past the threshold a release closes.
  bool _isPulling = false;
  Offset _pullOffset = Offset.zero;
  double _pullScale = 1.0;

  bool get _isZoomed => _transform.value.getMaxScaleOnAxis() > 1.05;
  bool get _hasGallery => widget.media.length > 1;

  @override
  void initState() {
    super.initState();
    // Platform views composite above the Flutter canvas on web, so any
    // cached video slot must be hidden DOM-side while this route is open.
    setDeviceVideosVisible(false);
    // Steal the keyboard from whatever sits behind the route (an open
    // composer's text field, a search box) — Escape and the arrows belong
    // to the viewer until it closes. The KeyboardListener's autofocus
    // then lands focus on this route's node.
    _previousFocus = FocusManager.instance.primaryFocus;
    _previousFocus?.unfocus();
  }

  @override
  void dispose() {
    // Hand the keyboard back — a desktop user closing the viewer with
    // Escape lands right back in the field they were typing in.
    final previous = _previousFocus;
    if (previous != null &&
        previous.context != null &&
        previous.canRequestFocus) {
      previous.requestFocus();
    }
    setDeviceVideosVisible(true);
    _animation?.dispose();
    _pageAnimation?.dispose();
    _transform.dispose();
    _pageDx.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        _index > 0) {
      _animateToIndex(_index - 1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        _index < widget.media.length - 1) {
      _animateToIndex(_index + 1);
    } else if (event.logicalKey == LogicalKeyboardKey.home && _index > 0) {
      _animateToIndex(0);
    } else if (event.logicalKey == LogicalKeyboardKey.end &&
        _index < widget.media.length - 1) {
      _animateToIndex(widget.media.length - 1);
    }
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _lastDoubleTapDown = details;
  }

  void _onDoubleTap() {
    if (_isZoomed) {
      _animateTo(Matrix4.identity());
      return;
    }
    const scale = _doubleTapScale;
    final position = _lastDoubleTapDown?.localPosition ??
        (context.size?.center(Offset.zero) ?? Offset.zero);
    // Zoom into the tapped point: scale about that point in local coords.
    _animateTo(Matrix4.identity() *
        Matrix4.translationValues(position.dx, position.dy, 0) *
        Matrix4.diagonal3Values(scale, scale, 1) *
        Matrix4.translationValues(-position.dx, -position.dy, 0));
  }

  void _animateTo(Matrix4 target) {
    _animation?.dispose();
    final controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
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
    if (_pageAnimation?.isAnimating ?? false) return;
    _animation?.stop();
    _startMatrix = _transform.value.clone();
    _startFocal = details.localFocalPoint;
    _startScale = _startMatrix.getMaxScaleOnAxis();
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final zoomGesture = _startScale > 1.05 || details.pointerCount >= 2;
    if (zoomGesture) {
      _cancelPaging();
      // Compose on the gesture-start matrix: scale about the start focal
      // point, then pan by the focal delta. One finger while zoomed
      // (details.scale == 1) degenerates to pure panning.
      final newScale = (_startScale * details.scale).clamp(1.0, _maxScale);
      final matrix = _startMatrix *
          Matrix4.translationValues(_startFocal.dx, _startFocal.dy, 0) *
          Matrix4.diagonal3Values(
              newScale / _startScale, newScale / _startScale, 1) *
          Matrix4.translationValues(-_startFocal.dx, -_startFocal.dy, 0) *
          Matrix4.translationValues(
              details.localFocalPoint.dx - _startFocal.dx,
              details.localFocalPoint.dy - _startFocal.dy,
              0);
      _transform.value = _clampPan(matrix, newScale);
      return;
    }
    // One finger at 1x: axis-lock on the first significant movement.
    if (_mode == _DragMode.none) {
      final dx = details.focalPointDelta.dx;
      final dy = details.focalPointDelta.dy;
      if (dx.abs() < _axisLockSlop && dy.abs() < _axisLockSlop) return;
      if (dx.abs() > dy.abs()) {
        _mode = _DragMode.paging;
      } else if (dy > 0) {
        _mode = _DragMode.pulling; // only downward pulls travel
      } else {
        return; // upward drag: neither paging nor dismissing
      }
    }
    if (_mode == _DragMode.paging) {
      var dx = details.focalPointDelta.dx;
      // Rubber-band past the ends when there is no neighbor to reveal.
      final canAdvance = _index < widget.media.length - 1;
      final canGoBack = _index > 0;
      if ((dx < 0 && !canAdvance) || (dx > 0 && !canGoBack)) dx *= 0.22;
      _pageDx.value += dx;
      return;
    }
    // Pulling: vertical dismiss drag, horizontal movement damped.
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

  void _cancelPaging() {
    if (_mode == _DragMode.paging) {
      _pageDx.value = 0;
      _mode = _DragMode.none;
    }
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
    if (_mode == _DragMode.paging) {
      final width = context.size?.width ?? 0;
      final velocity = details.velocity.pixelsPerSecond.dx;
      final progress = width <= 0 ? 0.0 : -_pageDx.value / width;
      int dir;
      if (velocity.abs() > _pageSwitchVelocity) {
        dir = velocity < 0 ? 1 : -1;
      } else if (progress.abs() > _pageSwitchRatio) {
        dir = progress < 0 ? 1 : -1;
      } else {
        dir = 0;
      }
      // A flick past the end rubber-bands back instead of switching.
      if ((dir > 0 && _index >= widget.media.length - 1) ||
          (dir < 0 && _index <= 0)) {
        dir = 0;
      }
      _animatePage(dir);
      return;
    }
    _mode = _DragMode.none;
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

  /// Settles a page drag: snaps to the neighbor when [dir] is ±1, springs
  /// back to the current page when 0.
  void _animatePage(int dir) {
    final width = context.size?.width ?? 0;
    _animatePageRaw(
      from: _pageDx.value,
      to: dir == 0 ? 0 : -dir * width,
      commitTo: dir == 0 ? null : _index + dir,
    );
  }

  void _animateToIndex(int target) {
    final width = context.size?.width ?? 0;
    if (width <= 0 || (_pageAnimation?.isAnimating ?? false)) return;
    _animatePageRaw(
      from: 0,
      to: target > _index ? -width : width,
      commitTo: target,
    );
  }

  void _animatePageRaw({
    required double from,
    required double to,
    int? commitTo,
  }) {
    _pageAnimation?.dispose();
    final controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    final tween = Tween<double>(begin: from, end: to)
        .animate(CurvedAnimation(parent: controller, curve: Curves.easeOutCubic));
    void listener() => _pageDx.value = tween.value;
    tween.addListener(listener);
    controller.addStatusListener((status) {
      if (status != AnimationStatus.forward) {
        tween.removeListener(listener);
        controller.dispose();
        if (identical(_pageAnimation, controller)) _pageAnimation = null;
      }
      if (status == AnimationStatus.completed && commitTo != null) {
        _commitPage(commitTo);
      }
    });
    _pageAnimation = controller;
    controller.forward();
  }

  void _commitPage(int newIndex) {
    setState(() {
      _index = newIndex.clamp(0, widget.media.length - 1);
      _mode = _DragMode.none;
      _isPulling = false;
      _pullOffset = Offset.zero;
      _pullScale = 1.0;
    });
    _pageDx.value = 0;
    _transform.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.media[_index];

    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Scaffold(
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
              // The gallery: current item (transformed when zoomed, pulled
              // away while dismissing) plus neighbor previews during a
              // page drag — never both paging and pulling.
              Positioned.fill(
                child: ValueListenableBuilder<double>(
                  valueListenable: _pageDx,
                  builder: (context, pageDx, _) {
                    final width = MediaQuery.sizeOf(context).width;
                    return Stack(
                      children: [
                        if (pageDx > 1 && _index > 0)
                          Positioned.fill(
                            child: Transform.translate(
                              offset: Offset(pageDx - width, 0),
                              child: Center(
                                  child: _ViewerImage(
                                      widget.media[_index - 1].imageUrl)),
                            ),
                          ),
                        if (pageDx < -1 && _index < widget.media.length - 1)
                          Positioned.fill(
                            child: Transform.translate(
                              offset: Offset(pageDx + width, 0),
                              child: Center(
                                  child: _ViewerImage(
                                      widget.media[_index + 1].imageUrl)),
                            ),
                          ),
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _transform,
                            builder: (context, _) {
                              return Transform.translate(
                                offset: Offset(pageDx, 0) + _pullOffset,
                                child: Transform.scale(
                                  scale: _pullScale,
                                  child: Transform(
                                    transform: _transform.value,
                                    child: Center(
                                      child: _ViewerImage(
                                        item.imageUrl,
                                        // The hero flight only exists for
                                        // the item the viewer opened on.
                                        heroTag: _index == widget.initialIndex
                                            ? widget.heroTag
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              // Top chrome: byline + position counter + close.
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: Row(
                    children: [
                      if (item.authorName != null)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Text(
                              item.authorName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color:
                                    RadarTheme.textPrimary.withValues(alpha: 0.92),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      if (_hasGallery)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '${_index + 1} / ${widget.media.length}',
                            style: TextStyle(
                              color:
                                  Colors.white.withValues(alpha: 0.75),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
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
                          : _hasGallery
                              ? 'Pinch to zoom · swipe to browse · swipe down to close'
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
      ),
    );
  }
}

/// The viewer's image: CDN fetch with a quiet error state (never a crash,
/// never an unhandled test exception). The FittedBox scales the error into
/// whatever constraints the hero flight passes through (they can be
/// arbitrarily small mid-animation).
class _ViewerImage extends StatelessWidget {
  const _ViewerImage(this.imageUrl, {this.heroTag});

  final String imageUrl;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final image = Image.network(
      imageUrl,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
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
    );
    if (heroTag == null) return image;
    return Hero(tag: heroTag!, child: image);
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
