# Pro-features implementatie-analyse

> Grondige inventarisatie: wat bestaat al, wat kunnen we hergebruiken, wat moet nieuw?

---

## 1. TRAINER (Pro-tier)

### 1.1 Smart Rebook Alerts
**Vereiste:** Seintje als klant 7 dagen niets boekt → 1-klik "We missen je" + link naar agenda.

| Component | Status | Herbruik / Opmerking |
|-----------|--------|----------------------|
| Pro Hub rebook-suggestions | **API + UI aanwezig** | `trainer/pro/rebook-suggestions` + `sendTrainerRebookSuggestion()` + `TrainerProHubScreen` (Rebook-tab). Backend **retourneert nu `[]`** – logica ontbreekt. |
| "7 dagen niet geboekt" logica | **Niet aanwezig** | Backend `GymiesProHubController::rebookSuggestions()` moet: laatste `scheduled_at` per klant ophalen, filteren waar `now - last_booking > 7 dagen`. |
| "We missen je" template + link | **Deels** | `sendTrainerRebookSuggestion(bookingId)` stuurt herboek-voorstel. Nieuwe endpoint of uitbreiding: template "We missen je" met `agenda_url` of directe link. Agenda-URL: `gymies.nl/trainers/{id}` of deep link naar app. |
| Berichten-infra | **Aanwezig** | `sendTrainerMessage()`, `trainer/clients/bulk-message`, chat UI. Template-bericht kan via bestaande message-API. |

**Actie:** Backend rebookSuggestions uitbreiden met "7 dagen geen sessie"-filter + template-bericht met agenda-link. App: Rebook-tab toont suggesties; mogelijk aparte "Smart Rebook" sectie met alert-badges.

---

### 1.2 Custom Intakeformulieren
**Vereiste:** Digitaal intakeformulier sturen → antwoorden in Dossier.

| Component | Status | Herbruik / Opmerking |
|-----------|--------|----------------------|
| Formulierbuilder | **Niet aanwezig** | Volledig nieuw: velden definiëren (text, number, select, checkbox). |
| Versturen naar klant | **Deels** | Berichten-systeem of notificatie. Kan als link: `gymies.nl/intake/{formId}?token=...`. |
| Antwoorden opslaan | **Deels** | Dossier-structuur: `updateTrainerClientDossier()`, `getTrainerClientDossier()`. Nieuwe velden: `intake_responses`, `intake_form_id`, etc. |
| Dossier-integratie | **Aanwezig** | `TrainerClientDossierScreen`, dossier-API. Intake kan als tab of sectie in Overview. |

**Actie:** Backend: `gymies_intake_forms` (trainer_id, fields_json), `gymies_intake_responses` (client_id, form_id, responses_json). App: form builder (Pro), client form view (invullen), dossier toont antwoorden.

---

### 1.3 Video-Library (Privé)
**Vereiste:** Instructievideo's per klant in dossier; alleen die klant ziet ze.

| Component | Status | Herbruik / Opmerking |
|-----------|--------|----------------------|
| Video upload (profiel) | **Aanwezig** | `TrainerMediaSection`: `postTrainerMedia(filePath, type: 'video', usage)`. Nu: story + gallery (publiek). |
| Video per klant | **Niet aanwezig** | Nieuwe usage: `client_video` + `client_user_id`. Of aparte tabel: `gymies_client_videos` (trainer_id, client_id, url, title). |
| Client video-weergave | **Niet aanwezig** | `ClientDossierScreen` of `ClientPhase2Screen`: sectie "Video's van je trainer". `video_player` package al in gebruik. |
| Opslag/URL | **Deels** | Media-upload flow bestaat; uitbreiden voor client-scoped media. |

**Actie:** Backend: client-video endpoints (upload, list per client). App: in dossier "Video toevoegen" (trainer), in ClientDossier "Video's" (klant). Hergebruik `TrainerMediaSection`-achtige upload-UI + `video_player`.

---

### 1.4 Financiële Forecast
**Vereiste:** Grafiek verwachte inkomsten komende maand (boekingen + actieve pakketten).

| Component | Status | Herbruik / Opmerking |
|-----------|--------|----------------------|
| Revenue forecast API | **Aanwezig** | `getTrainerRevenueForecast()` → `trainer/revenue-forecast`. |
| Trainer Finance screen | **Aanwezig** | `TrainerFinanceScreen` met Forecast-tab. Toont `forecast_cents`, `month_estimate_cents`. |
| Grafiek/visualisatie | **Beperkt** | Forecast-tab toont alleen `_kvCard` (key-value). Geen chart. |
| Data (boekingen, pakketten) | **Backend** | Forecast-endpoint moet al boekingen/pakketten gebruiken. Controleren of output voldoende is. |

