import Foundation

/// The Node side of the CatVod bridge. It is the host the bundle expects (`catServerFactory`,
/// `catDartServerPort`) and the only process that executes a downloaded source. Every route is
/// bound to 127.0.0.1 and refused without the per-launch token, so another app on the device
/// cannot drive a loaded source.
enum CatVodHostScript {
    static let source = #"""
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const readyPath = process.argv[2];
const token = crypto.randomBytes(24).toString('hex');
const { AsyncLocalStorage } = require('async_hooks');
const sourceContext = new AsyncLocalStorage();
let active = null;
let loadingSourceID = null;
let loadQueue = Promise.resolve();

function loopbackHost(hostname) {
  const host = String(hostname || '').toLowerCase().replace(/^\[|\]$/g, '');
  return host === 'localhost' || host === '127.0.0.1' || host === '::1';
}
function tokenizedLocalURL(value, base, allowedPorts) {
  let target;
  try { target = new URL(value, base); } catch (_) { return value; }
  if (!['http:', 'https:'].includes(target.protocol)) return value;
  if (!loopbackHost(target.hostname)) {
    if (!target.searchParams.has('x-readcc-token')) return value;
    target.searchParams.delete('x-readcc-token');
    return target.href;
  }
  const port = Number(target.port || (target.protocol === 'https:' ? 443 : 80));
  if (!allowedPorts.includes(port)) return null;
  target.hostname = '127.0.0.1';
  target.searchParams.set('x-readcc-token', token);
  return target.href;
}
function rewritePlaylist(text, request, owner) {
  const ports = description(owner).ports;
  const base = 'http://127.0.0.1:' + request.socket.localPort + request.url;
  return text.split(/(\r?\n)/).map(line => {
    if (!line || /^\r?\n$/.test(line)) return line;
    if (line.trim().startsWith('#')) {
      return line.replace(/URI="([^"]+)"/g, (_, uri) =>
        'URI="' + (tokenizedLocalURL(uri, base, ports) || 'about:blank') + '"');
    }
    const trimmed = line.trim();
    if (!trimmed) return line;
    const rewritten = tokenizedLocalURL(trimmed, base, ports);
    return rewritten ? line.replace(trimmed, rewritten) : 'about:blank';
  }).join('');
}
function wrapPlaylistResponse(req, res, owner, handler) {
  const chunks = [];
  const originals = { writeHead: res.writeHead, write: res.write, end: res.end, flushHeaders: res.flushHeaders };
  const isHLS = () => /\.m3u8?$/i.test(String(req.url).split('?')[0]) || /mpegurl|m3u/i.test(String(res.getHeader('content-type') || ''));
  const restore = () => Object.assign(res, originals);
  res.writeHead = function (status, reason, headers) {
    res.statusCode = status;
    if (typeof reason === 'string') res.statusMessage = reason;
    else headers = reason;
    if (Array.isArray(headers)) {
      for (let i = 0; i < headers.length; i += 2) res.setHeader(headers[i], headers[i + 1]);
    } else if (headers) {
      for (const [key, value] of Object.entries(headers)) res.setHeader(key, value);
    }
    return res;
  };
  res.flushHeaders = function () { if (!isHLS()) { restore(); return res.flushHeaders(); } };
  const collect = (chunk, encoding) => {
    if (chunk != null) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, typeof encoding === 'string' ? encoding : undefined));
  };
  res.write = function (chunk, encoding, callback) {
    if (!isHLS()) { restore(); return res.write(chunk, encoding, callback); }
    collect(chunk, encoding);
    if (typeof encoding === 'function') callback = encoding;
    if (callback) process.nextTick(callback);
    return true;
  };
  res.end = function (chunk, encoding, callback) {
    if (typeof chunk === 'function') { callback = chunk; chunk = undefined; }
    if (typeof encoding === 'function') callback = encoding;
    collect(chunk, encoding);
    let body = Buffer.concat(chunks);
    if (isHLS() || body.toString('utf8', 0, Math.min(body.length, 64)).includes('#EXTM3U')) {
      body = Buffer.from(rewritePlaylist(body.toString('utf8'), req, owner), 'utf8');
      res.removeHeader('etag');
      res.removeHeader('content-length');
      res.setHeader('content-type', 'application/vnd.apple.mpegurl');
      res.setHeader('content-length', body.length);
      res.setHeader('cache-control', 'no-store');
    }
    restore();
    return res.end(body, callback);
  };
  try {
    const result = handler(req, res);
    if (result && typeof result.catch === 'function') result.catch(error => {
      writeLog('bundle: ' + error.message);
      if (!res.headersSent) { res.statusCode = 500; res.end('bundle request failed'); }
      else res.destroy(error);
    });
    return result;
  } catch (error) {
    writeLog('bundle: ' + error.message);
    if (!res.headersSent) { res.statusCode = 500; res.end('bundle request failed'); }
    else res.destroy(error);
  }
}

