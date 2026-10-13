import 'dart:async';

import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/services/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import 's15_tuning_test.dart' show FakeTuningBackend;

class DelayedActivation extends FakeTuningBackend {
  DelayedActivation() : super({});
  final gate = Completer<void>();
  @override
  Future<void> activate() async {
    await gate.future;
    await super.activate();
  }
}

void main() {
  tearDown(() {
    Tuning.instance = Tuning();
    TuningValues.current = TuningValues.defaults();
  });

  test(
    'S8-02 §15.2 delayed startup activation cannot change a begun run',
    () async {
      final backend = DelayedActivation()
        ..fetched = {'curve_speed': '[[0,222],[150,250]]'};
      final service = Tuning(backend: backend);
      // main.dart launches this unawaited, before runApp.
      final startup = service.initialize();
      service.beginRun();
      final speedAtStart = RunConfig.cruise(0);
      backend.gate.complete();
      await startup;
      await service.pendingFetch;
      expect(
        RunConfig.cruise(0),
        speedAtStart,
        reason: '§15: values never change during a run',
      );
    },
  );

  test(
    '§15 a background fetch leaves every active key and source unchanged',
    () async {
      final backend = FakeTuningBackend({})
        ..fetched = {'coin_jar': '11', 'curve_speed': 'broken'}
        ..nextFetch = {'coin_jar': '99', 'curve_speed': '[[0,999]]'};
      final service = Tuning(backend: backend);
      await service.initialize();
      service.beginRun();
      final values = TuningValues.current;
      await service.pendingFetch;
      expect(identical(TuningValues.current, values), isTrue);
      expect(values.i('coin_jar'), 11);
      expect(values.sourceOf('curve_speed'), TuningSource.rejected);
    },
  );
}
