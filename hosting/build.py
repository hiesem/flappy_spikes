#!/usr/bin/env python3
"""Builds the flappyspikes.com website into hosting/public/ (the Firebase Hosting root). PRD-2.3 §5.4–§5.11, §11, §12.

    python3 hosting/build.py            # build + the §11.7 static checks (a failed check fails the build)
    python3 hosting/build.py --check    # only re-run the checks on hosting/public/

Standard library only. The approved design is design/landing_v23/ (workspace); its homepage, privacy page and
game.js live on in hosting/src/ with the PRD-2.3 changes on top. Fonts, icons and badges are pre-generated into
hosting/src/gen/ by hosting/tools/make_assets.py.

Every shared file (fonts, scripts, images, sounds) is published once under /a/ with a content hash in its name
(cached for a year, immutable); pages are small HTML files (cached for an hour). On Firebase Hosting
`cleanUrls: true` serves privacy.html at /privacy and index.html at /.
"""
import datetime, hashlib, html, json, pathlib, re, shutil, sys
from html.parser import HTMLParser

HOST = pathlib.Path(__file__).resolve().parent
SRC, OUT, REPO = HOST / 'src', HOST / 'public', HOST.parent
GAME = REPO / 'assets'
SITE = 'https://flappyspikes.com'
PLAY = 'https://play.google.com/store/apps/details?id=com.flappyspikes.flappy_spikes'
# collectibles in 2.3 (lib/skins/catalog.dart kCollectibleTotal after PRD-2.3 §19): 30 birds, 29 hats, 29 gear,
# 30 hoops, 30 trails (the "None" hat and gear don't count)
TOTAL = 148


def play_url(campaign):
    """PRD-2.3 §5.3: the Play URL with the install referrer; the site's own buttons use utm_campaign=landing / <slug>."""
    return f'{PLAY}&referrer=utm_source%3Dflappyspikes.com%26utm_medium%3Dweb_link%26utm_campaign%3D{campaign}'


# ------------------------------------------------------------------------------------------------ pages
ORG = {'@type': 'Organization', '@id': f'{SITE}/#org', 'name': 'Duo Leads', 'url': f'{SITE}/', 'logo': f'{SITE}/icon-512.png'}
GAME_NODE = {
    '@type': ['VideoGame', 'MobileApplication'], '@id': f'{SITE}/#game',
    'name': 'Flappy Spikes', 'alternateName': 'Flappy Spikes – Flap Fast, Fly Far',
    'description': None,  # INTRO, filled in below
    'applicationCategory': 'GameApplication', 'genre': 'Arcade',
    'operatingSystem': 'Android, iOS', 'gamePlatform': ['Android', 'iOS'],
    'offers': {'@type': 'Offer', 'price': '0', 'priceCurrency': 'EUR'},
    'datePublished': '2014',
    'publisher': {'@id': f'{SITE}/#org'}, 'author': {'@id': f'{SITE}/#org'},
    'url': f'{SITE}/', 'image': f'{SITE}/og.png', 'sameAs': [PLAY],
}
WEBSITE = {'@type': 'WebSite', '@id': f'{SITE}/#website', 'name': 'Flappy Spikes', 'url': f'{SITE}/', 'publisher': {'@id': f'{SITE}/#org'}}

COMPETITOR_NOTE = (' Flappy Bird, Don\'t Touch the Spikes, Flappy Dunk and Flappy Dragon are trademarks of their respective owners. '
                   'Flappy Spikes is not affiliated with or endorsed by them.')

