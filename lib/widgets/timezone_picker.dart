import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/airport_zones.dart';
import '../logic/home_base_timezone.dart';
import '../logic/jetlag_clock.dart';
import '../theme/jetlag_theme.dart';

/// One row in the timezone picker.
class TimezoneOption {
  const TimezoneOption({
    required this.id,
    required this.title,
    required this.detail,
    required this.favorite,
  });

  /// IANA id, for example `Europe/Amsterdam`.
  final String id;

  /// Korean city for a shortcut, otherwise the English city.
  final String title;

  /// IANA id when [title] is a city name. Empty when it would repeat [title].
  final String detail;

  final bool favorite;
}

/// Favorites and the remaining matches for one search.
class TimezoneSearch {
  const TimezoneSearch({required this.favorites, required this.others});

  /// Shortcut zones that match. In catalog order when the query is empty.
  final List<TimezoneOption> favorites;

  /// Every other matching zone, sorted by IANA id.
  final List<TimezoneOption> others;

  List<TimezoneOption> get all => [...favorites, ...others];
}

List<String>? _zoneIds;
Map<String, HomeBaseZone>? _favoritesById;

Map<String, HomeBaseZone> get _favorites {
  return _favoritesById ??= {for (final zone in kHomeBaseZones) zone.id: zone};
}

/// Every IANA id currently loaded from `latest_all`, sorted.
///
/// Falls back to the shortcut list when the database cannot be read.
List<String> allIanaZoneIds() {
  final cached = _zoneIds;
  if (cached != null) return cached;
  try {
    ensureJetlagTimeZones();
    final keys = tz.timeZoneDatabase.locations.keys.toList()..sort();
    if (keys.isNotEmpty) {
      _zoneIds = keys;
      return keys;
    }
  } catch (_) {}
  return [for (final zone in kHomeBaseZones) zone.id];
}

/// Zones matching [query].
///
/// An empty query lists the Korean shortcuts first, then every other loaded
/// zone. Otherwise the match is case-insensitive against the English city,
/// any part of the IANA id, and an airport code from [airportZones].
TimezoneSearch timezoneSearch(String query) {
  final q = query.trim().toLowerCase();
  final code = query.trim().toUpperCase();
  final airportHit = airportZones[code];
  final favorites = <TimezoneOption>[];
  final others = <TimezoneOption>[];

  for (final zone in kHomeBaseZones) {
    if (q.isNotEmpty && !_matches(zone.id, q, airportHit)) continue;
    favorites.add(_option(zone.id, zone));
  }
  for (final id in allIanaZoneIds()) {
    if (_favorites.containsKey(id)) continue;
    if (q.isNotEmpty && !_matches(id, q, airportHit)) continue;
    others.add(_option(id, null));
  }
  return TimezoneSearch(favorites: favorites, others: others);
}

bool _matches(String id, String query, String? airportHit) {
  if (airportHit == id) return true;
  final folded = id.toLowerCase().replaceAll('_', ' ');
  if (folded.contains(query)) return true;
  return _city(id).toLowerCase().contains(query);
}

TimezoneOption _option(String id, HomeBaseZone? favorite) {
  if (favorite != null) {
    return TimezoneOption(
      id: id,
      title: favorite.city,
      detail: id,
      favorite: true,
    );
  }
  final city = _city(id);
  return TimezoneOption(
    id: id,
    title: city.isEmpty ? id : city,
    detail: city == id ? '' : id,
    favorite: false,
  );
}

String _city(String id) {
  final slash = id.lastIndexOf('/');
  final tail = slash >= 0 ? id.substring(slash + 1) : id;
  return tail.replaceAll('_', ' ').trim();
}

/// Current UTC offset of [iana], including daylight saving at [at].
///
/// Empty when [iana] is not a loaded zone.
String timezoneOffsetLabel(String iana, {DateTime? at}) {
  final id = iana.trim();
  if (id.isEmpty) return '';
  try {
    ensureJetlagTimeZones();
    final moment = (at ?? DateTime.now()).toUtc();
    final offset = tz
        .getLocation(id)
        .timeZone(moment.millisecondsSinceEpoch)
        .offset;
    return _formatOffset(offset);
  } catch (_) {
    return '';
  }
}

String _formatOffset(Duration offset) {
  final minutes = offset.inMinutes;
  final sign = minutes < 0 ? '-' : '+';
  final abs = minutes.abs();
  final hours = abs ~/ 60;
  final mins = abs % 60;
  if (mins == 0) return 'UTC$sign$hours';
  return 'UTC$sign$hours:${mins.toString().padLeft(2, '0')}';
}

