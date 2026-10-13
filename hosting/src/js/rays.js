(() => {
  // PRD-2.3 §11.3 (CLS): every section's rays layer is placed with a translate, never with top / left, so a section
  // that grows (a web font swapping in) doesn't count as a layout shift. The centre is (--rx, --ry) of the section, or
  // the centre of the element named by data-rays-at (the phone in the hero and versus sections, as in the design).
  const zones = [...document.querySelectorAll('.zone')];
  const px = (v, size) => { v = (v || '').trim(); return v.endsWith('%') ? parseFloat(v) / 100 * size : parseFloat(v) || 0; };
  function place() {
    for (const z of zones) {
      const r = z.getBoundingClientRect(), cs = getComputedStyle(z), at = z.dataset.raysAt && document.getElementById(z.dataset.raysAt);
      let x = px(cs.getPropertyValue('--rx') || '70%', r.width), y = px(cs.getPropertyValue('--ry') || '50%', r.height);
      if (at) { const f = at.getBoundingClientRect(); x = f.left + f.width / 2 - r.left; y = f.top + f.height / 2 - r.top; }
      z.style.setProperty('--tx', (x - px(cs.getPropertyValue('--rx') || '70%', r.width)) + 'px');
      z.style.setProperty('--ty', y + 'px');
    }
  }
  place();
  addEventListener('load', place); addEventListener('resize', place);
  if (document.fonts) document.fonts.ready.then(place);
  if ('ResizeObserver' in window) { const ro = new ResizeObserver(place); zones.forEach((z) => ro.observe(z)); }
})();
