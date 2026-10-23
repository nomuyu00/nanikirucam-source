/* Web 問題ページ（/p/{id}）のスクリプト。
   - 牌をタップ → POST /api/answer（answerProblem）→ 分布の棒グラフと 3 軸の解を表示
   - GA4 のイベント web_problem_viewed / web_answered / web_store_clicked
     （測定 ID が空、または Do Not Track / Global Privacy Control のときは読み込まない）
   インラインスクリプトは使わない（CSP: script-src 'self' https://www.googletagmanager.com）。 */
(function () {
  'use strict';

  var dataEl = document.getElementById('nk-data');
  if (!dataEl) return;
  var data;
  try {
    data = JSON.parse(dataEl.textContent);
  } catch (e) {
    return;
  }
  var t = data.t;
  var lang = data.lang;
  var pid = data.problemId;

  /* ---------- 計測（GA4） ---------- */
  var doNotTrack =
    navigator.doNotTrack === '1' || window.doNotTrack === '1' || navigator.globalPrivacyControl === true;

  function initGa(id) {
    if (!id || doNotTrack || !/^G-[A-Z0-9]{4,}$/.test(id)) return;
    window.dataLayer = window.dataLayer || [];
    window.gtag = function () {
      window.dataLayer.push(arguments);
    };
    window.gtag('js', new Date());
    window.gtag('config', id, { anonymize_ip: true });
    var s = document.createElement('script');
    s.async = true;
    s.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(id);
    document.head.appendChild(s);
  }

  function track(name, params) {
    try {
      if (window.gtag) window.gtag('event', name, params || {});
    } catch (e) {
      /* 計測の失敗は無視 */
    }
  }

  initGa(data.ga4Id);
  track('web_problem_viewed', { problem_id: pid, lang: lang });

  /* ---------- 端末 ID（二重回答の判定用。localStorage に保存。個人は特定しない） ---------- */
  function randomId() {
    var bytes = new Uint8Array(18);
    var c = window.crypto || window.msCrypto;
    if (c && c.getRandomValues) {
      c.getRandomValues(bytes);
    } else {
      for (var i = 0; i < bytes.length; i++) bytes[i] = Math.floor(Math.random() * 256);
    }
    return btoa(String.fromCharCode.apply(null, bytes))
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');
  }

  function clientId() {
    try {
      var v = localStorage.getItem('nk_cid');
      if (!v || !/^[A-Za-z0-9_-]{16,64}$/.test(v)) {
        v = randomId();
        localStorage.setItem('nk_cid', v);
      }
      return v;
    } catch (e) {
      return randomId();
    }
  }

  function remember(tile) {
    try {
      localStorage.setItem('nk_ans_' + pid, tile);
    } catch (e) {
      /* 保存できなくても回答はできる */
    }
  }

  function recall() {
    try {
      return localStorage.getItem('nk_ans_' + pid);
    } catch (e) {
      return null;
    }
  }

  /* ---------- 表示用の補助 ---------- */
  var HONORS_JA = ['東', '南', '西', '北', '白', '發', '中'];
  var HONORS_EN = ['East', 'South', 'West', 'North', 'White', 'Green', 'Red'];
  var SUIT_JA = { m: '萬', p: '筒', s: '索' };
  var SUIT_EN = { m: 'Man', p: 'Pin', s: 'Sou' };
  var KANJI_NUM = ['', '一', '二', '三', '四', '五', '六', '七', '八'];

  function tileName(label) {
    var n = label.charAt(0);
    var s = label.charAt(1);
    if (s === 'z') return (lang === 'en' ? HONORS_EN : HONORS_JA)[Number(n) - 1] || label;
    if (lang === 'en') return (n === '0' ? 'Red 5 ' : n + ' ') + SUIT_EN[s];
    return (n === '0' ? '赤5' : n) + SUIT_JA[s];
  }

  function kind(label) {
    return label.charAt(0) === '0' ? '5' + label.charAt(1) : label;
  }

  function fmt(template, values) {
    return template.replace(/\{(\w+)\}/g, function (m, k) {
      return Object.prototype.hasOwnProperty.call(values, k) ? String(values[k]) : m;
    });
  }

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined && text !== null) e.textContent = text;
    return e;
  }

  function tileImg(label, cls) {
    var img = el('img', cls);
    img.src = '/tiles/' + label + '.png';
    img.alt = tileName(label);
    img.width = 160;
    img.height = 208;
    img.decoding = 'async';
    return img;
  }

  function shantenText(n) {
    if (n < 0) return t.shanten['-1'];
    if (n === 0) return t.shanten['0'];
    return fmt(t.shantenN, { n: lang === 'ja' ? KANJI_NUM[n] || n : n });
  }

  function axesOf(answer, label) {
    var k = kind(label);
    return ['balance', 'speed', 'points'].filter(function (axis) {
      return answer.byAxis[axis].some(function (l) {
        return kind(l) === k;
      });
    });
  }

  /* ---------- 結果の描画 ---------- */
  var resultBox = document.getElementById('nk-result');
  var hint = document.getElementById('nk-hint');
  var cta = document.getElementById('nk-cta');
  var buttons = Array.prototype.slice.call(document.querySelectorAll('button.tile'));

  function badge(axis) {
    return el('span', 'badge ' + axis, t.axis[axis]);
  }

  function render(res) {
    resultBox.textContent = '';
    resultBox.hidden = false;
    var j = res.judgement;

    var verdictClass = res.correct ? 'ok' : j.speed || j.points ? 'alt' : 'ng';
    var verdictText;
    if (res.correct) {
      verdictText = t.correct;
    } else if (j.speed || j.points) {
      var names = [];
      if (j.speed) names.push(t.axis.speed);
      if (j.points) names.push(t.axis.points);
      verdictText = fmt(t.alternative, { axis: names.join(lang === 'ja' ? '・' : ' / ') });
    } else {
      verdictText = t.incorrect;
    }
    resultBox.appendChild(el('p', 'verdict ' + verdictClass, verdictText));
    if (res.alreadyAnswered) resultBox.appendChild(el('p', 'verdict-sub', t.answeredBefore));

    /* みんなの回答 */
    var stats = res.stats;
    resultBox.appendChild(el('h2', null, t.distribution));
    var parts = [fmt(t.answerCount, { n: stats.total })];
    if (stats.total > 0) {
      parts.push(fmt(t.accuracy, { p: Math.round((stats.correct / stats.total) * 100) }));
    }
    resultBox.appendChild(el('p', 'count', parts.join(' ・ ')));

    var seen = {};
    var labels = [];
    data.tiles.forEach(function (l) {
      if (!seen[l]) {
        seen[l] = true;
        labels.push(l);
      }
    });
    labels.sort(function (a, b) {
      return (stats.byTile[b] || 0) - (stats.byTile[a] || 0);
    });
    var list = el('ul', 'bars');
    labels.forEach(function (label) {
      var count = stats.byTile[label] || 0;
      var axes = axesOf(res.answer, label);
      if (count === 0 && axes.length === 0 && label !== res.yourTile) return;
      var pct = stats.total > 0 ? (count / stats.total) * 100 : 0;
      var row = el('li', 'bar-row' + (label === res.yourTile ? ' mine' : ''));
      row.appendChild(tileImg(label, 'bar-tile'));
      var track = el('div', 'bar-track');
      var fill = el('div', 'bar-fill');
      fill.style.width = pct.toFixed(1) + '%'; /* CSSOM 経由（CSP の style-src に抵触しない） */
      track.appendChild(fill);
      row.appendChild(track);
      var pctEl = el('span', 'bar-pct', Math.round(pct) + '% (' + count + ')');
      if (axes.length) {
        var badges = el('span', 'badges');
        axes.forEach(function (a) {
          badges.appendChild(badge(a));
        });
        pctEl.appendChild(badges);
      }
      row.appendChild(pctEl);
      list.appendChild(row);
    });
    resultBox.appendChild(list);

    /* 3 軸の解 */
    resultBox.appendChild(el('h2', null, t.solutions));
    var answer = res.answer;
    var single =
      ['speed', 'points', 'balance']
        .map(function (a) {
          return answer.byAxis[a]
            .map(kind)
            .filter(function (v, i, arr) {
              return arr.indexOf(v) === i;
            })
            .sort()
            .join(',');
        })
        .filter(function (v, i, arr) {
          return arr.indexOf(v) === i;
        }).length === 1;
    var axesBox = el('div', 'axes');
    if (single) {
      var one = el('div', 'axis-row');
      one.appendChild(el('span', 'badge balance', t.singleAnswer));
      answer.byAxis.balance.forEach(function (l) {
        one.appendChild(tileImg(l, 'axis-tile'));
      });
      axesBox.appendChild(one);
    } else {
      ['balance', 'speed', 'points'].forEach(function (axis) {
        var row = el('div', 'axis-row');
        row.appendChild(badge(axis));
        answer.byAxis[axis].forEach(function (l) {
          row.appendChild(tileImg(l, 'axis-tile'));
        });
        axesBox.appendChild(row);
      });
    }
    resultBox.appendChild(axesBox);
    resultBox.appendChild(
      el(
        'p',
        'engine',
        shantenText(answer.shanten) + ' ・ ' + fmt(t.ukeire, { kinds: answer.ukeire.kinds, total: answer.ukeire.total }),
      ),
    );

    if (hint) hint.hidden = true;
    if (cta) cta.classList.add('highlight');
  }

  function showError() {
    var p = resultBox.querySelector('.error');
    if (!p) {
      p = el('p', 'error');
      resultBox.hidden = false;
      resultBox.appendChild(p);
    }
    p.textContent = t.errorGeneric;
  }

  function markSelected(tile) {
    buttons.forEach(function (b) {
      b.classList.toggle('selected', b.getAttribute('data-tile') === tile);
    });
  }

  /* ---------- 回答 ---------- */
  var busy = false;

  function submit(tile, silent) {
    if (busy) return;
    busy = true;
    buttons.forEach(function (b) {
      b.disabled = true;
    });
    markSelected(tile);
    fetch(data.answerEndpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ problemId: pid, tile: tile, source: 'web', fingerprint: clientId() }),
    })
      .then(function (r) {
        return r.json().then(function (body) {
          return { ok: r.ok, body: body };
        });
      })
      .then(function (r) {
        if (!r.ok || !r.body || !r.body.ok) throw new Error('bad response');
        remember(r.body.yourTile);
        markSelected(r.body.yourTile);
        render(r.body);
        if (!silent && !r.body.alreadyAnswered) {
          track('web_answered', { problem_id: pid, correct: r.body.correct ? 1 : 0, lang: lang });
        }
      })
      .catch(function () {
        showError();
        buttons.forEach(function (b) {
          b.disabled = false;
        });
        markSelected(null);
      })
      .then(function () {
        busy = false;
      });
  }

  buttons.forEach(function (b) {
    b.addEventListener('click', function () {
      submit(b.getAttribute('data-tile'), false);
    });
  });

  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[data-store]') : null;
    if (a) track('web_store_clicked', { problem_id: pid, platform: a.getAttribute('data-store') });
  });

  /* 回答済みの端末で開いたら、結果をすぐ表示する */
  var previous = recall();
  if (previous && data.tiles.indexOf(previous) !== -1) submit(previous, true);
})();
