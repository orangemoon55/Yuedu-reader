import Foundation

/// LX-compatible contract in an isolated WebKit content process. No filesystem, process,
/// native objects, DOM credentials or console log sink is exported to an imported script.
enum MusicJSBootstrap {
    static let source = #"""
(() => {
  'use strict';
  const callbacks = new Map(), handlers = new Map();
  let sequence = 0;
  const post = value => window.webkit.messageHandlers.readccMusic.postMessage(JSON.stringify(value));
  const events = Object.freeze({ request: 'request', inited: 'inited', updateAlert: 'updateAlert' });
  globalThis.console = Object.freeze({ log() {}, info() {}, error() {}, warn() {}, debug() {} });
  globalThis.lx = Object.freeze({
    EVENT_NAMES: events, env: 'mobile', version: '2.0.0',
    on(event, handler) {
      if (event === events.request && typeof handler === 'function') handlers.set(event, handler);
    },
    send(event, data) {
      if (event === events.inited) {
        if (!handlers.has(events.request)) throw Error('missing request handler');
        post({ kind: 'inited', data });
      }
      return Promise.resolve();
    },
    request(url, options, callback) {
      if (typeof options === 'function') { callback = options; options = {}; }
      if (typeof callback !== 'function') throw Error('request callback required');
      const id = String(++sequence);
      callbacks.set(id, callback);
      post({ kind: 'http', id, url: String(url), options: options || {} });
      return () => { callbacks.delete(id); post({ kind: 'cancelHTTP', id }); };
    }
  });
  Object.defineProperty(globalThis, '__readccMusicHTTP', { value(id, error, response) {
    const callback = callbacks.get(id); if (!callback) return;
    callbacks.delete(id);
    try { callback(error ? new Error(error) : null, response, response && response.body); } catch (_) {}
  }});
  Object.defineProperty(globalThis, '__readccMusicInvoke', { value(id, request) {
    Promise.resolve().then(() => {
      const handler = handlers.get(events.request);
      if (!handler) throw Error('missing request handler');
      return handler(request);
    }).then(data => post({ kind: 'result', id, data }),
      () => post({ kind: 'failure', id }));
  }});
})();
"""#
}
