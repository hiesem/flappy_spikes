/// Audit 17: the tester-tools flag. `--dart-define=FS_TESTER=true` opens
/// the debug panel (god mode, autopilot bot, RUN DEBUG, music / achievement
/// pages) in a non-debug tester build. It changes no gameplay value. The
/// production build has no define, so this is the compile-time constant
/// `false` and the tools are tree-shaken behind it (it replaced the
/// removed remote-tuning flag of PRD-2.3 §15).
const bool kTester = bool.fromEnvironment('FS_TESTER');
