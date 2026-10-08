import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../../components/bird.dart';
import '../../../../components/spike_strip.dart';
import '../../../../game/flappy_game.dart';
import '../../../../game/sound.dart';
import '../../../config/run_config.dart';
import '../../../config/saw_config.dart';
import '../../../director/plans.dart';
import '../../../effects/particle_pool.dart';
import '../../../effects/run_shake.dart';
import '../../../effects/shock_ring.dart';
import '../../../mistakes.dart';
import '../../../run_context.dart';
import '../../../run_controller.dart';
import '../../../run_events.dart';
import '../../../run_feature.dart';
import '../../../run_layers.dart';
import '../../hoop.dart';
import '../ring_arcs.dart';
import 'saw_kind.dart';

/// The saw rings' run-side parts (PRD-2 §3.18, §5.17):
///
/// - **deaths**: on a [RunDied] by a saw rim the design's moment plays
///   ([SawDeath]: Live Wire's electrified hold, Frost Ring's ice block,
///   Black Hole's spaghettification), driving the held bird through
///   `RunController.themedPose` and its tint (`Bird.deathTint`); the
///   controller then runs the same tumble (or none: Black Hole);
/// - **approach hums**: one loop per design that fades in as a saw ring
///   approaches and out when it has passed or the bird dies (volume ∝
///   closeness², the mock's `k² × 0.8`);
/// - **lensing**: the spike strips bend toward a Black Hole on screen;
/// - **analytics**: `sawring_death` {design, used: none / extra_life /
///   shield} (spawn / pass are sent by the kind).
class SawFeature extends RunFeature {
  RunContext? _c;
  SawDeath? _death;
  final Map<SawDesign, LoopHandle> _hums = {};
  final Map<SawDesign, double> _humVolume = {};

  /// The running death moment (tests).
  SawDeath? get death => _death;

  /// Current hum volumes (tests).
  Map<SawDesign, double> get humVolumes => Map.unmodifiable(_humVolume);

  @override
  void attach(RunContext c) {
    _c = c;
    c.events
      ..on<RunDied>(_onDied)
      ..on<MistakeSaved>(_onSaved);
    _resetBird();
  }

  static SawDesign? _designOf(Mistake m) {
    final h = m.hoop;
    if (m.cause != MistakeCause.saw || h == null || h.kind is! SawHoopKind) {
      return null;
    }
    return SawHoopKind.designOf(h);
  }

  void _onSaved(MistakeSaved e) {
    final d = _designOf(e.mistake);
    if (d == null) return;
    _c?.track('sawring_death', {
      'design': SawHoopKind.storageName(d),
      'used': e.by,
    });
  }

  void _onDied(RunDied e) {
    final c = _c;
    final d = _designOf(e.mistake);
    if (c == null || d == null) return;
    c.track('sawring_death', {
      'design': SawHoopKind.storageName(d),
      'used': 'none',
    });
    _stopHums();
    _death?.removeFromParent();
    final pose = ThemedDeathPose();
    c.run.themedPose = pose;
    final death = SawDeath(c, d, e.mistake.hoop!, pose);
    _death = death;
    c.game.world.add(death);
  }

  @override
  void update(double gameDt, double realDt) {
    final c = _c;
    if (c == null) return;
    _updateHums(c);
    _updateLens(c);
  }

  // ------------------------------------------------------------- hums

  void _updateHums(RunContext c) {
    final live =
        c.game.state == GameState.playing && !c.run.dying && !c.run.ended;
    final want = <SawDesign, double>{};
    if (live) {
      final birdX = c.s.camX + RunConfig.birdX;
      const span = RunConfig.worldWidth - RunConfig.birdX + SawConfig.humAhead;
      for (final h in c.run.spawner.hoops) {
        if (h.kind is! SawHoopKind || h.look.missed) continue;
        final x = h.planeX;
        if (x < birdX - SawConfig.humBehind ||
            x > c.s.camX + RunConfig.worldWidth + SawConfig.humAhead) {
          continue;
        }
        final k = 1 - math.max(0, x - birdX) / span;
        final d = SawHoopKind.designOf(h);
        want[d] = math.max(want[d] ?? 0, k.clamp(0.0, 1.0));
      }
    }
    for (final d in SawDesign.values) {
      final k = want[d] ?? 0;
      final vol = k * k * SawConfig.humGain;
      final handle = _hums[d];
      if (vol <= 0) {
        if (handle != null) {
          handle.stop();
          _hums.remove(d);
        }
        _humVolume.remove(d);
        continue;
      }
      if (handle == null || handle.stopped) {
        _hums[d] = c.loop(_loopOf(d), volume: vol);
        _humVolume[d] = vol;
      } else if (((_humVolume[d] ?? 0) - vol).abs() > .02) {
        handle.setVolume(vol);
        _humVolume[d] = vol;
      }
    }
  }

