// PRD-2.3 §5.4–§5.11, §11, §12: the built website in hosting/public/ (made by hosting/build.py, whose own
// static checks are the full §11.7 gate). These tests keep the committed output honest inside `flutter test`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _pages = [
  'index.html', 'how-to-play.html', 'birds.html', 'story.html', 'games-like-flappy-bird.html', 'versus.html',
  'support.html', 'privacy.html', 'delete-data.html', '404.html',
];

String _read(String path) => File('hosting/public/$path').readAsStringSync();

void main() {
  test('every page exists with one <h1>, a canonical and a description', () {
    for (final p in _pages) {
      final html = _read(p);
      expect(RegExp('<h1[ >]').allMatches(html).length, 1, reason: p);
      expect(html, contains('<link rel="canonical" href="https://flappyspikes.com/'), reason: p);
      expect(html, contains('<meta name="description" content="'), reason: p);
    }
  });

  test('§5.10 / §11.3: the 404 page is noindex', () {
    expect(_read('404.html'), contains('<meta name="robots" content="noindex">'));
  });

  test('§11.2: robots.txt and the sitemap', () {
    expect(_read('robots.txt'), 'User-agent: *\nAllow: /\n\nSitemap: https://flappyspikes.com/sitemap.xml\n');
    final locs = RegExp('<loc>(.*?)</loc>').allMatches(_read('sitemap.xml')).map((m) => m[1]).toList();
    expect(locs, [
      'https://flappyspikes.com/', 'https://flappyspikes.com/how-to-play', 'https://flappyspikes.com/birds',
      'https://flappyspikes.com/story', 'https://flappyspikes.com/games-like-flappy-bird', 'https://flappyspikes.com/versus',
      'https://flappyspikes.com/support', 'https://flappyspikes.com/privacy', 'https://flappyspikes.com/delete-data',
    ]);
  });

  test('§5.11: app-ads.txt carries the AdMob DIRECT line and no email address', () {
    final ads = _read('app-ads.txt');
    expect(ads, contains('google.com, pub-2660521344509391, DIRECT, f08c47fec0942fa0'));
    expect(ads.contains('@'), isFalse);
    expect(File('hosting/public/ads.txt').existsSync(), isFalse);
  });

  test('§12: no "touch the spikes" outside the competitor name on the comparison page', () {
    for (final p in _pages) {
      final low = _read(p).toLowerCase().replaceAll('&#x27;', "'").replaceAll('’', "'");
      for (final m in 'touch the spikes'.allMatches(low)) {
        final before = low.substring(m.start - 6, m.start);
        expect(p == 'games-like-flappy-bird.html' && before == "don't ", isTrue, reason: '$p at ${m.start}');
      }
    }
  });

  test('§5.2: the address only appears as HTML text or mailto:, never in scripts or JSON-LD', () {
    for (final p in _pages) {
      final html = _read(p);
      for (final s in RegExp(r'<script[^>]*>([\s\S]*?)</script>').allMatches(html)) {
        expect(s[1]!.contains('duoleads.com'), isFalse, reason: p);
      }
      expect(html, contains('<a href="mailto:hello@duoleads.com">hello@duoleads.com</a>'), reason: p);
    }
  });

  test('§11.3: the homepage JSON-LD has the game, the organisation and the website, and no ratings', () {
    final html = _read('index.html');
    final blob = RegExp(r'<script type="application/ld\+json">([\s\S]*?)</script>').firstMatch(html)![1]!;
    final graph = (jsonDecode(blob) as Map)['@graph'] as List;
    final types = graph.expand((n) => (n['@type'] is List) ? n['@type'] as List : [n['@type']]).toSet();
    expect(types, containsAll(['VideoGame', 'MobileApplication', 'Organization', 'WebSite']));
    expect(blob.contains('aggregateRating'), isFalse);
    expect(blob.contains('FAQPage'), isFalse);
  });

  test('§5.4: firebase.json serves hosting/public with clean URLs and long-cached hashed assets', () {
    final cfg = jsonDecode(File('firebase.json').readAsStringSync()) as Map;
    final h = cfg['hosting'] as Map;
    expect(h['public'], 'hosting/public');
    expect(h['cleanUrls'], isTrue);
    expect(h['trailingSlash'], isFalse);
    final a = (h['headers'] as List).firstWhere((x) => x['source'] == '/a/**') as Map;
    expect((a['headers'] as List).first['value'], 'public, max-age=31536000, immutable');
  });

  test('§5.3: store badges use the Play URL with the install referrer and a campaign', () {
    expect(_read('index.html'), contains(
        'https://play.google.com/store/apps/details?id=com.flappyspikes.flappy_spikes&amp;referrer=utm_source%3Dflappyspikes.com%26utm_medium%3Dweb_link%26utm_campaign%3Dlanding'));
    expect(_read('versus.html'), contains('utm_campaign%3Dversus'));
  });
}
