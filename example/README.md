# positioned_sliver_list examples

- `lib/main.dart`: the `SuperSliverList` demo app (item list and long document
  with sticky headers, jumping and animating to items, extent precalculation).
- `lib/positioned_list_example.dart`: the `scrollable_positioned_list`
  compatible API on 20,000 paragraphs, with a `Scrollbar` on the list's
  `ScrollController`, `jumpTo`, `scrollTo` and an `ItemPositionsListener`.

```sh
flutter run                                    # demo app
flutter run -t lib/positioned_list_example.dart  # compatibility API
```
