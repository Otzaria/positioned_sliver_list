import "dart:async";
import "dart:math" as math;

import "package:flutter/scheduler.dart";
import "package:flutter/widgets.dart";

import "extent_manager.dart";

/// Animates a [ScrollPosition] to a target offset that may change while the
/// animation runs, for example while the extents of items between the start
/// and the target are being measured.
///
/// A target more than [farDistance] viewports away is first jumped to, so
/// that the animation covers at most about one viewport and never builds the
/// items in between. The animation runs as a [ScrollActivity]: user input
/// (drag, hold, wheel) or another scroll activity cancels it.
class TargetScrollAnimation {
  TargetScrollAnimation._(this.position);

  /// Starts animating [position] towards [target].
  ///
  /// [target] returns the current target in scroll pixels, or null to stop.
  /// It is called once per frame and should be cheap.
  static TargetScrollAnimation start({
    required ScrollPosition position,
    required double? Function() target,
    required Duration duration,
    required Curve curve,
    double farDistance = 2.0,
    double nearDistance = 1.0,
  }) {
    final animation = TargetScrollAnimation._(position);
    animation._start(
      target: target,
      duration: duration,
      curve: curve,
      farDistance: farDistance,
      nearDistance: nearDistance,
    );
    return animation;
  }

  final ScrollPosition position;
  final _completer = Completer<void>();
  _TargetScrollActivity? _activity;
  bool _reachedTarget = false;

  /// Completes when the animation finished or was canceled.
  Future<void> get done => _completer.future;

  /// Whether the animation ran to its end (it was not canceled).
  bool get reachedTarget => _reachedTarget;

  /// Whether the animation is still running.
  bool get isAnimating => !_completer.isCompleted;

  /// Sum of the position changes made by others while animating, such as
  /// scroll offset corrections from layout. A target relative to the start
  /// position should add it.
  double get drift => _drift;
  double _drift = 0.0;

  /// Stops the animation where it is.
  void cancel() {
    final activity = _activity;
    if (activity != null && !activity.isDisposed) {
      activity.stop();
    } else {
      _finish(false);
    }
  }

  void _finish(bool reachedTarget) {
    if (_completer.isCompleted) {
      return;
    }
    _reachedTarget = reachedTarget;
    _activity = null;
    _completer.complete();
  }

  double? _clampedTarget(double? Function() target) {
    final value = target();
    if (value == null || !value.isFinite) {
      return null;
    }
    if (!position.hasContentDimensions) {
      return value;
    }
    return value.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  void _start({
    required double? Function() target,
    required Duration duration,
    required Curve curve,
    required double farDistance,
    required double nearDistance,
  }) {
    final initialTarget = _clampedTarget(target);
    if (initialTarget == null || !position.hasPixels) {
      _finish(false);
      return;
    }
    final delegate = position;
    if (delegate is! ScrollActivityDelegate) {
      position
          .animateTo(initialTarget, duration: duration, curve: curve)
          .whenComplete(() => _finish(true));
      return;
    }
    final viewport = position.hasViewportDimension
        ? position.viewportDimension
        : 0.0;
    final distance = initialTarget - position.pixels;
    if (viewport > 0 && distance.abs() > farDistance * viewport) {
      position.jumpTo(initialTarget - distance.sign * nearDistance * viewport);
    }
    if (duration <= Duration.zero) {
      _finish(true);
      return;
    }
    final activity = _TargetScrollActivity(
      delegate as ScrollActivityDelegate,
      position: position,
      vsync: position.context.vsync,
      target: () => _clampedTarget(target),
      duration: duration,
      curve: curve,
      direction: distance.sign,
      onDone: _finish,
      onDrift: (value) => _drift += value,
    );
    _activity = activity;
    position.beginActivity(activity);
  }
}

class _TargetScrollActivity extends ScrollActivity {
  _TargetScrollActivity(
    super.delegate, {
    required this.position,
    required TickerProvider vsync,
    required this.target,
    required this.duration,
    required this.curve,
    required this.direction,
    required this.onDone,
    required this.onDrift,
  }) {
    _ticker = vsync.createTicker(_tick)..start();
  }

  final ScrollPosition position;
  final double? Function() target;
  final Duration duration;
  final Curve curve;
  final double direction;
  final void Function(bool reachedTarget) onDone;
  final ValueSetter<double> onDrift;
  double? _lastSet;

  late final Ticker _ticker;
  double _lastProgress = 0.0;
  Duration _lastElapsed = Duration.zero;
  double _velocity = 0.0;
  bool _reachedTarget = false;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  bool _reported = false;

