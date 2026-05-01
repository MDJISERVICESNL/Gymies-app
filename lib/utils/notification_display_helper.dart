/// Helper om meldingen duidelijk weer te geven.
/// Lost "update - " en lege/ongeldige titels op door af te leiden van type en data.
///
/// De backend stuurt notificaties met een Laravel class name als `type`
/// (bv. "App\Notifications\GymiesNotification") en de echte content in een
/// JSON `data` payload. Deze helper doorzoekt alle mogelijke velden om
/// bruikbare titel en body te extraheren.
class NotificationDisplayHelper {
  NotificationDisplayHelper._();

  static dynamic _pick(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) return map[key];
    }
    return null;
  }

  static String _str(Map<String, dynamic> map, List<String> keys) {
    final v = _pick(map, keys);
    return v?.toString().trim() ?? '';
  }

  static Map<String, dynamic>? _map(Map<String, dynamic> map, List<String> keys) {
    final v = _pick(map, keys);
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  /// Geeft de geneste payload-data terug (data/meta/payload).
  static Map<String, dynamic> _payload(Map<String, dynamic> item) {
    return _map(item, ['data', 'meta', 'payload']) ?? <String, dynamic>{};
  }

  /// Doorzoekt zowel het root-item als de payload voor een string-veld.
  static String _deepStr(Map<String, dynamic> item, List<String> keys) {
    final root = _str(item, keys);
    if (root.isNotEmpty) return root;
    return _str(_payload(item), keys);
  }

  /// Normaliseert het type-veld door Laravel class names op te schonen
  /// en uit zowel root als payload te zoeken.
  /// Zoekt ook in event_type (queue-tabel) en channel.
  static String _normalizedType(Map<String, dynamic> item) {
    var raw = _str(item, ['type', 'notification_type', 'category', 'event_type', 'eventType']);

    // Laravel class name → alleen de laatste slug pakken
    // "App\Notifications\BookingConfirmed" → "bookingconfirmed"
    if (raw.contains('\\')) {
      raw = raw.split('\\').last;
    }

    // CamelCase naar lowercase, underscores houden (booking_confirmed → booking confirmed)
    raw = raw.toLowerCase().replaceAll('_', ' ').replaceAll('-', ' ');

    // Ook payload doorzoeken voor een concreter type
    final payloadType = _str(_payload(item), ['type', 'notification_type', 'category', 'event', 'action', 'event_type']).toLowerCase().replaceAll('_', ' ');

    // Channel kan ook hints geven (push, email, sms, in_app)
    final channel = _str(item, ['channel']).toLowerCase();

    return '$raw $payloadType $channel'.trim();
  }

  /// Verzamelt alle tekst uit het item en payload voor keyword-matching.
  static String _fullText(Map<String, dynamic> item) {
    final data = _payload(item);
    return [
      _str(item, ['title', 'subject']),
      _str(item, ['body', 'message', 'text']),
      _str(item, ['event_type', 'eventType', 'channel']),
      _str(data, ['title', 'subject']),
      _str(data, ['body', 'message', 'text']),
      _str(data, ['trainer_name', 'trainerName']),
      _str(data, ['event', 'action', 'reason', 'event_type']),
      _normalizedType(item),
    ].join(' ').toLowerCase();
  }

  /// Bepaalt of de gegeven titel generiek/leeg is en vervangen moet worden.
  static bool _isGenericTitle(String title) {
    final t = title.toLowerCase().trim();
    if (t.isEmpty) return true;
    if (t == 'update' || t == 'update -' || t == 'update - ') return true;
    if (t == 'melding' || t == 'notification' || t == 'notificatie') return true;
    if (t.startsWith('update -') && t.length < 20) return true;
    // Laravel class name als titel? Dat is ook generiek.
    if (t.contains('\\') || t.contains('app\\notifications')) return true;
    return false;
  }

  /// Geeft een menselijk leesbare titel op basis van type + keywords.
  static String _titleFromType(Map<String, dynamic> item) {
    final fullText = _fullText(item);
    final data = _payload(item);

    // Probeer eerst een concrete titel uit de payload
    final payloadTitle = _str(data, ['title', 'subject', 'heading']);
    if (payloadTitle.isNotEmpty && !_isGenericTitle(payloadTitle)) {
      return payloadTitle;
    }

    // Keyword-based type detectie
    if (fullText.contains('ticket') || fullText.contains('afgehandeld') || fullText.contains('support')) {
      return 'Ticket afgehandeld';
    }
    if (fullText.contains('annulering') || fullText.contains('geannuleerd') || fullText.contains('cancelled') || fullText.contains('cancel')) {
      return 'Sessie geannuleerd';
    }
    if (fullText.contains('bevestig') || fullText.contains('confirmed') || fullText.contains('goedgekeurd') || fullText.contains('approved')) {
      return 'Boeking bevestigd';
    }
    if (fullText.contains('booking') || fullText.contains('boeking') || fullText.contains('sessie') || fullText.contains('session')) {
      return 'Sessieboeking';
    }
    if (fullText.contains('message') || fullText.contains('chat') || fullText.contains('bericht')) {
      return 'Nieuw bericht';
    }
    if (fullText.contains('factuur') || fullText.contains('invoice') || fullText.contains('payment') || fullText.contains('betaling')) {
      return 'Factuur';
    }
    if (fullText.contains('standby') || fullText.contains('waitlist') || fullText.contains('wachtlijst')) {
      return 'Standby plek beschikbaar';
    }
    if (fullText.contains('check-in') || fullText.contains('checkin')) {
      if (fullText.contains('gemist') || fullText.contains('missed') || fullText.contains('no-show') || fullText.contains('noshow')) {
        return 'Gemiste check-in';
      }
      return 'Check-in open';
    }
    if (fullText.contains('reminder') || fullText.contains('herinnering')) {
      return 'Herinnering';
    }
    if (fullText.contains('review') || fullText.contains('beoordeling')) {
      return 'Nieuwe beoordeling';
    }
    if (fullText.contains('payout') || fullText.contains('uitbetaling') || fullText.contains('omzet')) {
      return 'Financieel';
    }
    if (fullText.contains('promo') || fullText.contains('pakket') || fullText.contains('aanbieding') || fullText.contains('korting')) {
      return 'Aanbieding';
    }
    if (fullText.contains('welkom') || fullText.contains('welcome') || fullText.contains('registr')) {
      return 'Welkom';
    }
    if (fullText.contains('reschedule') || fullText.contains('verplaats') || fullText.contains('verzet')) {
      return 'Sessie verplaatst';
    }
    // Laatste poging: event_type leesbaar maken
    // "booking_confirmed" → "Booking confirmed" → "Boeking bevestigd"
    final eventType = _str(item, ['event_type', 'eventType']);
    if (eventType.isNotEmpty) {
      final readable = eventType.replaceAll('_', ' ').replaceAll('-', ' ').trim();
      if (readable.isNotEmpty) {
        return '${readable[0].toUpperCase()}${readable.substring(1)}';
      }
    }

    return 'Melding';
  }

  /// Bouwt een duidelijke weergavetitel voor de melding.
  static String displayTitle(Map<String, dynamic> item) {
    // 1. Check root title
    final raw = _str(item, ['title', 'subject']);
    if (!_isGenericTitle(raw)) return raw;

    // 2. Check payload title
    final payloadTitle = _str(_payload(item), ['title', 'subject', 'heading']);
    if (payloadTitle.isNotEmpty && !_isGenericTitle(payloadTitle)) {
      return payloadTitle;
    }

    // 3. Afleiden uit type + keywords
    return _titleFromType(item);
  }

  /// Bouwt een duidelijke weergave-body voor de melding.
  /// Probeert altijd concrete info te geven (trainernaam, datum, bedrag).
  static String displayBody(Map<String, dynamic> item) {
    // 1. Check root body
    final raw = _str(item, ['body', 'message', 'text']);
    if (raw.isNotEmpty && raw != '-') return raw;

    // 2. Check payload body
    final data = _payload(item);
    final dataBody = _str(data, ['body', 'message', 'text', 'description', 'content']);
    if (dataBody.isNotEmpty && dataBody != '-') return dataBody;

    // 3. Bouw een concrete body op uit beschikbare payload-velden
    final trainerName = _str(data, ['trainer_name', 'trainerName', 'name', 'sender_name']);
    final date = _str(data, ['scheduled_at', 'session_date', 'date', 'booking_date', 'starts_at']);
    final amount = _str(data, ['amount', 'total', 'price', 'bedrag']);
    final reason = _str(data, ['reason', 'note', 'reden']);

    final title = displayTitle(item);
    final fullText = _fullText(item);

    // Context-specifieke body met concrete gegevens
    if (title == 'Ticket afgehandeld') {
      final ticketId = _deepStr(item, ['ticket_id', 'ticketId']);
      if (ticketId.isNotEmpty) return 'Je ticket #$ticketId is afgehandeld door Gymies.';
      return 'Je supportticket is afgehandeld door Gymies.';
    }

    if (title == 'Sessie geannuleerd') {
      final parts = <String>[];
      if (trainerName.isNotEmpty) parts.add('door $trainerName');
      if (date.isNotEmpty) parts.add('op ${_formatShortDate(date)}');
      if (reason.isNotEmpty) parts.add('— $reason');
      if (parts.isNotEmpty) return 'Sessie geannuleerd ${parts.join(' ')}.';
      return 'Je sessie is geannuleerd. Bekijk je boekingen.';
    }

    if (title == 'Boeking bevestigd') {
      final parts = <String>[];
      if (trainerName.isNotEmpty) parts.add('bij $trainerName');
      if (date.isNotEmpty) parts.add('op ${_formatShortDate(date)}');
      if (parts.isNotEmpty) return 'Sessie bevestigd ${parts.join(' ')}.';
      return 'Je boeking is bevestigd.';
    }

    if (title == 'Sessieboeking') {
      final parts = <String>[];
      if (trainerName.isNotEmpty) parts.add('met $trainerName');
      if (date.isNotEmpty) parts.add('op ${_formatShortDate(date)}');
      if (parts.isNotEmpty) return 'Update over je sessie ${parts.join(' ')}.';
      return 'Er is een update over je sessie.';
    }

    if (title == 'Sessie verplaatst') {
      final parts = <String>[];
      if (trainerName.isNotEmpty) parts.add('door $trainerName');
      if (date.isNotEmpty) parts.add('naar ${_formatShortDate(date)}');
      if (parts.isNotEmpty) return 'Sessie verplaatst ${parts.join(' ')}.';
      return 'Je sessie is verplaatst. Bekijk de nieuwe tijd.';
    }

    if (title == 'Nieuw bericht') {
      if (trainerName.isNotEmpty) return '$trainerName heeft je een bericht gestuurd.';
      return 'Je hebt een nieuw bericht ontvangen.';
    }

    if (title == 'Factuur') {
      final parts = <String>[];
      if (amount.isNotEmpty) parts.add('van €$amount');
      if (trainerName.isNotEmpty) parts.add('van $trainerName');
      if (parts.isNotEmpty) return 'Factuur ${parts.join(' ')}.';
      return 'Er is een update over je factuur.';
    }

    if (title == 'Standby plek beschikbaar') {
      if (date.isNotEmpty) return 'Er is een plek vrijgekomen op ${_formatShortDate(date)}. Boek nu!';
      return 'Er is een plek vrijgekomen. Boek nu!';
    }

    if (title == 'Herinnering') {
      final parts = <String>[];
      if (trainerName.isNotEmpty) parts.add('met $trainerName');
      if (date.isNotEmpty) parts.add('op ${_formatShortDate(date)}');
      if (parts.isNotEmpty) return 'Herinnering: sessie ${parts.join(' ')}.';
      return 'Je hebt binnenkort een sessie.';
    }

    if (title == 'Check-in open') {
      if (trainerName.isNotEmpty) return 'Check-in is nu open voor je sessie met $trainerName.';
      return 'Check-in is nu mogelijk voor je sessie.';
    }

    if (title == 'Gemiste check-in') {
      if (trainerName.isNotEmpty) return 'Je hebt je sessie met $trainerName gemist.';
      return 'Je hebt je sessie gemist. Neem contact op met je trainer.';
    }

    if (title == 'Nieuwe beoordeling') {
      if (trainerName.isNotEmpty) return '$trainerName heeft een beoordeling ontvangen.';
      return 'Er is een nieuwe beoordeling geplaatst.';
    }

    if (title == 'Aanbieding') {
      if (trainerName.isNotEmpty) return '$trainerName heeft een nieuwe aanbieding.';
      return 'Er is een nieuwe aanbieding beschikbaar.';
    }

    if (title == 'Welkom') {
      return 'Welkom bij Gymies! Ontdek trainers bij jou in de buurt.';
    }

    // Laatste poging: als er enige payload-info is, toon die
    if (trainerName.isNotEmpty && date.isNotEmpty) {
      return 'Update van $trainerName op ${_formatShortDate(date)}.';
    }
    if (trainerName.isNotEmpty) {
      return 'Update van $trainerName.';
    }

    // Probeer event_type als leesbare body te gebruiken
    final eventType = _str(item, ['event_type', 'eventType']);
    if (eventType.isNotEmpty) {
      final channel = _str(item, ['channel']);
      final channelLabel = channel == 'push' ? 'Pushmelding' : channel == 'email' ? 'E-mailmelding' : channel == 'sms' ? 'SMS-melding' : 'Melding';
      final readable = eventType.replaceAll('_', ' ').replaceAll('-', ' ').trim();
      return '$channelLabel: $readable. Tik voor details.';
    }

    // Absolute fallback
    return 'Tik voor meer informatie.';
  }

  /// Formatteert een ISO-datum kort: "25 apr" of "25 apr 14:30"
  static String _formatShortDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    const months = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
    final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (time == '00:00') return '${dt.day} ${months[dt.month - 1]}';
    return '${dt.day} ${months[dt.month - 1]} om $time';
  }

  /// Formatteert de datum voor weergave.
  static String formatDate(Map<String, dynamic> item) {
    final raw = _str(item, ['created_at', 'createdAt', 'date']);
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final notifDay = DateTime(dt.year, dt.month, dt.day);
    if (notifDay == today) {
      return 'Vandaag ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    final yesterday = today.subtract(const Duration(days: 1));
    if (notifDay == yesterday) {
      return 'Gisteren ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Controleert of deze melding een bruikbare deep-link target heeft.
  /// Zoekt in zowel root als payload voor IDs en actionable types.
  static bool hasActionableTarget(Map<String, dynamic> item) {
    final data = _payload(item);
    final type = _normalizedType(item);
    final fullText = _fullText(item);

    // Check voor directe IDs
    if (_deepStr(item, ['conversation_id', 'conversationId']).isNotEmpty) return true;
    if (_deepStr(item, ['booking_id', 'bookingId', 'session_id']).isNotEmpty) return true;
    if (_deepStr(item, ['invoice_id', 'invoiceId']).isNotEmpty) return true;
    if (_deepStr(item, ['trainer_user_id', 'trainerUserId', 'trainer_id']).isNotEmpty) return true;
    if (_deepStr(item, ['action_url', 'url', 'link']).isNotEmpty) return true;

    // Check voor type-based navigation
    if (fullText.contains('message') || fullText.contains('chat') || fullText.contains('bericht')) return true;
    if (fullText.contains('booking') || fullText.contains('session') || fullText.contains('sessie') || fullText.contains('boeking')) return true;
    if (fullText.contains('invoice') || fullText.contains('payment') || fullText.contains('factuur') || fullText.contains('betaling')) return true;
    if (fullText.contains('standby') || fullText.contains('waitlist') || fullText.contains('wachtlijst')) return true;

    return false;
  }
}
