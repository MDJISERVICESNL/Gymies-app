# Gymies App – Overzicht & Website-pariteit

> Vergelijking van de app met de website: wat hebben we, waar staat het, hoe is het ingedeeld?

---

## 1. Hebben we alles wat de website heeft?

**Ja.** De app dekt alle kernfunctionaliteit van de website. Hieronder de indeling en eventuele verschillen.

---

## 2. App-structuur – waar staat alles?

### 2.1 Start & Auth

| Scherm | Bestand | Toegang |
|--------|---------|---------|
| Login / Register | `login_register_screen.dart` | Eerste scherm bij niet-ingelogd |
| Wachtwoord vergeten | Via login-tab | Link in login-formulier |
| Wachtwoord reset (na e-mail link) | `password_reset_screen.dart` | Deep link: `gymies://wachtwoord-reset?token=X&email=Y` |
| E-mail verifiëren | `verify_email_screen.dart` | Na registratie |
| Loading / routing | `loading_screen.dart` | Bepaalt: Login, Client Dashboard, Trainer Dashboard of Admin |

---

### 2.2 Klant (Client)

**Start:** `DashboardScreen` (`dashboard_screen.dart`) – trainer-zoeken, filters, boekingen-overzicht.

**Drawer (hamburgermenu):**

| Menu-item | Scherm | Bestand |
|-----------|--------|---------|
| Mijn afspraken | ClientSessionsScreen | `client_sessions_screen.dart` |
| Berichten | ClientMessagesScreen | `client_messages_screen.dart` |
| Meldingen | ClientNotificationsScreen | `client_notifications_screen.dart` |
| Favorieten | ClientFavoritesScreen | `client_favorites_screen.dart` |
| Mijn dossier | ClientDossierScreen | `client_dossier_screen.dart` |
| Mijn wachtlijsten | ClientWaitlistScreen | `client_waitlist_screen.dart` |
| Groepslessen | ClientGroupSessionsScreen | `client_group_sessions_screen.dart` |
| Factuur | ClientInvoicesScreen | `client_invoices_screen.dart` |
| Support / help | ClientSupportScreen | `client_support_screen.dart` |
| Instellingen | ClientSettingsScreen | `client_settings_screen.dart` |

**Trainerprofiel (openbaar):**

| Sectie | Locatie |
|--------|---------|
| Trainer zoeken | Dashboard – zoekbalk + filters |
| Trainer openen | Tap op trainer-kaart |
| Volledig profiel | "Bekijk volledig profiel" → `ClientPublicTrainerProfileScreen` (in `client_trainer_profile_screen.dart`) |
| **Stories** | Klikbare storyring bovenaan profiel → fullscreen story viewer |
| **Galerij** | Sectie "Galerij" met foto's/video's → tap opent fullscreen viewer |
| Boeken | `ClientTrainerProfileScreen` – pakket/sessie kiezen, datum/slot, betalen |
| Check-in QR | `ClientCheckInQrScreen` – na boeking, in check-in window |
| **SOS** | Rode knop in app bar van check-in scherm |
| Reviews | `ClientTrainerReviewsScreen` – via profiel |
| Reschedule-card in chat | `RescheduleCardWidget` in `client_messages_screen.dart` – Akkoord / Afwijzen / Ander voorstel |

**Groepslessen:**

| Scherm | Bestand |
|--------|---------|
| Publieke lijst | `client_group_sessions_screen.dart` |
| Detail + inschrijven | `client_group_session_detail_screen.dart` |
| Mijn inschrijvingen | `client_my_group_sessions_screen.dart` |

---

### 2.3 Trainer

**Start:** `TrainerDashboardScreen` (`trainer_dashboard_screen.dart`).

**Drawer:**

| Menu-item | Scherm | Bestand |
|-----------|--------|---------|
| Mijn sessies | TrainerSessionsScreen | `trainer_sessions_screen.dart` |
| Agenda | TrainerAgendaScreen | `trainer_agenda_screen.dart` |
| Berichten | TrainerMessagesScreen | `trainer_messages_screen.dart` |
| Meldingen | TrainerNotificationsScreen | `trainer_notifications_screen.dart` |
| Inkomsten | TrainerIncomeScreen | `trainer_income_screen.dart` |
| Klanten *(Pro/Elite)* | TrainerClientsScreen | `trainer_clients_screen.dart` |
| Pakketten *(Pro/Elite)* | TrainerPackagesScreen | `trainer_packages_screen.dart` |
| Groepslessen *(Pro/Elite)* | TrainerGroupSessionsScreen | `trainer_group_sessions_screen.dart` |
| Support | ClientSupportScreen | `client_support_screen.dart` |
| Gym Dashboard *(Elite met gym)* | GymDashboardScreen | `gym_dashboard_screen.dart` |
| Instellingen | TrainerSettingsScreen | `trainer_settings_screen.dart` |

**Trainer-specifieke schermen:**

