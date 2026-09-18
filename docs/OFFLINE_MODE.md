# Offline Mode with Sync Queue

## Overview

Nova phone handhelds now support offline operation. When the device loses internet connectivity, all NATS publishes are automatically queued locally and synced when connectivity is restored.

**Key Features:**
- ✅ Works completely offline (no network required)
- ✅ Automatic sync queue (localStorage-backed)
- ✅ Exponential backoff retries (1s → 5s → 15s)
- ✅ Conflict-free deduplication (item IDs prevent duplicates)
- ✅ User control (manual retry, clear failed items)
- ✅ Visual status bar (shows offline/syncing/failed states)
- ✅ Survives page reload (localStorage persists)

---

## Architecture

### 1. Sync Queue (JavaScript Module)

**File**: `assets/js/sync_queue.js`

Manages a queue of NATS publishes that couldn't reach the server:

```javascript
// Enqueue when offline
const itemId = SyncQueue.enqueue(subject, payload);

// Get status for UI
const status = SyncQueue.getStatus();
// {
//   isOnline: boolean,
//   synced: number,
//   syncing: number,
//   queued: number,
//   failed: number,
//   total: number,
//   lastSync: timestamp,
//   nextRetry: timestamp
// }

// Sync all pending items
const results = await SyncQueue.syncAll(publishFn);
// { synced: 2, failed: 1, queued: 3 }
```

**Queue Item Structure:**
```javascript
{
  id: "1694968842123-abc123def",      // Unique ID (prevents duplicates)
  subject: "events.timer.session_completed",
  payload: "{...}",                   // Stringified JSON
  timestamp: 1694968842123,            // When queued
  retries: 0,                          // Retry count
  lastError: null,                     // Last error message
  status: "queued|syncing|synced|failed",
  lastRetry: timestamp,                // Last retry time
  metadata: {...}                      // Custom metadata
}
```

**Retry Strategy:**
- Queued items: Retry immediately if online
- Failed items: Exponential backoff (1s, 5s, 15s)
- Max retries: 3
- Manual retry available via UI button

### 2. Sync Status Component (Phoenix Component)

**File**: `lib/.../sync_status.ex`

**Usage in any handheld:**
```elixir
defmodule MyHandheldLive do
  def mount(_params, _session, socket) do
    {:ok, _} = PubSub.subscribe(..., "sync-queue")
    
    {:ok, socket
      |> assign(sync_status: %{}, is_online: true)
      |> fetch_initial_sync_status()}
  end

  def handle_info({:sync_status_update, status}, socket) do
    {:noreply, assign(socket, sync_status: status)}
  end
end
```

**Renders:**
- 🌐 Online: Shows "✓ X of Y synced"
- 📡 Offline: Shows "⚠️ Offline" + queue count
- ⟳ Syncing: Shows "Syncing..." + item count
- ✕ Failed: Shows error count + Retry button

### 3. Offline Detection Hook

**File**: `assets/js/sync_queue.js` - `OfflineDetectionHook`

Watches browser `online`/`offline` events and triggers sync attempts:

```javascript
export const OfflineDetectionHook = {
  mounted() {
    window.addEventListener('online', () => {
      this.pushEvent('sync-queue-online', {});
    });
    window.addEventListener('offline', () => {
      this.pushEvent('sync-queue-offline', {});
    });
  }
};
```

### 4. Sync Manager Hook

**File**: `assets/js/sync_queue.js` - `SyncManagerHook`

Periodically checks for items to sync (every 5 seconds if queued and online):

```javascript
export const SyncManagerHook = {
  mounted() {
    this.syncInterval = setInterval(() => {
      if (status.queued > 0 && status.isOnline) {
        this.pushEvent('sync-queue-retry', {});
      }
    }, 5000);
  }
};
```

---

## Integration Checklist

### For Existing Handhelds

To add offline support to a handheld:

1. **Import sync modules:**
   ```elixir
   import BotArmyDashboardLiveview.SyncStatus
   ```

2. **Add to mount:**
   ```elixir
   |> assign(sync_status: %{}, is_online: true)
   ```

3. **Add handlers in mount:**
   ```elixir
   phx-hook="OfflineDetectionHook"
   phx-hook="SyncManagerHook"
   ```

4. **Add handlers in LiveView:**
   ```elixir
   def handle_info(:sync_queue_online, socket) do
     {:noreply, assign(socket, is_online: true)}
   end

   def handle_info(:sync_queue_offline, socket) do
     {:noreply, assign(socket, is_online: false)}
   end

   def handle_event("sync-queue-retry", _params, socket) do
     # Trigger sync via JS interop
     {:noreply, socket}
   end
   ```

5. **Replace direct NATS publishes:**
   ```elixir
   # OLD:
   Gnat.pub(:nats_connection, subject, payload)

   # NEW (in JavaScript):
   const queue = createQueuedPublisher(async (subject, payload) => {
     return await Gnat.pub(:nats_connection, subject, payload);
   });
   await queue(subject, payload);
   ```

6. **Render sync status:**
   ```elixir
   <.sync_status status={@sync_status} is_online={@is_online} />
   ```

---

## Data Flow

