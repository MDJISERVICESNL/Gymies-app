import 'package:flutter/material.dart';

/// FAQ-categorieën en vragen voor het Help Center.
///
/// Elke [FaqCategory] bevat een lijst [FaqItem]s. Wanneer een item een
/// [actionLabel] heeft, kan de support-screen een knop tonen die naar het
/// juiste scherm navigeert. De [actionRoute] string wordt door de
/// support-screen vertaald naar een echte Navigator.push.
///
/// ──────────────────────────────────────────────────────────────────────
///  BELANGRIJK – Voeg NOOIT een route toe die niet bestaat in de app.
///  Verifieer elke route in de codebase voordat je hem hier toevoegt.
/// ──────────────────────────────────────────────────────────────────────

class FaqCategory {
  const FaqCategory({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.items,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final List<FaqItem> items;
}

class FaqItem {
  const FaqItem({
    required this.question,
    required this.answer,
    this.actionLabel,
    this.actionRoute,
  });

  final String question;
  final String answer;

  /// Label voor de actieknop (bijv. "Naar Mijn Sessies"). Null = geen knop.
  final String? actionLabel;

  /// Route-key die de support-screen vertaalt naar een Navigator.push.
  /// Beschikbare routes – ALLEEN deze bestaan daadwerkelijk:
  ///
  ///   'sessions'        → ClientSessionsScreen (tab 2 – Sessies)
  ///   'invoices'        → ClientInvoicesScreen
  ///   'profile'         → ClientProfileScreen
  ///   'settings'        → ClientSettingsScreen
  ///   'notifications'   → ClientNotificationsScreen
  ///   'dossier'         → ClientDossierScreen
  ///   'group_sessions'  → ClientGroupSessionsScreen
  ///   'waitlist'        → ClientWaitlistScreen
  ///   'favorites'       → ClientFavoritesStandaloneScreen
  ///   'password_reset'  → PasswordResetScreen (deep-link flow)
  ///   'new_ticket'      → Opent het nieuwe-ticket formulier (intern)
  ///
  /// Routes die NIET bestaan (en hier NIET gebruikt mogen worden):
  ///   ✗ 'notification_settings'  – er is geen toggle-UI voor notificatie-voorkeuren
  ///   ✗ 'account_delete'         – account verwijderen bestaat niet
  ///   ✗ 'payment_methods'        – betaalmethoden worden per boeking gekozen
  ///   ✗ 'report_trainer'         – meld-functie op trainerprofiel bestaat niet
  final String? actionRoute;
}

/// Alle FAQ-categorieën die in het Help Center worden getoond.
const List<FaqCategory> supportFaqCategories = [
  // ── Boekingen ──────────────────────────────────────────────────────
  FaqCategory(
    id: 'bookings',
    label: 'Boekingen',
    description: 'Wijzigen, annuleren, herschedulen',
    icon: Icons.calendar_month_rounded,
    items: [
      FaqItem(
        question: 'Hoe wijzig ik mijn boeking?',
        answer:
            'Ga naar het tabblad "Sessies" onderaan de app. Tik op de sessie '
            'die je wilt wijzigen en kies de gewenste actie in het menu. '
            'Je kunt tot 24 uur van tevoren kosteloos wijzigen.',
        actionLabel: 'Naar Mijn Sessies',
        actionRoute: 'sessions',
      ),
      FaqItem(
        question: 'Kan ik een sessie annuleren?',
        answer:
            'Ja, annuleren kan tot 12 uur voor de sessie. Ga naar het '
            'tabblad "Sessies", tik op de boeking en kies "Annuleren" in '
            'het actiemenu. Bij late annulering kunnen kosten in rekening '
            'worden gebracht.',
        actionLabel: 'Naar Mijn Sessies',
        actionRoute: 'sessions',
      ),
      FaqItem(
        question: 'Mijn trainer heeft afgezegd, wat nu?',
        answer:
            'Je ontvangt automatisch een volledige terugbetaling. '
            'Je kunt direct een nieuwe sessie boeken bij dezelfde trainer '
            'of via het tabblad "Ontdekken" een andere trainer zoeken.',
      ),
      FaqItem(
        question: 'Hoe boek ik een groepssessie?',
        answer:
            'Ga naar je Profiel → Groepslessen om beschikbare groepssessies '
            'te bekijken. Je kunt ook via het trainerprofiel zien welke '
            'groepslessen worden aangeboden.',
        actionLabel: 'Naar Groepslessen',
        actionRoute: 'group_sessions',
      ),
      FaqItem(
        question: 'Waar vind ik mijn boekingsgeschiedenis?',
        answer:
            'Ga naar het tabblad "Sessies". Onder "Geweest" zie je al je '
            'afgelopen sessies. Voor facturen ga je naar Profiel → Facturen.',
        actionLabel: 'Naar Mijn Sessies',
        actionRoute: 'sessions',
      ),
    ],
  ),

  // ── Betalingen ─────────────────────────────────────────────────────
  FaqCategory(
    id: 'payments',
    label: 'Betalingen',
    description: 'Facturen, terugbetalingen, abonnement',
    icon: Icons.account_balance_wallet_rounded,
    items: [
      FaqItem(
        question: 'Waar vind ik mijn facturen?',
        answer:
            'Ga naar je Profiel (tabblad rechtsonder) → tik op "Facturen" '
            'onder "Mijn activiteit". Hier kun je al je facturen bekijken, '
            'filteren op status en details opvragen.',
        actionLabel: 'Naar Facturen',
        actionRoute: 'invoices',
      ),
      FaqItem(
        question: 'Hoe vraag ik een terugbetaling aan?',
        answer:
            'Bij annulering binnen de termijn wordt automatisch '
            'terugbetaald via Mollie. Voor andere gevallen kun je een '
            'supportverzoek aanmaken met type "Betaling".',
        actionLabel: 'Supportverzoek aanmaken',
        actionRoute: 'new_ticket',
      ),
      FaqItem(
        question: 'Welke betaalmethoden worden geaccepteerd?',
        answer:
            'We accepteren iDEAL, creditcard (Visa/Mastercard), '
            'Bancontact en Apple Pay. De betaalmethode kies je bij elke '
            'boeking via onze betaalpartner Mollie.',
      ),
      FaqItem(
        question: 'Mijn betaling is mislukt, wat nu?',
        answer:
            'Controleer je bankrekening en probeer opnieuw via het '
            'tabblad "Sessies". Als het probleem aanhoudt, neem contact '
            'op met je bank of probeer een andere betaalmethode bij de '
            'volgende boeking.',
        actionLabel: 'Naar Mijn Sessies',
        actionRoute: 'sessions',
      ),
    ],
  ),

  // ── Mijn Account ───────────────────────────────────────────────────
  FaqCategory(
    id: 'account',
    label: 'Mijn Account',
    description: 'Profiel, wachtwoord, instellingen',
    icon: Icons.person_rounded,
    items: [
      FaqItem(
        question: 'Hoe wijzig ik mijn profiel?',
        answer:
            'Ga naar Profiel (tabblad rechtsonder) → Instellingen → '
            '"Mijn profiel". Hier kun je je naam, telefoonnummer, stad '
            'en bio aanpassen.',
        actionLabel: 'Naar Mijn Profiel',
        actionRoute: 'profile',
      ),
      FaqItem(
        question: 'Hoe verander ik mijn wachtwoord?',
        answer:
            'Ga naar Profiel → Instellingen → "Mijn profiel". Tik '
            'onderaan op "Wachtwoord wijzigen". Je hebt je huidige '
            'wachtwoord nodig plus een nieuw wachtwoord van minimaal '
            '8 tekens.',
        actionLabel: 'Naar Mijn Profiel',
        actionRoute: 'profile',
      ),
      FaqItem(
        question: 'Ik kan niet inloggen',
        answer:
            'Gebruik "Wachtwoord vergeten" op het loginscherm. Je '
            'ontvangt een e-mail met een reset-link. Controleer ook '
            'je spam-map en of je het juiste e-mailadres gebruikt.',
      ),
      FaqItem(
        question: 'Waar zie ik mijn meldingen?',
        answer:
            'Ga naar Profiel → "Meldingen" onder "Mijn activiteit". '
            'Hier vind je al je notificaties over boekingen, berichten '
            'en updates.',
        actionLabel: 'Naar Meldingen',
        actionRoute: 'notifications',
      ),
      FaqItem(
        question: 'Hoe zie ik mijn trainingsdossier?',
        answer:
            'Ga naar Profiel → "Mijn dossier" onder "Mijn activiteit". '
            'Hier vind je je persoonlijke trainingsdossier met notities '
            'van je trainer.',
        actionLabel: 'Naar Mijn Dossier',
        actionRoute: 'dossier',
      ),
      FaqItem(
        question: 'Hoe log ik uit?',
        answer:
            'Ga naar Profiel (tabblad rechtsonder) en scroll naar '
            'beneden. Tik op de "Uitloggen" knop onderaan de pagina.',
      ),
    ],
  ),

  // ── Mijn Trainer ───────────────────────────────────────────────────
  FaqCategory(
    id: 'trainer',
    label: 'Mijn Trainer',
    description: 'Contact, reviews, klachten',
    icon: Icons.fitness_center_rounded,
    items: [
      FaqItem(
        question: 'Mijn trainer reageert niet op berichten',
        answer:
            'Trainers reageren meestal binnen 24 uur. Controleer het '
            'tabblad "Berichten" of je bericht is verstuurd. Als je na '
            '48 uur nog niets hebt gehoord, maak dan een supportverzoek '
            'aan zodat wij contact opnemen met de trainer.',
        actionLabel: 'Supportverzoek aanmaken',
        actionRoute: 'new_ticket',
      ),
      FaqItem(
        question: 'Hoe laat ik een review achter?',
        answer:
            'Na elke afgeronde sessie ontvang je een melding om een '
            'review achter te laten. Je kunt ook naar het tabblad '
            '"Sessies" gaan, een afgelopen sessie openen en daar je '
            'review schrijven.',
        actionLabel: 'Naar Mijn Sessies',
        actionRoute: 'sessions',
      ),
      FaqItem(
        question: 'Ik wil een klacht indienen over mijn trainer',
        answer:
            'Het spijt ons dat je een slechte ervaring hebt gehad. '
            'Maak een supportverzoek aan met type "Geschil". Beschrijf '
            'de situatie zo duidelijk mogelijk en we behandelen dit met '
            'prioriteit.',
        actionLabel: 'Klacht indienen',
        actionRoute: 'new_ticket',
      ),
    ],
  ),

  // ── Veiligheid ─────────────────────────────────────────────────────
  FaqCategory(
    id: 'safety',
    label: 'Veiligheid',
    description: 'Melden, blokkeren, privacy',
    icon: Icons.shield_rounded,
    items: [
      FaqItem(
        question: 'Hoe meld ik ongepast gedrag?',
        answer:
            'Maak een supportverzoek aan met type "Incident" en '
            'beschrijf wat er is gebeurd. Vermeld de naam van de '
            'trainer en eventueel de sessie-datum. Meldingen worden '
            'binnen 24 uur behandeld.',
        actionLabel: 'Incident melden',
        actionRoute: 'new_ticket',
      ),
      FaqItem(
        question: 'Worden mijn gegevens veilig bewaard?',
        answer:
            'Ja, we voldoen volledig aan de AVG/GDPR. Je data wordt '
            'opgeslagen op beveiligde EU-servers. Betalingen worden '
            'veilig verwerkt via Mollie, een gecertificeerde '
            'betaalprovider.',
      ),
      FaqItem(
        question: 'Hoe kan ik mijn gegevens opvragen?',
        answer:
            'Je kunt een verzoek indienen via support met type "Overig". '
            'Wij sturen je een overzicht van al je opgeslagen gegevens '
            'binnen 30 dagen, conform de AVG.',
        actionLabel: 'Gegevensverzoek indienen',
        actionRoute: 'new_ticket',
      ),
    ],
  ),

  // ── Technisch ──────────────────────────────────────────────────────
  FaqCategory(
    id: 'technical',
    label: 'Technisch',
    description: 'Bugs, crashes, app problemen',
    icon: Icons.build_rounded,
    items: [
      FaqItem(
        question: 'De app crasht steeds',
        answer:
            'Probeer de app te updaten naar de nieuwste versie in de '
            'App Store of Google Play Store. Als het probleem aanhoudt: '
            'verwijder de app, herstart je telefoon en installeer de '
            'app opnieuw. Je data blijft behouden via je account.',
      ),
      FaqItem(
        question: 'Ik zie een wit of leeg scherm',
        answer:
            'Dit komt meestal door een verouderde app-versie of slecht '
            'internet. Update de app en controleer je wifi- of '
            'mobiele-dataverbinding. Probeer de app volledig te sluiten '
            'en opnieuw te openen.',
      ),
      FaqItem(
        question: 'Push-notificaties werken niet',
        answer:
            'Controleer je telefooninstellingen → Apps → GYMIES → '
            'Notificaties en zorg dat alles is ingeschakeld. '
            'Controleer ook in de app bij Profiel → Meldingen of je '
            'meldingen ontvangt.',
        actionLabel: 'Naar Meldingen',
        actionRoute: 'notifications',
      ),
      FaqItem(
        question: 'QR-code scanner werkt niet',
        answer:
            'Zorg dat je de camera-toestemming hebt gegeven aan de '
            'GYMIES-app. Ga naar je telefooninstellingen → Apps → '
            'GYMIES → Rechten → Camera → Toestaan. Herstart daarna '
            'de app.',
      ),
    ],
  ),
];
