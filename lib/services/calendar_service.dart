import 'package:flutter/foundation.dart';
import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/booking.dart';

/// Service voor het synchroniseren van boekingen met de device-kalender
/// (Apple Calendar / Google Calendar).
///
/// Twee modi:
/// 1. **Handmatig** – gebruiker tikt "Toevoegen aan agenda" in de sessie-acties.
/// 2. **Auto-sync** – na elke bevestigde boeking wordt het event automatisch
///    toegevoegd als de gebruiker dit heeft ingeschakeld.
class CalendarService {
  CalendarService._();
  static final CalendarService instance = CalendarService._();

  static const _kAutoSyncKey = 'gymies_calendar_auto_sync';
  static const _kTrainerAutoSyncKey = 'gymies_trainer_calendar_auto_sync';

  // ── Auto-sync voorkeur ──────────────────────────────────────

  /// Of auto-sync is ingeschakeld (opgeslagen in SharedPreferences).
  Future<bool> isAutoSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoSyncKey) ?? false;
  }

  /// Schakel auto-sync in of uit (client).
  Future<void> setAutoSync(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoSyncKey, enabled);
  }

  /// Of auto-sync is ingeschakeld voor trainers.
  Future<bool> isTrainerAutoSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kTrainerAutoSyncKey) ?? false;
  }

  /// Schakel auto-sync in of uit (trainer).
  Future<void> setTrainerAutoSync(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTrainerAutoSyncKey, enabled);
  }

  // ── Event aanmaken ──────────────────────────────────────────

  /// Voegt een enkele boeking toe aan de device-kalender.
  /// Toont het native "Add to Calendar" dialoog van het OS.
  ///
  /// Returns `true` als het event succesvol is aangemaakt (of het dialoog
  /// werd getoond – we kunnen niet garanderen dat de gebruiker bevestigde).
  Future<bool> addBookingToCalendar(Booking booking) async {
    try {
      final event = _buildEvent(booking);
      final result = await Add2Calendar.addEvent2Cal(event);
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[CalendarService] Fout bij toevoegen aan kalender: $e');
      return false;
    }
  }

  /// Bouwt een kalender-event van een Booking model.
  ///
  /// Titel format: "Gymies sessie – [Trainer Naam]"
  /// Als er een pakketnaam is: "Gymies – [Pakket] bij [Trainer]"
  Event _buildEvent(Booking booking) {
    // ── Titel ──
    final trainerName = booking.trainerName.isNotEmpty
        ? booking.trainerName
        : 'Trainer';
    final packageLabel = booking.packageName?.isNotEmpty == true
        ? booking.packageName!
        : null;
    final sessionLabel = booking.sessionType?.isNotEmpty == true
        ? _formatSessionType(booking.sessionType!)
        : null;

    // Prioriteit: pakket > sessietype > generiek
    final String title;
    if (packageLabel != null) {
      title = 'Gymies – $packageLabel bij $trainerName';
    } else if (sessionLabel != null) {
      title = 'Gymies $sessionLabel – $trainerName';
    } else {
      title = 'Gymies sessie – $trainerName';
    }

    // ── Tijden ──
    final start = booking.scheduledAt;
    final end = start.add(Duration(minutes: booking.durationMinutes));

    // ── Beschrijving ──
    final descParts = <String>[
      'Trainer: $trainerName',
      if (packageLabel != null) 'Pakket: $packageLabel',
      if (sessionLabel != null) 'Type: $sessionLabel',
      'Duur: ${booking.durationMinutes} minuten',
      '',
      'Geboekt via Gymies',
    ];
    if (booking.id.isNotEmpty) {
      descParts.add('Boeking #${booking.id}');
    }

    return Event(
      title: title,
      description: descParts.join('\n'),
      startDate: start,
      endDate: end,
      iosParams: const IOSParams(
        reminder: Duration(minutes: 30),
      ),
      androidParams: const AndroidParams(
        emailInvites: [],
      ),
    );
  }

  /// Maakt sessie-type leesbaar voor in de kalender-titel.
  /// "1-op-1" → "1-op-1", "duo" → "Duo sessie", "groepsles" → "Groepsles"
  String _formatSessionType(String type) {
    switch (type.toLowerCase()) {
      case 'duo':
        return 'Duo sessie';
      case 'groepsles':
      case 'group':
        return 'Groepsles';
      case '1-op-1':
      case '1op1':
      case 'personal':
        return 'Personal Training';
      default:
        // Capitalize eerste letter
        return type.isNotEmpty
            ? '${type[0].toUpperCase()}${type.substring(1)}'
            : type;
    }
  }

  // ── Trainer: event aanmaken ─────────────────────────────────

  /// Voegt een boeking toe aan de trainer's device-kalender.
  /// Gebruikt een trainer-perspectief titel: "Gymies sessie – [Klant Naam]"
  Future<bool> addBookingToTrainerCalendar(Booking booking) async {
    try {
      final event = _buildTrainerEvent(booking);
      final result = await Add2Calendar.addEvent2Cal(event);
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[CalendarService] Trainer kalender fout: $e');
      return false;
    }
  }

  /// Bouwt een kalender-event vanuit trainer-perspectief.
  ///
  /// Titel format: "Gymies sessie – [Klant Naam]"
  /// Als er een pakketnaam is: "Gymies – [Pakket] met [Klant]"
  Event _buildTrainerEvent(Booking booking) {
    final clientName = (booking.clientName?.isNotEmpty == true)
        ? booking.clientName!
        : 'Klant';
    final packageLabel = booking.packageName?.isNotEmpty == true
        ? booking.packageName!
        : null;
    final sessionLabel = booking.sessionType?.isNotEmpty == true
        ? _formatSessionType(booking.sessionType!)
        : null;

    final String title;
    if (packageLabel != null) {
      title = 'Gymies – $packageLabel met $clientName';
    } else if (sessionLabel != null) {
      title = 'Gymies $sessionLabel – $clientName';
    } else {
      title = 'Gymies sessie – $clientName';
    }

    final start = booking.scheduledAt;
    final end = start.add(Duration(minutes: booking.durationMinutes));

    final descParts = <String>[
      'Klant: $clientName',
      if (packageLabel != null) 'Pakket: $packageLabel',
      if (sessionLabel != null) 'Type: $sessionLabel',
      'Duur: ${booking.durationMinutes} minuten',
      '',
      'Geboekt via Gymies',
    ];
    if (booking.id.isNotEmpty) {
      descParts.add('Boeking #${booking.id}');
    }

    return Event(
      title: title,
      description: descParts.join('\n'),
      startDate: start,
      endDate: end,
      iosParams: const IOSParams(
        reminder: Duration(minutes: 30),
      ),
      androidParams: const AndroidParams(
        emailInvites: [],
      ),
    );
  }

  // ── Bulk sync ───────────────────────────────────────────────

  /// Voegt meerdere boekingen toe aan de kalender (bijv. bij eerste
  /// activering van auto-sync). Toont per event het native dialoog.
  Future<int> syncBookings(List<Booking> bookings) async {
    int synced = 0;
    // Filter alleen komende, niet-geannuleerde boekingen
    final upcoming = bookings.where(
      (b) => b.isUpcoming && b.status != 'cancelled',
    ).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    for (final booking in upcoming) {
      final ok = await addBookingToCalendar(booking);
      if (ok) synced++;
    }
    return synced;
  }
}
