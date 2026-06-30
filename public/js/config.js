/*
 * DUOPAY runtime configuration.
 *
 * The same frontend is shipped two ways:
 *   1. Served by the Node/Express backend as a web app  -> talks to a same-origin "/api".
 *   2. Bundled into a native Android/iOS app via Capacitor -> there is no backend on the
 *      device, so it must talk to an absolute backend URL over HTTPS.
 *
 * resolveApiBase() picks the right base URL at runtime. A user can override the backend
 * from Settings ("Server URL"), which is stored in localStorage — this is what lets the
 * mobile app point at any backend without being rebuilt.
 */
(function (global) {
  'use strict';

  // Default backend used by the mobile app when the user has not set a custom Server URL.
  // Change this to your production domain.
  var DEFAULT_SERVER_URL = 'https://moukas.tech';

  function isNativePlatform() {
    return !!(global.Capacitor &&
      typeof global.Capacitor.isNativePlatform === 'function' &&
      global.Capacitor.isNativePlatform());
  }

  // file://, capacitor://, ionic:// — loaded from local bundle, not an HTTP server.
  function isLocalBundle() {
    var p = global.location.protocol;
    return p === 'file:' || p === 'capacitor:' || p === 'ionic:';
  }

  function trimTrailingSlash(url) {
    return String(url || '').replace(/\/+$/, '');
  }

  // Returns the configured Server URL (without trailing slash), or '' if none/web default.
  function getServerUrl() {
    var saved = trimTrailingSlash(global.localStorage.getItem('server_url') || '');
    if (saved) return saved;
    if (isNativePlatform() || isLocalBundle()) return trimTrailingSlash(DEFAULT_SERVER_URL);
    return '';
  }

  // Resolves the API base. Web (same-origin) -> '/api'. Native/custom -> 'https://host/api'.
  function resolveApiBase() {
    var server = getServerUrl();
    return server ? server + '/api' : '/api';
  }

  global.DUOPAY_CONFIG = {
    DEFAULT_SERVER_URL: DEFAULT_SERVER_URL,
    isNativePlatform: isNativePlatform,
    getServerUrl: getServerUrl,
    resolveApiBase: resolveApiBase
  };
})(window);
