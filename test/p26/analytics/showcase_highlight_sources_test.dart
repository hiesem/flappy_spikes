import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/registry.dart';
import 'package:flappy_spikes/run/pickups/comet_star.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

class _Plan extends ShowcasePlan {
  const _Plan(this.plan);
  final ShowcaseRunPlan? plan;

  @override
  ShowcaseRunPlan? atStart({
    required int gamesPlayed,
    required int seen,
    required int attempt,
    required bool forced,
  }) => plan;
}

void main() {
  for (final source in ['planned', 'organic', 'normal', 'pair']) {
    for (final id in ['portal', 'comet', 'fever']) {
      if (source == 'pair' && id == 'portal') continue;
      FlameTester<FlappySpikesGame>(() {
        SharedPreferences.setMockInitialValues({});
        return FlappySpikesGame(
          soundEnabled: false,
          showcasePlan: _Plan(
            source == 'normal'
                ? null
                : const ShowcaseRunPlan(
                    highlightId: 'portal',
                    step: 0,
                    attempt: 1,
                    portalHoops: [7],
                    cometHoops: [9],
                    feverHoops: [5],
                  ),
          ),
        )..runSeed = 7;
      }, gameSize: Vector2(320, 568)).testGameWidget(
        '$id highlight identifies its source ($source)',
        setUp: (game, _) async {
          await game.ready();
          await preloadImages(game);
        },
        verify: (game, _) async {
          final run = await startRun(game);
          final highlights = <HighlightStarted>[];
          run.events.on<HighlightStarted>(highlights.add);
          final index = source == 'organic'
              ? 30
              : switch (id) {
                  'portal' => 7,
                  'comet' => 9,
                  _ => 5,
                };
          // Planned-ahead slots are not the hoop carrying the collected star.
          run.state.hoopIndex = 80;
          if (source == 'pair' && id == 'comet') {
            final pair = Hoop(
              plan: SlotPlan(
                index: index,
                kind: HoopKindId.pair,
                element: ElementId.pair,
                trackX: 1200,
                centreY: 300,
                opening: 160,
                advance: 310,
              ),
              kind: hoopKindFor(HoopKindId.pair)!,
            );
            run.events.emit(HoopPassed(pair));
          }
          if (source == 'pair' && id == 'fever') {
            run.state.hoopIndex = index + 1;
          }
          if (id == 'comet') {
            if (source == 'pair') {
              run.events.emit(const PickupCollected(ElementId.comet, null));
            } else {
              final item = GapItemPlan(
                kind: ElementId.comet,
                trackX: 1200,
                y: 300,
              );
              run.spawner.slotLog.add(
                SlotPlan(
                  index: index,
                  kind: HoopKindId.normal,
                  element: ElementId.normalHoop,
                  trackX: 1180,
                  centreY: 300,
                  opening: 160,
                  advance: 310,
                  attached: [item],
                ),
              );
              final star = CometStar(item, run.ctx);
              run.events.emit(PickupCollected(ElementId.comet, star));
            }
          } else if (source == 'pair') {
            run.events.emit(const FeverIgnite('pair'));
          } else {
            final kind = id == 'portal' ? HoopKindId.portal : HoopKindId.fever;
            final hoop = Hoop(
              plan: SlotPlan(
                index: index,
                kind: kind,
                element: id == 'portal' ? ElementId.portal : ElementId.fever,
                trackX: 1200,
                centreY: 300,
                opening: 160,
                advance: 310,
                extra: id == 'portal' ? RideId.cannon : null,
              ),
              kind: hoopKindFor(kind)!,
            );
            run.events.emit(HoopPassed(hoop, perfect: true));
            if (id == 'portal') {
              run.features.whereType<PortalRideFeature>().single.update(0, 0);
            }
          }
          expect(highlights, hasLength(1));
          expect(highlights.single.id, id);
          expect(highlights.single.scripted, source == 'planned');
          expect(highlights.single.hoop, index);
          await flushAndMount(game);
        },
      );
    }
  }
}