  /// Stops at the current position. Switching to idle is deferred because
  /// this may run while the scrollable is being deactivated.
  void stop() {
    _ticker.stop();
    _velocity = 0.0;
    _report();
    scheduleMicrotask(() {
      if (!_disposed) {
        delegate.goIdle();
      }
    });
  }

  void _report() {
    if (!_reported) {
      _reported = true;
      onDone(_reachedTarget);
    }
  }

  void _tick(Duration elapsed) {
    final lastSet = _lastSet;
    if (lastSet != null && position.pixels != lastSet) {
      onDrift(position.pixels - lastSet);
    }
    final f = target();
    if (f == null) {
      delegate.goIdle();
      return;
    }
    final t = math.min(1.0, elapsed.inMicroseconds / duration.inMicroseconds);
    final progress = curve.transform(t);
    final current = position.pixels;
    double next;
    if (t >= 1.0 || 1.0 - _lastProgress < 1e-9) {
      next = f;
    } else {
      // Close the remaining gap in proportion to the remaining curve, so a
      // target that moves (extents getting measured) is followed smoothly.
      next = f - (f - current) * (1.0 - progress) / (1.0 - _lastProgress);
      if ((next - current) * direction < 0) {
        next = current;
      }
    }
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    if (dt > 0) {
      _velocity = (next - current) / dt;
    }
    _lastElapsed = elapsed;
    _lastProgress = progress;
    delegate.setPixels(next);
    _lastSet = position.pixels;
    if (t >= 1.0) {
      _reachedTarget = true;
      _velocity = 0.0;
      delegate.goBallistic(0.0);
    }
  }

  @override
  bool get shouldIgnorePointer => true;

  @override
  bool get isScrolling => true;

  @override
  double get velocity => _velocity;

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _report();
    super.dispose();
  }
}

/// A jump or animation started by a list controller.
abstract interface class PositioningOperation {
  /// Completes when the operation finished or was canceled.
  Future<void> get done;

  bool get isAnimating;

  void cancel();
}

/// Animates to an item using [ExtentManager.getOffsetToReveal] alignment.
class AnimateToItem implements PositioningOperation {
  AnimateToItem({
    required this.extentManager,
    required Object revealOwner,
    required this.index,
    required this.alignment,
    required this.rect,
    required this.position,
    required this.duration,
    required this.curve,
  }) : _revealOwner = revealOwner;

  final Object _revealOwner;
  VoidCallback? onDisposed;

  final ExtentManager extentManager;
  final ValueGetter<int?> index;
  final double alignment;
  final Rect? rect;
  final ScrollPosition position;
  final Duration Function(double estimatedDistance) duration;
  final Curve Function(double estimatedDistance) curve;

  TargetScrollAnimation? _animation;
  final _completer = Completer<void>();

  @override
  Future<void> get done => _completer.future;

  bool get _isCurrent => identical(_revealOwner, extentManager.revealOwner);

  double? _target() {
    final index = this.index();
    if (index == null || !_isCurrent) {
      return null;
    }
    return extentManager.getOffsetToReveal(
      index,
      alignment,
      rect: rect,
      estimationOnly: true,
    );
  }

  void animate() {
    final start = _target();
    if (start == null || !start.isFinite) {
      cancel();
      return;
    }
    final estimatedDistance = (start - position.pixels).abs();
    final animation = TargetScrollAnimation.start(
      position: position,
      target: _target,
      duration: duration(estimatedDistance),
      curve: curve(estimatedDistance),
    );
    _animation = animation;
    animation.done.then((_) {
      if (animation.reachedTarget) {
        _settle();
      } else {
        extentManager.cancelReveal(_revealOwner);
      }
      _complete();
    });
  }

  // Lands exactly once the target item has been laid out and measured.
  void _settle() {
    final index = this.index();
    if (index == null || !_isCurrent || !position.hasPixels) {
      return;
    }
    final offset = extentManager.getOffsetToReveal(
      index,
      alignment,
      rect: rect,
      estimationOnly: false,
      owner: _revealOwner,
    );
    if (offset.isFinite && (offset - position.pixels).abs() > 1e-3) {
      position.jumpTo(offset);
    }
  }

  @override
  void cancel() {
    extentManager.cancelReveal(_revealOwner);
    final animation = _animation;
    if (animation != null && animation.isAnimating) {
      animation.cancel();
    } else {
      _complete();
    }
  }

  void _complete() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
    onDisposed?.call();
    onDisposed = null;
  }

  @override
  bool get isAnimating => _animation?.isAnimating ?? false;
}
