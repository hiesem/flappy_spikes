/// The C2 Home popup priority order.
enum HomeMoment {
  streakLost,
  levelUp,
  streakReward,
  leaderboardCollect,
  missionsChest,
  starRoad,
  noAds,
  rating,
}

/// One waiting leaderboard gift box. Several may be due at once; the oldest
/// is offered first and the others stay with their source for later visits.
final class HomeGiftBoxRequest {
  const HomeGiftBoxRequest({required this.id, required this.availableAt});

  final String id;
  final DateTime availableAt;
}

/// The typed requests that can be due on one Home visit. M1 has live sources
/// for LEVEL UP, No-Ads and rating only; M3 / M4 fill in the other fields.
final class HomeVisitRequests {
  const HomeVisitRequests({
    this.streakLost = false,
    this.levelUpCatchUp = false,
    this.streakReward = false,
    this.leaderboardGifts = const [],
    this.missionsChest = false,
    this.starRoad = false,
    this.noAds = false,
    this.rating = false,
  });

  final bool streakLost;
  final bool levelUpCatchUp;
  final bool streakReward;
  final List<HomeGiftBoxRequest> leaderboardGifts;
  final bool missionsChest;
  final bool starRoad;
  final bool noAds;
  final bool rating;
}

/// One Home visit and the context needed by the C2 exceptions.
final class HomeVisit {
  const HomeVisit({
    required this.day,
    required this.gamesPlayed,
    required this.requests,
  });

  final DateTime day;
  final int gamesPlayed;
  final HomeVisitRequests requests;
}

/// Routes one eligible Home moment. Without a typed visit the M1 seam remains
/// pass-through (the existing live callers are not all available yet). Once a
/// visit is declared, at most one selected moment may open on that visit.
abstract class HomeMoments {
  const HomeMoments();

  void beginVisit(HomeVisit visit) {}

  void show(HomeMoment moment, void Function() open);
}

class PassthroughHomeMoments extends HomeMoments {
  const PassthroughHomeMoments();

  static HomeMoment? _selected;
  static HomeGiftBoxRequest? _selectedGift;
  static DateTime? _selectedDay;
  static DateTime? _starRoadShownDay;
  static bool _shownThisVisit = false;
  static bool _bounded = false;

  @override
  void beginVisit(HomeVisit visit) {
    _bounded = true;
    _shownThisVisit = false;
    _selectedDay = _calendarDay(visit.day);
    _selectedGift = null;
    _selected = _select(visit);
  }

  HomeMoment? get selectedMoment => _selected;

  @override
  void show(HomeMoment moment, void Function() open) {
    if (!_bounded) {
      open();
      return;
    }
    if (_shownThisVisit || moment != _selected) return;
    _shownThisVisit = true;
    if (moment == HomeMoment.starRoad) _starRoadShownDay = _selectedDay;
    open();
  }

  HomeMoment? _select(HomeVisit visit) {
    final requests = visit.requests;
    if (requests.streakLost) return HomeMoment.streakLost;
    if (requests.levelUpCatchUp) return HomeMoment.levelUp;
    if (requests.streakReward) return HomeMoment.streakReward;
    final gift = oldestGift(requests.leaderboardGifts);
    if (gift != null) {
      _selectedGift = gift;
      return HomeMoment.leaderboardCollect;
    }
    if (requests.missionsChest) return HomeMoment.missionsChest;
    if (requests.starRoad &&
        visit.gamesPlayed >= 3 &&
        _starRoadShownDay != _calendarDay(visit.day)) {
      return HomeMoment.starRoad;
    }
    if (requests.noAds) return HomeMoment.noAds;
    if (requests.rating) return HomeMoment.rating;
    return null;
  }

  HomeGiftBoxRequest? get selectedGift => _selectedGift;

  DateTime _calendarDay(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  HomeGiftBoxRequest? oldestGift(List<HomeGiftBoxRequest> gifts) {
    if (gifts.isEmpty) return null;
    final sorted = [...gifts]
      ..sort((a, b) {
        final byTime = a.availableAt.compareTo(b.availableAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    return sorted.first;
  }
}
