/// A drop-in replacement for the `scrollable_positioned_list` API, built on
/// [SuperSliverList].
library;

export "src/compat/scrollable_positioned_list.dart";
export "src/header_anchor.dart" show HeaderAnchorHandle;
export "src/item_position.dart";
export "src/stick_target.dart" show StickTarget;
export "src/super_sliver_list.dart"
    show
        AnimationHandle,
        ListController,
        OverscrollToTarget,
        SuperSliverList,
        TargetRectResolver;
