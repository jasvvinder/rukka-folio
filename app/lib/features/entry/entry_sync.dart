// The save trigger of 05 §7 🔒, kept out of the screen so it is one testable
// call and not a widget detail.
//
// 07 §1 🔒 / 05 §9: a sync cycle never stands in front of an entry save. This
// is void, not a `Future` a caller could await, and it does nothing at all
// when there is no sync seam above the screen — an entry is saved on the
// phone either way, and the outbox is what makes it reach the server. The
// worst case of skipping it is latency (the next foreground, scope switch or
// backstop poll carries the row), never a lost entry.
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../shared/app_scope.dart';
import '../../shared/seams/sync_client.dart';
import '../../shared/sync/engine_sync_client.dart';

/// The sync seam above [context], or null when there is none (a preview, or a
/// screen pumped bare). Reads without registering a dependency: this is an
/// event-handler lookup, not a build-time one, and the save path must never
/// rebuild because sync changed.
SyncClient? syncClientOf(BuildContext context) =>
    context.getInheritedWidgetOfExactType<RkScope>()?.sync;

/// An entry (or its reversal) was just appended — nudge sync (05 §7).
///
/// The engine-backed client has the trigger by name; anything else gets the
/// seam's one verb, which is the same cycle under a different name (the seam
/// deliberately carries no `onEntrySaved`, so no UI fake has to grow one).
void notifyEntrySaved(SyncClient? sync) {
  if (sync == null) return;
  if (sync is EngineSyncClient) {
    sync.onEntrySaved();
    return;
  }
  unawaited(sync.syncNow());
}
