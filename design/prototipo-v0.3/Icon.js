(function () {
  const R = window.React;
  let p = null;
  function load() {
    if (window.lucide) return Promise.resolve();
    if (!p) p = new Promise((res) => {
      const s = document.createElement('script');
      s.src = (window.__resources && window.__resources.lucideJs) || 'https://unpkg.com/lucide@0.460.0/dist/umd/lucide.min.js';
      s.onload = res; s.onerror = res;
      document.head.appendChild(s);
    });
    return p;
  }
  const toPascal = (n) => String(n).split('-').map((w) => w ? w[0].toUpperCase() + w.slice(1) : '').join('');
  function Icon(props) {
    const name = props.i || props.icon || props.name || 'circle';
    const size = Number(props.size || 18);
    const [, force] = R.useState(0);
    R.useEffect(() => { if (!window.lucide) load().then(() => force((x) => x + 1)); }, []);
    const L = window.lucide;
    const node = L && L.icons && L.icons[toPascal(name)];
    let kids = [];
    if (node) kids = node[0] === 'svg' ? (node[2] || []) : node;
    return R.createElement('svg', {
      width: size, height: size, viewBox: '0 0 24 24', fill: 'none',
      stroke: 'currentColor', strokeWidth: props.stroke || 1.75,
      strokeLinecap: 'round', strokeLinejoin: 'round',
      style: Object.assign({ display: 'block', flex: 'none' }, props.color ? { color: props.color } : {}, props.style || {})
    }, kids.map((k, i) => R.createElement(k[0], Object.assign({ key: i }, k[1]))));
  }
  window.AtlasIcon = Icon;
  if (typeof module !== 'undefined') module.exports = { Icon };
})();
