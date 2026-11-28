/// Sleeps closer than this are one block. Three hours or more stay separate.
const kSleepMergeGap = Duration(hours: 3);

/// One sleep cycle. Blocks are whole multiples of this length.
const kSleepCycle = Duration(minutes: 90);

/// Night-sleep meal deadline: no meal at or after sleep start − this lead.
/// Light also stops this long before the next sleep. Not a fixed meal slot.
const kMealLead = Duration(hours: 2);

/// Default meal times on the mode clock (09:00, 13:00, 18:00).
const kDefaultMealMinutes = <int>[9 * 60, 13 * 60, 18 * 60];

/// How far a default meal may move for hotel arrival, hotel leave, or nap end.
const kMealShift = Duration(hours: 1);

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