**Actie:** Forecast-tab uitbreiden met een eenvoudige bar/line chart (bijv. `fl_chart` of custom `CustomPainter`). `ClientPhase2Screen` heeft `_ProgressMiniChart` – dat patroon hergebruiken.

---

### 1.5 Persoonlijke Booking Link
**Vereiste:** gymies.nl/jouwnaam → openbaar trainerprofiel.

| Component | Status | Herbruik / Opmerking |
|-----------|--------|----------------------|
| Trainer profiel (publiek) | **Aanwezig** | `GET trainers/{id}` – id is nu waarschijnlijk numeric. |
| Slug/username | **Niet aanwezig** | Trainer model heeft geen `slug` of `profile_slug`. Backend: `gymies_trainer_profiles.profile_slug` toevoegen. |
| Route gymies.nl/{slug} | **Niet aanwezig** | Web: route `gymies.nl/t/{slug}` of `gymies.nl/jouwnaam` die `trainers/{id}` resolve. Backend: `GET trainers/by-slug/{slug}` of `trainers?slug=x`. |
| Deep link / App Links | **Aanwezig** | `gymies://payment/complete`, app_links. Kan uitbreiden: `gymies.nl/t/jouwnaam` → app opent ClientTrainerProfileScreen. |

**Actie:** Backend: `profile_slug` kolom, unique, editable in trainer settings. Endpoint `trainers/by-slug/{slug}`. Web: landingspagina voor `/t/{slug}`. App: deep link configuratie.

---

## 2. KLANT (bij Pro-trainer)