const writeLog = (line) => {
  try { fs.appendFileSync(path.join(path.dirname(readyPath), 'host.log'), String(line) + '\n'); } catch (e) {}
};
const hostProcess = process;
hostProcess.exit = (code) => { writeLog('bundle requested exit ' + code); throw new Error('process.exit denied'); };

process.on('uncaughtException', (error) => writeLog('uncaught: ' + (error && error.stack || error)));
process.on('unhandledRejection', (error) => writeLog('rejected: ' + (error && error.stack || error)));

globalThis.catDartServerPort = () => 0;
globalThis.catServerFactory = (handler) => {
  const owner = sourceContext.getStore() || active;
  if (!owner) throw new Error('server outside source context');
  const server = http.createServer((req, res) => {
    const requestURL = new URL(req.url, 'http://127.0.0.1');
    if (req.headers['x-readcc-token'] !== token && requestURL.searchParams.get('x-readcc-token') !== token) {
      res.writeHead(401, { 'content-type': 'application/json' });
      res.end('{"error":"unauthorized"}');
      return;
    }
    if (active !== owner && loadingSourceID !== owner) {
      res.writeHead(409, { 'content-type': 'application/json' });
      return res.end('{"error":"source changed"}');
    }
    // Never expose the host secret to the bundle's route logic or upstream fetch URLs.
    requestURL.searchParams.delete('x-readcc-token');
    req.url = requestURL.pathname + requestURL.search;
    delete req.headers['x-readcc-token'];
    return sourceContext.run(owner, () => wrapPlaylistResponse(req, res, owner, handler));
  });
  const listen = server.listen.bind(server);
  server.listen = function (...values) {
    const callback = values.find((value) => typeof value === 'function');
    return listen(0, '127.0.0.1', callback);
  };
  owner.servers.push(server);
  return server;
};
globalThis.console = { log() {}, info() {}, warn() {}, error() {}, debug() {}, trace() {}, time() {}, timeEnd() {} };

function proxy(port, route, method, body, timeout) {
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? null : Buffer.from(typeof body === 'string' ? body : JSON.stringify(body));
    const request = http.request({
      host: '127.0.0.1', port, path: route, method: method || 'GET',
      headers: Object.assign({ 'x-readcc-token': token },
        payload ? { 'content-type': 'application/json', 'content-length': payload.length } : {})
    }, (response) => {
      const chunks = [];
      response.on('data', (chunk) => chunks.push(chunk));
      response.on('end', () => resolve({ status: response.statusCode, body: Buffer.concat(chunks).toString('utf8') }));
    });
    request.setTimeout(timeout || 45000, () => request.destroy(new Error('timeout')));
    request.on('error', reject);
    if (payload) request.write(payload);
    request.end();
  });
}

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function failure(status, message) { return Object.assign(new Error(message), { status }); }
function description(state) {
  const ports = state.servers.map(s => s.address()).filter(a => a && typeof a === 'object').map(a => a.port);
  return { sourceID: state.sourceID, port: state.port, ports, origin: 'http://127.0.0.1:' + state.port, sites: state.sites };
}
async function stopState(state) {
  if (!state) return;
  try { if (state.bundle && typeof state.bundle.stop === 'function') await state.bundle.stop(); } catch (_) {}
  for (const server of state.servers) {
    try { server.close(); if (server.closeAllConnections) server.closeAllConnections(); } catch (_) {}
  }
}
async function loadBundle(config) {
  if (typeof config.sourceID !== 'string' || !config.sourceID) throw failure(400, 'missing sourceID');
  if (typeof config.path !== 'string' || !path.isAbsolute(config.path) || !fs.existsSync(config.path)) throw failure(400, 'missing bundle');
  if (typeof config.data !== 'string' || !path.isAbsolute(config.data)) throw failure(400, 'missing state folder');
  const bundlePath = fs.realpathSync(config.path), dataPath = path.resolve(config.data);
  if (active && active.sourceID === config.sourceID && active.path === bundlePath && active.data === dataPath) return description(active);
  const previous = active;
  active = null;
  await stopState(previous);
  const state = { sourceID: config.sourceID, path: bundlePath, data: dataPath, servers: [], port: 0, sites: [], bundle: null };
  loadingSourceID = state;
  try {
    fs.mkdirSync(dataPath, { recursive: true });
    process.chdir(dataPath);
    await sourceContext.run(state, async () => {
      delete require.cache[require.resolve(bundlePath)];
      state.bundle = require(bundlePath);
      if (typeof state.bundle.start !== 'function') throw new Error('bundle has no start');
      await state.bundle.start({ sites: { list: [] }, pans: { list: [] }, color: [] });
    });
    for (let attempt = 0; attempt < 200 && !state.port; attempt++) {
      for (const server of state.servers) {
        const address = server.address();
        if (!address || typeof address !== 'object') continue;
        try {
          const result = await proxy(address.port, '/config', 'GET', undefined, 8000);
          if (result.status === 200) {
            const parsed = JSON.parse(result.body);
            if (parsed.video && Array.isArray(parsed.video.sites)) {
              state.port = address.port;
              state.sites = parsed.video.sites
                .filter(site => typeof site.api === 'string' && /^\/spider\/[A-Za-z0-9_./-]+$/.test(site.api) && !site.api.split('/').includes('..'))
                .map(site => ({ key: String(site.key || site.api), name: String(site.name || site.key || ''), api: site.api,
                  type: Number(site.type || 0), searchable: site.searchable === 1 || site.searchable === true,
                  filterable: site.filterable === 1 || site.filterable === true, indexs: site.indexs === 1 || site.indexs === true }));
              break;
            }
          }
        } catch (_) {}
      }
      if (!state.port) await delay(150);
    }
    if (!state.port) throw new Error('no video configuration');
    active = state;
    return description(state);
  } catch (error) { await stopState(state); throw error; }
  finally { loadingSourceID = null; }
}
function serial(operation) {
  const result = loadQueue.then(operation);
  loadQueue = result.catch(() => {});
  return result;
}
function requireSource(body) {
  if (!active) throw failure(409, 'no source loaded');
  if (body.sourceID !== active.sourceID) throw failure(409, 'source changed');
  return active;
}