  static SfxLoop _loopOf(SawDesign d) => switch (d) {
    SawDesign.liveWire => SfxLoop.sawWireHum,
    SawDesign.frostRing => SfxLoop.sawFrostHum,
    SawDesign.blackHole => SfxLoop.sawHoleHum,
  };

  void _stopHums() {
    for (final h in _hums.values) {
      if (!h.stopped) h.stop();
    }
    _hums.clear();
    _humVolume.clear();
  }

  // ------------------------------------------------------------- lens

  /// §5.17 the spike strips bend toward a Black Hole (strongest within
  /// ≈ 170 pt; more while it inhales); the outer edge stays fixed.
  void _updateLens(RunContext c) {
    final holes = <(Offset, double)>[];
    for (final h in c.run.spawner.hoops) {
      if (h.kind is! SawHoopKind ||
          SawHoopKind.designOf(h) != SawDesign.blackHole ||
          h.look.missed) {
        continue;
      }
      final sx = h.planeX - c.s.camX;
      if (sx < -SawConfig.lensRange ||
          sx > RunConfig.worldWidth + SawConfig.lensRange) {
        continue;
      }
      final seed = SawHoopKind.stateOf(h)?.seed ?? 0;
      holes.add((
        Offset(sx, h.position.y),
        SawConfig.lensStrength +
            SawConfig.lensHunger * SawHoopKind.hunger(c.s.runClock, seed),
      ));
    }
    Offset Function(Offset)? lens;
    if (holes.isNotEmpty) {
      lens = (p) {
        var x = p.dx, y = p.dy;
        for (final (o, k) in holes) {
          final dx = o.dx - p.dx, dy = o.dy - p.dy;
          final d = math.sqrt(dx * dx + dy * dy);
          final s = k * math.exp(-d / SawConfig.lensRange);
          x += dx * s;
          y += dy * s;
        }
        return Offset(x, y);
      };
    }
    for (final strip in c.game.world.children.whereType<SpikeStrip>()) {
      strip.lens = lens;
    }
  }

  /// Lens currently applied (tests).
  bool lensOn(FlappySpikesGame g) =>
      g.world.children.whereType<SpikeStrip>().any((s) => s.lens != null);

  // -------------------------------------------------------- lifecycle

  void _resetBird() {
    final b = _c?.game.runBird;
    if (b == null) return;
    b.deathTint = null;
    b.deathTintAmount = 0;
    if (b.isLoaded) b.lookComponent.scale = Vector2.all(1);
  }

  @override
  void onDeath(Mistake m) => _stopHums();

  @override
  void onRevive() {
    _death?.removeFromParent();
    _death = null;
    _resetBird();
  }

  @override
  void detach() {
    final c = _c;
    if (c != null) {
      c.events
        ..off<RunDied>(_onDied)
        ..off<MistakeSaved>(_onSaved);
      for (final strip in c.game.world.children.whereType<SpikeStrip>()) {
        strip.lens = null;
      }
    }
    _stopHums();
    _death?.removeFromParent();
    _death = null;
    _resetBird();
    _c = null;
  }
}

/// One saw death moment (PRD-2 §5.17), in the world (screen space) over
/// the dead bird: the held moment (driving [pose] and the bird's tint /
/// scale), then the design's afterlife while the tumble runs (Live Wire:
/// charred, smoking, twitching; Frost Ring: the ice block falls and
/// shatters on the floor spikes, the frozen bird stays; Black Hole: the
/// boom, a white shock ring, nothing left).
class SawDeath extends Component {
  SawDeath(this.c, this.design, this.hoop, this.pose)
    : super(priority: RunLayer.items);

  final RunContext c;
  final SawDesign design;
  final Hoop hoop;
  final ThemedDeathPose pose;

  /// Seconds since the hit.
  double t = 0;

  final ParticlePool pool = ParticlePool(capacity: 90);
  final RunShake _shake = RunShake();
  Offset _applied = Offset.zero;

  /// Where the bird was hit (screen) and the rim end it touched (screen).
  late Offset hitAt;
  late Offset contact;

  bool _cracked = false, _shattered = false, _swallowed = false;
  bool _twitching = false;
  double _crackleAcc = 0;

