// The usage dashboard (GET /dashboard): one page, no libraries, that asks for the files
// token, keeps it in the browser, and draws what GET /v1/usage/summary answers (usage.ts).

export const dashboardHTML = String.raw`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Lyre Usage</title>
<style>
:root {
  color-scheme: light;
  --surface-0: #f4f3f0; --surface-1: #fcfcfb; --border: #e3e2dd;
  --text-primary: #0b0b0b; --text-secondary: #52514e; --text-muted: #7c7b76;
  --grid: #ecebe7; --accent: #2a78d6; --critical: #c93636;
  --p-classic: #2a78d6; --p-spool: #eb6834; --p-gramophone: #1baf7a; --p-disc: #eda100; --p-liquid: #e87ba4;
  --seq-0: #f0f5fc; --seq-1: #cde2fb; --seq-2: #9ec5f4; --seq-3: #5598e7; --seq-4: #256abf; --seq-5: #104281;
  --ink-0: #0b0b0b; --ink-1: #0b0b0b; --ink-2: #0b0b0b; --ink-3: #fff; --ink-4: #fff; --ink-5: #fff;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    color-scheme: dark;
    --surface-0: #111110; --surface-1: #1a1a19; --border: #2c2c2a;
    --text-primary: #f0efec; --text-secondary: #c3c2b7; --text-muted: #8f8e86;
    --grid: #262624; --accent: #3987e5; --critical: #e66767;
    --p-classic: #3987e5; --p-spool: #d95926; --p-gramophone: #199e70; --p-disc: #c98500; --p-liquid: #d55181;
    --seq-0: #1e2430; --seq-1: #0d366b; --seq-2: #184f95; --seq-3: #256abf; --seq-4: #3987e5; --seq-5: #86b6ef;
    --ink-0: #f0efec; --ink-1: #f0efec; --ink-2: #f0efec; --ink-3: #fff; --ink-4: #0b0b0b; --ink-5: #0b0b0b;
  }
}
:root[data-theme="dark"] {
  color-scheme: dark;
  --surface-0: #111110; --surface-1: #1a1a19; --border: #2c2c2a;
  --text-primary: #f0efec; --text-secondary: #c3c2b7; --text-muted: #8f8e86;
  --grid: #262624; --accent: #3987e5; --critical: #e66767;
  --p-classic: #3987e5; --p-spool: #d95926; --p-gramophone: #199e70; --p-disc: #c98500; --p-liquid: #d55181;
  --seq-0: #1e2430; --seq-1: #0d366b; --seq-2: #184f95; --seq-3: #256abf; --seq-4: #3987e5; --seq-5: #86b6ef;
  --ink-0: #f0efec; --ink-1: #f0efec; --ink-2: #f0efec; --ink-3: #fff; --ink-4: #0b0b0b; --ink-5: #0b0b0b;
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--surface-0); color: var(--text-primary);
  font: 14px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
main { max-width: 1120px; margin: 0 auto; padding: 24px 16px 64px; }
header { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; justify-content: space-between; margin-bottom: 20px; }
h1 { font-size: 22px; margin: 0; letter-spacing: -0.01em; }
h2 { font-size: 15px; margin: 0 0 2px; }
.sub { color: var(--text-secondary); font-size: 13px; margin: 0 0 14px; }
.controls { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
select, input, button { font: inherit; color: var(--text-primary); background: var(--surface-1);
  border: 1px solid var(--border); border-radius: 8px; padding: 6px 10px; }
button { cursor: pointer; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(320px, 100%), 1fr)); gap: 16px; }
.card { background: var(--surface-1); border: 1px solid var(--border); border-radius: 14px; padding: 18px; min-width: 0; }
.wide { grid-column: 1 / -1; }
.tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(150px, 100%), 1fr)); gap: 12px; margin-bottom: 16px; }
.tile { background: var(--surface-1); border: 1px solid var(--border); border-radius: 14px; padding: 14px 16px; }
.tile .k { color: var(--text-secondary); font-size: 12px; }
.tile .v { font-size: 26px; font-weight: 600; letter-spacing: -0.02em; font-variant-numeric: tabular-nums; }
.tile .h { color: var(--text-muted); font-size: 12px; }
.bars { display: grid; grid-template-columns: minmax(90px, 38%) 1fr auto; gap: 6px 10px; align-items: center; }
.bars .l { color: var(--text-secondary); font-size: 13px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.bars .t { height: 14px; position: relative; }
.bars .b { position: absolute; left: 0; top: 0; bottom: 0; border-radius: 0 4px 4px 0; background: var(--accent); min-width: 2px; }
.bars .n { font-variant-numeric: tabular-nums; font-size: 13px; color: var(--text-primary); text-align: right; }
.legend { display: flex; flex-wrap: wrap; gap: 12px; margin: 0 0 10px; font-size: 12px; color: var(--text-secondary); }
.legend i { display: inline-block; width: 10px; height: 10px; border-radius: 3px; margin-right: 5px; vertical-align: -1px; }
.stack { display: flex; align-items: flex-end; gap: 3px; height: 180px; border-bottom: 1px solid var(--grid); padding-top: 6px; }
.stack .col { flex: 1; display: flex; flex-direction: column-reverse; gap: 2px; min-width: 3px; height: 100%; }
.stack .seg { width: 100%; }
.stack .seg:last-child { border-radius: 4px 4px 0 0; }
.axis { display: flex; justify-content: space-between; color: var(--text-muted); font-size: 11px; margin-top: 4px; }
table { width: 100%; border-collapse: collapse; font-size: 13px; font-variant-numeric: tabular-nums; }
th { text-align: left; color: var(--text-secondary); font-weight: 500; border-bottom: 1px solid var(--border); padding: 6px 8px 6px 0; }
td { border-bottom: 1px solid var(--grid); padding: 6px 8px 6px 0; }
td.r, th.r { text-align: right; }
.heat td.c { text-align: center; border: 2px solid var(--surface-1); border-radius: 4px; }
.scroll { overflow-x: auto; }
.empty, .err { color: var(--text-muted); font-size: 13px; }
.err { color: var(--critical); }
#tip { position: fixed; pointer-events: none; background: var(--text-primary); color: var(--surface-1);
  padding: 6px 9px; border-radius: 8px; font-size: 12px; display: none; z-index: 10; max-width: 260px; }
#gate { max-width: 420px; margin: 12vh auto; }
#gate p { color: var(--text-secondary); }
#gate form { display: flex; gap: 8px; }
#gate input { flex: 1; }
</style>
</head>
<body>
<div id="tip"></div>
<main>
  <section id="gate" class="card" hidden>
    <h1>Lyre Usage</h1>
    <p>Enter the relay's files token (in ~/.lyre-relay/files-token). It's kept in this browser only.</p>
    <form id="gateForm"><input id="token" type="password" autocomplete="off" placeholder="Files token" aria-label="Files token"><button>Open</button></form>
    <p id="gateErr" class="err"></p>
  </section>
  <div id="app" hidden>
    <header>
      <div><h1>Lyre Usage</h1><div class="sub" id="generated">Loading…</div></div>
      <div class="controls">
        <label for="days" class="sub" style="margin:0">Range</label>
        <select id="days"><option value="7">Last 7 days</option><option value="30" selected>Last 30 days</option><option value="90">Last 90 days</option></select>
        <button id="signOut" title="Forget the token in this browser">Sign out</button>
      </div>
    </header>
    <div class="tiles" id="tiles"></div>
    <div class="grid">
      <section class="card wide"><h2>Players in use</h2><p class="sub">Phones using each player, by day (a phone using two players counts in both).</p><div id="active"></div></section>
      <section class="card"><h2>Player switches</h2><p class="sub">From → to, and how long the first was used before.</p><div id="switches"></div></section>
      <section class="card"><h2>Coming back</h2><p class="sub">Launches by install week and days since install. No one is followed: each launch carries only its week.</p><div id="returning"></div></section>
      <section class="card"><h2>Time to first song</h2><p class="sub">Average seconds from opening Lyre to music, by where it was started.</p><div id="firstPlay"></div></section>
      <section class="card"><h2>Where music starts</h2><p class="sub">Every play started in Lyre, by where.</p><div id="playSources"></div></section>
      <section class="card wide"><h2>Dead ends</h2><p class="sub">Screens left within 2 seconds of opening, against how often they're opened.</p><div id="bounces"></div></section>
      <section class="card"><h2>Searches</h2><p class="sub">Searches that found nothing in the library, by player.</p><div id="searches"></div></section>
      <section class="card"><h2>Freezes</h2><p class="sub">Main thread blocked 250 ms or more, by screen.</p><div id="hangs"></div></section>
      <section class="card"><h2>Features found</h2><p class="sub">Share of counted installs that have ever used each.</p><div id="features"></div></section>
      <section class="card"><h2>Feature use</h2><p class="sub">Each use, all players.</p><div id="featureUse"></div></section>
      <section class="card"><h2>Errors shown</h2><div id="errors"></div></section>
      <section class="card"><h2>Versions</h2><p class="sub">Launches by version and build.</p><div id="versions"></div></section>
    </div>
  </div>
</main>
<script>
(function () {
  var PLAYERS = ["classic", "spool", "gramophone", "disc", "liquid"];
  var NAMES = { classic: "Classic", spool: "Spool", gramophone: "Gramophone", disc: "Disc", liquid: "Liquid" };
  var FEATURES = { songsShelf: "Songs shelf", discover: "Apple Music shelf", cardDeck: "Card decks", cardSwipe: "Card swiping",
    cardFullScreen: "Card full screen", shuffle: "Shuffle", swipeToQueue: "Swipe to queue", love: "Love (★)",
    addToPlaylist: "Add to playlist", reportProblem: "Report a Problem", shareDiagnostics: "Share Diagnostics", search: "Search" };
  // Kept in the browser where it can be, else for this visit only.
  var memory = {};
  var store = { get: function (k) { try { var v = localStorage.getItem(k); if (v !== null) return v; } catch (e) {} return k in memory ? memory[k] : null; },
    set: function (k, v) { if (v === null) delete memory[k]; else memory[k] = v;
      try { v === null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch (e) {} } };
  var $ = function (id) { return document.getElementById(id); };
  var tip = $("tip");
  var fmt = new Intl.NumberFormat();

  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return "&#" + c.charCodeAt(0) + ";"; }); }
  function num(x) { return Number(x) || 0; }
  function rows(data, key) { var r = data[key]; return Array.isArray(r) ? r : null; }
  function failed(data, key) { var r = data[key]; return r && r.error ? '<p class="err">Couldn’t load: ' + esc(r.error) + '</p>' : '<p class="empty">Nothing counted yet.</p>'; }
  function player(p) { return NAMES[p] || p; }
  function hover(el, text) { el.setAttribute("data-tip", text); el.setAttribute("aria-label", text); }

  document.addEventListener("mousemove", function (e) {
    var t = e.target.closest && e.target.closest("[data-tip]");
    if (!t) { tip.style.display = "none"; return; }
    tip.textContent = t.getAttribute("data-tip");
    tip.style.display = "block";
    var x = Math.min(e.clientX + 12, window.innerWidth - tip.offsetWidth - 8);
    tip.style.left = x + "px"; tip.style.top = (e.clientY + 14) + "px";
  });

  function bars(list, opts) {
    if (!list || !list.length) return '<p class="empty">Nothing counted yet.</p>';
    var max = Math.max.apply(null, list.map(function (r) { return r.value; })) || 1;
    var html = '<div class="bars">';
    list.forEach(function (r) {
      html += '<div class="l" title="' + esc(r.label) + '">' + esc(r.label) + '</div>' +
        '<div class="t" data-tip="' + esc(r.tip || (r.label + ": " + r.shown)) + '"><div class="b" style="width:' + (100 * r.value / max).toFixed(1) + '%' +
        (r.color ? ';background:' + r.color : '') + '"></div></div><div class="n">' + esc(r.shown) + '</div>';
    });
    return html + '</div>';
  }

  function table(head, body) {
    if (!body.length) return '<p class="empty">Nothing counted yet.</p>';
    return '<div class="scroll"><table><thead><tr>' + head.map(function (h) { return '<th' + (h.r ? ' class="r"' : '') + '>' + esc(h.t) + '</th>'; }).join("") +
      '</tr></thead><tbody>' + body.map(function (row) { return '<tr>' + row.map(function (c, i) { return '<td' + (head[i].r ? ' class="r"' : '') + '>' + esc(c) + '</td>'; }).join("") + '</tr>'; }).join("") + '</tbody></table></div>';
  }

  function render(data) {
    $("generated").textContent = "Last " + data.days + " days · updated " + new Date(data.generated).toLocaleString();
    var totals = {}; (rows(data, "totals") || []).forEach(function (r) { totals[r.name] = num(r.n); });

    var fp = rows(data, "firstPlay") || [];
    var fpN = fp.reduce(function (a, r) { return a + num(r.n); }, 0);
    var fpAvg = fpN ? fp.reduce(function (a, r) { return a + num(r.n) * num(r.seconds); }, 0) / fpN : null;
    var se = rows(data, "searches") || [];
    var seAll = se.reduce(function (a, r) { return a + num(r.n); }, 0);
    var seEmpty = se.filter(function (r) { return r.result === "empty"; }).reduce(function (a, r) { return a + num(r.n); }, 0);
    var tiles = [
      ["Counted installs", fmt.format(totals.install || 0), "phones sharing statistics"],
      ["Launches", fmt.format(totals.launch || 0), "sessions begun"],
      ["Plays", fmt.format(totals.play || 0), "started in Lyre"],
      ["First song in", fpAvg == null ? "—" : fpAvg.toFixed(1) + " s", "average, from launch"],
      ["Empty searches", seAll ? Math.round(100 * seEmpty / seAll) + "%" : "—", fmt.format(seAll) + " searches"],
      ["Freezes", fmt.format(totals.hang || 0), "250 ms or longer"]
    ];
    $("tiles").innerHTML = tiles.map(function (t) { return '<div class="tile"><div class="k">' + esc(t[0]) + '</div><div class="v">' + esc(t[1]) + '</div><div class="h">' + esc(t[2]) + '</div></div>'; }).join("");

    // Players in use, stacked by day.
    var act = rows(data, "activeByDay");
    if (act && act.length) {
      var days = {}, maxDay = 0;
      act.forEach(function (r) { (days[r.date] = days[r.date] || {})[r.player] = num(r.n); });
      var dates = Object.keys(days).sort();
      dates.forEach(function (d) { var s = 0; for (var p in days[d]) s += days[d][p]; maxDay = Math.max(maxDay, s); });
      var html = '<div class="legend">' + PLAYERS.map(function (p) { return '<span><i style="background:var(--p-' + p + ')"></i>' + NAMES[p] + '</span>'; }).join("") + '</div><div class="stack">';
      dates.forEach(function (d) {
        html += '<div class="col">';
        PLAYERS.forEach(function (p) {
          var v = days[d][p] || 0; if (!v) return;
          html += '<div class="seg" style="height:calc(' + (100 * v / maxDay).toFixed(2) + '% - 2px);background:var(--p-' + p + ')" data-tip="' + esc(d + " · " + NAMES[p] + ": " + fmt.format(v)) + '"></div>';
        });
        html += '</div>';
      });
      $("active").innerHTML = html + '</div><div class="axis"><span>' + esc(dates[0]) + '</span><span>peak ' + fmt.format(maxDay) + ' a day</span><span>' + esc(dates[dates.length - 1]) + '</span></div>';
    } else $("active").innerHTML = failed(data, "activeByDay");

    var sw = rows(data, "switches");
    $("switches").innerHTML = sw ? table([{ t: "From" }, { t: "To" }, { t: "Switches", r: 1 }, { t: "Used before", r: 1 }],
      sw.map(function (r) { return [player(r.from_player), player(r.to_player), fmt.format(num(r.n)), duration(num(r.seconds))]; })) : failed(data, "switches");

    // Coming back: launches by install week × days since install, bucketed.
    var ret = rows(data, "returning");
    if (ret && ret.length) {
      var buckets = [["Day 0", 0, 0], ["Day 1", 1, 1], ["2–7", 2, 7], ["8–30", 8, 30], ["31+", 31, 1e9]];
      var cohorts = {}, peak = 0;
      ret.forEach(function (r) {
        var d = num(r.day), c = (cohorts[r.cohort] = cohorts[r.cohort] || [0, 0, 0, 0, 0]);
        buckets.forEach(function (b, i) { if (d >= b[1] && d <= b[2]) c[i] += num(r.n); });
      });
      Object.keys(cohorts).forEach(function (k) { cohorts[k].forEach(function (v) { peak = Math.max(peak, v); }); });
      var h = '<div class="scroll"><table class="heat"><thead><tr><th>Installed</th>' + buckets.map(function (b) { return '<th class="r">' + b[0] + '</th>'; }).join("") + '</tr></thead><tbody>';
      Object.keys(cohorts).sort().reverse().forEach(function (k) {
        h += '<tr><td>' + esc(k) + '</td>' + cohorts[k].map(function (v, i) {
          var step = v ? Math.min(5, 1 + Math.floor(4 * v / peak)) : 0;
          return '<td class="c" style="background:var(--seq-' + step + ');color:var(--ink-' + step + ')" data-tip="' + esc(k + " · " + buckets[i][0] + ": " + fmt.format(v) + " launches") + '">' + (v ? fmt.format(v) : "") + '</td>';
        }).join("") + '</tr>';
      });
      $("returning").innerHTML = h + '</tbody></table></div>';
    } else $("returning").innerHTML = failed(data, "returning");

    // Time to first song, by source (all players together).
    if (fp.length) {
      var bySource = {};
      fp.forEach(function (r) { var s = bySource[r.source] = bySource[r.source] || { n: 0, t: 0 }; s.n += num(r.n); s.t += num(r.n) * num(r.seconds); });
      $("firstPlay").innerHTML = bars(Object.keys(bySource).map(function (k) { var s = bySource[k]; var avg = s.t / s.n;
        return { label: k, value: avg, shown: avg.toFixed(1) + " s", tip: k + ": " + avg.toFixed(1) + " s average over " + fmt.format(s.n) + " sessions" }; })
        .sort(function (a, b) { return b.value - a.value; }));
    } else $("firstPlay").innerHTML = failed(data, "firstPlay");

    var ps = rows(data, "playSources");
    $("playSources").innerHTML = ps ? bars(ps.map(function (r) { return { label: r.source, value: num(r.n), shown: fmt.format(num(r.n)) }; })) : failed(data, "playSources");

    // Dead ends: bounces against views.
    var views = {}; (rows(data, "screens") || []).forEach(function (r) { views[r.screen] = num(r.n); });
    var bo = rows(data, "bounces");
    if (bo) {
      var list = bo.map(function (r) { var v = views[r.screen] || num(r.n); return { screen: r.screen, n: num(r.n), views: v, rate: num(r.n) / Math.max(v, 1), seconds: num(r.seconds) }; })
        .sort(function (a, b) { return b.rate - a.rate; }).slice(0, 15);
      $("bounces").innerHTML = bars(list.map(function (r) { return { label: r.screen, value: r.rate, shown: Math.round(100 * r.rate) + "% of " + fmt.format(r.views),
        tip: r.screen + ": left within 2 s " + fmt.format(r.n) + " of " + fmt.format(r.views) + " times (after " + r.seconds.toFixed(1) + " s on average)" }; }));
    } else $("bounces").innerHTML = failed(data, "bounces");

    if (se.length) {
      var byPlayer = {};
      se.forEach(function (r) { var p = byPlayer[r.player] = byPlayer[r.player] || { all: 0, empty: 0 }; p.all += num(r.n); if (r.result === "empty") p.empty += num(r.n); });
      $("searches").innerHTML = bars(PLAYERS.filter(function (p) { return byPlayer[p]; }).map(function (p) { var s = byPlayer[p];
        return { label: NAMES[p], value: s.empty / s.all, color: "var(--p-" + p + ")", shown: Math.round(100 * s.empty / s.all) + "% of " + fmt.format(s.all) }; }));
    } else $("searches").innerHTML = failed(data, "searches");

    var hg = rows(data, "hangs");
    if (hg) {
      var byScreen = {};
      hg.forEach(function (r) { var s = byScreen[r.screen] = byScreen[r.screen] || { n: 0, ms: 0 }; s.n += num(r.n); s.ms += num(r.n) * num(r.ms); });
      $("hangs").innerHTML = bars(Object.keys(byScreen).map(function (k) { var s = byScreen[k];
        return { label: k || "unknown", value: s.n, shown: fmt.format(s.n), tip: (k || "unknown") + ": " + fmt.format(s.n) + " freezes, " + Math.round(s.ms / s.n) + " ms on average" }; })
        .sort(function (a, b) { return b.value - a.value; }).slice(0, 12));
    } else $("hangs").innerHTML = failed(data, "hangs");

    var ff = rows(data, "featuresFound");
    var installs = (rows(data, "installs") || []).reduce(function (a, r) { return a + num(r.n); }, 0);
    if (ff) {
      $("features").innerHTML = installs ? bars(ff.map(function (r) { var share = Math.min(1, num(r.n) / installs);
        return { label: FEATURES[r.feature] || r.feature, value: share, shown: Math.round(100 * share) + "%", tip: (FEATURES[r.feature] || r.feature) + ": found on " + fmt.format(num(r.n)) + " of " + fmt.format(installs) + " installs" }; }))
        : '<p class="empty">No installs counted in this range.</p>';
    } else $("features").innerHTML = failed(data, "featuresFound");

    var fu = rows(data, "featureUse");
    if (fu) {
      var byF = {}; fu.forEach(function (r) { byF[r.feature] = (byF[r.feature] || 0) + num(r.n); });
      $("featureUse").innerHTML = bars(Object.keys(byF).map(function (k) { return { label: FEATURES[k] || k, value: byF[k], shown: fmt.format(byF[k]) }; })
        .sort(function (a, b) { return b.value - a.value; }));
    } else $("featureUse").innerHTML = failed(data, "featureUse");

    var er = rows(data, "errors");
    $("errors").innerHTML = er ? table([{ t: "Kind" }, { t: "Shown", r: 1 }], er.map(function (r) { return [r.kind, fmt.format(num(r.n))]; })) : failed(data, "errors");
    var ve = rows(data, "versions");
    $("versions").innerHTML = ve ? table([{ t: "Version" }, { t: "Build", r: 1 }, { t: "Launches", r: 1 }], ve.map(function (r) { return [r.version, r.build, fmt.format(num(r.n))]; })) : failed(data, "versions");
  }

  function duration(s) {
    if (s < 90) return Math.round(s) + " s";
    if (s < 5400) return Math.round(s / 60) + " min";
    if (s < 172800) return (s / 3600).toFixed(1) + " h";
    return Math.round(s / 86400) + " days";
  }

  function load() {
    var token = store.get("lyreUsageToken");
    if (!token) { $("gate").hidden = false; $("app").hidden = true; return; }
    $("gate").hidden = true; $("app").hidden = false;
    var days = $("days").value;
    $("generated").textContent = "Loading…";
    fetch("/v1/usage/summary?days=" + encodeURIComponent(days), { headers: { Authorization: "Bearer " + token } })
      .then(function (r) {
        if (r.status === 401) { store.set("lyreUsageToken", null); $("gateErr").textContent = "That token wasn’t accepted."; load(); throw null; }
        return r.json().then(function (j) { if (!r.ok) throw new Error(j.error || r.status); return j; });
      })
      .then(render)
      .catch(function (e) { if (e) $("generated").innerHTML = '<span class="err">' + esc(e.message || e) + '</span>'; });
  }

  $("gateForm").addEventListener("submit", function (e) {
    e.preventDefault();
    var t = $("token").value.trim(); if (!t) return;
    store.set("lyreUsageToken", t); $("gateErr").textContent = ""; load();
  });
  $("signOut").addEventListener("click", function () { store.set("lyreUsageToken", null); load(); });
  $("days").addEventListener("change", function () { store.set("lyreUsageDays", $("days").value); load(); });
  var savedDays = store.get("lyreUsageDays"); if (savedDays) $("days").value = savedDays;
  load();
})();
</script>
</body>
</html>
`;
