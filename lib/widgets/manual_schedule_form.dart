import 'package:flutter/material.dart';

import '../data/airport_zones.dart';
import '../logic/home_base_timezone.dart';
import '../logic/jetlag_clock.dart';
import '../logic/layover_pickup.dart';
import '../models/bunk_shift.dart';
import '../models/flight_leg.dart';
import '../models/flight_schedule_input.dart';
import '../models/jetlag_schedule.dart';
import '../models/user_settings.dart';
import '../theme/jetlag_theme.dart';
import 'timezone_picker.dart';
import 'wheel_time_picker.dart';

/// Round-trip entry. Each airport time is a local wall clock, stored as UTC.
class ManualScheduleForm extends StatefulWidget {
  const ManualScheduleForm({
    super.key,
    this.timeZone = kJetlagFallbackHomeBase,
    this.referenceTimeZone = kJetlagFallbackHomeBase,
    this.settings = UserSettings.defaults,
    this.role = JetlagCrewRole.flightOps,
    this.initial,
    this.notice,
  });

  static const routeName = 'manual-schedule';

  /// Zone used until an airport code selects one.
  final String timeZone;
  final String referenceTimeZone;
  final UserSettings settings;
  final JetlagCrewRole role;

  /// A saved journey, including a return-only record from an older file.
  final FlightScheduleInput? initial;

  /// Shown when a file could not be read and the crew should type the trip.
  final String? notice;

  @override
  State<ManualScheduleForm> createState() => _ManualScheduleFormState();
}

class _LegDraft {
  _LegDraft({
    required String zone,
    required this.stdDay,
    required this.staDay,
    required this.stdTime,
    required this.staTime,
  }) : originZone = zone,
       destinationZone = zone;

  final TextEditingController flight = TextEditingController();
  final TextEditingController origin = TextEditingController();
  final TextEditingController destination = TextEditingController();
  String originZone;
  String destinationZone;
  bool originManual = false;
  bool destinationManual = false;
  DateTime stdDay;
  DateTime staDay;
  TimeOfDay stdTime;
  TimeOfDay staTime;
  BunkShift? bunk;

  void dispose() {
    flight.dispose();
    origin.dispose();
    destination.dispose();
  }
}

