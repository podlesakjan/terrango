# Actionable Task List for UI Responsiveness

This document outlines the refactoring tasks required to address the issues identified in the audit.

---

### Task 1: Optimize Location Updates with a Dedicated Provider

**Priority:** High
**JIRA/GitHub Issue:** `BUG-101: Optimize location updates to prevent global rebuilds`

**Description:**
The current implementation of `_onNewPosition` calls `setState`, triggering a rebuild of the entire `MapScreen`. This is inefficient for frequent location updates.

**Refactoring Instructions:**
1.  Create a new `StateNotifierProvider` to manage the user's current position and H3 index.
2.  Update the `_startLocationTracking` method to update the new provider instead of calling `setState`.
3.  Consume the new provider in widgets that need to react to location changes, such as the `_StatusBar` or for refreshing the hex source, without rebuilding the entire screen.

**Code Snippet (Provider):**
```dart
final currentPositionProvider = StateNotifierProvider<CurrentPositionNotifier, geolocator.Position?>((ref) {
  return CurrentPositionNotifier();
});

class CurrentPositionNotifier extends StateNotifier<geolocator.Position?> {
  CurrentPositionNotifier() : super(null);

  void updatePosition(geolocator.Position newPosition) {
    state = newPosition;
  }
}
```

**Code Snippet (Usage):**
```dart
// In _onNewPosition:
ref.read(currentPositionProvider.notifier).updatePosition(position);

// In a widget that needs the position:
final currentPosition = ref.watch(currentPositionProvider);
```

---

### Task 2: Offload H3 Calculations to a Separate Isolate

**Priority:** High
**JIRA/GitHub Issue:** `BUG-102: Move H3 geometry calculations off the main isolate`

**Description:**
CPU-intensive H3 calculations (`kRing`, `geoToH3`) are blocking the main UI thread, causing the UI to freeze during map interaction.

**Refactoring Instructions:**
1.  Create a helper function that performs the H3 calculations.
2.  In `_syncVisibleHexesFromViewport` and `_toH3IndexString`, wrap the calls to the H3 library in `compute()` or `Isolate.run()` to execute them in a background isolate.
3.  Ensure the results are returned to the main isolate and used to update the relevant state.

**Code Snippet (Isolate Wrapper):**
```dart
// Helper function for isolate
Future<Set<String>> _calculateVisibleIndexes(Map<String, dynamic> params) async {
  final h3 = const H3Factory().load();
  final centerH3Index = params['centerH3Index'] as String;
  final radius = params['radius'] as int;
  return h3.kRing(BigInt.parse(centerH3Index, radix: 16), radius)
      .map((index) => index.toRadixString(16))
      .toSet();
}

// In _syncVisibleHexesFromViewport:
final visibleIndexes = await compute(_calculateVisibleIndexes, {
  'centerH3Index': centerH3Index,
  'radius': radius,
});
```

---

### Task 3: Refactor `_HexContextSheet` to Use `FutureProvider`

**Priority:** Medium
**JIRA/GitHub Issue:** `REFACTOR-201: Simplify hex detail fetching with FutureProvider`

**Description:**
The `_HexContextSheetState` uses manual, imperative logic for fetching and updating hex details, which is complex and error-prone.

**Refactoring Instructions:**
1.  Create a `FutureProvider.family` that takes an H3 index and fetches the corresponding hex details from the `gameApiDataSourceProvider`.
2.  Convert `_HexContextSheet` to a `ConsumerWidget`.
3.  Use `ref.watch` to consume the new provider, which will handle the loading, data, and error states automatically.
4.  To handle real-time updates from the socket, use `ref.listen` on the `gameSocketEventControllerProvider`'s event stream and call `ref.invalidate` on the `FutureProvider` when a relevant event occurs.

**Code Snippet (Provider):**
```dart
final hexDetailProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, h3Index) {
  return ref.watch(gameApiDataSourceProvider).getHexDetail(h3Index);
});
```

**Code Snippet (Widget):**
```dart
class _HexContextSheet extends ConsumerWidget {
  // ... constructor ...

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(hexDetailProvider(hex.h3Index));

    ref.listen(gameSocketEventControllerProvider.select((s) => s.events), (_, eventStream) {
        eventStream.listen((event) {
            if (event['data']?['h3Index'] == hex.h3Index) {
                ref.invalidate(hexDetailProvider(hex.h3Index));
            }
        });
    });

    return detailAsync.when(
      data: (detail) => _buildDetailContent(detail),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('Failed to load: $error'),
    );
  }
  // ...
}
```