# slug, source, title, description, og title, og description, sitemap?, extra
PAGES = [
    dict(slug='', src='index_src.html', out='index.html',
         title='Flappy Spikes - Flap Fast, Fly Far',
         description=f'Flap fast, fly far. Fly through the hoops, race real players and unlock {TOTAL} birds, hats and gear. Free on Android and iPhone.',
         og_title='Flappy Spikes', og_description='Flap fast, fly far. Fly through the hoops and race real players.'),
    dict(slug='how-to-play', cta_from='#EBD3F5', src='pages/how-to-play.html', name='How to play',
         title='How to Play Flappy Spikes: Tips & Power-ups',
         description='Tap to fly, thread the hoops, catch fire on perfects. Every power-up, ring and ride in Flappy Spikes explained, plus tips to beat your best.'),
    dict(slug='birds', cta_from='#B9F3E1', src='pages/birds.html', name='Birds, skins and ranks',
         title='Flappy Spikes Birds, Skins & Ranks',
         description='All 30 birds plus hats, gear, hoops and trails. See every rank from Egg to Legend and the score that unlocks it.'),
    dict(slug='story', cta_from='#EBD3F5', src='pages/story.html', name='The story',
         title='The Flappy Spikes Story: 2014 to 2026',
         description='Flappy Spikes first flew on iPhone in 2014. In 2026 Duo Leads rebuilt it with hoops, versus races and new birds. Here is how.'),
    dict(slug='games-like-flappy-bird', cta_from='#EBD3F5', src='pages/games-like-flappy-bird.html', name='Games like Flappy Bird',
         title="Games Like Flappy Bird & Don't Touch the Spikes",
         description='Love one-tap flying games? See how Flappy Spikes compares to Flappy Bird, Flappy Dunk, Flappy Dragon and Don\'t Touch the Spikes. Free on Android and iOS.',
         trademark_extra=COMPETITOR_NOTE),
    dict(slug='versus', cta_from='#B9F3E1', src='pages/versus.html', name='Versus',
         title='Flappy Spikes Versus: Race Real Players',
         description="Versus mode puts you against a real player's recorded run. Watch their score climb, beat it to win. How matching and the versus bar work."),
    dict(slug='support', src='pages/support.html', name='Support', doc=True,
         title='Flappy Spikes Support and FAQ',
         description='Help with purchases, ads, Play Games, versus, sound and your data in Flappy Spikes, and how to mail us.'),
    dict(slug='privacy', src='privacy_src.html', name='Privacy policy', doc=True,
         title='Flappy Spikes Privacy Policy',
         description='What Flappy Spikes collects, why, who processes it, how long it is kept and how to delete it.'),
    dict(slug='delete-data', src='pages/delete-data.html', name='Delete your data', doc=True,
         title='Delete Your Flappy Spikes Account and Data',
         description='How to delete your Flappy Spikes versus data and account, in the app or by email, and what is kept.'),
    dict(slug='404', src='pages/404.html', out='404.html', sitemap=False, noindex=True,
         title='Page Not Found | Flappy Spikes', description='This page flew off. Head back to the Flappy Spikes homepage.'),
]
CONTENT = {'how-to-play', 'birds', 'story', 'games-like-flappy-bird', 'versus'}
# the VideoGame node's description (the homepage's visible intro paragraph was removed in site v2)
INTRO = ('Flappy Spikes is a free one-tap flying game for Android, iPhone and iPad. Tap to flap, fly your bird through the hoops '
         'and stay clear of the spikes. First released on iPhone in 2014 and rebuilt in 2026, it now has versus races against '
         'real players, power-ups, portal rides, 30 birds to unlock and 10 ranks from Egg to Legend. Flap fast, fly far.')


def page_url(slug):
    return f'{SITE}/' if slug == '' else f'{SITE}/{slug}'


def jsonld(p):
    nodes = []
    if p['slug'] == '':
        nodes = [dict(GAME_NODE, description=INTRO), ORG, WEBSITE]
    elif p['slug'] != '404':
        url = page_url(p['slug'])
        nodes = [
            {'@type': 'WebPage', '@id': url + '#webpage', 'url': url, 'name': p['title'], 'description': p['description'],
             'isPartOf': {'@id': f'{SITE}/#website'}, 'publisher': {'@id': f'{SITE}/#org'}},
            {'@type': 'BreadcrumbList', 'itemListElement': [
                {'@type': 'ListItem', 'position': 1, 'name': 'Home', 'item': f'{SITE}/'},
                {'@type': 'ListItem', 'position': 2, 'name': p['name'], 'item': url}]},
        ]
        if p['slug'] == 'story':
            nodes[0]['about'] = {'@id': f'{SITE}/#game'}
            nodes.append(dict(GAME_NODE, description=INTRO))
            nodes.append(ORG)
    if not nodes:
        return ''
    data = json.dumps({'@context': 'https://schema.org', '@graph': nodes}, ensure_ascii=False, indent=1)
    return '<script type="application/ld+json">\n' + data.replace('</', '<\\/') + '\n</script>'