### Going Offline (User loses internet)
```
1. User performs action (e.g., "complete task")
2. Handheld attempts: Gnat.pub(...) → fails
3. Caught by queued publisher wrapper
4. Item added to SyncQueue (localStorage)
5. UI shows: "⚠️ Offline • 1 queued"
6. User continues working offline
```

### Coming Online (Connectivity restored)
```
1. Browser detects online event
2. OfflineDetectionHook → pushes sync-queue-online
3. SyncManagerHook starts polling every 5s
4. On next interval: SyncQueue.getNextToSync()
5. SyncQueue.syncAll(publishFn) attempts all items
6. Successfully published: marked as synced
7. Failed: marked as failed, retried with backoff
8. UI updates: "✓ X of Y synced" or "✕ 2 failed"
```

### Manual Retry (User clicks retry)
```
1. User sees: "✕ 2 failed to sync" + Retry button
2. Clicks Retry
3. SyncQueue.clearFailed() removes old failures (optional)
4. SyncQueue.syncAll() attempts remaining items
5. UI updates with result
```

---

## LocalStorage Schema

```javascript
// Key: "nova_sync_queue"
// Value: [
//   {
//     id: "1694968842123-abc123def",
//     subject: "events.timer.session_completed",
//     payload: "{...}",
//     timestamp: 1694968842123,
//     retries: 0,
//     lastError: null,
//     status: "synced",
//     syncedAt: 1694968850000
//   },
//   ...
// ]

// Key: "nova_sync_status"
// Value: {
//   isOnline: true,
//   synced: 2,
//   syncing: 0,
//   queued: 0,
//   failed: 0,
//   total: 2,
//   lastSync: 1694968850000,
//   nextRetry: null
// }
```

---

## Testing

### Manual Testing

**Scenario 1: Queue while offline**
1. Open DevTools Network tab → Throttle offline
2. Complete an action in handheld
3. See action queued (UI shows "⚠️ Offline • 1 queued")
4. Open DevTools Console: `SyncQueue.getQueue()` → verify item exists
5. Set online: Throttle back to normal
6. See item syncs ("✓ 1 of 1 synced")

**Scenario 2: Retry on failure**
1. Go offline, complete 2 actions
2. Simulate network error (block specific subject)
3. Go online, see "✕ 2 failed"
4. Click Retry button
5. See items retry with backoff

**Scenario 3: Persist across reload**
1. Go offline, complete actions
2. See queue in localStorage
3. Reload page (still offline)
4. Queue and sync status restored from localStorage
5. Go online, see automatic sync

### E2E Tests (Future)

```javascript
test('offline queue persists across reload', async ({ page }) => {
  await page.goto('/timer-phone');
  
  // Simulate offline
  await page.context().setOffline(true);
  
  // Complete action
  await page.click('[data-action="complete-task"]');
  
  // Verify queued
  expect(await page.textContent('.sync-status')).toContain('Offline');
  
  // Reload
  await page.reload();
  
  // Queue restored
  expect(await page.textContent('.sync-status')).toContain('Offline');
  
  // Go online
  await page.context().setOffline(false);
  
  // Wait for sync
  await page.waitForFunction(
    () => document.body.textContent.includes('synced'),
    { timeout: 5000 }
  );
});
```

---

## Limitations & Future Improvements

### Current Limitations
- Queue stored in localStorage (5-50MB limit per domain)
- No encryption (localStorage is readable by any script on domain)
- No conflict resolution (last-write-wins if duplicate IDs)
- Manual cleanup required (failed items don't auto-delete)

### Phase 7 Enhancements
- Encrypt queue with AES-256
- IndexedDB backend for larger storage
- Conflict resolution via server timestamps
- Auto-cleanup of old synced items (7+ days)
- Sync stats dashboard (chart of queue over time)
- Bandwidth optimization (batch publishes)
- Bidirectional sync (receive updates while offline)

---

## API Reference

### SyncQueue Methods

| Method | Signature | Returns | Purpose |
|--------|-----------|---------|---------|
| `enqueue` | `(subject, payload, metadata?)` | `itemId` | Add to queue |
| `getQueue` | `()` | `Item[]` | Get all items |
| `getStatus` | `()` | `Status` | Get status snapshot |
| `syncAll` | `(publishFn)` | `Promise<Results>` | Sync pending items |
| `markSynced` | `(itemId)` | `void` | Mark item complete |
| `markFailed` | `(itemId, error)` | `void` | Mark item failed |
| `clearSynced` | `()` | `void` | Remove synced items |
| `clearFailed` | `()` | `void` | Remove failed items |
| `reset` | `()` | `boolean` | Clear entire queue |
| `getLastSyncTime` | `()` | `timestamp?` | Last successful sync |
| `getNextRetryTime` | `()` | `timestamp?` | Scheduled next retry |

---

## Status Bar UI States

```
🌐 Online, no queue:
  (hidden or minimal)

⚠️ Offline:
  "⚠️ Offline • 3 queued"

⟳ Syncing:
  "⟳ Syncing... (2)"

✓ Synced:
  "✓ 5 of 5 synced"

✕ Failed:
  "✕ 2 failed to sync [Retry]"
```

---

**Status**: Ready for integration (Phase 6)  
**Files**: 2 (sync_queue.js, sync_status.ex)  
**LOC**: ~400  
**Test Coverage**: E2E tests ready (Phase 7)
