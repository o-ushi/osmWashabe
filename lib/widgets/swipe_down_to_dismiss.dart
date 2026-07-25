import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Fullscreen-dialog route whose built-in pop transition slides straight
/// down (instead of the standard push/pop's horizontal slide), so it doesn't
/// fight with [SwipeDownToDismiss]'s drag-to-dismiss when the threshold is
/// crossed mid-gesture. Use this for any route wrapped in
/// [SwipeDownToDismiss] — pairing it with a plain [CupertinoPageRoute]
/// produces the down-then-jump-right artifact this was built to avoid.
Route<T> fullscreenDismissRoute<T>({required WidgetBuilder builder}) {
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => CupertinoPageRoute<T>(
        fullscreenDialog: true,
        builder: builder,
      ),
    _ => MaterialPageRoute<T>(
        fullscreenDialog: true,
        builder: builder,
      ),
  };
}

enum _DragAxis { none, vertical, horizontal }

/// Wraps [child] so dragging down or right pops the route with the screen
/// visibly sliding under the finger, matching the calculator's dismiss gesture
/// instead of the default push/pop transition.
///
/// The pop decision is made only on release (drag distance past a threshold,
/// or a fast enough flick), exactly like the calculator's own
/// `onVerticalDragEnd` check — never mid-drag. On release we drive the rest
/// of the motion ourselves with an [AnimationController] — gliding fully
/// off-screen (dismiss) or easing back to zero (cancelled drag) — and only
/// call [Navigator.pop] once the screen has already animated past the
/// edge. Handing off to the route's own fixed-duration exit transition
/// mid-gesture is what used to make the screen "overtake" the finger and
/// rocket away; finishing our own animation first keeps the motion continuous
/// and the actual pop invisible.
///
/// Pass [scrollController] when [child] contains a scrollable: downward
/// dismiss only engages once that scrollable is already at its top offset, so
/// normal scrolling is left untouched. Rightward dismiss works regardless of
/// scroll position. Omit [scrollController] for non-scrolling screens.
class SwipeDownToDismiss extends StatefulWidget {
  const SwipeDownToDismiss({
    super.key,
    required this.child,
    this.scrollController,
  });

  final Widget child;
  final ScrollController? scrollController;

  @override
  State<SwipeDownToDismiss> createState() => _SwipeDownToDismissState();
}

class _SwipeDownToDismissState extends State<SwipeDownToDismiss>
    with SingleTickerProviderStateMixin {
  static const _popDistanceThreshold = 160.0;
  static const _popVelocityThreshold = 800.0;

  /// Minimum/maximum wall-clock time for the release-to-offscreen glide,
  /// regardless of how fast or slow the actual flick velocity implies —
  /// keeps a barely-past-threshold release from crawling for a full second,
  /// and an extreme flick from finishing in an unnaturally instant snap.
  static const _dismissMinMs = 140;
  static const _dismissMaxMs = 320;
  static const _settleBackMs = 220;

  static const _dragStartSlop = 12.0;

  Offset _dragOffset = Offset.zero;
  Offset? _pointerDown;
  bool _dragging = false;
  _DragAxis _axis = _DragAxis.none;
  VelocityTracker? _velocityTracker;
  late final AnimationController _controller;
  Animation<Offset>? _offsetAnimation;

  bool get _atTop {
    final controller = widget.scrollController;
    if (controller == null || !controller.hasClients) return true;
    return controller.offset <= 0;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addListener(() {
        final animation = _offsetAnimation;
        if (animation != null) setState(() => _dragOffset = animation.value);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss(double releaseVelocity, _DragAxis axis) {
    final size = MediaQuery.sizeOf(context);
    final target = switch (axis) {
      _DragAxis.vertical => Offset(0, size.height + 80),
      _DragAxis.horizontal => Offset(size.width + 80, 0),
      _DragAxis.none => Offset.zero,
    };
    final current = axis == _DragAxis.vertical ? _dragOffset.dy : _dragOffset.dx;
    final targetValue =
        axis == _DragAxis.vertical ? target.dy : target.dx;
    final distance = targetValue - current;
    final speed = releaseVelocity > 200 ? releaseVelocity : 1400.0;
    final durationMs =
        (distance / speed * 1000).clamp(_dismissMinMs, _dismissMaxMs).round();

    _offsetAnimation = Tween<Offset>(begin: _dragOffset, end: target)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.duration = Duration(milliseconds: durationMs);
    _controller.forward(from: 0).whenComplete(() {
      if (mounted) Navigator.pop(context);
    });
  }

  void _settleBack() {
    _offsetAnimation = Tween<Offset>(begin: _dragOffset, end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.duration = const Duration(milliseconds: _settleBackMs);
    _controller.forward(from: 0);
  }

  void _resetGesture() {
    _velocityTracker = null;
    _pointerDown = null;
    _dragging = false;
    _axis = _DragAxis.none;
  }

  void _onPointerUp() {
    if (!_dragging || _dragOffset == Offset.zero) {
      _resetGesture();
      return;
    }
    final velocity =
        _velocityTracker?.getVelocity().pixelsPerSecond ?? Offset.zero;
    final axis = _axis;
    _resetGesture();

    final releaseVelocity =
        axis == _DragAxis.vertical ? velocity.dy : velocity.dx;
    final dragDistance =
        axis == _DragAxis.vertical ? _dragOffset.dy : _dragOffset.dx;
    if (releaseVelocity > _popVelocityThreshold ||
        dragDistance > _popDistanceThreshold) {
      _dismiss(releaseVelocity, axis);
    } else {
      _settleBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _controller.stop();
        _pointerDown = event.position;
        _dragging = false;
        _axis = _DragAxis.none;
        _velocityTracker = VelocityTracker.withKind(event.kind);
        _velocityTracker!.addPosition(event.timeStamp, event.position);
      },
      onPointerMove: (event) {
        _velocityTracker?.addPosition(event.timeStamp, event.position);

        if (!_dragging) {
          final down = _pointerDown;
          if (down == null) return;

          final totalDx = event.position.dx - down.dx;
          final totalDy = event.position.dy - down.dy;
          if (totalDx.abs() < _dragStartSlop && totalDy.abs() < _dragStartSlop) {
            return;
          }

          // Compare against the other axis's magnitude (`.abs()`), not its
          // raw signed value. Scrolling up (totalDy negative) with even a
          // few px of incidental rightward drift — common when a right
          // thumb pivots at the wrist mid-scroll — used to satisfy
          // `totalDx >= totalDy` trivially (any positive beats any
          // negative), locking the horizontal dismiss axis right at the
          // start of what was actually a vertical scroll.
          if (totalDx >= _dragStartSlop &&
              totalDx >= totalDy.abs() &&
              totalDx > 0) {
            _dragging = true;
            _axis = _DragAxis.horizontal;
          } else if (_atTop &&
              totalDy >= _dragStartSlop &&
              totalDy > totalDx.abs() &&
              totalDy > 0) {
            _dragging = true;
            _axis = _DragAxis.vertical;
          } else {
            return;
          }
        }

        if (_axis == _DragAxis.vertical && event.delta.dy > 0) {
          setState(() => _dragOffset += Offset(0, event.delta.dy));
        } else if (_axis == _DragAxis.horizontal && event.delta.dx > 0) {
          setState(() => _dragOffset += Offset(event.delta.dx, 0));
        }
      },
      onPointerUp: (_) => _onPointerUp(),
      onPointerCancel: (_) {
        _resetGesture();
        if (_dragOffset != Offset.zero) _settleBack();
      },
      child: Transform.translate(
        offset: _dragOffset,
        child: widget.child,
      ),
    );
  }
}
