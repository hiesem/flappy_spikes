// Temporary QA host bridge: the real app, with test setup via code_cache.
// Evidence retains this source; the delivered commit contains the report only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flame/game.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/purchases.dart';
import 'package:flappy_spikes/main.dart' as app;
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/items/jar.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flutter/widgets.dart';
import 'package:flappy_spikes/services/reminders.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> main() async {
  await app.main();
  FlappySpikesGame? found;
  void visit(Element e) {
    final w = e.widget;
    if (w is GameWidget<FlappySpikesGame>) found = w.game;
    e.visitChildren(visit);
  }

  while (found == null || !found!.isLoaded) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
  }
  final game = found!;
  // Cancel scheduled reminders; this run permits only debug notifications.
  game.reminders = const NoopReminders();
  await FlutterLocalNotificationsPlugin().cancelAll();
  final input = File('${Directory.systemTemp.path}/p23_command.json');
  final output = File('${Directory.systemTemp.path}/p23_state.json');
  var seq = -1, busy = false;
  Timer.periodic(const Duration(milliseconds: 150), (_) async {
    if (busy) return;
    busy = true;
    try {
      if (await input.exists()) {
        final c =
            jsonDecode(await input.readAsString()) as Map<String, dynamic>;
        if (c['seq'] != seq) {
          seq = c['seq'] as int;
          switch (c['op']) {
            case 'best':
              await game.storage.saveBestScore(c['value'] as int);
              // WP-L the stored level follows the forced best here.
              await game.menu.levels.recordRun(c['value'] as int);
              game.refreshHome();
            case 'score':
              final run = game.run;
              if (run != null) {
                run.ctx.addScore((c['value'] as int) - run.state.score);
              }
            case 'prepare':
              game.runDebug.bot = c['bot'] == true;
              game.runDebug.god = c['god'] == true;
              game.runSeed = (c['seed'] as int?) ?? 7;
              await game.storage.saveMetElements({
                for (final e in ElementId.values) e.storageId,
              });
            case 'kill':
              game.runDebug.god = false;
              final r = game.run;
              if (r != null) {
                r.state.invulnerable = 0;
                r.state.hearts = 0;
                r.state.shield = false;
                r.state.extraLife = false;
                game.onBirdHit(MistakeCause.spikes);
              }
            case 'home':
              game.goHome();
            case 'no_ads':
              await game.menu.setNoAds(c['value'] == true);
            case 'gift':
              game.openNoAdsCelebration(
                gift: const GiftGrant(
                  IapProduct.giftCoins10000,
                  coins: 10000,
                  noAds: false,
                ),
              );
            case 'skin':
              final layer = SkinLayer.values.byName(c['layer']);
              game.selectSkinTab(layer);
              game.tapItem(layer, c['id'] as String);
            case 'pickup':
              final e = ElementId.values.firstWhere(
                (e) => e.storageId == c['id'],
              );
              game.run?.events.emit(PickupCollected(e, null));
            case 'force':
              game.debugForceElement(
                ElementId.values.firstWhere((e) => e.storageId == c['id']),
              );
            case 'noads_probe':
              await game.storage.saveNoAdsPopupLastMs(
                DateTime.now().millisecondsSinceEpoch -
                    (c['minutes'] as int) * 60000,
              );
              await game.storage.saveLastRunMood('best');
              final reason = game.menu.noAdsPopup.evaluate();
              debugPrint(
                'P23QA noads probe minutes=${c['minutes']} eligible=${reason?.name}',
              );
              if (reason != null &&
                  !game.modalPopupOpen &&
                  game.menuScene == MenuScene.home) {
                await game.menu.noAdsPopup.markShown();
                game.openNoAdsPopup(reason: reason.name, check: 'after_run');
              }
            case 'noads_age':
              await game.storage.saveNoAdsPopupLastMs(
                DateTime.now().millisecondsSinceEpoch -
                    (c['minutes'] as int) * 60000,
              );
          }
          debugPrint('P23QA command $seq ${c['op']}');
        }
      }
      final r = game.run;
      final h = game.viewHeight;
      final s = <String, Object?>{
        'start': [
          Config.homeStartRectFor(h).center.dx,
          Config.homeStartRectFor(h).center.dy,
        ],
        'modeTap': [
          Config.homeModeRectFor(h).center.dx,
          Config.homeModeRectFor(h).center.dy,
        ],
        'seq': seq,
        'state': game.state.name,
        'menu': game.menuScene.name,
        'modal': game.modalPopupOpen,
        'mode': game.homeMode.name,
        'waiting': r?.waiting,
        'clock': r?.state.runClock,
        'score': r?.state.score,
        'hoops': r?.state.hoopsPassed,
        'spawned': r?.state.spawned,
        'jarCaught': r?.state.jar?.caught,
        'jarFull': r?.features.whereType<JarFeature>().firstOrNull?.fullJars,
        'jarBroken': r?.features
            .whereType<JarFeature>()
            .firstOrNull
            ?.brokenJars,
        'best': game.storage.bestScore,
        'games': game.storage.gamesPlayed,
        'hint': game.storage.firstRunHintSeen,
        'height': h,
        'music': game.sound.musicPlaying,
        'skipped': game.sound.ownMusicSkipped,
        'banner': game.runHasBanner,
        'interstitial': game.interstitialShowing,
        'noads': game.storage.noAds,
        'popup': game.noAdsPopup != null,
        'noadsShows': game.storage.noAdsPopupShowsToday,
        'canContinue': game.resultsScreen?.canContinue,
        'ringKinds': [
          for (final p in r?.spawner.hoops ?? const <Hoop>[]) p.plan.kind.name,
        ],
        'rings': [
          for (final p in r?.spawner.hoops ?? const <Hoop>[])
            {
              'x': p.frame().centre.x - (r?.state.camX ?? 0),
              'opening': p.opening,
            },
        ],
      };
      await output.writeAsString(jsonEncode(s));
    } catch (e, st) {
      debugPrint('P23QA bridge error $e $st');
    } finally {
      busy = false;
    }
  });
}
