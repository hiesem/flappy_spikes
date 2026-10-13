(() => {
  // PRD-2.3 §11.4: the sticky store bar on phones. Same HTML for everyone; CSS shows it only below 720 px wide.
  const bar = document.getElementById('storebar'), hero = document.getElementById('hero-badges');
  if (!bar || !hero || !('IntersectionObserver' in window)) return;
  let closed = false;
  try { closed = sessionStorage.getItem('fs-storebar') === 'closed'; } catch (e) {}
  const set = (show) => {
    show = show && !closed;
    bar.classList.toggle('show', show); bar.setAttribute('aria-hidden', String(!show));
    bar.querySelectorAll('a, button').forEach((el) => { el.tabIndex = show ? 0 : -1; });
    document.body.classList.toggle('has-bar', show && matchMedia('(max-width: 719.98px)').matches);
  };
  new IntersectionObserver(([e]) => set(!e.isIntersecting && e.boundingClientRect.top < 0)).observe(hero);
  document.getElementById('storebar-close').addEventListener('click', () => {
    closed = true; set(false);
    try { sessionStorage.setItem('fs-storebar', 'closed'); } catch (e) {}
  });
})();