/// Closed-state label. A shortcut keeps its Korean city name.
String timezoneButtonLabel(String selected) {
  final id = selected.trim();
  final favorite = _favorites[id];
  if (favorite != null) return '${favorite.city} · ${favorite.id}';
  if (id.isEmpty) return kJetlagFallbackHomeBase;
  return id;
}

/// Searchable IANA picker used for the home base and a layover zone.
///
/// [selected] is shown even when it is missing from the loaded list, so a
/// previously stored home base never blanks the control.
class TimezonePicker extends StatelessWidget {
  const TimezonePicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.buttonKey = const ValueKey('jetlag-timezone-picker'),
  });

  final String selected;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    final offset = timezoneOffsetLabel(selected);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: JetlagTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JetlagTheme.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: buttonKey,
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? () => _open(context) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    timezoneButtonLabel(selected),
                    overflow: TextOverflow.ellipsis,
                    style: JetlagTheme.body,
                  ),
                ),
                if (offset.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(offset, style: JetlagTheme.caption),
                ],
                const SizedBox(width: 4),
                Icon(
                  Icons.unfold_more,
                  size: 20,
                  color: enabled
                      ? JetlagTheme.textSecondary
                      : JetlagTheme.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final next = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JetlagTheme.bg,
      builder: (context) => _TimezoneSearchSheet(selected: selected),
    );
    if (next == null || next == selected) return;
    onChanged(next);
  }
}

class _TimezoneSearchSheet extends StatefulWidget {
  const _TimezoneSearchSheet({required this.selected});

  final String selected;

  @override
  State<_TimezoneSearchSheet> createState() => _TimezoneSearchSheetState();
}

class _TimezoneSearchSheetState extends State<_TimezoneSearchSheet> {
  final _query = TextEditingController();
  var _text = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.92;
    final search = timezoneSearch(_text);
    final selectedId = widget.selected.trim();
    final known = {for (final option in search.all) option.id};
    final pinned =
        _text.trim().isEmpty &&
            selectedId.isNotEmpty &&
            !known.contains(selectedId)
        ? selectedId
        : '';
    final rows = <_SheetRow>[
      if (pinned.isNotEmpty) ...[
        const _SheetRow.header('현재 선택'),
        _SheetRow.zone(
          TimezoneOption(
            id: pinned,
            title: pinned,
            detail: '',
            favorite: false,
          ),
        ),
      ],
      if (_text.trim().isEmpty && search.favorites.isNotEmpty)
        const _SheetRow.header('자주 쓰는 시간대'),
      for (final option in search.favorites) _SheetRow.zone(option),
      if (_text.trim().isEmpty && search.others.isNotEmpty)
        const _SheetRow.header('모든 시간대'),
      for (final option in search.others) _SheetRow.zone(option),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const ValueKey('timezone-search'),
                controller: _query,
                autofocus: true,
                style: JetlagTheme.body,
                cursorColor: JetlagTheme.duty,
                decoration: InputDecoration(
                  hintText: '도시, 시간대, 공항 코드',
                  hintStyle: JetlagTheme.caption,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _query.clear();
                            setState(() => _text = '');
                          },
                          icon: const Icon(Icons.close, size: 18),
                        ),
                  filled: true,
                  fillColor: JetlagTheme.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: JetlagTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: JetlagTheme.border),
                  ),
                ),
                onChanged: (value) => setState(() => _text = value),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('해당하는 시간대가 없습니다', style: JetlagTheme.body),
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final option = row.option;
                        if (option == null) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              row.header!,
                              style: JetlagTheme.caption,
                            ),
                          );
                        }
                        final selected = option.id == selectedId;
                        final offset = timezoneOffsetLabel(option.id);
                        return ListTile(
                          key: ValueKey('timezone-option-${option.id}'),
                          selected: selected,
                          selectedColor: JetlagTheme.duty,
                          title: Text(option.title, style: JetlagTheme.body),
                          subtitle: option.detail.isEmpty
                              ? null
                              : Text(option.detail, style: JetlagTheme.caption),
                          trailing: offset.isEmpty
                              ? null
                              : Text(offset, style: JetlagTheme.caption),
                          onTap: () => Navigator.of(context).pop(option.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetRow {
  const _SheetRow.header(this.header) : option = null;
  const _SheetRow.zone(this.option) : header = null;

  final String? header;
  final TimezoneOption? option;
}
