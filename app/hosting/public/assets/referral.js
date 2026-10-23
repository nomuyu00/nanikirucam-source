/* 紹介コードの着地ページ（/r/{code}）。
   パスからコードを取り出して表示し、Google Play のリンクの referrer にコードを入れる。
   iOS は v1 では遅延ディープリンクを持たないので、コードをコピーしてアプリに貼り付けてもらう。 */
(function () {
  'use strict';

  var match = /\/r\/([A-Za-z0-9-]+)\/?$/.exec(location.pathname);
  var raw = match ? match[1].toUpperCase().replace(/-/g, '') : '';
  var valid = /^[A-HJ-NP-Z2-9]{8}$/.test(raw);

  var codeEl = document.getElementById('code');
  var withCode = document.getElementById('with-code');
  var withoutCode = document.getElementById('without-code');
  if (valid) {
    if (codeEl) codeEl.textContent = raw;
    if (withCode) withCode.hidden = false;
  } else if (withoutCode) {
    withoutCode.hidden = false;
  }

  var play = document.getElementById('store-android');
  if (play && valid) {
    var referrer = encodeURIComponent('utm_source=share&utm_campaign=referral&ref=' + raw);
    play.href = play.href + (play.href.indexOf('?') === -1 ? '?' : '&') + 'referrer=' + referrer;
  }

  var copy = document.getElementById('copy');
  if (copy) {
    copy.addEventListener('click', function () {
      if (!valid || !navigator.clipboard) return;
      navigator.clipboard.writeText(raw).then(
        function () {
          copy.textContent = 'コピーしました';
        },
        function () {
          copy.textContent = 'コピーできませんでした';
        },
      );
    });
  }
})();
