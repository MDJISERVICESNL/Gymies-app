# Play Store – screenshot-afmetingen

Alle varianten komen uit de App Store-bron (`final/appstore/`, 1290×2796).

## Map `playstore_all_sizes/`

| Submap | Afmetingen | Oriëntatie |
|--------|------------|------------|
| `1242x2688_portrait/` | 1242 × 2688 px | Staand |
| `1284x2778_portrait/` | 1284 × 2778 px | Staand |
| `2688x1242_landscape/` | 2688 × 1242 px | Liggend (90° gedraaid) |
| `2778x1284_landscape/` | 2778 × 1284 px | Liggend (90° gedraaid) |

## Map `playstore/` (default)

- **1284 × 2778 px** – handige standaard voor upload (één set bestanden).

## Opnieuw genereren

```bash
cd appstorescreenshots/redisgnn
python3 export_playstore_sizes.py
```