  /// Frost Ring: the block is gone (shattered on the spikes).
  bool get shattered => _shattered;

  /// Black Hole: the bird was swallowed.
  bool get swallowed => _swallowed;

  double get hold => switch (design) {
    SawDesign.liveWire => SawConfig.wireHold,
    SawDesign.frostRing => SawConfig.frostHold,
    SawDesign.blackHole => SawConfig.holeHold,
  };

  bool get held => t < hold;

  Bird? get _bird {
    final b = c.game.runBird;
    return b != null && b.isLoaded ? b : null;
  }

  Offset get _birdAt {
    final p = c.game.runBirdPosition;
    return p == null ? hitAt : Offset(p.x, p.y);
  }

  @override
  Future<void> onLoad() async {
    final p = c.game.runBirdPosition;
    hitAt = p == null
        ? Offset(RunConfig.birdX, c.viewHeight / 2)
        : Offset(p.x, p.y);
    final f = hoop.frame();
    final birdTrack = c.run.birdTrackPosition() ?? Vector2(0, 0);
    final top = f.rimEnd(0, -1), bot = f.rimEnd(0, 1);
    final e = top.distanceTo(birdTrack) < bot.distanceTo(birdTrack) ? top : bot;
    contact = Offset(e.x - c.s.camX, e.y - c.s.camY);
    switch (design) {
      case SawDesign.liveWire:
        c.sfx(Sfx.sawWireZap);
      case SawDesign.frostRing:
        c.sfx(Sfx.sawFrostCrunch);
        final r = c.cosmetic;
        for (var i = 0; i < 16; i++) {
          pool.spawn(
            shape: ParticleShape.circle,
            x: contact.dx,
            y: contact.dy,
            vx: (r.nextDouble() - .5) * 180,
            vy: (r.nextDouble() - .5) * 180,
            w: 5,
            color: const Color(0xFFE8FBFF),
            life: .5,
          );
        }
      case SawDesign.blackHole:
        c.sfx(Sfx.sawHoleRoar);
        c.sfx(Sfx.sawHoleSubdrop);
    }
  }

  @override
  void update(double dt) {
    t += dt;
    pool.step(dt);
    switch (design) {
      case SawDesign.liveWire:
        _wire(dt);
      case SawDesign.frostRing:
        _frost(dt);
      case SawDesign.blackHole:
        _hole(dt);
    }
    _shake.update(dt);
    final o = _shake.offset;
    final vf = c.game.camera.viewfinder;
    vf.position = vf.position + Vector2(o.dx - _applied.dx, o.dy - _applied.dy);
    _applied = o;
  }

  @override
  void onRemove() {
    final vf = c.game.camera.viewfinder;
    vf.position = vf.position - Vector2(_applied.dx, _applied.dy);
    _applied = Offset.zero;
    super.onRemove();
  }

  // ------------------------------------------------------------ Live Wire

  void _wire(double dt) {
    final b = _bird;
    final r = c.cosmetic;
    if (held) {
      _shake.sustain = 4;
      pose.offset.setValues(
        (r.nextDouble() - .5) * 2 * SawConfig.wireJitter,
        (r.nextDouble() - .5) * 2 * SawConfig.wireJitter,
      );
      pose.angle = (r.nextDouble() - .5) * 2 * SawConfig.wireJitterAngle;
      final xray =
          t % (SawConfig.wireXray + SawConfig.wireBright) < SawConfig.wireXray;
      if (b != null) {
        b.deathTint = xray ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
        b.deathTintAmount = xray ? 1 : .55;
      }
      _crackleAcc += dt * 9;
      if (_crackleAcc >= 1) {
        _crackleAcc -= 1;
        c.sfx(Sfx.sawWireCrackle);
      }
      return;
    }
    _shake.sustain = 0;
    pose.offset.setZero();
    if (b != null) {
      b.deathTint = const Color(0xFF141414);
      b.deathTintAmount = .82;
    }
    final at = _birdAt;
    if (r.nextDouble() < dt * 16) {
      pool.spawn(
        shape: ParticleShape.circle,
        x: at.dx,
        y: at.dy - 8,
        vx: (r.nextDouble() - .5) * 24,
        vy: -55,
        w: 10,
        color: const Color(0x99323232),
        life: 1.2,
        gravity: -20,
        scale1: 4,
      );
    }
    if (r.nextDouble() < dt * 14) {
      final a = r.nextDouble() * RingArcs.tau;
      pool.spawn(
        shape: ParticleShape.circle,
        x: at.dx + math.cos(a) * 14,
        y: at.dy + math.sin(a) * 14,
        vx: math.cos(a) * 120,
        vy: math.sin(a) * 120 - 40,
        w: 4,
        color: r.nextBool() ? const Color(0xFFFFFFFF) : SawConfig.wireCyan,
        life: .3,
        gravity: 500,
      );
    }
    final tw = (t * SawConfig.wireTwitchRate * 1.1) % 1 < .12;
    if (tw && !_twitching) c.sfx(Sfx.sawWireCrackle);
    _twitching = tw;
  }

