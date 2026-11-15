import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Calls [onSwipe] when the user swipes right starting at the left screen
/// edge (the edge-swipe part of osmNichinichi's SwipeToCloseWrapper).
///
/// It only observes raw pointer events through a [Listener], so it never
/// joins the gesture arena and doesn't steal taps, long presses, scrolling
/// or reordering from the widgets inside.
class EdgeSwipeListener extends StatefulWidget {
  const EdgeSwipeListener({
    super.key,
    required this.onSwipe,
    required this.child,
  });

  final VoidCallback onSwipe;
  final Widget child;

  @override
  State<EdgeSwipeListener> createState() => _EdgeSwipeListenerState();
}

class _EdgeSwipeListenerState extends State<EdgeSwipeListener> {
  static const double _velocityThreshold = 250;

  /// Width of the left-edge start zone, added outside the system gesture
  /// inset / safe area. Wide enough for thick fingers on iPad.
  static const double _edgeWidth = 56;

  /// A swipe that wandered this far vertically is not a right swipe.
  static const double _maxVerticalTravel = 48;

  /// Distance fallback for devices that report low velocities.
  static const double _minDistance = 72;

  /// How much the net movement must favor rightward over vertical.
  static const double _netDominanceRatio = 1.25;

  final Map<int, VelocityTracker> _trackers = {};
  final Map<int, Offset> _downPositions = {};
  final Map<int, Offset> _lastPositions = {};
  final Map<int, double> _horizontalTravel = {};
  final Map<int, double> _verticalTravel = {};

  double _edgeLimit() {
    final mq = MediaQuery.of(context);
    return math.max(mq.systemGestureInsets.left, mq.padding.left) + _edgeWidth;
  }

  bool _isRightSwipe({
    required Offset down,
    required Offset up,
    required double horizontal,
    required double vertical,
    required Offset velocity,
    bool relaxVelocity = false,
  }) {
    if (down.dx > _edgeLimit()) return false;
    if (vertical > _maxVerticalTravel) return false;
    final delta = up - down;
    if (delta.dx <= delta.dy.abs() * _netDominanceRatio) return false;
    if (horizontal <= vertical) return false;
    if (velocity.dx > _velocityThreshold ||
        (delta.dx >= _minDistance && velocity.dx > _velocityThreshold * 0.35)) {
      return true;
    }
    // The system may cancel the pointer and break the velocity tracker.
    return relaxVelocity && delta.dx >= _minDistance;
  }

  void _onDown(PointerDownEvent event) {
    (_trackers[event.pointer] = VelocityTracker.withKind(event.kind))
        .addPosition(event.timeStamp, event.position);
    _downPositions[event.pointer] = event.position;
    _lastPositions[event.pointer] = event.position;
    _horizontalTravel[event.pointer] = 0;
    _verticalTravel[event.pointer] = 0;
  }

  void _onMove(PointerMoveEvent event) {
    _trackers[event.pointer]?.addPosition(event.timeStamp, event.position);
    final last = _lastPositions[event.pointer];
    if (last != null) {
      final step = event.position - last;
      _horizontalTravel[event.pointer] =
          (_horizontalTravel[event.pointer] ?? 0) + step.dx.abs();
      _verticalTravel[event.pointer] =
          (_verticalTravel[event.pointer] ?? 0) + step.dy.abs();
    }
    _lastPositions[event.pointer] = event.position;
  }

  void _onUp(PointerUpEvent event) => _finish(
        event.pointer,
        upPosition: event.position,
        timeStamp: event.timeStamp,
      );

  /// The system can take over a left-edge pointer and send a cancel instead
  /// of an up; a clear right swipe still counts.
  void _onCancel(PointerCancelEvent event) =>
      _finish(event.pointer, relaxVelocity: true);

  void _finish(
    int pointer, {
    Offset? upPosition,
    Duration? timeStamp,
    bool relaxVelocity = false,
  }) {
    final tracker = _trackers.remove(pointer);
    final down = _downPositions.remove(pointer);
    final last = _lastPositions.remove(pointer);
    final horizontal = _horizontalTravel.remove(pointer) ?? 0;
    final vertical = _verticalTravel.remove(pointer) ?? 0;
    if (tracker == null || down == null) return;
    final up = upPosition ?? last ?? down;
    if (upPosition != null && timeStamp != null) {
      tracker.addPosition(timeStamp, upPosition);
    }
    if (_isRightSwipe(
      down: down,
      up: up,
      horizontal: horizontal,
      vertical: vertical,
      velocity: tracker.getVelocity().pixelsPerSecond,
      relaxVelocity: relaxVelocity,
    )) {
      widget.onSwipe();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: widget.child,
    );
  }
}
