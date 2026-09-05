import "package:flutter/foundation.dart";

/// A temporary layout constraint for a mounted header in a vertical list.
///
/// The caller controls its lifetime. Cancel when the related size animations
/// finish, on new scroll input, or before explicit navigation. Cancellation is
/// idempotent and cannot cancel a replacement anchor.
class HeaderAnchorHandle {
  @internal
  HeaderAnchorHandle(this._onCancel);

  VoidCallback? _onCancel;
  bool get isActive => _onCancel != null;

  void cancel() {
    final callback = _onCancel;
    _onCancel = null;
    callback?.call();
  }
}