  // ----------------------------------------------------------- Frost Ring

  void _frost(double dt) {
    final b = _bird;
    final k = math.min(1.0, t / SawConfig.frostForm);
    if (b != null) {
      b.deathTint = SawConfig.frostTint;
      b.deathTintAmount = .8 * k;
    }
    if (!_cracked && t >= SawConfig.frostCrack) {
      _cracked = true;
      c.sfx(Sfx.sawFrostCrack);
      _shake.kick(3);
    }
    final tumble = c.run.tumble;
    if (!_shattered &&
        !held &&
        tumble != null &&
        (tumble.bounces > 0 || tumble.resting)) {
      _shattered = true;
      c.sfx(Sfx.sawFrostShatter);
      _shake.kick(9);
      final at = _birdAt;
      final r = c.cosmetic;
      for (var i = 0; i < SawConfig.frostShards; i++) {
        final a = -math.pi * r.nextDouble();
        final s = 140 + r.nextDouble() * 300;
        pool.spawn(
          shape: ParticleShape.triangle,
          x: at.dx + (r.nextDouble() - .5) * 30,
          y: at.dy,
          vx: math.cos(a) * s,
          vy: math.sin(a) * s,
          w: 2 * (4 + r.nextDouble() * 8),
          color: i % 5 == 0 ? const Color(0xFFEC008C) : const Color(0xFFBFF0FF),
          life: 1 + r.nextDouble() * .6,
          gravity: 900,
          rot: r.nextDouble() * 6,
          spin: (r.nextDouble() - .5) * 20,
        );
      }
    }
  }

  // ----------------------------------------------------------- Black Hole

  void _hole(double dt) {
    final b = _bird;
    final k = math.min(1.0, t / SawConfig.holeHold);
    if (!_swallowed) {
      final e = k * k;
      pose.offset.setValues(
        (contact.dx - hitAt.dx) * e,
        (contact.dy - hitAt.dy) * e,
      );
      pose.angle += dt * (6 + 20 * k);
      _shake.blackHolePull(k);
      if (b != null) {
        b.lookComponent.scale = Vector2(
          math.max(.02, (1 + 1.6 * k) * (1 - k)),
          math.max(.02, (1 - k) * .7),
        );
        b.setSpriteOpacity(1 - .3 * k);
      }
    }
    if (!_swallowed && t >= SawConfig.holeHold) {
      _swallowed = true;
      _shake
        ..sustain = 0
        ..blackHoleBoom();
      c.sfx(Sfx.sawHoleBoom);
      c.game.world.add(
        ShockRing(priority: RunLayer.fx).play(
          contact,
          rx: 8,
          color: const Color(0xFFFFFFFF),
          length: .6,
          scaleFrom: 1,
          scaleTo: 1,
          grow: 84,
          strokeFrom: 5,
          strokeTo: 1,
        ),
      );
      if (b != null) {
        b.setSpriteOpacity(0);
        b.lookComponent.scale = Vector2.all(1);
      }
    }
  }

  // ---------------------------------------------------------------- draw

  @override
  void render(Canvas canvas) {
    pool.paint(canvas);
    switch (design) {
      case SawDesign.liveWire:
        _renderWire(canvas);
      case SawDesign.frostRing:
        _renderFrost(canvas);
      case SawDesign.blackHole:
        _renderHole(canvas);
    }
  }

