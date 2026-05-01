/// Gedeelde hulpfuncties voor het ophalen van waarden uit een Map met
/// meerdere mogelijke sleutels. Vervangt de lokale _str/_pick/_int methodes
/// die in bijna elk scherm werden gedupliceerd.
library;

/// Eerste niet-null, niet-lege waarde uit [map] voor een van de [keys].
dynamic mapPick(Map<String, dynamic>? map, List<String> keys) {
  if (map == null) return null;
  for (final k in keys) {
    if (map.containsKey(k) && map[k] != null) return map[k];
  }
  return null;
}

/// String-waarde uit [map] voor de eerste overeenkomende sleutel in [keys].
/// Geeft lege string terug als niets gevonden of de waarde leeg is.
String mapStr(Map<String, dynamic>? map, List<String> keys) {
  if (map == null) return '';
  for (final k in keys) {
    final v = map[k];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
  }
  return '';
}

/// Int-waarde uit [map] voor de eerste overeenkomende sleutel in [keys].
/// Geeft [fallback] (standaard 0) terug als niets gevonden of niet parseerbaar.
int mapInt(Map<String, dynamic>? map, List<String> keys, {int fallback = 0}) {
  final v = mapPick(map, keys);
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}

/// Bool-waarde uit [map] voor de eerste overeenkomende sleutel in [keys].
bool mapBool(Map<String, dynamic>? map, List<String> keys,
    {bool fallback = false}) {
  final v = mapPick(map, keys);
  if (v is bool) return v;
  if (v is num) return v.toInt() == 1;
  final s = v?.toString().toLowerCase();
  if (s == 'true' || s == '1') return true;
  return fallback;
}

/// Converteert een waarde in centen naar een eurosterkte string (bijv. "49.99").
/// Geeft lege string terug als [centsRaw] null is.
String centsToEuroString(dynamic centsRaw) {
  int? cents;
  if (centsRaw is int) {
    cents = centsRaw;
  } else if (centsRaw is num) {
    cents = centsRaw.toInt();
  } else {
    cents = int.tryParse(centsRaw?.toString() ?? '');
  }
  if (cents == null) return '';
  return (cents / 100).toStringAsFixed(2);
}
