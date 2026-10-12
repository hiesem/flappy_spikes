// Read-only local bridge: exercises the compiled production validator, no Firebase.
const fs = require('node:fs');
const {checkRun, scoreAt} = require('../../functions/lib/timeline.js');
const runs = JSON.parse(fs.readFileSync(0, 'utf8'));
process.stdout.write(JSON.stringify(runs.map(({run, replay}) => ({
  reason: checkRun(run, run.best),
  replay: (replay ?? []).map(cs => scoreAt(run.tl, run.fl, cs)),
}))));
