(() => {
  // The sticky "get the game" card, on phones and tablets only: Android gets the Google Play badge, iPhone / iPad the
  // App Store badge (iPadOS reports a Mac user agent, so a Mac with a touch screen counts as an iPad). No card on
  // desktops. It shows once the hero badges have scrolled off the top and hides while the closing call to action
  // (which has both badges) or the footer is on screen.
  const bar = document.getElementById('storebar'), hero = document.getElementById('hero-badges');
  if (!bar || !hero || !('IntersectionObserver' in window)) return;
  const ua = navigator.userAgent;
  const os = /Android/i.test(ua) ? 'android'
    : (/iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) ? 'ios' : null;
  if (!os) return;
  bar.dataset.os = os;
  bar.querySelector(os === 'ios' ? '.gp' : '.as').remove();
  let closed = false, past = false;
  const covers = new Set();
  try { closed = sessionStorage.getItem('fs-storebar') === 'closed'; } catch (e) {}
  const set = () => {
    const show = past && !covers.size && !closed;
    bar.classList.toggle('show', show); bar.setAttribute('aria-hidden', String(!show));
    bar.querySelectorAll('a, button').forEach((el) => { el.tabIndex = show ? 0 : -1; });
  };
  new IntersectionObserver(([e]) => { past = !e.isIntersecting && e.boundingClientRect.top < 0; set(); }).observe(hero);
  const io = new IntersectionObserver((es) => { es.forEach((e) => covers[e.isIntersecting ? 'add' : 'delete'](e.target)); set(); });
  document.querySelectorAll('.cta .badges, footer').forEach((el) => io.observe(el));
  document.getElementById('storebar-close').addEventListener('click', () => {
    closed = true; set();
    try { sessionStorage.setItem('fs-storebar', 'closed'); } catch (e) {}
  });
})();
