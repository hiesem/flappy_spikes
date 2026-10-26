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

/// Routes one eligible Home moment. [PassthroughHomeMoments] is the inert
/// test seam; production uses [HomeMomentBudget], whose visit state belongs
/// to that policy instance (and therefore to the player's game).
abstract class HomeMoments {
  const HomeMoments();

  void beginVisit(HomeVisit visit) {}

  void show(HomeMoment moment, void Function() open);

  /// An explicit debug-panel force. Custom routing seams still observe it;
  /// production bypasses the automatic popup budget without changing it.
  void showDebug(HomeMoment moment, void Function() open) => show(moment, open);

  /// [show], but tells the caller whether [open] ran. Custom policies that do
  /// not need the answer keep the old [show]-only contract (the default here
  /// treats an invocation as opened).
  bool tryShow(HomeMoment moment, void Function() open) {
    show(moment, open);
    return true;
  }
}

/// The original no-state seam: it deliberately opens every request. Kept
/// const for the M1 skeleton and for injected tests that want no budget.
class PassthroughHomeMoments extends HomeMoments {
  const PassthroughHomeMoments();

  @override
  void show(HomeMoment moment, void Function() open) => open();

  @override
  bool tryShow(HomeMoment moment, void Function() open) {
    open();
    return true;
  }
}

/// The C2 budget used by production: at most one big game popup per Home
/// visit. All visit / day state is owned by this instance; a second game or
/// policy can never overwrite it. A request that is not selected stays with
/// its live source and can be offered on a later [beginVisit].
class HomeMomentBudget extends HomeMoments {
  HomeMomentBudget();

  HomeMoment? _selected;
  HomeGiftBoxRequest? _selectedGift;
  DateTime? _selectedDay;
  DateTime? _starRoadShownDay;
  bool _shownThisVisit = false;
  bool _visitActive = false;

  /// The moment selected for the current visit (tests / diagnostics).
  HomeMoment? get selectedMoment => _selected;

  /// The oldest gift selected for a leaderboard GO TO COLLECT visit.
  HomeGiftBoxRequest? get selectedGift => _selectedGift;

  /// Whether a typed Home visit has been declared on this instance.
  bool get visitActive => _visitActive;

  @override
  void beginVisit(HomeVisit visit) {
    _visitActive = true;
    _shownThisVisit = false;
    _selectedDay = _calendarDay(visit.day);
    _selectedGift = null;
    _selected = _select(visit);
  }

  @override
  void showDebug(HomeMoment moment, void Function() open) => open();

  @override
  void show(HomeMoment moment, void Function() open) {
    tryShow(moment, open);
  }

  @override
  bool tryShow(HomeMoment moment, void Function() open) {
    if (!_visitActive) {
      open();
      return true;
    }
    if (_shownThisVisit) return false;
    // Rating becomes due on the results page, after the Home visit started.
    // It has no higher-priority peer there (those are gathered at the
    // arrival), so an otherwise empty visit may still offer it. Once any
    // moment has been selected, the C2 priority remains strict.
    if (moment != _selected && _selected != null) return false;
    _shownThisVisit = true;
    _selected = moment;
    if (moment == HomeMoment.starRoad) _starRoadShownDay = _selectedDay;
    open();
    return true;
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
