import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../services/firebase_versus_backend.dart';
import '../services/identity.dart';
import '../services/versus_service.dart';
import 'lb_config.dart';
import 'lb_models.dart';

/// Failures (including malformed responses) are null, so callers can retry.
/// Queueing, local resets and gift application are owned by LB2/LB3.
abstract class LeaderboardService {
  Future<LbGetBoardResult?> getBoard({LbBoardTab tab = LbBoardTab.today});
  Future<LbSubmitRunResult?> submitRun(Map<String, Object?> request);
  Future<LbClaimGiftResult?> claimGift(String id, {List<String>? owned});
}

class NoopLeaderboardService implements LeaderboardService {
  const NoopLeaderboardService();
  @override
  Future<LbGetBoardResult?> getBoard({
    LbBoardTab tab = LbBoardTab.today,
  }) async => null;
  @override
  Future<LbSubmitRunResult?> submitRun(Map<String, Object?> request) async =>
      null;
  @override
  Future<LbClaimGiftResult?> claimGift(
    String id, {
    List<String>? owned,
  }) async => null;
}

typedef LbCallable =
    Future<Object?> Function(String name, Map<String, Object?> request);

/// Serializes callable requests with versus Auth changes. Timeouts only stop
/// waiting: an in-flight plugin keeps the lane until it actually settles.
/// Reentrant for the guest-account cleanup inside a versus account switch.
class LbCallSerializer {
  final Object _zoneKey = Object();
  Future<void>? _tail;

  Future<T> run<T>(Future<T> Function() operation) {
    if (Zone.current[_zoneKey] == true) return Future.sync(operation);
    Future<T> start() =>
        runZoned(() => Future.sync(operation), zoneValues: {_zoneKey: true});
    final previous = _tail;
    final result = previous == null ? start() : previous.then((_) => start());
    late final Future<void> tail;
    tail = result.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_tail, tail)) _tail = null;
    });
    _tail = tail;
    return result;
  }
}

/// Uses the existing versus startup, App Check and identity implementation.
/// Installed in main in place of its default backend, with the same lane as
/// the leaderboard. Pool searches remain independent of the callable lane.
class LeaderboardVersusBackend extends FirebaseVersusBackend {
  LeaderboardVersusBackend({required this.calls});
  final LbCallSerializer calls;

  @override
  Future<String> start() => calls.run(super.start);

  @override
  Future<void> link(
    PlatformIdentity identity, {
    Future<void> Function()? beforeSwitch,
  }) => calls.run(() => super.link(identity, beforeSwitch: beforeSwitch));

  @override
  Future<bool> deleteMyData() => calls.run(super.deleteMyData);

  @override
  Future<bool> deleteOnline() => calls.run(super.deleteOnline);
}

class FirebaseLeaderboardService implements LeaderboardService {
  FirebaseLeaderboardService({
    required this.versus,
    LbCallSerializer? calls,
    LbCallable? callable,
  }) : _calls = calls ?? LbCallSerializer(),
       _callable = callable ?? _firebaseCall;

  final VersusService versus;
  final LbCallSerializer _calls;
  final LbCallable _callable;

  static Future<Object?> _firebaseCall(
    String name,
    Map<String, Object?> request,
  ) async {
    final result =
        await FirebaseFunctions.instanceFor(region: LbConfig.functionsRegion)
            .httpsCallable(
              name,
              options: HttpsCallableOptions(timeout: LbConfig.callTimeout),
            )
            .call<Object?>(request);
    return result.data;
  }

  Future<T?> _request<T>(
    String name,
    Map<String, Object?> request,
    T Function(Map<String, Object?>) parse,
  ) async {
    var expired = false;
    try {
      return await (() async {
        // No separate anonymous sign-in or App Check activation. initialize
        // shares every startup/retry path and activation with versus.
        await versus.initialize();
        if (expired || !versus.ready) return null;
        return _calls.run<T?>(() async {
          // A request that expired waiting for auth must never execute late.
          if (expired || !versus.ready) return null;
          final data = await _callable(name, request);
          if (expired) return null;
          return parse(Map<String, Object?>.from(data as Map));
        });
      })().timeout(LbConfig.callTimeout);
    } catch (_) {
      return null;
    } finally {
      expired = true;
    }
  }

  @override
  Future<LbGetBoardResult?> getBoard({LbBoardTab tab = LbBoardTab.today}) =>
      _request(LbConfig.boardFunction, {
        'tab': tab.name,
      }, LbGetBoardResult.fromJson);

  @override
  Future<LbSubmitRunResult?> submitRun(Map<String, Object?> request) =>
      _request(LbConfig.submitFunction, request, LbSubmitRunResult.fromJson);

  @override
  Future<LbClaimGiftResult?> claimGift(String id, {List<String>? owned}) =>
      _request(
        LbConfig.claimFunction,
        LbClaimGiftRequest(id: id, owned: owned).toJson(),
        LbClaimGiftResult.fromJson,
      );
}

/// A scriptable callable transport with the production parsing, timeout and
/// error handling. Scripts may throw, delay, return JSON or return null.
class FakeLeaderboardService extends FirebaseLeaderboardService {
  FakeLeaderboardService({
    LbCallable? onCall,
    VersusService? versus,
    super.calls,
  }) : super(
         versus: versus ?? FakeVersusService(),
         callable: onCall ?? ((_, _) async => null),
       );
}
