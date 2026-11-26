/// Sleeps closer than this are one block. Three hours or more stay separate.
const kSleepMergeGap = Duration(hours: 3);

/// One sleep cycle. Blocks are whole multiples of this length.
const kSleepCycle = Duration(minutes: 90);

/// A meal is placed this long before sleep, and light stops this long before
/// the next sleep.
const kMealLead = Duration(hours: 2);
