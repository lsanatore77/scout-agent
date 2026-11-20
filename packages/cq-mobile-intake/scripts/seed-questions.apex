// CQ Mobile Intake: load the default questions, their read-aloud clips and the quick-log categories.
// Run once after installing the package. Safe to run again (anything already there is skipped).
//   Developer Console > Debug > Open Execute Anonymous Window: paste this, Execute.
//   Or: sf apex run --file scripts\seed-questions.apex --target-org <alias>
CqIntakeSetup.loadDefaults();
