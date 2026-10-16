import 'backdrop_scene.dart';
import 'scenes/s01_nest.dart';
import 'scenes/s02_sky.dart';
import 'scenes/s03_city.dart';
import 'scenes/s04_clock.dart';
import 'scenes/s05_desk.dart';
import 'scenes/s06_candy.dart';
import 'scenes/s07_origami.dart';
import 'scenes/s08_sea.dart';
import 'scenes/s09_dream.dart';
import 'scenes/s10_space.dart';
import 'seams/seam.dart';
import 'seams/seam01_waterfall.dart';
import 'seams/seam02_crane.dart';
import 'seams/seam03_bell_rope.dart';
import 'seams/seam04_cuckoo.dart';
import 'seams/seam05_gumballs.dart';
import 'seams/seam06_book.dart';
import 'seams/seam07_dive.dart';
import 'seams/seam08_rising.dart';
import 'seams/seam09_liftoff.dart';
import 'seams/seam10_homecoming.dart';

/// PRD-2.4 §3.3 the ten scenes in story order (`FNS`). Each lives in its
/// own file under `scenes/`; fill a scene in its file, not here.
const List<BackdropScene> kScenes = [
  NestScene(),
  SkyScene(),
  CityScene(),
  ClockScene(),
  DeskScene(),
  CandyScene(),
  OrigamiScene(),
  SeaScene(),
  DreamScene(),
  SpaceScene(),
];

/// PRD-2.4 §3.3 the ten seams (`LINKS`): `kSeams[i]` joins scene i to scene
/// i + 1 (mod 10). Each lives in its own file under `seams/`.
const List<Seam> kSeams = [
  WaterfallSeam(),
  CraneSeam(),
  BellRopeSeam(),
  CuckooSeam(),
  GumballsSeam(),
  BookSeam(),
  DiveSeam(),
  RisingSeam(),
  LiftOffSeam(),
  HomecomingSeam(),
];