class _ManualScheduleFormState extends State<ManualScheduleForm> {
  late final _LegDraft _out;
  late final _LegDraft _ret;
  var _returnOriginDirty = false;
  var _fillingReturn = false;
  var _includePickup = false;
  late DateTime _pickupDay;
  late TimeOfDay _pickupTime;
  DateTime? _showupUtc;
  var _showupManual = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final zone = _knownZone(widget.timeZone, widget.referenceTimeZone);
    final today = _today(widget.referenceTimeZone);
    _out = _LegDraft(
      zone: zone,
      stdDay: today.add(const Duration(days: 1)),
      staDay: today.add(const Duration(days: 2)),
      stdTime: const TimeOfDay(hour: 10, minute: 0),
      staTime: const TimeOfDay(hour: 18, minute: 0),
    );
    _ret = _LegDraft(
      zone: zone,
      stdDay: today.add(const Duration(days: 3)),
      staDay: today.add(const Duration(days: 4)),
      stdTime: const TimeOfDay(hour: 10, minute: 0),
      staTime: const TimeOfDay(hour: 18, minute: 0),
    );
    _pickupDay = today.add(const Duration(days: 2));
    _pickupTime = const TimeOfDay(hour: 15, minute: 0);
    _applyInitial(widget.initial);
  }

  @override
  void dispose() {
    _out.dispose();
    _ret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showup = _showupInstant();
    final leave = showup == null ? null : widget.settings.departHomeUtc(showup);
    final wake = showup == null
        ? null
        : widget.settings.wakeForShowupUtc(showup);
    return Scaffold(
      key: const ValueKey('manual-schedule-form'),
      backgroundColor: JetlagTheme.bg,
      appBar: AppBar(title: const Text('스케줄 직접 입력')),
      body: ListView(
        key: const ValueKey('manual-schedule-scroll'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (widget.notice != null) ...[
            _notice(widget.notice!),
            const SizedBox(height: 16),
          ],
          const Text(
            '각 시각은 그 공항의 현지 시각입니다. 저장할 때 UTC로 바꿉니다.',
            style: JetlagTheme.caption,
          ),
          const SizedBox(height: 16),
          _legSection(
            title: '가는 편',
            leg: _out,
            flightKey: const ValueKey('manual-out-flight'),
            originKey: const ValueKey('manual-out-origin'),
            destinationKey: const ValueKey('manual-out-destination'),
            stdKey: const ValueKey('manual-out-std'),
            staKey: const ValueKey('manual-out-sta'),
            bunkKey: const ValueKey('manual-bunk-out'),
            originZoneKey: const ValueKey('manual-zone-out-origin'),
            destinationZoneKey: const ValueKey('manual-zone-out-destination'),
            onOrigin: (value) =>
                _onAirport(leg: _out, raw: value, origin: true),
            onDestination: _onOutboundDestination,
          ),
          const SizedBox(height: 20),
          _legSection(
            title: '오는 편',
            leg: _ret,
            flightKey: const ValueKey('manual-ret-flight'),
            originKey: const ValueKey('manual-ret-origin'),
            destinationKey: const ValueKey('manual-ret-destination'),
            stdKey: const ValueKey('manual-ret-std'),
            staKey: const ValueKey('manual-ret-sta'),
            bunkKey: const ValueKey('manual-bunk-ret'),
            originZoneKey: const ValueKey('manual-zone-ret-origin'),
            destinationZoneKey: const ValueKey('manual-zone-ret-destination'),
            onOrigin: (value) {
              if (!_fillingReturn) _returnOriginDirty = true;
              _onAirport(leg: _ret, raw: value, origin: true);
            },
            onDestination: (value) =>
                _onAirport(leg: _ret, raw: value, origin: false),
          ),
          const SizedBox(height: 8),
          _showupSection(showup),
          if (leave != null && wake != null) ...[
            const SizedBox(height: 4),
            Text(
              '기상 ${_clock(wake)}',
              key: const ValueKey('manual-home-wake'),
              style: JetlagTheme.body,
            ),
            Text(
              '집 출발 ${_clock(leave)}',
              key: const ValueKey('manual-home-leave'),
              style: JetlagTheme.body,
            ),
            Text(
              '홈베이스 시각 · 기상 = 쇼업 − 이동 − 준비, 집 출발 = 쇼업 − 이동',
              style: JetlagTheme.micro,
            ),
          ],
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('레이오버 현지 픽업', style: JetlagTheme.body),
            subtitle: Text(_place(_layoverCode()), style: JetlagTheme.caption),
            value: _includePickup,
            onChanged: (value) => setState(() => _includePickup = value),
          ),
          if (_includePickup) ...[
            _WhenRow(
              rowKey: const ValueKey('manual-layover-pickup'),
              label: '픽업',
              place: _place(_layoverCode()),
              value: _stamp(_pickupDay, _pickupTime),
              note: _leadNote(_leadMinutes()),
              noteKey: const ValueKey('manual-layover-lead'),
              onTap: () => _pickWhen(
                day: _pickupDay,
                time: _pickupTime,
                apply: (day, time) => setState(() {
                  _pickupDay = day;
                  _pickupTime = time;
                }),
              ),
            ),
            if (_leadMinutes() != null) _leadStepper(_leadMinutes()!),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const ValueKey('manual-error'),
              style: JetlagTheme.caption.copyWith(color: JetlagTheme.debt),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            key: const ValueKey('manual-save'),
            onPressed: _submit,
            child: const Text('타임라인에 반영'),
          ),
        ),
      ),
    );
  }

  Widget _legSection({
    required String title,
    required _LegDraft leg,
    required Key flightKey,
    required Key originKey,
    required Key destinationKey,
    required Key stdKey,
    required Key staKey,
    required Key bunkKey,
    required Key originZoneKey,
    required Key destinationZoneKey,
    required ValueChanged<String> onOrigin,
    required ValueChanged<String> onDestination,
  }) {
    final originCode = _airport(leg.origin);
    final destinationCode = _airport(leg.destination);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: JetlagTheme.title),
        const SizedBox(height: 8),
        _field(
          key: flightKey,
          controller: leg.flight,
          label: '편명',
          hint: 'XX000',
          requiredField: false,
        ),
        const SizedBox(height: 12),
        _field(
          key: originKey,
          controller: leg.origin,
          label: '출발 공항',
          hint: 'ICN',
          onChanged: onOrigin,
        ),
        _zoneLine(
          code: originCode,
          zone: leg.originZone,
          manual: leg.originManual,
          buttonKey: originZoneKey,
          onChanged: (zone) => setState(() {
            leg.originZone = zone;
            leg.originManual = true;
          }),
        ),
        const SizedBox(height: 12),
        _field(
          key: destinationKey,
          controller: leg.destination,
          label: '도착 공항',
          hint: 'AMS',
          onChanged: onDestination,
        ),
        _zoneLine(
          code: destinationCode,
          zone: leg.destinationZone,
          manual: leg.destinationManual,
          buttonKey: destinationZoneKey,
          onChanged: (zone) => setState(() {
            leg.destinationZone = zone;
            leg.destinationManual = true;
          }),
        ),
        _WhenRow(
          rowKey: stdKey,
          label: '출발 STD',
          place: _place(originCode),
          value: _stamp(leg.stdDay, leg.stdTime),
          onTap: () => _pickWhen(
            day: leg.stdDay,
            time: leg.stdTime,
            apply: (day, time) => setState(() {
              leg.stdDay = day;
              leg.stdTime = time;
            }),
          ),
        ),
        _WhenRow(
          rowKey: staKey,
          label: '도착 STA',
          place: _place(destinationCode),
          value: _stamp(leg.staDay, leg.staTime),
          onTap: () => _pickWhen(
            day: leg.staDay,
            time: leg.staTime,
            apply: (day, time) => setState(() {
              leg.staDay = day;
              leg.staTime = time;
            }),
          ),
        ),
        const SizedBox(height: 4),
        Text('$title 벙크', style: JetlagTheme.caption),
        const SizedBox(height: 8),
        _bunkPicker(bunkKey, leg),
      ],
    );
  }

  Widget _zoneLine({
    required String? code,
    required String zone,
    required bool manual,
    required Key buttonKey,
    required ValueChanged<String> onChanged,
  }) {
    if (code != null && !manual) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('$code 시간대 · $zone', style: JetlagTheme.caption),
      );
    }
    if (!manual) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TimezonePicker(
        buttonKey: buttonKey,
        selected: zone,
        onChanged: onChanged,
      ),
    );
  }

  Widget _bunkPicker(Key key, _LegDraft leg) {
    final shifts = BunkShift.forRole(widget.role);
    final selected = leg.bunk != null && leg.bunk!.role == widget.role
        ? leg.bunk!
        : null;
    return SegmentedButton<BunkShift>(
      key: key,
      showSelectedIcon: false,
      emptySelectionAllowed: true,
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      segments: [
        for (final shift in shifts)
          ButtonSegment<BunkShift>(value: shift, label: Text(shift.label)),
      ],
      selected: selected == null ? const <BunkShift>{} : {selected},
      onSelectionChanged: (next) => setState(() {
        leg.bunk = next.isEmpty ? null : next.first;
      }),
    );
  }

  Widget _showupSection(DateTime? showup) {
    final lead = widget.settings.normalized().homeShowupLead.inMinutes;
    final place = '홈베이스';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WhenRow(
          rowKey: const ValueKey('manual-home-showup'),
          label: '홈베이스 쇼업',
          place: place,
          value: showup == null ? '가는 편 출발 후 계산' : _clock(showup),
          onTap: showup == null
              ? () {}
              : () => _pickWhen(
                  day: _dayInHome(showup),
                  time: _timeInHome(showup),
                  apply: (day, time) => setState(() {
                    _showupUtc = _instant(widget.referenceTimeZone, day, time);
                    _showupManual = true;
                  }),
                ),
        ),
        Text(
          _showupManual ? '직접 입력' : '자동 · 출발 $lead분 전',
          style: JetlagTheme.caption,
        ),
        if (_showupManual)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('manual-home-revert'),
              onPressed: () => setState(() {
                _showupManual = false;
                _showupUtc = null;
              }),
              child: const Text('자동으로 되돌리기'),
            ),
          ),
      ],
    );
  }

  Widget _notice(String text) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: JetlagTheme.elevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JetlagTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          text,
          key: const ValueKey('manual-schedule-notice'),
          style: JetlagTheme.body,
        ),
      ),
    );
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String hint,
    bool requiredField = true,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      key: key,
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      style: JetlagTheme.body,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: requiredField ? label : '$label (선택)',
        hintText: hint,
        labelStyle: JetlagTheme.caption,
        hintStyle: JetlagTheme.micro,
        filled: true,
        fillColor: JetlagTheme.elevated,
        enabledBorder: _border(JetlagTheme.border),
        focusedBorder: _border(JetlagTheme.duty),
      ),
    );
  }

  OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color),
    );
  }

  void _onAirport({
    required _LegDraft leg,
    required String raw,
    required bool origin,
  }) {
    final code = _airportText(raw);
    if (code == null) {
      setState(() {});
      return;
    }
    final resolved = zoneForAirport(code);
    setState(() {
      if (origin) {
        if (resolved != null) {
          leg.originZone = resolved;
          leg.originManual = false;
        } else {
          leg.originManual = true;
        }
      } else if (resolved != null) {
        leg.destinationZone = resolved;
        leg.destinationManual = false;
      } else {
        leg.destinationManual = true;
      }
    });
  }

  void _onOutboundDestination(String raw) {
    _onAirport(leg: _out, raw: raw, origin: false);
    if (_returnOriginDirty) return;
    setState(() {
      _fillingReturn = true;
      _ret.origin.text = raw;
      _ret.originZone = _out.destinationZone;
      _ret.originManual = _out.destinationManual;
      _fillingReturn = false;
    });
  }

  DateTime? _showupInstant() {
    if (_showupManual && _showupUtc != null) return _showupUtc!.toUtc();
    if (!_started(_out, false)) return null;
    final std = _tryInstant(_out.originZone, _out.stdDay, _out.stdTime);
    if (std == null) return null;
    return std.subtract(widget.settings.normalized().homeShowupLead);
  }

  DateTime? _tryInstant(String zone, DateTime day, TimeOfDay time) {
    try {
      return _instant(zone, day, time);
    } catch (_) {
      return null;
    }
  }

  DateTime _instant(String zone, DateTime day, TimeOfDay time) {
    return zonedUtc(
      iana: zone,
      year: day.year,
      month: day.month,
      day: day.day,
      hour: time.hour,
      minute: time.minute,
    );
  }

  String _clock(DateTime utc) {
    final home = widget.referenceTimeZone;
    return '${formatHm(utc, home)} ${zoneAbbreviation(utc, home)}';
  }

  DateTime _dayInHome(DateTime utc) {
    final wall = wallClock(utc, widget.referenceTimeZone);
    return DateTime(wall.year, wall.month, wall.day);
  }

  TimeOfDay _timeInHome(DateTime utc) {
    final wall = wallClock(utc, widget.referenceTimeZone);
    return TimeOfDay(hour: wall.hour, minute: wall.minute);
  }

  String _stamp(DateTime day, TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '${day.month}월 ${day.day}일 · $hour:$minute';
  }

  String _place(String? code) {
    if (code == null || code.isEmpty) return '현지 시각';
    return '$code 현지';
  }

  String? _layoverCode() {
    return _airport(_out.destination) ?? _airport(_ret.origin);
  }

  /// Return departure, when the return leg is a real flight.
  DateTime? _returnDepartureUtc() {
    if (!_started(_ret, true)) return null;
    final std = _tryInstant(_ret.originZone, _ret.stdDay, _ret.stdTime);
    final sta = _tryInstant(_ret.destinationZone, _ret.staDay, _ret.staTime);
    if (std == null || sta == null || !sta.isAfter(std)) return null;
    return std;
  }

  int? _leadMinutes() {
    final departure = _returnDepartureUtc();
    if (departure == null) return null;
    final pickup = _tryInstant(_layoverZone(), _pickupDay, _pickupTime);
    if (pickup == null) return null;
    return pickupLeadMinutes(departure, pickup);
  }

  String? _leadNote(int? minutes) {
    if (minutes == null) return null;
    return '오는 편 ${pickupRelativeToDeparture(minutes)}';
  }

  void _applyLead(int minutes) {
    final departure = _returnDepartureUtc();
    if (departure == null) return;
    final pickup = pickupUtcFromLead(departure, minutes);
    final split = _split(pickup, _layoverZone());
    setState(() {
      _pickupDay = split.$1;
      _pickupTime = split.$2;
    });
  }

  Widget _leadStepper(int minutes) {
    return Row(
      key: const ValueKey('manual-layover-lead-step'),
      children: [
        IconButton(
          onPressed: minutes <= 0
              ? null
              : () => _applyLead(stepPickupLead(minutes, -1)),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Expanded(
          child: Text(
            pickupRelativeToDeparture(minutes),
            textAlign: TextAlign.center,
            style: JetlagTheme.body,
          ),
        ),
        IconButton(
          onPressed: minutes >= pickupLeadMaxMinutes
              ? null
              : () => _applyLead(stepPickupLead(minutes, 1)),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  String? _airport(TextEditingController controller) =>
      _airportText(controller.text);

  String? _airportText(String raw) {
    final code = raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^[A-Z]{3,4}$').hasMatch(code)) return null;
    return code;
  }

  Future<void> _pickWhen({
    required DateTime day,
    required TimeOfDay time,
    required void Function(DateTime day, TimeOfDay time) apply,
  }) async {
    final today = DateTime.now();
    final pickedDay = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 2),
      helpText: '날짜',
      cancelText: '취소',
      confirmText: '완료',
      builder: (context, child) {
        return Theme(data: JetlagTheme.material, child: child!);
      },
    );
    if (pickedDay == null || !mounted) return;
    final pickedTime = await showWheelTimePicker(
      context: context,
      initial: time,
    );
    if (pickedTime == null) return;
    apply(DateTime(pickedDay.year, pickedDay.month, pickedDay.day), pickedTime);
  }

  void _submit() {
    final outbound = _readLeg(_out, '가는 편');
    if (_error != null && outbound == null && _started(_out, false)) return;
    final returning = _readLeg(_ret, '오는 편');
    if (outbound == null && returning == null) {
      if (_error == null) _fail('가는 편 또는 오는 편을 입력해 주세요.');
      return;
    }
    if (_error != null) return;

    DateTime? pickup;
    if (_includePickup) {
      pickup = _tryInstant(_layoverZone(), _pickupDay, _pickupTime);
      if (pickup == null) {
        _fail('픽업 시간대를 확인한 뒤 다시 저장해 주세요.');
        return;
      }
    }

    Navigator.pop(
      context,
      FlightScheduleInput.journey(
        outbound: outbound,
        returning: returning,
        homeShowup: _showupManual ? _showupUtc : null,
        layoverPickup: pickup,
        crewRole: widget.role,
        referenceTimeZone: widget.referenceTimeZone,
        outboundBunk: _keptBunk(_out.bunk),
        returnBunk: _keptBunk(_ret.bunk),
      ),
    );
  }

  FlightLeg? _readLeg(_LegDraft leg, String name) {
    final started = _started(leg, identical(leg, _ret));
    if (!started) {
      _error = null;
      return null;
    }
    final origin = _airport(leg.origin);
    final destination = _airport(leg.destination);
    final flight = leg.flight.text.trim().toUpperCase();
    if (origin == null || destination == null) {
      _fail('$name의 출발·도착 공항은 영문 3~4자로 입력해 주세요.');
      return null;
    }
    if (flight.isNotEmpty && !RegExp(r'^[A-Z0-9]{2,8}$').hasMatch(flight)) {
      _fail('편명은 영문과 숫자 2~8자로 입력해 주세요.');
      return null;
    }
    final std = _tryInstant(leg.originZone, leg.stdDay, leg.stdTime);
    final sta = _tryInstant(leg.destinationZone, leg.staDay, leg.staTime);
    if (std == null || sta == null) {
      _fail('$name 시간대를 확인한 뒤 다시 저장해 주세요.');
      return null;
    }
    if (!sta.isAfter(std)) {
      _fail('$name 도착(STA)은 출발(STD) 이후여야 합니다.');
      return null;
    }
    _error = null;
    return FlightLeg(
      flightNumber: flight,
      origin: origin,
      destination: destination,
      originTimeZone: leg.originZone,
      destinationTimeZone: leg.destinationZone,
      std: std,
      sta: sta,
    );
  }

  bool _started(_LegDraft leg, bool returning) {
    if (leg.flight.text.trim().isNotEmpty) return true;
    if (_airport(leg.destination) != null) return true;
    if (!returning && _airport(leg.origin) != null) return true;
    if (returning && _returnOriginDirty && _airport(leg.origin) != null) {
      return true;
    }
    return false;
  }

  String _layoverZone() {
    final code = _layoverCode();
    final fromOut = code == null ? null : zoneForAirport(code);
    return fromOut ?? _out.destinationZone;
  }

  BunkShift? _keptBunk(BunkShift? bunk) {
    if (bunk != null && bunk.role == widget.role) return bunk;
    return null;
  }

  void _fail(String message) => setState(() => _error = message);

  void _applyInitial(FlightScheduleInput? initial) {
    if (initial == null) return;
    final outbound = initial.outbound;
    final returning = initial.returning;
    if (outbound != null) _fillLeg(_out, outbound);
    if (returning != null) {
      _fillLeg(_ret, returning);
      final outDest = _airport(_out.destination);
      final retOrigin = _airport(_ret.origin);
      _returnOriginDirty = outDest == null || outDest != retOrigin;
    }
    if (initial.homeShowupUtc != null) {
      _showupManual = true;
      _showupUtc = initial.homeShowupUtc;
    }
    final pickup = initial.layoverPickupUtc;
    if (pickup != null) {
      _includePickup = true;
      final split = _split(pickup, _layoverZone());
      _pickupDay = split.$1;
      _pickupTime = split.$2;
    }
    final outBunk = initial.outboundBunk;
    final retBunk = initial.returnBunk;
    if (outBunk != null && outBunk.role == widget.role) _out.bunk = outBunk;
    if (retBunk != null && retBunk.role == widget.role) _ret.bunk = retBunk;
  }

  void _fillLeg(_LegDraft leg, FlightLeg flight) {
    leg.flight.text = flight.flightNumber;
    leg.origin.text = flight.origin;
    leg.destination.text = flight.destination;
    leg.originZone = _knownZone(flight.originTimeZone, leg.originZone);
    leg.destinationZone = _knownZone(
      flight.destinationTimeZone,
      leg.destinationZone,
    );
    final originCode = _airport(leg.origin);
    final destinationCode = _airport(leg.destination);
    leg.originManual = _manualZone(originCode, leg.originZone);
    leg.destinationManual = _manualZone(destinationCode, leg.destinationZone);
    final std = _split(flight.stdUtc, leg.originZone);
    final sta = _split(flight.staUtc, leg.destinationZone);
    leg.stdDay = std.$1;
    leg.stdTime = std.$2;
    leg.staDay = sta.$1;
    leg.staTime = sta.$2;
  }

  bool _manualZone(String? code, String zone) {
    if (code == null) return false;
    final resolved = zoneForAirport(code);
    if (resolved == null) return true;
    return resolved != zone;
  }

  (DateTime, TimeOfDay) _split(DateTime utc, String zone) {
    try {
      final wall = wallClock(utc, zone);
      return (
        DateTime(wall.year, wall.month, wall.day),
        TimeOfDay(hour: wall.hour, minute: wall.minute),
      );
    } catch (_) {
      final plain = utc.toUtc();
      return (
        DateTime(plain.year, plain.month, plain.day),
        TimeOfDay(hour: plain.hour, minute: plain.minute),
      );
    }
  }

  DateTime _today(String zone) {
    try {
      final wall = wallClock(DateTime.now().toUtc(), zone);
      return DateTime(wall.year, wall.month, wall.day);
    } catch (_) {
      final now = DateTime.now().toUtc();
      return DateTime(now.year, now.month, now.day);
    }
  }

  String _knownZone(String zone, String fallback) {
    final trimmed = zone.trim();
    if (trimmed.isEmpty) return fallback;
    try {
      wallClock(DateTime.now().toUtc(), trimmed);
      return trimmed;
    } catch (_) {
      return fallback;
    }
  }
}

class _WhenRow extends StatelessWidget {
  const _WhenRow({
    required this.rowKey,
    required this.label,
    required this.place,
    required this.value,
    this.note,
    this.noteKey,
    required this.onTap,
  });

  final Key rowKey;
  final String label;
  final String place;
  final String value;
  final String? note;
  final Key? noteKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: rowKey,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: JetlagTheme.body),
            Text(place, style: JetlagTheme.caption),
            const SizedBox(height: 2),
            Text(value, style: JetlagTheme.localClock),
            if (note != null) ...[
              const SizedBox(height: 2),
              Text(note!, key: noteKey, style: JetlagTheme.caption),
            ],
          ],
        ),
      ),
    );
  }
}