| Feature | Scherm | Bestand |
|---------|--------|---------|
| Profiel bewerken | TrainerProfileScreen | `trainer_profile_screen.dart` |
| Etalage (Stories, Gallery, SEO) | TrainerStorefrontEditorScreen | `trainer_storefront_editor_screen.dart` |
| Check-in scanner | TrainerCheckInScannerScreen | `trainer_check_in_scanner_screen.dart` |
| **Safe session** | TrainerSessionsScreen | Start/stop via menu op boeking |
| **SOS** | Rode FAB rechtsonder in sessies-scherm |
| Abonnement | TrainerSubscriptionScreen | `trainer_subscription_screen.dart` |
| Onboarding | TrainerOnboardingScreen | `trainer_onboarding_screen.dart` |
| Documenten | TrainerDocumentsScreen | `trainer_documents_screen.dart` |
| Promocodes | TrainerPromoCodesScreen | `trainer_promo_codes_screen.dart` |
| Pro Hub | TrainerProHubScreen | `trainer_pro_hub_screen.dart` |
| Dossier builder | TrainerDossierBuilderScreen | `trainer_dossier_builder_screen.dart` |
| Klant-dossier | TrainerClientDossierScreen | `trainer_client_dossier_screen.dart` |
| Financiën | TrainerFinanceScreen | `trainer_finance_screen.dart` |
| Studio | TrainerStudioScreen | `trainer_studio_screen.dart` |

**Etalage-editor:** Via `TrainerSectionMenu` → Profiel of via `trainer_profile_screen.dart` / `trainer_section_menu.dart` (sectie `storefront`).

---

### 2.4 Gym (Elite)

**Toegang:** Drawer → "Gym Dashboard" (alleen als `getGymMembership()` succesvol).

| Scherm | Bestand |
|--------|---------|
| Dashboard | `gym_dashboard_screen.dart` |
| Trainers | `gym_trainers_screen.dart` |
| Boekingen | `gym_bookings_screen.dart` |
| Klanten | `gym_clients_screen.dart` |
| Instellingen | `gym_settings_screen.dart` |

---

### 2.5 Admin (Control Tower)

**Toegang:** Alleen voor `isAdmin`-gebruikers.

| Scherm | Bestand |
|--------|---------|
| Control Tower | `control_tower_screen.dart` |
| User detail | `admin_user_detail_screen.dart` |
| Berichten/tickets | `admin_messages_screen.dart` |
| Ticket detail | `admin_ticket_detail_screen.dart` |
| Subscription features | `admin_subscription_features_screen.dart` |

---

## 3. Feature-pariteit met website

| Website-feature | App | Locatie |
|-----------------|-----|---------|
| **Auth** | ✓ | Login, register, wachtwoord reset (incl. deep link) |
| **Trainer zoeken** | ✓ | Dashboard, filters (regio, prijs, afstand, etc.) |
| **Trainerprofiel** | ✓ | Stories, galerij, pakketten, beschikbaarheid, boeken |
| **Boeken & betalen** | ✓ | Mollie-flow in app |
| **Berichten** | ✓ | Client + trainer chat |
| **Reschedule-card** | ✓ | Akkoord / Afwijzen / Ander voorstel in chat |
| **Check-in QR** | ✓ | Client toont QR, trainer scant |
| **Safe session** | ✓ | Start/stop in trainer-sessies |
| **SOS** | ✓ | Client (check-in) + trainer (sessies FAB) |
| **Groepslessen** | ✓ | Lijst, detail, inschrijven, betalen |
| **Wachtlijst** | ✓ | Client + trainer |
| **Facturen** | ✓ | Client facturen-overzicht |
| **Dossier** | ✓ | Client (Pro/Elite trainer) + trainer dossier |
| **Etalage (Stories, Gallery, SEO)** | ✓ | Trainer storefront-editor |
| **Gym (Elite)** | ✓ | Dashboard, trainers, boekingen, klanten, instellingen |
| **Abonnementen** | ✓ | Starter onbeperkt klanten; Pro/Elite features |

---

## 4. Bestandsstructuur (lib/screens)

```
lib/screens/
├── loading_screen.dart           # Routing start
├── login_register_screen.dart
├── password_reset_screen.dart
├── verify_email_screen.dart
│
├── dashboard_screen.dart         # Klant-dashboard
├── client_*.dart                 # Klant-schermen (sessions, messages, etc.)
├── client_trainer_profile_screen.dart  # Trainerprofiel + openbaar profiel
├── client_check_in_qr_screen.dart
│
├── trainer_dashboard_screen.dart
├── trainer_*.dart                # Trainer-schermen
├── trainer_storefront_editor_screen.dart
├── trainer_check_in_scanner_screen.dart
│
├── gym_dashboard_screen.dart
├── gym_*.dart                    # Gym-schermen
│
├── control_tower_screen.dart     # Admin
├── admin_*.dart
│
└── widgets/
    ├── trainer_section_menu.dart
    ├── trainer_media_section.dart
    ├── trainer_state_views.dart
    └── reschedule_card_widget.dart
```

---

## 5. Mogelijke website-features niet (volledig) in app

| Feature | Status |
|---------|--------|
| Referralcode valideren | API aanwezig, UI mogelijk beperkt |
| Site-media (landingspagina) | Backend; app heeft geen landingspagina |
| GDPR export/delete | API aanwezig; mogelijk via Support |
| Brede admin Control Tower | Basis in app; volledige console op website |

---

## 6. Samenvatting

De app heeft **pariteit met de website** voor alle kernflows:

- Auth, trainer zoeken, profiel (incl. stories & galerij), boeken, betalen
- Berichten, reschedule, check-in, safe session, SOS
- Groepslessen, wachtlijst, facturen, dossier
- Trainer: sessies, agenda, inkomsten, klanten, pakketten, groepslessen, etalage
- Gym (Elite): dashboard, trainers, boekingen, klanten, instellingen
- Wachtwoord reset via deep link

De indeling volgt de rollen: **Klant** (dashboard + drawer), **Trainer** (dashboard + drawer + secties), **Gym** (eigen dashboard), **Admin** (Control Tower).