# ------------------------------------------------------------------------------------------------ assets
_assets = {}


def resolve(ref):
    if ref.startswith('@'):
        return GAME / ref[1:]
    return SRC / ref


def publish_bytes(name, data):
    stem, dot, ext = name.rpartition('.')
    h = hashlib.sha256(data).hexdigest()[:10]
    rel = f'a/{stem}.{h}.{ext}'
    (OUT / rel).parent.mkdir(parents=True, exist_ok=True)
    (OUT / rel).write_bytes(data)
    return '/' + rel


def asset(ref):
    """Publishes a shared file under /a/<name>.<hash>.<ext> once and returns its URL. JS/CSS are templated first."""
    if ref in _assets:
        return _assets[ref]
    if ref == 'js/paint.js':
        data = render(paint_js(), {}).encode()
    else:
        p = resolve(ref)
        data = p.read_bytes()
        if p.suffix in ('.js', '.css', '.svg') and b'{{' in data:
            data = render(data.decode(), {}).encode()
    url = publish_bytes(pathlib.PurePath(ref).name, data)
    _assets[ref] = url
    return url


def paint_js():
    """The shared painters for the other pages: the helper block of game.js (as the design's build.py slices it for the
    link preview), plus the image loading, exported as window.FS. No sound."""
    g = (SRC / 'js/game.js').read_text()
    helpers = g[g.index("  const PINK = '#EC008C'"):g.index('  // =====================================================================================\n  // 1. hero')]
    helpers = helpers[:helpers.index('  // ---------- sound')] + helpers[helpers.index('  // ---------- palettes'):]
    names = sorted(set(re.findall(r'^  (?:function|const|let) (\w+)', helpers, re.M)) |
                   {'PLUM', 'GOLD', 'SOFT', 'ACCENT', 'TAU', 'RING_GOLD', 'RING_BRIGHT', 'STAR_IN', 'mix', 'rnd', 'clamp'})
    pre = g[g.index('(() => {'):g.index("  const PINK = '#EC008C'")]
    return (pre + helpers + '  window.FS = { REDUCED, IMG, ' + ', '.join(names) + ' };\n})();\n')


# ------------------------------------------------------------------------------------------------ templating
def badges(campaign, appstore_id=False):
    a_id = ' id="appstore"' if appstore_id else ''
    return (f'<a class="badge" href="{html.escape(play_url(campaign))}"><img src="{asset("gen/gp.webp")}" width="196" height="58" alt="Get it on Google Play"></a>\n'
            f'          <a class="badge"{a_id} href="#appstore" onclick="return false"><img src="{asset("gen/as.webp")}" width="196" height="58" alt="Download on the App Store"></a>')


def brand(href):
    return (f'<a class="brand" href="{href}"><img src="{asset("gen/icon-40.webp")}" srcset="{asset("gen/icon-40.webp")} 1x, '
            f'{asset("gen/icon-80.webp")} 2x" width="40" height="40" alt=""><span>Flappy Spikes</span></a>')


def noscript_email(pink=False):
    svg = asset('gen/contact-pink.svg' if pink else 'gen/contact.svg')
    w, h = (159, 21) if pink else (140, 19)
    return f'<noscript> (<img src="{svg}" width="{w}" height="{h}" alt="our email address, as an image">)</noscript>'


TOKEN = re.compile(r'\{\{\s*([^{}]+?)\s*\}\}')


