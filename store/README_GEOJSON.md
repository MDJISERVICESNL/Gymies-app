# Geographic regions (GeoJSON)

Voor sommige store-stappen wordt een **`.geojson`** gevraagd met **exact één `MultiPolygon`** (dat mag **meerdere polygonen** bevatten, bv. NL nu en BE later).

## Nu: alleen Nederland (aanbevolen)

| Bestand | Gebruik |
|---------|---------|
| **`gymies_supported_regions_netherlands_only_multipolygon.geojson`** | Root is alleen `MultiPolygon` met **één** polygon = vereenvoudigde bbox **Nederland**. Gebruik dit als de portal een “los” MultiPolygon-bestand wil. |
| `gymies_supported_regions_netherlands_featurecollection.geojson` | Zelfde gebied, maar als `FeatureCollection` met één feature (handig voor preview in geojson.io). |

Bounding box Nederland (vereenvoudigd): ongeveer **3.31–7.22 °O**, **50.75–53.55 °N**.

## Later uitbreiden naar België (handigste aanpak)

Je hoeft **geen nieuw bestandstype** te kiezen: blijf bij **één `MultiPolygon`**, en voeg een **tweede polygon** toe in `coordinates`.

- Nu: `coordinates` = `[ [ ring_NL ] ]` (één polygon)
- Straks: `coordinates` = `[ [ ring_NL ], [ ring_BE ] ]` (twee polygonen, nog steeds **één** MultiPolygon)

**Voorbeeld België** (vereenvoudigde bbox, ca. **2.54–6.41 °O**, **49.50–51.51 °N**):

```json
{
  "type": "MultiPolygon",
  "coordinates": [
    [
      [
        [3.31, 50.75],
        [7.22, 50.75],
        [7.22, 53.55],
        [3.31, 53.55],
        [3.31, 50.75]
      ]
    ],
    [
      [
        [2.54, 49.50],
        [6.41, 49.50],
        [6.41, 51.51],
        [2.54, 51.51],
        [2.54, 49.50]
      ]
    ]
  ]
}
```

Optioneel daarna **Luxemburg** op dezelfde manier als derde polygon.

## Andere bestanden (archief / andere scenario’s)

| Bestand | Bedoeling |
|---------|-----------|
| `gymies_supported_regions_benelux*.geojson` | Hele Benelux in één klap (als je dat ooit in één keer wilt). |
| `gymies_supported_regions_worldwide*.geojson` | Wereldwijde rechthoek. |

## Validatie

Controleer met [geojson.io](https://geojson.io) of [geojsonlint.com](https://geojsonlint.com) voordat je uploadt.

## Store-instellingen

Naast dit bestand moet je in **App Store Connect** / **Play Console** vaak ook **landen/regio’s** voor verkoop en distributie instellen. Dit GeoJSON is alleen de **geografische dekking** die ze apart vragen—houd die in lijn met waar je app echt ondersteuning en content aanbiedt.
