// The header menu (the three gold lines). Plain script, no imports, so a
// failure in the page's own module can never leave the menu dead.
(function () {
  var btn = document.getElementById('menuBtn');
  var menu = document.getElementById('siteMenu');
  if (!btn || !menu) return;

  // Mark the page the reader is on with the small gold dot.
  var here = location.pathname.replace(/\/(index(\.html)?)?$/, '/').replace(/\.html$/, '');
  var links = menu.querySelectorAll('a[data-page]');
  for (var i = 0; i < links.length; i++) {
    var target = links[i].getAttribute('data-page');
    if ((target === 'home' && here === '/') || here === '/' + target) {
      links[i].setAttribute('aria-current', 'page');
    }
  }

  function onDocClick(e) {
    if (!menu.contains(e.target) && !btn.contains(e.target)) close();
  }
  function onKey(e) {
    if (e.key === 'Escape') {
      close();
      btn.focus();
    }
  }
  function open() {
    menu.hidden = false;
    btn.setAttribute('aria-expanded', 'true');
    document.addEventListener('click', onDocClick, true);
    document.addEventListener('keydown', onKey);
  }
  function close() {
    menu.hidden = true;
    btn.setAttribute('aria-expanded', 'false');
    document.removeEventListener('click', onDocClick, true);
    document.removeEventListener('keydown', onKey);
  }

  btn.addEventListener('click', function () {
    if (menu.hidden) open();
    else close();
  });
})();
