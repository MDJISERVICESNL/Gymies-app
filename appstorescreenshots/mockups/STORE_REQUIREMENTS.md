# App Store & Play Store – Screenshot-vereisten

## App Store (iOS)

| Device | Portrait | Landscape |
|--------|----------|-----------|
| 6.9" (iPhone 15 Pro Max) | 1290 × 2796 px | 2796 × 1290 px |
| 6.5" (iPhone 14 Plus) | 1284 × 2778 px | 2778 × 1284 px |
| 5.5" (iPhone 8 Plus) | 1242 × 2208 px | 2208 × 1242 px |

- **Formaat:** PNG of JPEG (RGB, geen transparantie)
- **Max. bestandsgrootte:** 10 MB per screenshot
- **Aantal:** 1–10 per localisatie (aanbevolen: 5–8)

## Play Store (Android)

- **Min. resolutie:** 1080 px op de kortste zijde
- **Aanbevolen:** 1080 × 1920 px (9:16) of 1920 × 1080 px (16:9)
- **Formaat:** PNG of JPEG (24-bit, geen alpha)
- **Aantal:** Min. 2, max. 8 screenshots

## Resizen voor upload

Als de mockups niet exact de juiste afmetingen hebben, kun je ze resizen met:

```bash
# Voorbeeld: 1290×2796 voor App Store (sips op macOS)
sips -z 2796 1290 mockup_01_trainer_dashboard.png --out mockup_01_appstore.png
```

Of gebruik een tool als [Screenshot Studio](https://appscreengen.com/) of Figma voor precieze afmetingen.
