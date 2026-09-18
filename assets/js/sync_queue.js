// Offline sync queue for Nova phone handhelds
// Queues NATS publishes when offline, syncs when online

const QUEUE_KEY = 'nova_sync_queue';
const STATUS_KEY = 'nova_sync_status';
const MAX_RETRIES = 3;
const RETRY_DELAYS = [1000, 5000, 15000]; // ms: 1s, 5s, 15s

export const SyncQueue = {
  // Get entire queue
  getQueue() {
    try {
      const stored = localStorage.getItem(QUEUE_KEY);
      return stored ? JSON.parse(stored) : [];
    } catch (e) {
      console.warn('SyncQueue: Failed to read queue', e);
      return [];
    }
  },

  // Save queue to storage
  setQueue(queue) {
    try {
      localStorage.setItem(QUEUE_KEY, JSON.stringify(queue));
      return true;
    } catch (e) {
      console.warn('SyncQueue: Failed to save queue', e);
      return false;
    }
  },

  // Add item to queue
  enqueue(subject, payload, metadata = {}) {
    const queue = this.getQueue();
    const item = {
      id: `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      subject,
      payload: typeof payload === 'string' ? payload : JSON.stringify(payload),
      timestamp: Date.now(),
      retries: 0,
      lastError: null,
      metadata,
      status: 'queued'
    };

    queue.push(item);
    this.setQueue(queue);
    this.updateStatus();

    return item.id;
  },

  // Mark item as synced
  markSynced(itemId) {
    const queue = this.getQueue();
    const item = queue.find(i => i.id === itemId);
    if (item) {
      item.status = 'synced';
      item.syncedAt = Date.now();
      this.setQueue(queue);
    }
  },

  // Mark item as failed
  markFailed(itemId, error) {
    const queue = this.getQueue();
    const item = queue.find(i => i.id === itemId);
    if (item) {
      item.status = 'failed';
      item.lastError = error;
      item.retries += 1;
      this.setQueue(queue);
    }
  },

  // Get next item to sync
  getNextToSync() {
    const queue = this.getQueue();
    return queue.find(item => {
      if (item.status === 'synced' || item.status === 'syncing') return false;
      if (item.retries >= MAX_RETRIES) return false;

      // Check if enough time has passed for retry
      const delayIndex = Math.min(item.retries, RETRY_DELAYS.length - 1);
      const delay = RETRY_DELAYS[delayIndex];
      const nextRetryTime = item.lastRetry ? item.lastRetry + delay : 0;

      return Date.now() >= nextRetryTime;
    });
  },

  // Attempt to sync all pending items
  async syncAll(publishFn) {
    if (!navigator.onLine) {
      console.log('SyncQueue: Offline, skipping sync');
      return { synced: 0, failed: 0, queued: this.getQueue().length };
    }

    const results = { synced: 0, failed: 0, queued: 0 };
    let item;

    while ((item = this.getNextToSync())) {
      item.status = 'syncing';
      this.setQueue(this.getQueue());

      try {
        await publishFn(item.subject, item.payload);
        this.markSynced(item.id);
        results.synced += 1;
      } catch (error) {
        item.lastRetry = Date.now();
        this.markFailed(item.id, error.message);
        results.failed += 1;

        // Stop on error to prevent flooding
        if (item.retries >= MAX_RETRIES) {
          console.warn(`SyncQueue: Item ${item.id} failed after ${MAX_RETRIES} retries`, error);
        }
        break;
      }
    }

    results.queued = this.getQueue().filter(i => i.status !== 'synced').length;
    this.updateStatus();

    return results;
  },

  // Get status for UI
  getStatus() {
    try {
      const stored = localStorage.getItem(STATUS_KEY);
      return stored ? JSON.parse(stored) : this.computeStatus();
    } catch (e) {
      return this.computeStatus();
    }
  },

  // Compute current status
  computeStatus() {
    const queue = this.getQueue();
    const synced = queue.filter(i => i.status === 'synced').length;
    const syncing = queue.filter(i => i.status === 'syncing').length;
    const queued = queue.filter(i => i.status === 'queued').length;
    const failed = queue.filter(i => i.status === 'failed').length;

    const status = {
      isOnline: navigator.onLine,
      synced,
      syncing,
      queued,
      failed,
      total: queue.length,
      lastSync: this.getLastSyncTime(),
      nextRetry: this.getNextRetryTime()
    };

    this.updateStatus(status);
    return status;
  },

  // Update status in storage
  updateStatus(status) {
    if (!status) status = this.computeStatus();
    try {
      localStorage.setItem(STATUS_KEY, JSON.stringify(status));
    } catch (e) {
      console.warn('SyncQueue: Failed to update status', e);
    }
  },

  // Get last sync time
  getLastSyncTime() {
    const queue = this.getQueue();
    const lastSynced = queue.filter(i => i.syncedAt).sort((a, b) => b.syncedAt - a.syncedAt)[0];
    return lastSynced ? lastSynced.syncedAt : null;
  },

  // Get next scheduled retry time
  getNextRetryTime() {
    const queue = this.getQueue();
    const pending = queue.filter(i => i.status === 'queued' || i.status === 'failed');

    if (pending.length === 0) return null;

    const nextItem = pending.sort((a, b) => {
      const aDelay = RETRY_DELAYS[Math.min(a.retries, RETRY_DELAYS.length - 1)] || 0;
      const bDelay = RETRY_DELAYS[Math.min(b.retries, RETRY_DELAYS.length - 1)] || 0;
      return (a.lastRetry || 0) + aDelay - ((b.lastRetry || 0) + bDelay);
    })[0];

    if (!nextItem) return null;

    const delayIndex = Math.min(nextItem.retries, RETRY_DELAYS.length - 1);
    const delay = RETRY_DELAYS[delayIndex];
    return (nextItem.lastRetry || Date.now()) + delay;
  },

  // Clear synced items (cleanup)
  clearSynced() {
    const queue = this.getQueue().filter(i => i.status !== 'synced');
    this.setQueue(queue);
    this.updateStatus();
  },

  // Clear failed items with user confirmation
  clearFailed() {
    const queue = this.getQueue().filter(i => i.status !== 'failed');
    this.setQueue(queue);
    this.updateStatus();
  },

  // Reset entire queue (dangerous)
  reset() {
    try {
      localStorage.removeItem(QUEUE_KEY);
      localStorage.removeItem(STATUS_KEY);
      return true;
    } catch (e) {
      console.warn('SyncQueue: Failed to reset', e);
      return false;
    }
  }
};

// Hook for offline/online detection
export const OfflineDetectionHook = {
  mounted() {
    this.handleOnline = () => {
      console.log('SyncQueue: Online detected');
      this.pushEvent('sync-queue-online', {});
    };

    this.handleOffline = () => {
      console.log('SyncQueue: Offline detected');
      this.pushEvent('sync-queue-offline', {});
    };

    window.addEventListener('online', this.handleOnline);
    window.addEventListener('offline', this.handleOffline);

    // Initial status
    this.pushEvent('sync-status-update', SyncQueue.getStatus());
  },

  destroyed() {
    window.removeEventListener('online', this.handleOnline);
    window.removeEventListener('offline', this.handleOffline);
  }
};

// Periodically check for items to sync
export const SyncManagerHook = {
  mounted() {
    this.syncInterval = setInterval(() => {
      const status = SyncQueue.getStatus();
      if (status.queued > 0 && status.isOnline) {
        this.pushEvent('sync-queue-retry', {});
      }
    }, 5000); // Check every 5 seconds
  },

  destroyed() {
    if (this.syncInterval) clearInterval(this.syncInterval);
  }
};

// Wrap NATS publish to use queue
export const createQueuedPublisher = (natsPublisher) => {
  return async (subject, payload) => {
    try {
      if (navigator.onLine) {
        await natsPublisher(subject, payload);
        return { success: true, queued: false };
      } else {
        const itemId = SyncQueue.enqueue(subject, payload);
        return { success: true, queued: true, itemId };
      }
    } catch (error) {
      // Network error while online — queue it
      const itemId = SyncQueue.enqueue(subject, payload, { error: error.message });
      return { success: true, queued: true, itemId };
    }
  };
};