async function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    let size = 0; const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > (limit || 65536)) { reject(new Error('body too large')); req.destroy(); return; }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

const control = http.createServer(async (req, res) => {
  const send = (status, value) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(value)); };
  if (req.headers['x-readcc-token'] !== token) return send(401, { error: 'unauthorized' });
  const url = new URL(req.url, 'http://127.0.0.1');
  try {
    if (url.pathname === '/ping') return send(200, { ok: true });
    if (url.pathname === '/load' && req.method === 'POST') {
      const body = JSON.parse(await readBody(req) || '{}');
      const result = await serial(() => loadBundle(body));
      return send(200, Object.assign({ ok: true }, result));
    }
    if (url.pathname === '/invoke' && req.method === 'POST') {
      const body = JSON.parse(await readBody(req) || '{}');
      return await serial(async () => {
        const state = requireSource(body);
        const site = state.sites.find(site => site.api === body.api && site.key === body.site);
        if (!site) throw failure(400, 'unknown site');
        const action = String(body.action || '');
        if (!['home', 'category', 'search', 'detail', 'play'].includes(action)) throw failure(400, 'unsupported action');
        if (body.arguments != null && (typeof body.arguments !== 'object' || Array.isArray(body.arguments))) throw failure(400, 'invalid arguments');
        const result = await proxy(state.port, site.api + '/' + action, 'POST', body.arguments || {}, 60000);
        return send(200, result);
      });
    }
    if (url.pathname === '/proxy' && req.method === 'POST') {
      const body = JSON.parse(await readBody(req) || '{}');
      return await serial(async () => {
        const state = requireSource(body);
        const method = String(body.method || 'GET').toUpperCase();
        const route = String(body.path || '');
        const readCredentials = method === 'GET' && route === '/website/api/credentials';
        const editCredential = ['PUT', 'DELETE'].includes(method) && /^\/website\/api\/credential\/[A-Za-z0-9_-]+\/[A-Za-z0-9_-]+$/.test(route);
        if (!readCredentials && !editCredential) throw failure(400, 'unsupported credential route');
        const result = await proxy(state.port, route, method, body.body, 30000);
        return send(200, result);
      });
    }
    return send(404, { error: 'not found' });
  } catch (error) {
    writeLog('control: ' + (error && error.stack || error));
    return send(error.status || (error instanceof SyntaxError ? 400 : 500), { error: String(error && error.message || error) });
  }
});
control.listen(0, '127.0.0.1', () => {
  fs.writeFileSync(readyPath + '.tmp', JSON.stringify({ port: control.address().port, token }));
  fs.renameSync(readyPath + '.tmp', readyPath);
});
"""#
}
