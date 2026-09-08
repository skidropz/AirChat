/*
 * airchat-bridge.js — the only file in the shared web bundle that knows about iOS.
 *
 * Loaded before app.js. In a normal browser, or inside the Android WebView, every
 * symbol it defines stays undefined, so app.js keeps its original behaviour.
 *
 * Two things happen when (and only when) the page is running inside AirChat.app on
 * iOS:
 *
 *  1. `window.AndroidInterface` is recreated on top of WKScriptMessageHandlerWithReply.
 *     app.js was written against Android's synchronous JS interface
 *     (getBatteryLevel() / updateSystemUiTheme()) and WKWebView has no synchronous
 *     bridge, so battery reads come from a cache that the native side refreshes.
 *     That keeps one code path for both hosts instead of forking the bundle.
 *
 *  2. `window.AirChatNative` is the raw transport (postMessage → Promise) that app.js
 *     uses for mic recording, photo picking and haptics — the three things WKWebView
 *     will not do for a plain http:// origin.
 */
(function () {
    'use strict';

    var handlers = window.webkit && window.webkit.messageHandlers;
    if (!handlers || !handlers.airchat) {
        // Not the iOS host app: nothing to install.
        return;
    }

    function call(payload) {
        try {
            var result = handlers.airchat.postMessage(payload);
            if (result && typeof result.then === 'function') {
                return result.catch(function () { return null; });
            }
            return Promise.resolve(result || null);
        } catch (e) {
            return Promise.resolve(null);
        }
    }

    var native = {
        available: true,
        platform: 'ios',
        call: call,
        onAudio: null,
        onImage: null
    };
    window.AirChatNative = native;
    window.isAirChatNativeHost = true;

    // --- results pushed from Swift ------------------------------------------
    window.__onNativeAudio = function (dataUrl) {
        if (typeof native.onAudio === 'function') { native.onAudio(dataUrl); }
    };
    window.__onNativeImage = function (dataUrl) {
        if (typeof native.onImage === 'function') { native.onImage(dataUrl); }
    };

    // --- Android compatibility shim -----------------------------------------
    var cachedBattery = 0;
    function refreshBattery() {
        call({ action: 'battery' }).then(function (value) {
            if (typeof value === 'number' && value > 0) cachedBattery = value;
        });
    }
    refreshBattery();
    setInterval(refreshBattery, 10000);

    window.AndroidInterface = {
        getBatteryLevel: function () { return cachedBattery; },
        updateSystemUiTheme: function (theme) { call({ action: 'theme', value: theme }); }
    };

    // The actual behaviour (recorder state, overlay, timers, sending) lives in
    // app.js, which owns those variables — it just uses AirChatNative.call() as
    // its transport. This file stays a dumb pipe.
})();
