/* Provides window.claude.use('db' | 'user') on top of Supabase, so the board code
   (written against a tiny document-store API) runs unchanged outside claude.ai.
   Tables: docs (realtime) and blobs (photos, fetched on demand). */
(function () {
  var cfg = window.GEMBA_CONFIG || {};
  var BLOB_COLS = { photos: 1, snapphotos: 1 };
  var sb = null, started = null;
  var cache = {};   // col -> Map(id -> data)
  var subs = {};    // col -> [fn]
  var loaded = {};  // col -> bool

  function clone(o) { return JSON.parse(JSON.stringify(o)); }
  function split(path) { var i = path.indexOf('/'); return [path.slice(0, i), path.slice(i + 1)]; }
  function tbl(col) { return BLOB_COLS[col] ? 'blobs' : 'docs'; }
  function fail(err) { var e = new Error(err && err.message || 'db error'); e.code = 'unavailable'; return e; }
  function merge(a, b) {
    if (a && b && typeof a === 'object' && typeof b === 'object' && !Array.isArray(a) && !Array.isArray(b)) {
      var out = Object.assign({}, a);
      Object.keys(b).forEach(function (k) { out[k] = k in a ? merge(a[k], b[k]) : b[k]; });
      return out;
    }
    return b;
  }
  function emit(col, only) {
    var m = cache[col] || new Map();
    var docs = Array.from(m.entries()).map(function (e) { return { id: e[0], data: function () { return clone(e[1]); } }; });
    (only ? [only] : subs[col] || []).forEach(function (f) { try { f({ docs: docs, metadata: { fromCache: false } }); } catch (x) { console.error(x); } });
  }
  async function load(col) {
    var r = await sb.from('docs').select('path,data').eq('col', col);
    if (r.error) throw fail(r.error);
    var m = new Map();
    r.data.forEach(function (row) { m.set(split(row.path)[1], row.data); });
    cache[col] = m; loaded[col] = true;
  }
  function onChange(p) {
    var row = p.eventType === 'DELETE' ? p.old : p.new;
    if (!row || !row.path) return;
    var s = split(row.path), col = s[0], id = s[1];
    if (!subs[col] || !loaded[col]) return;
    if (p.eventType === 'DELETE') cache[col].delete(id); else cache[col].set(id, row.data);
    emit(col);
  }
  // one shared client (also used by stats.js)
  function client() {
    if (!sb && window.supabase && cfg.supabaseUrl) {
      try { sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, { realtime: { params: { eventsPerSecond: 20 } } }); } catch (e) { sb = null; }
    }
    return sb;
  }
  window.gembaClient = client;

  function start() {
    if (started) return started;
    started = new Promise(function (resolve) {
      if (!client()) { resolve(false); return; }
      var first = true;
      sb.channel('gemba-docs')
        .on('postgres_changes', { event: '*', schema: 'public', table: 'docs' }, onChange)
        .subscribe(function (status) {
          if (status === 'SUBSCRIBED') {
            // (re)load everything subscribed; also covers events missed while offline
            Promise.all(Object.keys(subs).map(function (c) { return load(c).then(function () { emit(c); }); })).catch(function () {});
            if (first) { first = false; resolve(true); }
          }
        });
      setTimeout(function () { if (first) { first = false; resolve(true); } }, 6000);
    });
    return started;
  }

  var db = {
    collection: function (col) {
      return {
        onSnapshot: function (fn, onErr) {
          (subs[col] = subs[col] || []).push(fn);
          load(col).then(function () { emit(col, fn); }).catch(function (e) { if (onErr) onErr(e); });
        }
      };
    },
    doc: function (path) {
      var p = split(path), col = p[0], id = p[1], t = tbl(col);
      function local(fn) { if (!cache[col]) return; fn(cache[col]); emit(col); }
      return {
        get: async function () {
          var r = await sb.from(t).select('data').eq('path', path).maybeSingle();
          if (r.error) throw fail(r.error);
          return { exists: !!r.data, data: function () { return r.data ? clone(r.data.data) : undefined; } };
        },
        set: async function (data) {
          var r = await sb.from(t).upsert({ path: path, col: col, data: data, updated_at: new Date().toISOString() });
          if (r.error) throw fail(r.error);
          if (t === 'docs') local(function (m) { m.set(id, clone(data)); });
        },
        update: async function (data) {
          var r = await sb.rpc('doc_merge', { p_path: path, p_data: data });
          if (r.error) throw fail(r.error);
          if (!r.data) { var e = new Error('missing'); e.code = 'invalid_argument'; throw e; }
          local(function (m) { m.set(id, merge(m.get(id) || {}, clone(data))); });
        },
        delete: async function () {
          var r = await sb.from(t).delete().eq('path', path);
          if (r.error) throw fail(r.error);
          if (t === 'docs') local(function (m) { m.delete(id); });
        }
      };
    }
  };

  // Phase 1: anyone with the link may edit. Phase 2 will replace this with real sign-in.
  var user = { can: async function () { return true; } };

  window.claude = {
    use: async function (name) {
      if (!cfg.supabaseUrl || !window.supabase) return null;
      if (name === 'user') return user;
      if (name !== 'db') return null;
      return (await start()) ? db : null;
    }
  };
})();