def render(text, page):
    def sub(m):
        k = m.group(1)
        if k.startswith('> '):
            return render((SRC / 'partials' / (k[2:].strip() + '.html')).read_text().rstrip('\n'), page)
        if k.startswith('a:'):
            return asset(k[2:])
        if k.startswith('css:'):
            return render((SRC / 'css' / k[4:]).read_text(), page)
        if k.startswith('js:'):
            return render((SRC / 'js' / k[3:]).read_text(), page)
        if k.startswith('play:'):
            return html.escape(play_url(k[5:]))
        if k.startswith('badges:'):
            parts = k.split(':')
            return badges(parts[1], len(parts) > 2)
        if k.startswith('brand:'):
            return brand(k[6:])
        if k == 'total':
            return str(TOTAL)
        if k == 'noscript_email':
            return noscript_email()
        if k == 'noscript_email_pink':
            return noscript_email(True)
        if k.startswith('page.'):
            return str(page.get(k[5:], ''))
        raise SystemExit(f'unknown template token {{{{{k}}}}}')
    for _ in range(8):
        new = TOKEN.sub(sub, text)
        if new == text:
            break
        text = new
    return text


# ------------------------------------------------------------------------------------------------ build
def build():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    for p in PAGES:
        slug = p['slug']
        page = dict(p)
        page.setdefault('og_title', p['title'])
        page.setdefault('og_description', p['description'])
        page['url'] = page_url(slug)
        page['robots'] = '<meta name="robots" content="noindex">\n' if p.get('noindex') else ''
        page['jsonld'] = jsonld(p)
        page['campaign'] = slug or 'landing'
        page.setdefault('trademark_extra', '')
        page['title'] = html.escape(p['title'], quote=True)
        page['description'] = html.escape(p['description'], quote=True)
        page['og_title'] = html.escape(page['og_title'], quote=True)
        page['og_description'] = html.escape(page['og_description'], quote=True)
        page['trademark_extra'] = html.escape(page['trademark_extra'], quote=False)
        text = render((SRC / p['src']).read_text(), page)
        left = sorted(set(re.findall(r'__[A-Z][A-Z_]+__|\{\{[^}]*\}\}', text)))
        assert not left, f'{p["src"]}: unreplaced {left}'
        out = p.get('out') or f'{slug}.html'
        (OUT / out).write_text(text)
    # root files with fixed names (linked from OG tags, favicons, the press kit and the ad networks)
    shutil.copyfile(SRC / 'img/og.png', OUT / 'og.png')
    for n in ('favicon.ico', 'icon-48.png', 'icon-96.png', 'icon-192.png', 'icon-512.png', 'apple-touch-icon.png'):
        shutil.copyfile(SRC / 'gen' / n, OUT / n)
    shutil.copyfile(SRC / 'app-ads.txt', OUT / 'app-ads.txt')     # byte-identical to https://hiesem.github.io/app-ads.txt (§5.11)
    (OUT / 'robots.txt').write_text('User-agent: *\nAllow: /\n\nSitemap: https://flappyspikes.com/sitemap.xml\n')
    today = datetime.date.today().isoformat()
    urls = ''.join(f'  <url><loc>{page_url(p["slug"])}</loc><lastmod>{today}</lastmod></url>\n' for p in PAGES if p.get('sitemap', True))
    (OUT / 'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n'
                                     '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + urls + '</urlset>\n')
    for f in sorted(OUT.glob('*.html')):
        print(f'{f.name:32} {f.stat().st_size // 1024:4} KB')
    total = sum(f.stat().st_size for f in (OUT / 'a').iterdir())
    print(f'{"a/ (" + str(len(list((OUT / "a").iterdir()))) + " shared files)":32} {total // 1024:4} KB')


# ------------------------------------------------------------------------------------------------ checks (§11.7)
class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.h1 = 0; self.title = None; self._in = []; self.desc = None; self.canonical = None; self.robots = None
        self.jsonld = []; self.imgs = []; self.links = []; self.ids = set(); self.text = []; self.attr_vals = []; self.scripts = []
        self.lang = None; self.og = {}

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if 'id' in a:
            self.ids.add(a['id'])
        if tag == 'html':
            self.lang = a.get('lang')
        if tag == 'h1':
            self.h1 += 1
        if tag == 'meta' and a.get('name') == 'description':
            self.desc = a.get('content')
        if tag == 'meta' and a.get('name') == 'robots':
            self.robots = a.get('content')
        if tag == 'meta' and a.get('property', '').startswith('og:'):
            self.og[a['property']] = a.get('content')
        if tag == 'link' and a.get('rel') == 'canonical':
            self.canonical = a.get('href')
        if tag == 'img':
            self.imgs.append(a)
        if tag == 'a' and 'href' in a:
            self.links.append(a['href'])
        for k, v in attrs:
            if v and not (tag == 'a' and k == 'href' and v.startswith('mailto:')):
                self.attr_vals.append((tag, k, v))
        self._in.append((tag, a))

    def handle_endtag(self, tag):
        while self._in:
            t, _ = self._in.pop()
            if t == tag:
                break

    def handle_data(self, data):
        top = self._in[-1] if self._in else (None, {})
        if top[0] == 'title':
            self.title = (self.title or '') + data
        elif top[0] == 'script':
            if top[1].get('type') == 'application/ld+json':
                self.jsonld.append(data)
            self.scripts.append(data)
        elif top[0] == 'style':
            self.scripts.append(data)
        else:
            self.text.append(data)


EMAIL = re.compile(r'[\w.+-]+@[\w-]+\.[a-z]{2,}', re.I)


def check():
    errors = []
    err = lambda f, m: errors.append(f'{f}: {m}')
    sitemap = re.findall(r'<loc>(.*?)</loc>', (OUT / 'sitemap.xml').read_text())
    paths = {u[len(SITE):] or '/' for u in sitemap}
    files = {'/' + str(p.relative_to(OUT)) for p in OUT.rglob('*') if p.is_file()}
    for p in PAGES:
        out = p.get('out') or f'{p["slug"]}.html'
        f = OUT / out
        src = f.read_text()
        d = Page(); d.feed(src)
        if d.lang != 'en': err(out, 'missing <html lang="en">')
        if d.h1 != 1: err(out, f'{d.h1} <h1> elements (want exactly 1)')
        if not d.title or len(html.unescape(d.title)) > 60: err(out, f'title missing or > 60 chars: {d.title!r}')
        if not d.desc or len(d.desc) > 155: err(out, f'meta description missing or > 155 chars ({len(d.desc or "")}): {d.desc!r}')
        want = page_url(p['slug'])
        if d.canonical != want: err(out, f'canonical {d.canonical!r} != {want!r}')
        if d.og.get('og:url') != want: err(out, f'og:url {d.og.get("og:url")!r} != canonical')
        if p.get('noindex') and d.robots != 'noindex': err(out, 'missing <meta name="robots" content="noindex">')
        if p.get('sitemap', True) and want not in sitemap: err(out, 'not in the sitemap')
        # JSON-LD
        types = []
        for blob in d.jsonld:
            try:
                data = json.loads(blob)
            except ValueError as e:
                err(out, f'JSON-LD does not parse: {e}'); continue
            for n in data.get('@graph', [data]):
                t = n.get('@type'); types += t if isinstance(t, list) else [t]
                if EMAIL.search(json.dumps(n)): err(out, 'email address inside JSON-LD')
            if 'aggregateRating' in blob or 'FAQPage' in blob or '"Review"' in blob: err(out, 'forbidden JSON-LD (rating / review / FAQPage)')
        if p['slug'] == '':
            for t in ('VideoGame', 'MobileApplication', 'Organization', 'WebSite'):
                if t not in types: err(out, f'JSON-LD lacks {t}')
        elif p['slug'] != '404':
            for t in ('WebPage', 'BreadcrumbList'):
                if t not in types: err(out, f'JSON-LD lacks {t}')
            if p['slug'] == 'story' and 'VideoGame' not in types: err(out, 'JSON-LD lacks the VideoGame node')
        # images
        for a in d.imgs:
            for k in ('alt', 'width', 'height'):
                if k not in a: err(out, f'<img src={a.get("src")}> lacks {k}')
        # links
        for href in d.links:
            if href.startswith(('http://', 'https://', 'mailto:')):
                if href.startswith(SITE): err(out, f'absolute internal link {href} (use a root path)')
                continue
            if href.startswith('#'):
                if href[1:] and href[1:] not in d.ids: err(out, f'anchor {href} has no target')
                continue
            if not href.startswith('/'):
                err(out, f'relative link {href} (internal links are clean root paths)'); continue
            path = href.split('#')[0].split('?')[0]
            if path not in paths and path not in files:
                err(out, f'internal link {href} is not a page in the sitemap')
            if path.endswith('.html') or (path != '/' and path.endswith('/')):
                err(out, f'internal link {href} would go through a cleanUrls redirect')
        # email only as HTML text or mailto:
        for tag, k, v in d.attr_vals:
            if EMAIL.search(v): err(out, f'email address in <{tag} {k}=…>')
        for s in d.scripts:
            if EMAIL.search(s): err(out, 'email address inside a script or style')
        # §12: no "touch the spikes" except the competitor's name on the comparison page
        low = html.unescape(src).lower().replace('’', "'")
        for m in re.finditer(r'touch the spikes', low):
            if p['slug'] != 'games-like-flappy-bird' or low[max(0, m.start() - 6):m.start()] != "don't ":
                err(out, f'"touch the spikes" at offset {m.start()}')
        # content pages: >= 300 words, links home and to two other pages, a store block with its own campaign
        if p['slug'] in CONTENT:
            main = re.search(r'<main.*?</main>', src, re.S).group(0)
            words = len(re.findall(r"[A-Za-z0-9'’]+", re.sub(r'<[^>]+>', ' ', re.sub(r'<(script|style|canvas)[^>]*>.*?</\1>', ' ', main, flags=re.S))))
            if words < 300: err(out, f'only {words} words of text in <main>')
            others = {h for h in d.links if h.startswith('/') and h.split('#')[0] not in ('/', '/' + p['slug'])}
            if '/' not in d.links: err(out, 'no link back to the homepage')
            if len({h.split('#')[0] for h in others}) < 2: err(out, 'links to fewer than two other pages')
            if f'utm_campaign%3D{p["slug"]}' not in src: err(out, 'store block without its own campaign')
    # non-HTML files carry no address at all
    for f in OUT.rglob('*'):
        if f.is_file() and f.suffix in ('.js', '.css', '.txt', '.xml', '.json'):
            t = f.read_text(errors='ignore')
            if EMAIL.search(t): err(f.name, 'email address in a non-HTML file')
            if 'touch the spikes' in t.lower(): err(f.name, '"touch the spikes"')
    gh = SRC / 'app-ads.txt'
    if (OUT / 'app-ads.txt').read_bytes() != gh.read_bytes(): err('app-ads.txt', 'differs from the GitHub copy')
    if (OUT / 'robots.txt').read_text() != 'User-agent: *\nAllow: /\n\nSitemap: https://flappyspikes.com/sitemap.xml\n':
        err('robots.txt', 'not the §11.2 contents')
    want = {'/', '/how-to-play', '/birds', '/story', '/games-like-flappy-bird', '/versus', '/support', '/privacy', '/delete-data'}
    if paths != want: err('sitemap.xml', f'pages {sorted(paths)} != {sorted(want)}')
    if errors:
        print('\nCHECKS FAILED:\n  ' + '\n  '.join(errors))
        sys.exit(1)
    print(f'checks: {len(PAGES)} pages OK (h1, title, description, canonical, JSON-LD, images, links, email, tagline)')


if __name__ == '__main__':
    if '--check' not in sys.argv:
        build()
    check()
