(() => {
  // The FAQ accordions (<details>) open and close with a short ease-in-out: the card (and so the whole FAQ section)
  // grows or shrinks to its new height while the answer fades and slides in or out. Without JS, or with reduced
  // motion, the plain <details> behaviour stays.
  if (!('animate' in Element.prototype) || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const EASE = 'cubic-bezier(.65, 0, .35, 1)', OPEN_MS = 340, CLOSE_MS = 280;
  document.querySelectorAll('.faq details').forEach((d) => {
    const s = d.querySelector('summary');
    if (!s) return;
    const body = [...d.children].filter((c) => c !== s);
    let grow = null, fades = [];
    s.addEventListener('click', (e) => {
      e.preventDefault();
      const opening = !d.open || d.classList.contains('closing');
      const from = d.getBoundingClientRect().height;   // mid-animation too: the height on screen right now
      if (grow) grow.cancel();
      fades.forEach((a) => a.cancel());
      let to;
      if (opening) {
        d.classList.remove('closing');
        d.open = true;
        to = d.getBoundingClientRect().height;
      } else {
        d.classList.add('closing');                      // turns the marker back to a plus right away
        const cs = getComputedStyle(d);
        to = s.getBoundingClientRect().height + parseFloat(cs.paddingTop) + parseFloat(cs.paddingBottom) +
             parseFloat(cs.borderTopWidth) + parseFloat(cs.borderBottomWidth);
      }
      const ms = opening ? OPEN_MS : CLOSE_MS;
      d.style.overflow = 'hidden';
      grow = d.animate({ height: [from + 'px', to + 'px'] }, { duration: ms, easing: EASE });
      fades = body.map((el) => el.animate(opening
        ? { opacity: [0, 1], transform: ['translateY(-8px)', 'none'] }
        : { opacity: [1, 0], transform: ['none', 'translateY(-6px)'] },
        { duration: opening ? ms : ms * .7, delay: opening ? ms * .15 : 0, easing: EASE, fill: 'both' }));
      const g = grow;
      g.onfinish = () => {
        if (grow !== g) return;
        grow = null; d.style.overflow = '';
        if (!opening) { d.open = false; d.classList.remove('closing'); }
        fades.forEach((a) => a.cancel()); fades = [];
      };
    });
  });
})();
