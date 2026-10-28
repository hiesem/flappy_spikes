import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../game/storage.dart';
import '../run/config/tuning_values.dart';
import '../services/obf_strings.g.dart';
import 'star_road.dart';
import 'star_road_claims.dart';

/// Coordinates the shared UTC season and resumes interrupted automatic claims.
class StarRoadSeason {
  StarRoadSeason(this.storage, this.claims);
  final GameStorage storage;
  final StarRoadClaims claims;
  Future<void>? _inFlight;
  Map<String, dynamic>? _summary;

  int get utcDay =>
      storage.now().toUtc().millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
  int get epoch => tuning.i('star_road_epoch_day');
  int get currentSeason =>
      starRoadSeasonForDay(math.max(epoch, utcDay), epochDay: epoch);
  int get daysLeft =>
      starRoadDaysLeft(math.max(epoch, utcDay), epochDay: epoch);

  Future<void> settle() =>
      _inFlight ??= _settle().whenComplete(() => _inFlight = null);

  Future<void> _settle() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(Obf.prefStarRoadRollover);
    Map<String, dynamic>? journal = raw == null
        ? null
        : jsonDecode(raw) as Map<String, dynamic>;
    if (journal?['pending'] == true) {
      await _finish(prefs, journal!);
    } else {
      _summary = journal;
    }
    final current = currentSeason;
    if (current <= storage.starRoadSeason) return;
    final old = claims.road;
    journal = {
      'pending': true,
      'from': old.season,
      'to': current,
      'tiers': old.claimable,
      'awards': <String, Object?>{},
    };
    await prefs.setString(Obf.prefStarRoadRollover, jsonEncode(journal));
    await _finish(prefs, journal);
  }

  Future<void> _finish(
    SharedPreferences prefs,
    Map<String, dynamic> journal,
  ) async {
    final from = journal['from'] as int;
    if (storage.starRoadSeason == from) {
      for (final tier in (journal['tiers'] as List).cast<int>()) {
        await claims.claim(tier);
      }
      await storage.saveStarRoadXp(0);
      await storage.saveStarRoadClaimed({});
      await storage.saveStarRoadSeason(journal['to'] as int);
    }
    final latest = prefs.getString(Obf.prefStarRoadRollover);
    if (latest != null) journal = jsonDecode(latest) as Map<String, dynamic>;
    if (from == 0 || (journal['tiers'] as List).isEmpty) {
      await prefs.remove(Obf.prefStarRoadRollover);
    } else {
      journal['pending'] = false;
      _summary = Map.of(journal);
      await prefs.setString(Obf.prefStarRoadRollover, jsonEncode(journal));
    }
  }

  Map<String, dynamic>? takeSummary() {
    final summary = _summary;
    if (summary == null) return null;
    _summary = null;
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.remove(Obf.prefStarRoadRollover),
      ),
    );
    return summary;
  }
}
