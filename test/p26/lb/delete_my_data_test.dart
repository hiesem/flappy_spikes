import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import '../../helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/game/save_seal.dart';
import 'package:flappy_spikes/leaderboard/lb_models.dart';
import 'package:flappy_spikes/leaderboard/lb_queue.dart';
import 'package:flappy_spikes/leaderboard/lb_service.dart';
import 'package:flappy_spikes/services/obf_strings.g.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final success in [false, true]) {
    final versus = FakeVersusService()..deleteSucceeds = success;
    FlameTester<FlappySpikesGame>(() {
      SharedPreferences.setMockInitialValues({Obf.prefStreakDays: 4});
      return FlappySpikesGame(soundEnabled: false, versus: versus);
    }).testGameWidget(
      'delete confirmation clears local board only after server success=$success',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
        game.openSettings();
        await flushAndMount(game);
        await game.storage.saveLbGroupId('keep-until-server-success');
        await game.storage.saveLbGiftsClaimed({'sealed-gift'});
      },
      verify: (game, _) async {
        game.openDeleteDataConfirm();
        await flushAndMount(game);
        await game.confirmDeleteMyData();
        expect(versus.deleteCalls, 1);
        expect(
          game.storage.lbGroupId,
          success ? '' : 'keep-until-server-success',
        );
        expect(
          game.storage.lbGiftsClaimed,
          success ? isEmpty : {'sealed-gift'},
        );
        expect(game.storage.streakDays, 4);
      },
    );
  }
  for (final versusReset in [true, false]) {
    test(
      '${versusReset ? 'versus delete' : 'board resetLocal'} clears lb keys and sealed claims, keeps streak',
      () async {
        SharedPreferences.setMockInitialValues({
          Obf.prefStreakDays: 6,
          Obf.prefStreakLastDay: 123,
        });
        final sealer = MemorySaveSealer();
        final storage = GameStorage(sealer: sealer);
        await storage.load();
        await storage.saveLbQueue(['pending']);
        await storage.saveLbGroupId('group');
        await storage.saveLbGroupEnd(999);
        await storage.saveLbLastRank(2);
        await storage.saveLbGiftsClaimed({'gift'});
        await storage.saveLbGiftPending({'id': 'gift'});
        await storage.saveLbInfoSeen(true);
        if (versusReset) {
          await storage.resetVersusData();
        } else {
          await LbQueue(
            storage: storage,
            service: const NoopLeaderboardService(),
            request: (runs) => LbSubmitRunRequest(runs: runs),
          ).resetLocal();
        }
        final loaded = GameStorage(sealer: sealer);
        await loaded.load();
        expect(loaded.lbQueue, isEmpty);
        expect(loaded.lbGroupId, '');
        expect(loaded.lbGroupEnd, 0);
        expect(loaded.lbLastRank, 0);
        expect(loaded.lbGiftsClaimed, isEmpty);
        expect(loaded.sealUntrusted, false);
        expect(loaded.lbGiftPending, isEmpty);
        expect(loaded.lbInfoSeen, false);
        expect(loaded.streakDays, 6);
        expect(loaded.streakLastDay, 123);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey(Obf.prefLbGiftsClaimed), false);
      },
    );
  }
}