### 2.1 Progressie Tracker (Visueel)
**Vereiste:** Grafieken (gewicht, vet%, kracht-PR's) uit dossier.

| Component | Status | Herbruik / Opmerking |
|-----------|--------|----------------------|
| Progress data | **Aanwezig** | `getMyProgressSnapshot()`, `getMySharedDossier()`. Velden: `weight_history`, `performance_series`, `attendance_history`. |
| Chart component | **Aanwezig** | `ClientPhase2Screen` heeft `_ProgressMiniChart` (bar chart) + `SegmentedButton` (gewicht/prestatie/attendance). Privacy-opt-in. |
| ClientDossierScreen | **Aanwezig** | Nieuw; toont progressie als tekst, geen grafieken. |
| Dossier session entries | **Aanwezig** | Trainer vult in via `createTrainerClientSessionNote`, `saveTrainerClientProgress`. |

**Actie:** Chart van ClientPhase2Screen verplaatsen/hernutten in ClientDossierScreen. Of ClientDossierScreen uitbreiden met `_ProgressMiniChart`-achtige grafiek. Data uit `progress` / `sharedDossier` halen. Eventueel ClientPhase2Screen deprecaten ten faveure van ClientDossierScreen.

---

### 2.2 Maaltijd- & Gewoonte-checklists
**Vereiste:** Dagelijkse taken (bijv. "2L water", "150g eiwit"); klant vinkt af.

| Component | Status | Herbruik / Opmerking |
|-----------|--------|----------------------|
| Checklist model | **Niet aanwezig** | Volledig nieuw. |
| Trainer: taken definiëren | **Niet aanwezig** | Nieuwe UI in dossier of apart scherm. |
| Client: taken zien + afvinken | **Niet aanwezig** | Nieuwe sectie in ClientDossier of dashboard. |
| Datamodel | **Nieuw** | Bijv. `gymies_client_habits` (trainer_id, client_id, title, type: daily/weekly, created_at). `gymies_habit_completions` (habit_id, date, completed_at). |

**Actie:** Backend: habit + completion endpoints. App: trainer stelt habits in (in dossier of Pro Hub), klant ziet checklist per dag en vinkt af. UI: `CheckboxListTile` of custom checkbox-rij.

---

### 2.3 Achievements / Badges
**Vereiste:** Badges voor mijlpalen (5 sessies op rij, eerste 100kg squat).

| Component | Status | Herbruik / Opmerking |
|-----------|--------|----------------------|
| TrainerBadges | **Aanwezig** | `lib/utils/trainer_badges.dart`: `TrainerBadge`, `TrainerBadgePill`. Voor **trainers** (verified, woman2woman, etc.). |
| Client badges | **Niet aanwezig** | Andere semantiek: klant-mijlpalen, niet trainer-attributen. |
| Badge-definitie | **Herbruik** | Zelfde `TrainerBadge`-achtige structuur: id, label, icon, color. Nieuwe `ClientBadge` of generiek `AchievementBadge`. |
| Opslag | **Nieuw** | Backend: welke badges een klant heeft. Bijv. `client_achievements` (client_id, badge_id, unlocked_at) of berekend uit sessies/dossier. |

**Actie:** Backend: achievement-definities + unlock-logica (bijv. 5 sessies streak → badge). App: `ClientAchievementsWidget` of sectie in ClientDossier. Hergebruik `TrainerBadgePill`-styling.

---

### 2.4 Gedeelde Documenten
**Vereiste:** Centrale plek voor trainingsschema, voedingsplan (PDF) van trainer.

| Component | Status | Herbruik / Opmerking |
|-----------|--------|----------------------|
| Trainer documenten | **Aanwezig** | `TrainerDocumentsScreen`: bedrijfsgegevens, factuurgegevens, VOG, diploma. Niet per-klant. |
| Document upload | **Deels** | Geen generieke file-upload voor "document naar klant". |
| Client documenten bekijken | **Niet aanwezig** | Geen scherm "Mijn documenten van trainer". |
| Factuur PDF | **Aanwezig** | Factuur-PDF wordt gegenereerd. `url_launcher` voor openen. |

**Actie:** Backend: `gymies_client_documents` (trainer_id, client_id, title, file_url, type). Upload-endpoint. App: trainer kan in dossier "Document uploaden", klant ziet in ClientDossier "Documenten"-sectie met download-link. `url_launcher` of `open_file` voor PDF.

---

### 2.5 Directe Support-knop + Priority label
**Vereiste:** Kortere lijn naar trainer; berichten van Pro-trainer-klanten krijgen "Priority" in trainer-inbox.

| Component | Status | Herbruik / Opmerking |
|-----------|--------|----------------------|
| ClientSupportScreen | **Aanwezig** | Ticket indienen (type, subject, message, booking_id). |
| "Direct naar trainer" | **Deels** | Support gaat nu naar centraal ticketsysteem. Optioneel: "Direct naar trainer" = open chat met trainer in plaats van support ticket. |
| Berichten | **Aanwezig** | `ClientMessagesScreen`, chat. Klant kan altijd naar trainer chatten. |
| Priority in trainer-inbox | **Niet aanwezig** | `TrainerMessagesScreen`: geen priority-sorting. Backend: flag `from_pro_client` of `priority: true` op conversation. |

**Actie:** Support-knop op klant-dashboard kan 2 opties: "Support (ticket)" en "Direct bericht naar trainer". Voor Priority: backend conversations flag; trainer messages-scherm sorteert Priority bovenaan of toont badge. Kleine UI-wijziging.

---

## Samenvatting herbruik

| Gebied | Sterk herbruik | Deels / uitbreiden | Nieuw |
|--------|----------------|--------------------|-------|
| Rebook Alerts | Pro Hub, rebook API, berichten | Backend rebook-logica (7 dagen) | Template + agenda-link |
| Intakeformulieren | Dossier-API | - | Form builder, responses, client form |
| Video-Library | Media upload, video_player | Usage client-scoped | Client video UI |
| Financiële Forecast | Forecast API, Finance screen | - | Chart-component |
| Booking Link | trainers/{id}, deep links | - | Slug, by-slug endpoint, web route |
| Progressie Tracker | Progress API, ClientPhase2 chart | ClientDossierScreen | Integreren chart in dossier |
| Checklists | - | - | Habits + completions, hele flow |
| Achievements | TrainerBadge-styling | - | Badge-defs, unlock-logica |
| Gedeelde Documenten | url_launcher, factuur-PDF | - | Document storage, UI beide kanten |
| Priority Support | Support, Messages | - | Priority-flag, sortering |

---

## Aanbevolen volgorde implementatie

1. **Smart Rebook Alerts** – Backend rebookSuggestions (7 dagen) + bestaande UI
2. **Progressie Tracker** – Chart in ClientDossierScreen (minste nieuwe code)
3. **Financiële Forecast chart** – Alleen UI in bestaande Forecast-tab
4. **Persoonlijke Booking Link** – Backend slug + web route (hoge impact, redelijke inspanning)
5. **Gedeelde Documenten** – Document-upload + client weergave
6. **Priority Support** – Kleine backend + trainer messages-sortering
7. **Video-Library** – Uitbreiding media met client-scope
8. **Achievements** – Nieuwe domein, hergebruik badge-UI
9. **Maaltijd- & Gewoonte-checklists** – Volledig nieuw domein
10. **Custom Intakeformulieren** – Meest complex (form builder + flow)
