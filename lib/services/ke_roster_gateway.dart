import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/flight_schedule_input.dart';
import 'flight_schedule_link.dart';

/// Hides the roster import card until the link is turned back on.
const kShowRosterImport = false;

enum KeRosterOpenResult { opened, notInstalled, failed }

/// Opens KE Roster and accepts `jetlagguide://schedule` replies.
///
/// Cold start is [takeInitialLink]. A running app receives [incoming].
class KeRosterGateway {
  KeRosterGateway({MethodChannel? channel, this.canOpen, this.openUri})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'jetlag_guide/deep_link';
  static const waitRouteName = 'ke-roster-wait';

  /// Asks the installed roster app to send the current layover back here.
  static final Uri exportUri = Uri(
    scheme: 'keroster',
    host: 'schedule',
    path: '/export',
    queryParameters: const {'callback': 'jetlagguide://schedule'},
  );

  final MethodChannel _channel;
  final Future<bool> Function(Uri uri)? canOpen;
  final Future<bool> Function(Uri uri)? openUri;
  final _live = StreamController<FlightScheduleInput>.broadcast();
  var _bound = false;
  var _closed = false;

  Stream<FlightScheduleInput> get incoming => _live.stream;

  void bind() {
    if (_bound || _closed) return;
    _bound = true;
    _channel.setMethodCallHandler(_onCall);
  }

  Future<void> _onCall(MethodCall call) async {
    if (_closed || call.method != 'onLink' || call.arguments is! String) {
      return;
    }
    final input = FlightScheduleLink.tryParse(call.arguments as String);
    if (input == null) {
      debugPrint('Jet Lag Guide: ignored schedule link ${call.arguments}');
      return;
    }
    if (!_live.isClosed) _live.add(input);
  }

  /// Link that launched the process, if the platform stored one.
  Future<FlightScheduleInput?> takeInitialLink() async {
    try {
      final raw = await _channel.invokeMethod<String>('getInitialLink');
      if (raw == null || raw.isEmpty) return null;
      return FlightScheduleLink.tryParse(raw);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error, stack) {
      debugPrint('Jet Lag Guide: initial link failed: $error\n$stack');
      return null;
    }
  }

  Future<KeRosterOpenResult> open() async {
    try {
      final allowed = await (canOpen ?? canLaunchUrl)(exportUri);
      if (!allowed) return KeRosterOpenResult.notInstalled;
      final opened = await (openUri ?? _launch)(exportUri);
      return opened ? KeRosterOpenResult.opened : KeRosterOpenResult.failed;
    } on MissingPluginException {
      return KeRosterOpenResult.failed;
    } on PlatformException catch (error, stack) {
      debugPrint('Jet Lag Guide: KE Roster launch failed: $error\n$stack');
      return KeRosterOpenResult.failed;
    }
  }

  Future<bool> _launch(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void dispose() {
    _closed = true;
    if (_bound) _channel.setMethodCallHandler(null);
    _live.close();
  }
}
