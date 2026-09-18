// Local storage utilities for phone handhelds
// Persists user preferences across sessions

const STORAGE_KEY = 'nova_phone_prefs';
const DEFAULTS = {
  lastRoute: '/timer-phone',
  lastVisited: {},
  favorites: [],
  theme: 'dark',
  navLayout: 'bottom', // or 'hidden' when implemented
  sessionHistory: [],
  sessionMaxItems: 50
};

export const PhoneStorage = {
  // Get all preferences
  getPrefs() {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      return stored ? JSON.parse(stored) : { ...DEFAULTS };
    } catch (e) {
      console.warn('PhoneStorage: Failed to read prefs', e);
      return { ...DEFAULTS };
    }
  },

  // Save all preferences
  setPrefs(prefs) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(prefs));
      return true;
    } catch (e) {
      console.warn('PhoneStorage: Failed to save prefs', e);
      return false;
    }
  },

  // Record a handheld visit with metadata
  recordVisit(route, metadata = {}) {
    const prefs = this.getPrefs();
    prefs.lastRoute = route;
    prefs.lastVisited[route] = {
      timestamp: Date.now(),
      ...metadata
    };
    this.setPrefs(prefs);
  },

  // Add to session history (work sessions, energy logs, etc)
  addToSessionHistory(type, data) {
    const prefs = this.getPrefs();
    if (!prefs.sessionHistory) prefs.sessionHistory = [];

    prefs.sessionHistory.unshift({
      type, // 'work', 'habit', 'mood', 'reflection', etc
      data,
      timestamp: Date.now()
    });

    // Keep only last N items
    if (prefs.sessionHistory.length > prefs.sessionMaxItems) {
      prefs.sessionHistory = prefs.sessionHistory.slice(0, prefs.sessionMaxItems);
    }

    this.setPrefs(prefs);
  },

  // Get session history (optional type filter)
  getSessionHistory(type = null) {
    const prefs = this.getPrefs();
    if (!prefs.sessionHistory) return [];

    if (type) {
      return prefs.sessionHistory.filter(s => s.type === type);
    }
    return prefs.sessionHistory;
  },

  // Toggle favorite for a route
  toggleFavorite(route) {
    const prefs = this.getPrefs();
    if (!prefs.favorites) prefs.favorites = [];

    const idx = prefs.favorites.indexOf(route);
    if (idx > -1) {
      prefs.favorites.splice(idx, 1);
    } else {
      prefs.favorites.push(route);
    }

    this.setPrefs(prefs);
    return !prefs.favorites.includes(route);
  },

  // Check if route is favorited
  isFavorite(route) {
    const prefs = this.getPrefs();
    return prefs.favorites && prefs.favorites.includes(route);
  },

  // Get visit count for a route
  getVisitCount(route) {
    const prefs = this.getPrefs();
    if (!prefs.lastVisited || !prefs.lastVisited[route]) return 0;

    // Count from session history as backup
    const count = (prefs.sessionHistory || []).filter(s => s.data?.route === route).length;
    return Math.max(1, count);
  },

  // Get most recently visited routes
  getMostRecentRoutes(limit = 3) {
    const prefs = this.getPrefs();
    if (!prefs.lastVisited) return [];

    return Object.entries(prefs.lastVisited)
      .sort(([, a], [, b]) => b.timestamp - a.timestamp)
      .slice(0, limit)
      .map(([route]) => route);
  },

  // Clear old session history (older than days)
  clearOldSessions(days = 30) {
    const prefs = this.getPrefs();
    const cutoffTime = Date.now() - (days * 24 * 60 * 60 * 1000);

    if (prefs.sessionHistory) {
      prefs.sessionHistory = prefs.sessionHistory.filter(s => s.timestamp > cutoffTime);
    }

    this.setPrefs(prefs);
  },

  // Get stats for a session type
  getSessionStats(type) {
    const sessions = this.getSessionHistory(type);
    if (sessions.length === 0) {
      return { count: 0, firstSession: null, lastSession: null, totalTime: 0 };
    }

    return {
      count: sessions.length,
      firstSession: new Date(sessions[sessions.length - 1].timestamp),
      lastSession: new Date(sessions[0].timestamp),
      // For work sessions: sum durations if available
      totalTime: sessions.reduce((sum, s) => sum + (s.data?.duration || 0), 0)
    };
  },

  // Clear all preferences (reset)
  reset() {
    try {
      localStorage.removeItem(STORAGE_KEY);
      return true;
    } catch (e) {
      console.warn('PhoneStorage: Failed to reset', e);
      return false;
    }
  }
};

// Hook for automatic session recording
export const SessionRecorderHook = {
  mounted() {
    const route = window.location.pathname;
    PhoneStorage.recordVisit(route, {
      userAgent: navigator.userAgent.substring(0, 50)
    });
  }
};
