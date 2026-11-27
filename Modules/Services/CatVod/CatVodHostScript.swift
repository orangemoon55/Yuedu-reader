import Foundation

/// Embedded loopback host. The controller, internal bundle transport and player are separate
/// trust domains. A player can only read previously advertised media on the current source.
/// This bridge is not a sandbox for executable Node bundles.
enum CatVodHostScript {
    static let source = #"""
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { AsyncLocalStorage } = require('async_hooks');
const { pipeline } = require('stream');
const readyPath = path.resolve(process.argv[2]);
const randomKey = () => crypto.randomBytes(24).toString('hex');
const token = randomKey(); // control.json and authenticated control requests only
const sourceContext = new AsyncLocalStorage();
const PREFIX = '/.readcc-media/';
const JSON_LIMIT = 4 * 1024 * 1024, PLAYLIST_LIMIT = 1024 * 1024, GRANT_LIMIT = 16384;
let active = null, loading = null, loadQueue = Promise.resolve();
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
function failure(status, message) { return Object.assign(new Error(message), { status, publicMessage: message }); }
function log(event) { // Never log URLs, arguments, credential values or a bundle's error/stack.
  try { fs.appendFileSync(path.join(path.dirname(readyPath), 'host.log'), event + '\n', { mode: 0o600 }); } catch (_) {}
}
process.exit = () => { throw Error('process.exit denied'); };
process.on('uncaughtException', () => log('uncaught bundle exception'));
process.on('unhandledRejection', () => log('unhandled bundle rejection'));
globalThis.console = { log() {}, info() {}, warn() {}, error() {}, debug() {}, trace() {}, time() {}, timeEnd() {} };
function send(res, status, value) {
  if (res.destroyed || res.writableEnded) return;
  if (res.headersSent) return res.destroy();
  res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' });
  res.end(JSON.stringify(value));
}
function ports(state) {
  return state.servers.map(s => s.address()).filter(a => a && typeof a === 'object').map(a => a.port);
}
function description(state) {
  return { sourceID: state.sourceID, port: state.port, ports: ports(state), mediaScope: state.mediaScope,
    origin: 'http://127.0.0.1:' + state.port, sites: state.sites };
}
function localHost(host) { return ['localhost', '127.0.0.1', '[::1]'].includes(host); }
const internalHeader = name => /^x-readcc-/i.test(name) || /^readcc-source$/i.test(name);
const safeMediaPath = pathname => {
  // Check decoded path components without altering the actual signed/encoded request target.
  let decoded;
  try { decoded = decodeURIComponent(pathname); } catch (_) { return false; }
  if (!decoded.startsWith('/') || /[\\?#%;\x00-\x1f\x7f]/.test(decoded) || /\/\//.test(decoded)) return false;
  const pieces = decoded.toLowerCase().split('/');
  return !pieces.some(c => ['.', '..', '.readcc-media', 'admin', 'website', 'config', 'credential', 'credentials',
    'management', 'site', 'sites', 'spider', 'load', 'invoke', 'ping'].includes(c));
};
function hasSecret(value, state) {
  return value.includes(token) || value.includes(state.mediaScope) || value.includes(state.bridge);
}
function mediaTarget(state, value, base) {
  if (typeof value !== 'string' || !value || value.length > 16384 || /[\x00-\x1f\x7f\\]/.test(value) || hasSecret(value, state)) return null;
  let u; try { u = new URL(value, base); } catch (_) { return null; }
  if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password || [...u.searchParams.keys()].some(internalHeader)) return null;
  if (!localHost(u.hostname)) {
    if (/^127\.|^0\.0\.0\.0$|\.localhost\.?$|^localhost\.$|^\[::(?:ffff:.*)?\]$/.test(u.hostname)) return null;
    return { remote: value }; // Do not serialize URL or URLSearchParams for a remote signed URI.
  }
  const port = Number(u.port), route = u.pathname + u.search;
  if (u.protocol !== 'http:' || !ports(state).includes(port) || !safeMediaPath(u.pathname)) return null;
  return { port, route, fragment: u.hash };
}
function grant(state, value, base) {
  const target = mediaTarget(state, value, base);
  if (!target) return null;
  if ('remote' in target) return target.remote;
  const {port, route, fragment} = target;
  const key = port + ':' + route;
  // Bound storage for long-running browsing/live video. Refresh on read or rediscovery.
  state.grants.delete(key);
  if (state.grants.size >= GRANT_LIMIT) state.grants.delete(state.grants.values().next().value);
  state.grants.add(key);
  return 'http://127.0.0.1:' + port + PREFIX + state.mediaScope + route + fragment;
}
// Mirror CatVodContentParser's accepted address shapes, not arbitrary JSON traversal.
// Pair labels, headers, malformed FongMi v containers and failed envelopes are not grants.
function playbackAddresses(value, depth = 0, stringDepth = 0) {
  if (depth >= 8) throw Error('playback nesting');
  const scalar = v => typeof v === 'string' ? v : typeof v === 'number' && Number.isFinite(v) ? String(v) : null;
  const valid = v => {
    if (typeof v !== 'string') return false;
    if (v.startsWith('/') && !v.startsWith('//') && !v.includes('\\')) return true;
    try { const u = new URL(v); return ['http:', 'https:'].includes(u.protocol) && !!u.hostname; } catch (_) { return false; }
  };
  const meaningful = v => v != null && v !== false && v !== 0 && !(typeof v === 'string' && ['', 'false', 'null', '0'].includes(v.trim().toLowerCase())) && !(typeof v === 'object' && !Object.keys(v).length);
  const failedStatus = v => {
    if (v == null) return false;
    if (typeof v === 'number' || typeof v === 'boolean') return Number(v) !== 0 && Number(v) !== 200;
    if (typeof v !== 'string') return true;
    const s = v.trim().toLowerCase();
    return !['', '0', '200', 'ok', 'success', 'true'].includes(s) && !((s !== '') && [0, 200].includes(Number(s)));
  };
  const falseSuccess = v => {
    if (typeof v === 'boolean' || typeof v === 'number') return Number(v) === 0;
    const s = (scalar(v) || '').trim().toLowerCase();
    if (['', 'false', 'no', 'off', '0'].includes(s)) return true;
    return Number.isFinite(Number(s)) && Number(s) === 0;
  };
  const check = v => {
    if (!v || typeof v !== 'object' || Array.isArray(v)) return;
    if (meaningful(v.error) || (meaningful(v.msg) && ['list', 'vodlist', 'vodList', 'items', 'videos'].some(k => Array.isArray(v[k]) && !v[k].length)) ||
        ['status', 'code', 'status_code', 'error_code', 'errno'].some(k => failedStatus(v[k])) ||
        ('success' in v && falseSuccess(v.success))) throw Error('playback business failure');
  };
  check(value);
  if (typeof value === 'string') {
    const s = value.trim();
    if (s.startsWith('{') || s.startsWith('[')) {
      if (stringDepth >= 1) throw Error('playback string nesting');
      return playbackAddresses(JSON.parse(s), depth, stringDepth + 1);
    }
    return valid(s) ? [s] : [];
  }
  if (Array.isArray(value)) {
    if (value.length && value.every(v => typeof v === 'string' && valid(v.trim()))) return value.map(v => v.trim());
    const pairs = [];
    for (let i = 0; i + 1 < value.length; i += 2) {
      const name = scalar(value[i]), address = scalar(value[i + 1]);
      if (name != null && address != null && valid(address.trim())) pairs.push(address.trim());
    }
    if (pairs.length) return pairs;
    for (const item of value) if (item && typeof item === 'object') {
      const found = playbackAddresses(item, depth + 1, stringDepth); if (found.length) return found;
    }
  } else if (value && typeof value === 'object') {
    if (Array.isArray(value.values)) {
      value.values.forEach(check);
      const choices = value.values.flatMap(entry => {
        const address = entry && !Array.isArray(entry) && typeof entry === 'object' ? scalar(entry.v) : null;
        return address != null && valid(address.trim()) ? [address.trim()] : [];
      });
      if (choices.length) return choices;
    }
    for (const key of ['url', 'play', 'play_url', 'data', 'result']) if (key in value) {
      const found = playbackAddresses(value[key], depth + 1, stringDepth); if (found.length) return found;
    }
  }
  return [];
}
// The control payload, including headers and opaque episode IDs, remains untouched.
function registerResponse(state, action, text) {
  let root; try { root = JSON.parse(text); } catch (_) { return; }
  const base = 'http://127.0.0.1:' + state.port + '/';
  if (action === 'play') {
    try { for (const address of playbackAddresses(root)) grant(state, address, base); } catch (_) {}
    return;
  }
  function visit(v, depth) {
    if (depth > 12 || v == null) return;
    if (typeof v === 'string') {
      const s = v.trim();
      if ((s[0] === '{' || s[0] === '[') && depth < 3) { try { visit(JSON.parse(s), depth + 1); } catch (_) {} }
    } else if (Array.isArray(v)) {
      for (const item of v) visit(item, depth + 1);
    } else if (typeof v === 'object') {
      for (const [k, item] of Object.entries(v)) {
        if (['data', 'result', 'list', 'vodlist', 'vodList', 'items', 'videos', 'video', 'detail'].includes(k)) visit(item, depth + 1);
        else if (['vod_pic', 'pic', 'vodPic', 'cover', 'poster'].includes(k) && typeof item === 'string') grant(state, item.trim(), base);
      }
    }
  }
  visit(root, 0);
}
function rewritePlaylist(state, text, base) {
  const rewrite = raw => grant(state, raw, base) || 'about:blank';
  return text.split(/(\r?\n)/).map(line => {
    const s = line.trim();
    if (!s) return line;
    if (s.startsWith('#')) return line.replace(/([:,](?:[A-Z0-9-]+-)?URI=")([^"]+)(")/g, (_, prefix, uri, end) => prefix + rewrite(uri) + end);
    return line.replace(s, () => rewrite(s));
  }).join('');
}

async function bounded(stream, limit, status) {
  if (Number(stream.headers['content-length']) > limit) throw failure(status, 'body too large');
  const chunks = []; let size = 0;
  for await (const chunk of stream) {
    size += chunk.length;
    if (size > limit) throw failure(status, 'body too large');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, size);
}
function internalRequest(state, port, route, method, headers, body, timeout) {
  return http.request({ host: '127.0.0.1', port, path: route, method, headers: {
    ...headers, 'x-readcc-bridge': state.bridge, ...(body ? { 'content-type': 'application/json', 'content-length': body.length } : {})
  }, agent: false, timeout }).on('timeout', function () { this.destroy(Error('timeout')); });
}
async function proxy(state, port, route, method, body, timeout) {
  const payload = body == null ? null : Buffer.from(typeof body === 'string' ? body : JSON.stringify(body));
  const response = await new Promise((resolve, reject) => {
    internalRequest(state, port, route, method, {}, payload, timeout).once('response', resolve).once('error', reject).end(payload);
  });
  try { return { status: response.statusCode, body: (await bounded(response, JSON_LIMIT, 502)).toString('utf8') }; }
  finally { response.destroy(); }
}
const hopHeader = name => /^(?:connection|keep-alive|te|trailer|transfer-encoding|upgrade|proxy-.*)$/i.test(name);
async function media(state, req, res, port, route) {
  const headers = {};
  for (const [key, val] of Object.entries(req.headers)) {
    if (!internalHeader(key) && !hopHeader(key) && !['host', 'content-length', 'expect', 'accept-encoding'].includes(key) && !hasSecret(String(val), state)) headers[key] = val;
  }
  headers['accept-encoding'] = 'identity';
  const upstream = internalRequest(state, port, route, req.method, headers, null, 45000);
  const cancel = () => upstream.destroy();
  res.once('close', cancel);
  try {
    const incoming = await new Promise((resolve, reject) => upstream.once('response', resolve).once('error', reject).end());
    if (active !== state) throw failure(409, 'source changed');
    const status = incoming.statusCode, base = 'http://127.0.0.1:' + port + route;
    const out = { 'referrer-policy': 'no-referrer', 'cache-control': 'no-store' };
    // Never pass unreviewed Location, Link, Refresh, cookies or arbitrary response headers to the player.
    for (const key of ['content-type', 'content-length', 'content-range', 'accept-ranges', 'content-encoding', 'etag', 'last-modified']) {
      const val = incoming.headers[key];
      if (val != null && !hasSecret(String(val), state)) out[key] = val;
    }
    if ([301, 302, 303, 307, 308].includes(status)) {
      const location = grant(state, incoming.headers.location, base);
      if (!location) throw failure(502, 'invalid media redirect');
      res.writeHead(status, { 'location': location, 'referrer-policy': 'no-referrer', 'cache-control': 'no-store', 'content-length': 0 });
      return res.end(); // Discard upstream redirect body (may contain unfiltered links).
    }
    const isPlaylist = status === 200 && (/mpegurl/i.test(out['content-type'] || '') || /\.m3u8?$/i.test(new URL(base).pathname));
    if (isPlaylist) {
      if (out['content-encoding'] && out['content-encoding'] !== 'identity') throw failure(502, 'unsupported playlist encoding');
      delete out['content-length']; delete out.etag; delete out['last-modified']; delete out['accept-ranges'];
      out['content-type'] = 'application/vnd.apple.mpegurl';
      if (req.method !== 'HEAD') {
        const body = await bounded(incoming, PLAYLIST_LIMIT, 502);
        const rewritten = Buffer.from(rewritePlaylist(state, body.toString('utf8'), base));
        if (rewritten.length > PLAYLIST_LIMIT * 4) throw failure(502, 'playlist too large');
        if (active !== state) throw failure(409, 'source changed');
        out['content-length'] = rewritten.length;
        res.writeHead(status, out); return res.end(rewritten);
      }
    }
    res.writeHead(status, out);
    if (req.method === 'HEAD' || status === 204 || status === 304) return res.end();
    // Ordinary binary and partial responses stream with backpressure; no text conversion or buffering.
    await new Promise((resolve, reject) => pipeline(incoming, res, err => err ? reject(err) : resolve()));
  } finally { res.removeListener('close', cancel); upstream.destroy(); }
}
function bundleDispatch(owner, handler, req, res) {
  if (owner !== active && owner !== loading) return send(res, 409, { error: 'source changed' });
  if (req.headers['x-readcc-bridge'] === owner.bridge) {
    // IncomingMessage exposes both normalized and raw headers; remove private transit metadata from both.
    for (let i = req.rawHeaders.length - 2; i >= 0; i -= 2) {
      if (internalHeader(req.rawHeaders[i])) req.rawHeaders.splice(i, 2);
    }
    for (const key of Object.keys(req.headers)) if (internalHeader(key)) delete req.headers[key];
    return sourceContext.run(owner, async () => {
      try { await handler(req, res); } catch (_) { send(res, 500, { error: 'bundle request failed' }); }
    });
  }
  const prefix = PREFIX + owner.mediaScope;
  if (owner !== active || !['GET', 'HEAD'].includes(req.method) || !req.url.startsWith(prefix + '/')) return send(res, 401, { error: 'unauthorized' });
  const port = req.socket.localPort, route = req.url.slice(prefix.length), key = port + ':' + route;
  if (!owner.grants.has(key)) return send(res, 403, { error: 'not a media resource' });
  owner.grants.delete(key); owner.grants.add(key);
  return media(owner, req, res, port, route).catch(err => send(res, err.status || 502, { error: err.publicMessage || 'media unavailable' }));
}
globalThis.catDartServerPort = () => 0;
globalThis.catServerFactory = handler => {
  const owner = sourceContext.getStore();
  if (!owner || (owner !== active && owner !== loading)) throw Error('server outside source context');
  const server = http.createServer((req, res) => bundleDispatch(owner, handler, req, res));
  const listen = server.listen.bind(server);
  server.listen = (...args) => listen(0, '127.0.0.1', args.find(v => typeof v === 'function'));
  owner.servers.push(server); return server;
};
async function stopState(state) {
  if (!state) return;
  state.grants.clear();
  for (const server of state.servers) {
    try { server.close(); if (server.closeAllConnections) server.closeAllConnections(); } catch (_) {}
  }
  try { if (state.bundle && typeof state.bundle.stop === 'function') await state.bundle.stop(); } catch (_) {}
}
async function loadBundle(config) {
  if (typeof config.sourceID !== 'string' || !config.sourceID) throw failure(400, 'missing sourceID');
  if (typeof config.path !== 'string' || !path.isAbsolute(config.path) || !fs.existsSync(config.path)) throw failure(400, 'missing bundle');
  if (typeof config.data !== 'string' || !path.isAbsolute(config.data)) throw failure(400, 'missing state folder');
  const bundlePath = fs.realpathSync(config.path), data = path.resolve(config.data);
  if (active && active.sourceID === config.sourceID && active.path === bundlePath && active.data === data) return description(active);
  const previous = active; active = null; await stopState(previous);
  const state = { sourceID: config.sourceID, path: bundlePath, data, servers: [], port: 0, sites: [],
    bundle: null, mediaScope: randomKey(), bridge: randomKey(), grants: new Set(),
    siteConfigs: new Map(), initialized: new Map() };
  loading = state;
  try {
    fs.mkdirSync(data, { recursive: true }); process.chdir(data);
    await sourceContext.run(state, async () => {
      delete require.cache[require.resolve(bundlePath)]; state.bundle = require(bundlePath);
      if (typeof state.bundle.start !== 'function') throw Error('missing start');
      await state.bundle.start({ sites: { list: [] }, pans: { list: [] }, color: [] });
    });
    for (let attempt = 0; attempt < 200 && !state.port; attempt++) {
      for (const port of ports(state)) {
        try {
          const result = await proxy(state, port, '/config', 'GET', undefined, 8000);
          if (result.status !== 200) continue;
          const parsed = JSON.parse(result.body);
          if (!parsed.video || !Array.isArray(parsed.video.sites)) continue;
          state.port = port;
          state.sites = parsed.video.sites.filter(s => typeof s.api === 'string' && /^\/spider\/[A-Za-z0-9_./-]+$/.test(s.api) && !s.api.split('/').includes('..'))
            .map(s => {
              const site = { key: String(s.key || s.api), name: String(s.name || s.key || ''), api: s.api,
                type: Number(s.type || 0), searchable: s.searchable === 1 || s.searchable === true,
                filterable: s.filterable === 1 || s.filterable === true, indexs: s.indexs === 1 || s.indexs === true };
              // ext belongs to this installed site; never serialize it in description().
              const ext = typeof s.ext === 'string' ? s.ext : s.ext && typeof s.ext === 'object' ? JSON.stringify(s.ext) : '';
              state.siteConfigs.set(JSON.stringify([site.key, site.api]), ext);
              return site;
            });
          break;
        } catch (_) {}
      }
      if (!state.port) await delay(150);
    }
    if (!state.port) throw failure(502, 'no video configuration');
    active = state; return description(state);
  } catch (err) { await stopState(state); throw err; } finally { loading = null; }
}
function serial(operation) {
  const result = loadQueue.then(operation); loadQueue = result.catch(() => {}); return result;
}
function requireSource(body) {
  if (!active || body.sourceID !== active.sourceID) throw failure(409, 'source changed');
  return active;
}
const control = http.createServer(async (req, res) => {
  if (req.headers['x-readcc-token'] !== token) return send(res, 401, { error: 'unauthorized' });
  try {
    if (req.url === '/ping' && req.method === 'GET') return send(res, 200, { ok: true });
    if (req.method !== 'POST' || !['/load', '/invoke', '/proxy'].includes(req.url)) return send(res, 404, { error: 'not found' });
    const body = JSON.parse((await bounded(req, 65536, 413)).toString('utf8') || '{}');
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw failure(400, 'invalid body');
    const result = await serial(async () => {
      if (req.url === '/load') return { ok: true, ...await loadBundle(body) };
      const state = requireSource(body);
      if (req.url === '/invoke') {
        const site = state.sites.find(s => s.api === body.api && s.key === body.site);
        if (!site) throw failure(400, 'unknown site');
        const action = body.action;
        if (!['home', 'category', 'search', 'detail', 'play'].includes(action)) throw failure(400, 'unsupported action');
        if (body.arguments != null && (typeof body.arguments !== 'object' || Array.isArray(body.arguments))) throw failure(400, 'invalid arguments');
        // One provider owns mutable state per API. A -> B -> A with different ext
        // must initialize A again; failed init must never mark that API ready.
        const ext = state.siteConfigs.get(JSON.stringify([site.key, site.api])) || '';
        if (state.initialized.get(site.api) !== ext) {
          state.initialized.delete(site.api);
          const init = await proxy(state, state.port, site.api + '/init', 'POST', {
            ext, bridge: 'http://127.0.0.1:' + state.port
          }, 60000);
          if (init.status !== 404 && !(init.status >= 200 && init.status < 300)) return init;
          state.initialized.set(site.api, ext);
        }
        let reply = await proxy(state, state.port, site.api + '/' + action, 'POST', body.arguments || {}, 60000);
        // Only these documented search outcomes mean no matches, never auth/5xx.
        if (action === 'search' && (reply.status === 404 || (reply.status >= 200 && reply.status < 300 && !reply.body.trim()))) {
          reply = { status: 200, body: '{"list":[]}' };
        }
        if (reply.status >= 200 && reply.status < 300) registerResponse(state, action, reply.body);
        return reply;
      }
      const method = String(body.method || 'GET').toUpperCase(), route = String(body.path || '');
      const read = method === 'GET' && route === '/website/api/credentials';
      const edit = ['PUT', 'DELETE'].includes(method) && /^\/website\/api\/credential\/[A-Za-z0-9_-]+\/[A-Za-z0-9_-]+$/.test(route);
      if (!read && !edit) throw failure(400, 'unsupported credential route');
      return proxy(state, state.port, route, method, body.body, 30000);
    });
    send(res, 200, result);
  } catch (err) {
    log('control request failed');
    send(res, err.status || (err instanceof SyntaxError ? 400 : 500), { error: err.publicMessage || 'control request failed' });
  }
});
control.listen(0, '127.0.0.1', () => {
  fs.writeFileSync(readyPath + '.tmp', JSON.stringify({ port: control.address().port, token }), { mode: 0o600 });
  fs.renameSync(readyPath + '.tmp', readyPath);
});
"""#
}
