/// Centrale euro-formatting: zorgt dat bedragen ALTIJD als euro worden getoond
/// met Nederlandse komma-notatie (bijv. €15,00 i.p.v. €15.00 of 1500 cents).
///
/// Gebruik: `import '../utils/currency_format.dart';`
///   formatEuro(1500)       → '€15,00'
///   formatEuro(0)          → '€0,00'
///   formatEuro(null)       → 'Prijs op aanvraag'
///   formatEuroShort(1500)  → '€15'    (hele euro's, geen decimalen)
///   formatEuroPp(1500)     → '€15,00 p.p.'

/// Formatteer centen naar euro-string met Nederlandse komma.
/// [cents] mag int, double, num, String, of null zijn.
/// Retourneert 'Prijs op aanvraag' als de waarde null of ≤ 0 is.
String formatEuro(dynamic cents, {String fallback = 'Prijs op aanvraag'}) {
  final value = _parseCents(cents);
  if (value == null || value <= 0) return fallback;
  final euros = (value / 100).toStringAsFixed(2).replaceAll('.', ',');
  return '€$euros';
}

/// Formatteer centen naar euro-string, altijd getoond (ook bij 0).
String formatEuroAlways(dynamic cents) {
  final value = _parseCents(cents) ?? 0;
  final euros = (value / 100).toStringAsFixed(2).replaceAll('.', ',');
  return '€$euros';
}

/// Korte weergave: hele euro's zonder decimalen (bijv. €15).
String formatEuroShort(dynamic cents, {String fallback = 'Prijs op aanvraag'}) {
  final value = _parseCents(cents);
  if (value == null || value <= 0) return fallback;
  final euros = (value / 100).toStringAsFixed(0);
  return '€$euros';
}

/// Met 'per persoon' suffix.
String formatEuroPp(dynamic cents, {String fallback = 'Gratis'}) {
  final value = _parseCents(cents);
  if (value == null || value <= 0) return fallback;
  final euros = (value / 100).toStringAsFixed(2).replaceAll('.', ',');
  return '€$euros p.p.';
}

/// Parse diverse input-types naar int centen.
int? _parseCents(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is num) return v.toInt();
  if (v is String) {
    final trimmed = v.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed) ?? double.tryParse(trimmed)?.round();
  }
  return null;
}
