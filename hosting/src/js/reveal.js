(() => {
  // Scroll-in reveal on the content pages. Runs inline at the end of <body>: only blocks that start below the first
  // screen are hidden (so nothing visible ever blinks and the hero is never delayed), and without JS, without
  // IntersectionObserver or with reduced motion nothing is hidden at all. Siblings come in with a short stagger.
  if (!('IntersectionObserver' in window) || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const SEL = ['.sec-head', '.sec .panel', '.cards > .card', '.steps3 > *', '.ladder > li', '.duo > .art', '.scale > div', '.chips > li',
    '.tl', '.results3 > div', '.flow > li', '.compare-wrap', '.vsbar-wrap', '.pair', '.rar > h3', '.group > h3', '.press', '.sec .note'].join(',');
  const fold = innerHeight;
  const els = [...document.querySelectorAll('main .zone:not(.first) ' + SEL.split(',').join(', main .zone:not(.first) '))]
    .filter((e) => e.getBoundingClientRect().top > fold - 20);
  if (!els.length) return;
  const order = new Map();
  els.forEach((e) => {
    const p = e.parentElement, i = order.get(p) || 0; order.set(p, i + 1);
    e.style.setProperty('--d', Math.min(i, 8) * 0.06 + 's');
    e.classList.add('rv');
  });
  document.documentElement.classList.add('rv-on');
  const io = new IntersectionObserver((es) => es.forEach((en) => {
    if (en.isIntersecting) { en.target.classList.add('in'); io.unobserve(en.target); }
  }), { rootMargin: '0px 0px -8% 0px' });
  els.forEach((e) => io.observe(e));
  // a safety net: a print, a jump to an anchor far down or a very fast scroll never leaves a block hidden
  addEventListener('beforeprint', () => els.forEach((e) => e.classList.add('in')));
})();
