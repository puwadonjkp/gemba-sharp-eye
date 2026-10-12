/* Visitor stats: "online now" via Realtime Presence + daily/total counter from Supabase. */
(function () {
  var box = document.getElementById('vstat');
  if (!box || !window.gembaClient) return;
  var sb = window.gembaClient();
  if (!sb) return;
  function $(id) { return document.getElementById(id); }
  function num(n) { return Number(n || 0).toLocaleString('en-US'); }
  function safe(fn, d) { try { return fn(); } catch (e) { return d; } }

  // ---- counter: one visit per browser session; "unique" = first visit of the day from this browser ----
  var today = new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 10); // Bangkok date
  function show(r) {
    if (!r) return;
    $('v-today').textContent = num(r.today_views);
    $('v-uni').textContent = num(r.today_uniques);
    $('v-total').textContent = num(r.total_views);
    box.hidden = false;
  }
  async function refresh() {
    try { var r = await sb.rpc('visit_summary'); if (!r.error) show(r.data); } catch (e) {}
  }
  (async function () {
    var counted = safe(function () { return sessionStorage.getItem('gemba_hit'); }, null);
    if (counted) { refresh(); return; }
    var isNew = safe(function () { return localStorage.getItem('gemba_vday') !== today; }, true);
    try {
      var r = await sb.rpc('visit_hit', { p_new_day_visitor: isNew });
      if (!r.error) {
        show(r.data);
        safe(function () { sessionStorage.setItem('gemba_hit', '1'); localStorage.setItem('gemba_vday', today); });
      }
    } catch (e) {}
  })();
  setInterval(refresh, 60000);

  // ---- online now (presence): one entry per open tab ----
  var key = 't' + Math.random().toString(36).slice(2, 10);
  var ch = sb.channel('gemba-presence', { config: { presence: { key: key } } });
  function count() {
    var n = Object.keys(ch.presenceState()).length;
    $('v-on').textContent = n || 1;
    box.hidden = false;
  }
  ch.on('presence', { event: 'sync' }, count)
    .subscribe(function (status) { if (status === 'SUBSCRIBED') ch.track({ at: Date.now() }); });
})();