  void _renderWire(Canvas canvas) {
    final at = _birdAt;
    final r = Mulberry((t * 30).floor() * 131 + 7);
    final segs = <BoltSeg>[];
    if (held) {
      RingArcs.halo(canvas, at, 48, const Color(0xFF78F0FF), .55);
      final far = Offset(
        contact.dx,
        2 * hoop.position.y - contact.dy - c.s.camY,
      );
      for (final src in [contact, far]) {
        Lightning.seg(src.dx, src.dy, at.dx, at.dy, 24, r, segs, 0);
      }
      final spikes = Paint()
        ..color = const Color(0xE6DCFFFF)
        ..strokeWidth = 1.4;
      for (var i = 0; i < 14; i++) {
        final a = i / 14 * RingArcs.tau + (r() - .5) * .3;
        final r1 = 23 + r() * 7;
        canvas.drawLine(
          at + Offset(math.cos(a) * 17, math.sin(a) * 17),
          at + Offset(math.cos(a) * r1, math.sin(a) * r1),
          spikes,
        );
      }
      // Short white flashes at the start of each X-ray beat.
      if (t % (SawConfig.wireXray + SawConfig.wireBright) < .04) {
        RingArcs.halo(canvas, at, 70, const Color(0xFFFFFFFF), .6);
      }
    } else if (!_twitching) {
      return;
    }
    final n = held ? 5 : 2;
    for (var i = 0; i < n; i++) {
      Offset e() {
        final s = (r() * 4).floor();
        final u = (r() - .5) * 30;
        return switch (s) {
          0 => at + Offset(-15, u),
          1 => at + Offset(15, u),
          2 => at + Offset(u, -15),
          _ => at + Offset(u, 15),
        };
      }

      final a = e(), b = e();
      Lightning.seg(a.dx, a.dy, b.dx, b.dy, 10, r, segs, 1);
    }
    Lightning.paint(canvas, segs, k: held ? 1.2 : .7);
    if (held &&
        t % (SawConfig.wireXray + SawConfig.wireBright) < SawConfig.wireXray) {
      _skeleton(canvas, at);
    }
  }

  /// §5.17 the white X-ray skeleton on the black silhouette.
  void _skeleton(Canvas canvas, Offset at) {
    final p = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(pose.angle);
    canvas.drawLine(const Offset(-15, 3), const Offset(3, 3), p);
    for (final x in const [-11.0, -6.0, -1.0]) {
      final path = Path()
        ..moveTo(x, -6)
        ..quadraticBezierTo(x + 3, 3, x, 12);
      canvas.drawPath(path, p);
    }
    canvas.drawCircle(
      const Offset(8, -4),
      7,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      const Offset(9.5, -6),
      2.3,
      Paint()..color = const Color(0xFF000000),
    );
    canvas.drawRect(
      const Rect.fromLTWH(5, 1, 7, 1.6),
      Paint()..color = const Color(0xFF000000),
    );
    canvas.restore();
  }

  void _renderFrost(Canvas canvas) {
    if (_shattered) return;
    final at = _birdAt;
    final k = math.min(1.0, t / SawConfig.frostForm);
    final s = .4 + .6 * k;
    final rot = held ? 0.0 : math.min(.18, (t - hold) * .6);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(rot);
    canvas.scale(s);
    const w = SawConfig.frostBlockW, h = SawConfig.frostBlockH;
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    canvas.drawRect(
      rect,
      Paint()..color = Color.fromRGBO(207, 243, 255, .3 * k + .1),
    );
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Color.fromRGBO(255, 255, 255, k);
    canvas.drawRect(rect, edge);
    canvas.drawPath(
      Path()
        ..moveTo(-22, -18)
        ..lineTo(-6, -18)
        ..moveTo(-22, -18)
        ..lineTo(-22, -4)
        ..moveTo(14, 16)
        ..lineTo(22, 8),
      edge,
    );
    if (t > SawConfig.frostCrack) {
      final u = math.min(1.0, (t - SawConfig.frostCrack) / .15);
      final r = Mulberry(hoop.plan.index * 1000 + 3);
      final crack = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFFFFFFFF);
      for (var i = 0; i < 6; i++) {
        var x = 0.0, y = 0.0, a = r() * RingArcs.tau;
        final path = Path()..moveTo(0, 0);
        final n = math.max(1, (4 * u).round());
        for (var j = 0; j < n; j++) {
          a += (r() - .5) * 1.2;
          x += math.cos(a) * 7;
          y += math.sin(a) * 6;
          path.lineTo(x, y);
        }
        canvas.drawPath(path, crack);
      }
    }
    canvas.restore();
  }

  void _renderHole(Canvas canvas) {
    final k = math.min(1.0, t / SawConfig.holeHold);
    if (!_swallowed || t < SawConfig.holeHold + .6) {
      final a = _swallowed
          ? .35 * (1 - (t - SawConfig.holeHold) / .6).clamp(0.0, 1.0)
          : .35 * k;
      RingArcs.halo(
        canvas,
        contact,
        SawConfig.holeDarkRadius,
        const Color(0xFF140028),
        a,
      );
    }
  }
}
