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
const bundleServers = [];
let active = null;

const writeLog = (line) => {
  try { fs.appendFileSync(path.join(path.dirname(readyPath), 'host.log'), String(line) + '\n'); } catch (e) {}
};
const hostProcess = process;
hostProcess.exit = (code) => { writeLog('bundle requested exit ' + code); throw new Error('process.exit denied'); };

process.on('uncaughtException', (error) => writeLog('uncaught: ' + (error && error.stack || error)));
process.on('unhandledRejection', (error) => writeLog('rejected: ' + (error && error.stack || error)));

globalThis.catDartServerPort = () => 0;
globalThis.catServerFactory = (handler) => {
  const server = http.createServer((req, res) => {
    if (req.headers['x-readcc-token'] !== token) {
      res.writeHead(401, { 'content-type': 'application/json' });
      res.end('{"error":"unauthorized"}');
      return;
    }
    handler(req, res);
  });
  const listen = server.listen.bind(server);
  server.listen = function (...values) {
    const callback = values.find((value) => typeof value === 'function');
    return listen(0, '127.0.0.1', callback);
  };
  bundleServers.push(server);
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

async function loadBundle(config) {
  if (active) {
    try { if (active.bundle && typeof active.bundle.stop === 'function') await active.bundle.stop(); } catch (e) {}
    for (const server of active.servers) { try { server.close(); } catch (e) {} }
    active = null;
  }
  bundleServers.length = 0;
  if (!config.path || !fs.existsSync(config.path)) throw new Error('missing bundle');
  if (!config.data) throw new Error('missing state folder');
  fs.mkdirSync(config.data, { recursive: true });
  try { process.chdir(config.data); } catch (e) {}
  delete require.cache[require.resolve(config.path)];
  const bundle = require(config.path);
  if (typeof bundle.start !== 'function') throw new Error('bundle has no start');
  await bundle.start({ sites: { list: [] }, pans: { list: [] }, color: [] });
  let port = 0;
  let sites = [];
  for (let attempt = 0; attempt < 200 && !port; attempt++) {
    for (const server of bundleServers) {
      const address = server.address();
      if (!address || typeof address !== 'object') continue;
      try {
        const result = await proxy(address.port, '/config', 'GET', undefined, 8000);
        if (result.status === 200) {
          const parsed = JSON.parse(result.body);
          if (parsed.video && Array.isArray(parsed.video.sites)) {
            port = address.port;
            sites = parsed.video.sites
              .filter((site) => typeof site.api === 'string' && site.api.startsWith('/spider/'))
              .map((site) => ({
                key: String(site.key || site.api), name: String(site.name || site.key || ''),
                api: site.api, type: Number(site.type || 0),
                searchable: site.searchable === 1 || site.searchable === true,
                filterable: site.filterable === 1 || site.filterable === true,
                indexs: site.indexs === 1 || site.indexs === true
              }));
            break;
          }
        }
      } catch (e) {}
    }
    if (!port) await delay(150);
  }
  if (!port) throw new Error('no video configuration');
  active = { bundle, port, sites, servers: bundleServers.slice() };
  return { port, sites };
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
      const result = await loadBundle(body);
      return send(200, { ok: true, port: result.port, sites: result.sites });
    }
    if (url.pathname === '/invoke' && req.method === 'POST') {
      if (!active) return send(409, { error: 'no source loaded' });
      const body = JSON.parse(await readBody(req) || '{}');
      const action = String(body.action || '');
      if (!['home', 'category', 'search', 'detail', 'play'].includes(action)) return send(400, { error: 'unsupported action' });
      const result = await proxy(active.port, body.api + '/' + action, 'POST', body.arguments || {}, 60000);
      return send(200, { status: result.status, body: result.body });
    }
    if (url.pathname === '/proxy' && req.method === 'POST') {
      if (!active) return send(409, { error: 'no source loaded' });
      const body = JSON.parse(await readBody(req) || '{}');
      const method = String(body.method || 'GET').toUpperCase();
      if (!['GET', 'PUT', 'DELETE', 'POST'].includes(method)) return send(400, { error: 'unsupported method' });
      const result = await proxy(active.port, String(body.path || ''), method, body.body, 30000);
      return send(200, { status: result.status, body: result.body });
    }
    return send(404, { error: 'not found' });
  } catch (error) {
    writeLog('control: ' + (error && error.stack || error));
    return send(500, { error: String(error && error.message || error) });
  }
});
control.listen(0, '127.0.0.1', () => {
  fs.writeFileSync(readyPath + '.tmp', JSON.stringify({ port: control.address().port, token }));
  fs.renameSync(readyPath + '.tmp', readyPath);
});
"""#
}
