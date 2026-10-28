/// The 32 entries in the approved flight guide (PRD 2.6 §934, Q16).
class GuideEntry {
  const GuideEntry(this.id, this.group, this.name, this.rule);
  final String id, group, name, rule;
  bool isMet(Set<String> met) => met.contains(id);
  String nameFor(Set<String> met) => isMet(met) ? name : '? ? ?';
  String ruleFor(Set<String> met) => isMet(met) ? rule : 'Not met yet.';
}

const flightGuideEntries = <GuideEntry>[
  GuideEntry(
    'normal_hoop',
    'HOOPS',
    'HOOP',
    'Fly through it. A clean pass, rim untouched, builds your streak.',
  ),
  GuideEntry(
    'angled_ring',
    'HOOPS',
    'TILTED RING',
    'It leans to one side. Fly through along the slant.',
  ),
  GuideEntry(
    'moving_ring',
    'HOOPS',
    'MOVING RING',
    'The dashed line shows where it moves.',
  ),
  GuideEntry(
    'bullseye',
    'HOOPS',
    'BULLSEYE',
    'Hit the centre of the target for bonus coins.',
  ),
  GuideEntry(
    'train',
    'HOOPS',
    'RING TRAIN',
    'Three rings close together. Pass all three for a bonus.',
  ),
  GuideEntry(
    'spring',
    'HOOPS',
    'SPRING RING',
    'It launches you up or down to the next hoop.',
  ),
  GuideEntry(
    'switch_ring',
    'HOOPS',
    'SWITCH RING',
    'Touch the switch first, or the ring stays shut.',
  ),
  GuideEntry(
    'pair',
    'HOOPS',
    'GIFT PAIR',
    'Two rings, two gifts. Fly through the one you want.',
  ),
  GuideEntry(
    'fever',
    'HOOPS',
    'FEVER RING',
    'Fly through clean to jump your streak to ×5 and catch fire.',
  ),
  GuideEntry(
    'lucky_spin',
    'HOOPS',
    'LUCKY SPIN',
    'Fly through to stop the wheel and win coins.',
  ),
  GuideEntry('heart', 'PICK-UPS', 'HEART', 'Catch 3 hearts for an extra life.'),
  GuideEntry(
    'star_trail',
    'PICK-UPS',
    'STAR TRAIL',
    'Catch all 8 stars for a PERFECT LINE bonus.',
  ),
  GuideEntry(
    'egg',
    'PICK-UPS',
    'EGG',
    'Carry it through 5 hoops to hatch a chick: +1 point per hoop.',
  ),
  GuideEntry(
    'piggy',
    'PICK-UPS',
    'PIGGY BANK',
    'Grab it, then catch the coins that follow.',
  ),
  GuideEntry(
    'jar',
    'PICK-UPS',
    'FIREFLY JAR',
    'Catch 20 fireflies before 3 of them escape.',
  ),
  GuideEntry(
    'feather',
    'PICK-UPS',
    'GOLDEN FEATHER',
    'Hold 3 to open the balloon bonus after a run.',
  ),
  GuideEntry(
    'puzzle_piece',
    'PICK-UPS',
    'PUZZLE PIECE',
    'Find 4 pieces to finish a picture and win coins.',
  ),
  GuideEntry(
    'shield',
    'POWER-UPS',
    'SHIELD',
    'Takes one hit for you. No timer.',
  ),
  GuideEntry(
    'big_hoops',
    'POWER-UPS',
    'BIG HOOPS',
    'Bigger golden hoops at the start of your run.',
  ),
  GuideEntry(
    'hourglass',
    'POWER-UPS',
    'HOURGLASS',
    'Slows the world down for a few seconds.',
  ),
  GuideEntry(
    'mini_bird',
    'POWER-UPS',
    'MINI BIRD',
    'Shrinks you to half size, so every ring is roomier.',
  ),
  GuideEntry(
    'coin_frenzy',
    'POWER-UPS',
    'COIN FRENZY',
    'For a few seconds every ring pays extra coins.',
  ),
  GuideEntry(
    'comet',
    'RIDES',
    'COMET',
    'Catch the star in a hoop and fly on autopilot as a comet.',
  ),
  GuideEntry(
    'portal_cannon',
    'RIDES',
    'CANNON COASTER',
    'A portal ride: shot from a cannon onto a roller-coaster.',
  ),
  GuideEntry(
    'portal_pinball',
    'RIDES',
    'PINBALL',
    'A portal ride: bounced around a giant pinball table.',
  ),
  GuideEntry(
    'portal_sea',
    'RIDES',
    'DEEP SEA',
    'A portal ride: a dive through the waves.',
  ),
  GuideEntry(
    'portal_space',
    'RIDES',
    'SPACE',
    'A portal ride: lift-off around the planets.',
  ),
  GuideEntry(
    'portal_storm',
    'RIDES',
    'STORM',
    'A portal ride: through the thunder clouds.',
  ),
  GuideEntry(
    'portal_volcano',
    'RIDES',
    'VOLCANO',
    'A portal ride: down the lava tube and out of the crater.',
  ),
  GuideEntry(
    'spikes',
    'HAZARDS',
    'SPIKES',
    'Touch the top or bottom spikes and the run is over.',
  ),
  GuideEntry(
    'saw',
    'HAZARDS',
    'SAW RING',
    'Its rim is deadly. Fly right through the middle.',
  ),
  GuideEntry(
    'squeeze',
    'HAZARDS',
    'SPIKE SQUEEZE',
    'The spike walls close in for a while. Stay in the middle.',
  ),
];

int flightGuideMetCount(Set<String> met) =>
    flightGuideEntries.where((e) => e.isMet(met)).length;
bool flightGuideHasDot(Set<String> met, int seen) =>
    flightGuideMetCount(met) > seen;
