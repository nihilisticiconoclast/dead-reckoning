/* Dead Reckoning — dashboard
   Reads window.__DATA__ if present (self-contained preview), else fetches
   ./data.json (the file the nightly Action regenerates). Renders everything
   below the hero into #app. Plots are hand-built SVG — no chart library. */
(function () {
  'use strict';

  // ---- formatting -----------------------------------------------------------
  var f3 = function (x) { return (x == null || isNaN(x)) ? '—' : x.toFixed(3); };
  var f2 = function (x) { return (x == null || isNaN(x)) ? '—' : x.toFixed(2); };
  var pc = function (x) { return (x == null || isNaN(x)) ? '—' : Math.round(x * 100) + '%'; };
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
  function fmtDate(s) {
    var d = new Date(s + 'T00:00:00Z');
    return d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC' });
  }

  var YOU = 'var(--route-you)', MODEL = 'var(--route-model)';

  // ---- scoreboard -----------------------------------------------------------
  function scoreboard(d) {
    var y = d.forecasters.you, c = d.forecasters.claude;
    var youLeads = y.brier <= c.brier;
    function card(f, color, leads) {
      return '' +
        '<div class="score-card" style="border-top:2px solid ' + color + '">' +
          '<div class="eyebrow" style="color:' + color + '">' + esc(f.label) +
            (leads ? ' · leading' : '') + '</div>' +
          '<div class="score-brier mono">' + f3(f.brier) + '</div>' +
          '<div class="score-sub mono dim">Brier · lower is better</div>' +
          '<div class="score-row mono">' +
            '<span><span class="faint">BSS</span> ' + f3(f.bss) + '</span>' +
            '<span><span class="faint">log loss</span> ' + f3(f.logloss) + '</span>' +
          '</div>' +
        '</div>';
    }
    return '<section class="standing">' +
      card(y, YOU, youLeads) +
      '<div class="versus mono faint">vs</div>' +
      card(c, MODEL, !youLeads) +
      '<div class="score-meta">' +
        '<div class="eyebrow">Ledger</div>' +
        '<div class="mono"><span class="figure">' + d.counts.resolved + '</span> resolved</div>' +
        '<div class="mono"><span class="figure">' + d.counts.open + '</span> open · ' +
          '<span class="figure">' + d.counts.awaiting + '</span> awaiting</div>' +
        '<div class="mono dim">base rate ' + pc(d.base_rate) + '</div>' +
      '</div>' +
    '</section>';
  }

  // ---- reliability diagram + sharpness --------------------------------------
  function calibration(d) {
    var ML = 52, MR = 16, MT = 16, S = 336;           // square plot
    var X0 = ML, X1 = ML + S, Yc0 = MT, Yc1 = MT + S; // calibration band
    var STRIP = 70, SG = 26, SY1 = Yc1 + SG + STRIP;  // sharpness strip baseline
    var W = X1 + MR, Hh = SY1 + 26;
    var X = function (p) { return X0 + p * S; };
    var Y = function (o) { return Yc1 - o * S; };

    var s = '<svg viewBox="0 0 ' + W + ' ' + Hh + '" role="img" ' +
      'aria-label="Reliability diagram: observed frequency against forecast probability">';

    // grid + frame
    var ticks = [0, 0.25, 0.5, 0.75, 1];
    ticks.forEach(function (t) {
      s += '<line x1="' + X(t) + '" y1="' + Yc0 + '" x2="' + X(t) + '" y2="' + Yc1 +
        '" style="stroke:var(--grid)"/>';
      s += '<line x1="' + X0 + '" y1="' + Y(t) + '" x2="' + X1 + '" y2="' + Y(t) +
        '" style="stroke:var(--grid)"/>';
      s += '<text x="' + X(t) + '" y="' + (SY1 + 16) + '" class="ax">' + t.toFixed(2) + '</text>';
      s += '<text x="' + (X0 - 8) + '" y="' + (Y(t) + 3) + '" class="ax" text-anchor="end">' + t.toFixed(2) + '</text>';
    });
    s += '<rect x="' + X0 + '" y="' + Yc0 + '" width="' + S + '" height="' + S +
      '" fill="none" style="stroke:var(--hairline)"/>';
    // perfect-calibration diagonal
    s += '<line x1="' + X(0) + '" y1="' + Y(0) + '" x2="' + X(1) + '" y2="' + Y(1) +
      '" style="stroke:var(--ink-faint)" stroke-dasharray="3 4"/>';
    s += '<text x="' + (X(0.5) + 6) + '" y="' + (Y(0.5) - 7) + '" class="ax" ' +
      'transform="rotate(-45 ' + X(0.5) + ' ' + Y(0.5) + ')">perfect calibration</text>';

    // series
    function series(bins, color) {
      if (!bins.length) return '';
      var g = '<g>';
      var pts = bins.map(function (b) { return X(b.mean_forecast) + ',' + Y(b.observed); }).join(' ');
      g += '<polyline points="' + pts + '" fill="none" style="stroke:' + color +
        ';opacity:.55" stroke-width="1.4"/>';
      bins.forEach(function (b) {
        var r = 3 + Math.sqrt(b.n) * 2.4;
        g += '<circle cx="' + X(b.mean_forecast) + '" cy="' + Y(b.observed) + '" r="' + r.toFixed(1) +
          '" style="fill:' + color + ';fill-opacity:.18;stroke:' + color + '"/>';
      });
      return g + '</g>';
    }
    s += series(d.calibration.claude, MODEL);
    s += series(d.calibration.you, YOU);

    // axis titles
    s += '<text x="' + X(0.5) + '" y="' + (SY1 + 24) + '" class="ax-t" text-anchor="middle">forecast probability</text>';
    s += '<text class="ax-t" text-anchor="middle" transform="translate(' + (X0 - 34) + ' ' +
      ((Yc0 + Yc1) / 2) + ') rotate(-90)">observed frequency</text>';

    // sharpness histogram (where each forecaster placed its bets)
    var maxN = 1;
    ['you', 'claude'].forEach(function (k) { d.calibration[k].forEach(function (b) { maxN = Math.max(maxN, b.n); }); });
    s += '<text x="' + X0 + '" y="' + (Yc1 + 18) + '" class="ax-t">sharpness — forecasts per bin</text>';
    s += '<line x1="' + X0 + '" y1="' + SY1 + '" x2="' + X1 + '" y2="' + SY1 + '" style="stroke:var(--hairline)"/>';
    function bars(bins, color, off) {
      var g = '';
      bins.forEach(function (b) {
        var mid = (b.lo + b.hi) / 2, h = (b.n / maxN) * STRIP;
        g += '<rect x="' + (X(mid) + off) + '" y="' + (SY1 - h) + '" width="5" height="' + h +
          '" style="fill:' + color + ';fill-opacity:.8"/>';
      });
      return g;
    }
    s += bars(d.calibration.you, YOU, -5.5);
    s += bars(d.calibration.claude, MODEL, 0.5);
    s += '</svg>';

    return '<section><div class="eyebrow">Calibration</div>' +
      '<h2 class="section">Do the probabilities mean what they say?</h2>' +
      '<div class="grid-2">' +
        '<figure class="panel plot">' + s + '</figure>' +
        '<div class="readout">' +
          '<p class="lede">A point sitting on the dashed line is honest: of the times you said <span class="mono">70%</span>, ' +
          'about <span class="mono">70%</span> happened. Above the line is under-confidence, below is over-confidence. ' +
          'Point size is how many forecasts landed in that bin.</p>' +
          '<ul class="key">' +
            '<li><span class="dot" style="background:' + YOU + '"></span> You</li>' +
            '<li><span class="dot" style="background:' + MODEL + '"></span> Claude</li>' +
          '</ul>' +
        '</div>' +
      '</div></section>';
  }

  // ---- Murphy decomposition -------------------------------------------------
  function decomposition(d) {
    var y = d.forecasters.you, c = d.forecasters.claude;
    var maxRel = Math.max(y.reliability, c.reliability, 0.001);
    var maxRes = Math.max(y.resolution, c.resolution, 0.001);
    function bar(v, max, color) {
      return '<span class="meter"><span style="width:' + (v / max * 100) + '%;background:' + color + '"></span></span>';
    }
    function row(label, gloss, yv, cv, kind) {
      var max = kind === 'rel' ? maxRel : kind === 'res' ? maxRes : 0;
      var bars = kind ? '<td>' + bar(yv, max, YOU) + '</td><td>' + bar(cv, max, MODEL) + '</td>' :
        '<td></td><td></td>';
      return '<tr><th>' + label + '<span class="faint"> · ' + gloss + '</span></th>' +
        '<td class="mono">' + f3(yv) + '</td><td class="mono">' + f3(cv) + '</td>' + bars + '</tr>';
    }
    return '<section><div class="eyebrow">Decomposition</div>' +
      '<h2 class="section">Why one of you is ahead</h2>' +
      '<div class="panel"><table class="decomp">' +
        '<thead><tr><th></th><th class="mono" style="color:' + YOU + '">You</th>' +
          '<th class="mono" style="color:' + MODEL + '">Claude</th><th colspan="2"></th></tr></thead><tbody>' +
        row('Reliability', 'calibration error, want 0', y.reliability, c.reliability, 'rel') +
        row('Resolution', 'discrimination, want high', y.resolution, c.resolution, 'res') +
        row('Uncertainty', 'irreducible, set by base rate', y.uncertainty, c.uncertainty, null) +
        '<tr class="sum"><th>Brier <span class="faint"> · reliability − resolution + uncertainty</span></th>' +
          '<td class="mono">' + f3(y.brier) + '</td><td class="mono">' + f3(c.brier) + '</td><td colspan="2"></td></tr>' +
      '</tbody></table>' +
      '<p class="lede" style="margin-top:1rem">' + verdict(y, c) + '</p>' +
      '</div></section>';
  }
  function verdict(y, c) {
    var sharper = y.resolution > c.resolution ? 'You' : 'Claude';
    var calib = y.reliability < c.reliability ? 'You' : 'Claude';
    var winner = y.brier < c.brier ? 'your' : "the model's";
    if (sharper !== calib)
      return sharper + ' make the sharper, better-discriminated calls; ' + calib.toLowerCase() +
        ' is the better-calibrated. On net Brier the ' + (sharper === 'You' ? 'discrimination' : 'calibration') +
        ' wins — ' + winner + ' edge holds.';
    return sharper + ' lead on both calibration and discrimination here.';
  }

  // ---- cumulative Brier -----------------------------------------------------
  function timeseries(d) {
    var t = d.timeseries, n = t.labels.length;
    if (!n) return '';
    var ML = 52, MR = 16, MT = 18, MB = 40, W = 760, H = 260;
    var PW = W - ML - MR, PH = H - MT - MB;
    var maxY = Math.max.apply(null, t.you.concat(t.claude).concat([d.base_rate * (1 - d.base_rate)]));
    maxY = Math.ceil(maxY * 20) / 20 + 0.0;
    var X = function (i) { return ML + (n === 1 ? PW / 2 : (i / (n - 1)) * PW); };
    var Y = function (v) { return MT + PH - (v / maxY) * PH; };
    var s = '<svg viewBox="0 0 ' + W + ' ' + H + '" role="img" aria-label="Cumulative Brier score over resolved forecasts">';
    for (var g = 0; g <= 4; g++) {
      var v = maxY * g / 4;
      s += '<line x1="' + ML + '" y1="' + Y(v) + '" x2="' + (W - MR) + '" y2="' + Y(v) + '" style="stroke:var(--grid)"/>';
      s += '<text x="' + (ML - 8) + '" y="' + (Y(v) + 3) + '" class="ax" text-anchor="end">' + v.toFixed(2) + '</text>';
    }
    // base-rate (no-skill) reference
    var ref = d.base_rate * (1 - d.base_rate);
    s += '<line x1="' + ML + '" y1="' + Y(ref) + '" x2="' + (W - MR) + '" y2="' + Y(ref) +
      '" style="stroke:var(--ink-faint)" stroke-dasharray="2 4"/>';
    s += '<text x="' + (W - MR) + '" y="' + (Y(ref) - 5) + '" class="ax" text-anchor="end">always base rate</text>';
    function line(arr, color) {
      var pts = arr.map(function (v, i) { return X(i) + ',' + Y(v); }).join(' ');
      var g = '<polyline points="' + pts + '" fill="none" style="stroke:' + color + '" stroke-width="1.8"/>';
      g += '<circle cx="' + X(arr.length - 1) + '" cy="' + Y(arr[arr.length - 1]) + '" r="3" style="fill:' + color + '"/>';
      return g;
    }
    s += line(t.claude, MODEL) + line(t.you, YOU);
    // x labels: first, middle, last
    [0, Math.floor((n - 1) / 2), n - 1].filter(function (v, i, a) { return a.indexOf(v) === i; }).forEach(function (i) {
      s += '<text x="' + X(i) + '" y="' + (H - 14) + '" class="ax" text-anchor="middle">' + esc(t.labels[i]) + '</text>';
    });
    s += '<text class="ax-t" text-anchor="middle" transform="translate(' + (ML - 36) + ' ' + (MT + PH / 2) + ') rotate(-90)">cumulative Brier</text>';
    s += '</svg>';
    return '<section><div class="eyebrow">Track</div>' +
      '<h2 class="section">Running score, oldest to newest</h2>' +
      '<figure class="panel plot wide">' + s +
      '<figcaption class="dim">Each step folds in one resolved forecast. Below the dashed line is genuine skill over forecasting the base rate.</figcaption>' +
      '</figure></section>';
  }

  // ---- ledgers --------------------------------------------------------------
  function tag(cat) { return '<span class="cat mono">' + esc(cat) + '</span>'; }

  function positions(d) {
    if (!d.open.length) return '';
    var rows = d.open.map(function (q) {
      return '<tr><td class="mono id">' + esc(q.id) + '</td>' +
        '<td>' + esc(q.text) + ' ' + tag(q.category) + '</td>' +
        '<td class="mono" style="color:' + YOU + '">' + f2(q.you) + '</td>' +
        '<td class="mono" style="color:' + MODEL + '">' + f2(q.claude) + '</td>' +
        '<td class="mono dim">' + fmtDate(q.resolves) + '</td></tr>';
    }).join('');
    return '<section><div class="eyebrow">Open positions</div>' +
      '<h2 class="section">Committed, not yet resolved</h2>' +
      '<div class="panel"><table class="ledger"><thead><tr>' +
        '<th>ID</th><th>Question</th><th style="color:' + YOU + '">You</th>' +
        '<th style="color:' + MODEL + '">Claude</th><th>Resolves</th></tr></thead>' +
        '<tbody>' + rows + '</tbody></table></div></section>';
  }

  function awaiting(d) {
    if (!d.awaiting.length) return '';
    var rows = d.awaiting.map(function (q) {
      return '<tr><td class="mono id">' + esc(q.id) + '</td>' +
        '<td>' + esc(q.text) + ' ' + tag(q.category) + '</td>' +
        '<td class="mono" style="color:' + YOU + '">' + f2(q.you) + '</td>' +
        '<td class="mono" style="color:' + MODEL + '">' + f2(q.claude) + '</td>' +
        '<td class="mono dim">' + fmtDate(q.resolves) + '</td>' +
        '<td class="mono faint">' + esc(q.hint) + '</td></tr>';
    }).join('');
    return '<section><div class="eyebrow">Awaiting fix</div>' +
      '<h2 class="section">Past due, needs resolving</h2>' +
      '<div class="panel"><table class="ledger"><thead><tr>' +
        '<th>ID</th><th>Question</th><th style="color:' + YOU + '">You</th>' +
        '<th style="color:' + MODEL + '">Claude</th><th>Due</th><th>Resolver</th></tr></thead>' +
        '<tbody>' + rows + '</tbody></table></div></section>';
  }

  function log(d) {
    if (!d.resolved.length) return '';
    var rows = d.resolved.slice().reverse().map(function (q) {
      var hit = q.outcome === 1;
      var oc = '<span style="color:' + (hit ? 'var(--yes)' : 'var(--no)') + '">' + (hit ? 'yes' : 'no') + '</span>';
      var win = q.brier_you <= q.brier_claude;
      return '<tr><td class="mono id">' + esc(q.id) + '</td>' +
        '<td>' + esc(q.text) + ' ' + tag(q.category) + '</td>' +
        '<td class="mono" style="color:' + YOU + '">' + f2(q.you) + '</td>' +
        '<td class="mono" style="color:' + MODEL + '">' + f2(q.claude) + '</td>' +
        '<td class="mono">' + oc + '</td>' +
        '<td class="mono' + (win ? ' lead' : '') + '">' + f3(q.brier_you) + '</td></tr>';
    }).join('');
    return '<section><div class="eyebrow">Log</div>' +
      '<h2 class="section">Resolved reckonings</h2>' +
      '<div class="panel"><table class="ledger"><thead><tr>' +
        '<th>ID</th><th>Question</th><th style="color:' + YOU + '">You</th>' +
        '<th style="color:' + MODEL + '">Claude</th><th>Outcome</th><th>Your Brier</th></tr></thead>' +
        '<tbody>' + rows + '</tbody></table>' +
        '<p class="dim" style="margin:.9rem 0 0">Highlighted Brier marks the forecast where you matched or beat the model.</p>' +
      '</div></section>';
  }

  // ---- continuous (CRPS) ----------------------------------------------------
  // Scale-aware number format: continuous outcomes range from fx rates near 1 to
  // index levels in the thousands, so fixed decimals won't do.
  function fnum(x) {
    if (x == null || isNaN(x)) return '—';
    var a = Math.abs(x);
    if (a >= 1000) return Math.round(x).toLocaleString('en-GB');
    if (a >= 100)  return x.toFixed(0);
    if (a >= 10)   return x.toFixed(1);
    if (a >= 1)    return x.toFixed(2);
    return x.toFixed(3);
  }
  function dist(f) {                                   // { mu, sigma } -> "1.30 ± 0.04"
    if (!f || f.mu == null || isNaN(f.mu)) return '—';
    return fnum(f.mu) + ((f.sigma == null || isNaN(f.sigma)) ? '' : ' ± ' + fnum(f.sigma));
  }

  // PIT histogram: where each outcome fell in its predictive CDF. Flat = honest
  // spread; ∪ = over-confident (too narrow); ∩ = under-confident (too wide).
  function pitHistogram(c) {
    var W = 336, H = 168, ML = 26, MR = 10, MT = 14, MB = 28;
    var PW = W - ML - MR, PH = H - MT - MB;
    var you = c.pit.you || [], cl = c.pit.claude || [];
    var maxN = 1, sumYou = 0;
    you.forEach(function (n) { maxN = Math.max(maxN, n); sumYou += n; });
    cl.forEach(function (n) { maxN = Math.max(maxN, n); });
    var bw = PW / 10;
    var X = function (k) { return ML + k * bw; };
    var Y = function (n) { return MT + PH - (n / maxN) * PH; };
    var s = '<svg viewBox="0 0 ' + W + ' ' + H + '" role="img" ' +
      'aria-label="PIT histogram: where outcomes fell in their predictive distribution">';
    s += '<line x1="' + ML + '" y1="' + (MT + PH) + '" x2="' + (ML + PW) + '" y2="' + (MT + PH) +
      '" style="stroke:var(--hairline)"/>';
    if (sumYou) {                                      // uniform (calibrated) reference
      var ey = Y(sumYou / 10);
      s += '<line x1="' + ML + '" y1="' + ey + '" x2="' + (ML + PW) + '" y2="' + ey +
        '" style="stroke:var(--ink-faint)" stroke-dasharray="2 4"/>';
      s += '<text x="' + (ML + PW) + '" y="' + (ey - 4) + '" class="ax" text-anchor="end">flat = calibrated</text>';
    }
    function bars(arr, color, off) {
      var g = '';
      arr.forEach(function (n, k) {
        g += '<rect x="' + (X(k) + off) + '" y="' + Y(n) + '" width="' + (bw / 2 - 1).toFixed(1) +
          '" height="' + ((n / maxN) * PH).toFixed(1) + '" style="fill:' + color + ';fill-opacity:.8"/>';
      });
      return g;
    }
    s += bars(you, YOU, 1) + bars(cl, MODEL, bw / 2);
    [0, 0.5, 1].forEach(function (t) {
      s += '<text x="' + (ML + t * PW) + '" y="' + (H - 9) + '" class="ax" text-anchor="middle">' + t.toFixed(1) + '</text>';
    });
    s += '<text x="' + (ML + PW / 2) + '" y="' + (H - 9 + 0) + '" class="ax-t" text-anchor="middle" dy="14">PIT</text>';
    s += '</svg>';
    return s;
  }

  function continuousSection(d) {
    var c = d.continuous;
    if (!c) return '';
    var html = '<section><div class="eyebrow">Continuous · CRPS</div>' +
      '<h2 class="section">Forecasts of a number, not a yes/no</h2>';

    if (c.n > 0) {
      var y = c.forecasters.you, m = c.forecasters.claude;
      var youLeads = (y.crpss || 0) >= (m.crpss || 0);
      function card(f, color, leads) {
        return '<div class="score-card" style="border-top:2px solid ' + color + '">' +
          '<div class="eyebrow" style="color:' + color + '">' + esc(f.label) +
            (leads ? ' · leading' : '') + '</div>' +
          '<div class="score-brier mono">' + f3(f.crpss) + '</div>' +
          '<div class="score-sub mono dim">CRPSS · skill vs climatology · higher is better</div>' +
          '<div class="score-row mono">' +
            '<span><span class="faint">mean CRPS</span> ' + fnum(f.crps) + '</span>' +
            '<span class="faint">' + f.n + ' resolved · mixed units</span>' +
          '</div></div>';
      }
      html += '<div class="grid-2">' +
        '<section class="standing">' + card(y, YOU, youLeads) +
          '<div class="versus mono faint">vs</div>' + card(m, MODEL, !youLeads) + '</section>' +
        '<figure class="panel plot">' + pitHistogram(c) +
          '<figcaption class="dim">Each resolved outcome dropped into one of ten CDF bins. ' +
          'A flat histogram is well-calibrated spread; a ∪ shape is over-confident, a ∩ under-confident.</figcaption>' +
        '</figure></div>';

      var rrows = c.questions.slice().reverse().map(function (q) {
        var win = (q.crps_you != null && !isNaN(q.crps_you)) &&
                  (q.crps_claude == null || isNaN(q.crps_claude) || q.crps_you <= q.crps_claude);
        return '<tr><td class="mono id">' + esc(q.id) + '</td>' +
          '<td>' + esc(q.text) + ' ' + tag(q.category) + '</td>' +
          '<td class="mono dim">' + esc(q.units || '') + '</td>' +
          '<td class="mono">' + fnum(q.outcome) + '</td>' +
          '<td class="mono' + (win ? ' lead' : '') + '">' + fnum(q.crps_you) + '</td>' +
          '<td class="mono">' + fnum(q.crps_claude) + '</td></tr>';
      }).join('');
      html += '<div class="panel" style="margin-top:1.1rem"><div class="eyebrow">Log · continuous</div>' +
        '<table class="ledger"><thead><tr><th>ID</th><th>Question</th><th>Units</th><th>Outcome</th>' +
          '<th style="color:' + YOU + '">Your CRPS</th><th style="color:' + MODEL + '">Claude CRPS</th></tr></thead>' +
        '<tbody>' + rrows + '</tbody></table>' +
        '<p class="dim" style="margin:.9rem 0 0">CRPS is in each question’s own units — lower is better. ' +
        'Highlighted marks where you matched or beat the model.</p></div>';
    } else {
      html += '<p class="lede">No continuous question has resolved yet. The skill score (CRPSS), ' +
        'mean CRPS, and the PIT calibration histogram appear here as each one lands. ' +
        'The committed positions are below.</p>';
    }

    if (c.open && c.open.length) {
      var orows = c.open.map(function (q) {
        return '<tr><td class="mono id">' + esc(q.id) + '</td>' +
          '<td>' + esc(q.text) + ' ' + tag(q.category) + '</td>' +
          '<td class="mono" style="color:' + YOU + '">' + dist(q.you) + '</td>' +
          '<td class="mono" style="color:' + MODEL + '">' + dist(q.claude) + '</td>' +
          '<td class="mono dim">' + esc(q.units || '') + '</td>' +
          '<td class="mono dim">' + fmtDate(q.resolves) + '</td></tr>';
      }).join('');
      html += '<div class="panel" style="margin-top:1.1rem"><div class="eyebrow">Open positions · continuous</div>' +
        '<table class="ledger"><thead><tr><th>ID</th><th>Question</th>' +
          '<th style="color:' + YOU + '">You</th><th style="color:' + MODEL + '">Claude</th>' +
          '<th>Units</th><th>Resolves</th></tr></thead>' +
        '<tbody>' + orows + '</tbody></table>' +
        '<p class="dim" style="margin:.9rem 0 0">Each forecast is a predictive distribution, shown as ' +
        '<span class="mono">μ ± σ</span>. Add <span class="mono">your</span> distribution in ' +
        '<span class="mono">questions.yml</span> before each resolves.</p></div>';
    }

    return html + '</section>';
  }

  // ---- footer ---------------------------------------------------------------
  function footer(d) {
    return '<footer><hr class="rule"/>' +
      '<p class="mono faint">Generated ' + esc(d.generated_at) +
      ' · forecasts are pre-registered by commit timestamp · regenerated nightly by GitHub Actions</p></footer>';
  }

  // ---- boot -----------------------------------------------------------------
  function render(d) {
    var app = document.getElementById('app');
    app.innerHTML =
      scoreboard(d) + '<hr class="rule"/>' +
      calibration(d) +
      decomposition(d) +
      timeseries(d) +
      positions(d) +
      awaiting(d) +
      log(d) +
      continuousSection(d) +
      footer(d);
  }

  function fail(msg) {
    var app = document.getElementById('app');
    app.innerHTML = '<section class="panel"><div class="eyebrow">No fix</div>' +
      '<p>Could not load <span class="mono">data.json</span>. ' + esc(msg) +
      '</p><p class="dim">Run the scorer (<span class="mono">Rscript R/score.R</span>) to generate it.</p></section>';
  }

  if (window.__DATA__) { render(window.__DATA__); return; }
  fetch('./data.json', { cache: 'no-store' })
    .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
    .then(render)
    .catch(function (e) { fail(e.message); });
})();
