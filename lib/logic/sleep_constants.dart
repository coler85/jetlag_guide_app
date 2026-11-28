/// Sleeps closer than this are one block. Three hours or more stay separate.
const kSleepMergeGap = Duration(hours: 3);

/// One sleep cycle. Blocks are whole multiples of this length.
const kSleepCycle = Duration(minutes: 90);

/// A meal is placed this long before sleep, and light stops this long before
/// the next sleep.
const kMealLead = Duration(hours: 2);

/// STA-to-first-sleep window that still counts as an immediate arrival sleep.
const kArrivalSleepSoon = Duration(hours: 6);

/// Hard cap on post-arrival nap cycles (3 hours).
const kNapMaxCycles = 2;

/// Nap must end at least this long before the next night sleep starts.
const kNapGapBeforeNight = kSleepMergeGap;

/// Flight overlap with the mode night at or above this is an overnight flight.
const kOvernightFlightMin = Duration(hours: 3);

/// Local clock hour when an evening departure window begins (inclusive).
const kEveningDepartureStart = 17;

/// Largest move of the body-clock night during a flight, toward the destination.
const kInflightMaxShift = Duration(hours: 3);

/// Inflight rest is not shown until this long after takeoff.
const kInflightAfterTakeoff = Duration(minutes: 30);

/// Inflight rest stops this long before landing.
const kInflightBeforeLanding = Duration(hours: 1);
