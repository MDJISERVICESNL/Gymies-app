import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';

/// FAQ categories and questions for the Help Center.

class FaqCategory {
  FaqCategory({
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
  FaqItem({
    required this.question,
    required this.answer,
    this.actionLabel,
    this.actionRoute,
  });

  final String question;
  final String answer;
  final String? actionLabel;
  final String? actionRoute;
}

/// Returns localized FAQ categories based on the current locale.
List<FaqCategory> getSupportFaqCategories(BuildContext context) {
  final t = S.of(context);
  return [
    FaqCategory(
      id: 'bookings',
      label: t.faqCatBoekingen,
      description: t.faqCatBoekDesc,
      icon: Icons.calendar_month_rounded,
      items: [
        FaqItem(question: t.faqQWijzigBoeking, answer: t.faqAWijzigBoeking, actionLabel: t.faqActionNaarSessies, actionRoute: 'sessions'),
        FaqItem(question: t.faqQAnnuleerSessie, answer: t.faqAAnnuleerSessie, actionLabel: t.faqActionNaarSessies, actionRoute: 'sessions'),
        FaqItem(question: t.faqQTrainerAfgezegd, answer: t.faqATrainerAfgezegd),
        FaqItem(question: t.faqQGroepssessie, answer: t.faqAGroepssessie, actionLabel: t.faqActionNaarGroepslessen, actionRoute: 'group_sessions'),
        FaqItem(question: t.faqQBoekingsgeschiedenis, answer: t.faqABoekingsgeschiedenis, actionLabel: t.faqActionNaarSessies, actionRoute: 'sessions'),
      ],
    ),
    FaqCategory(
      id: 'payments',
      label: t.faqCatBetalingen,
      description: t.faqCatBetalDesc,
      icon: Icons.account_balance_wallet_rounded,
      items: [
        FaqItem(question: t.faqQFacturen, answer: t.faqAFacturen, actionLabel: t.faqActionNaarFacturen, actionRoute: 'invoices'),
        FaqItem(question: t.faqQTerugbetaling, answer: t.faqATerugbetaling, actionLabel: t.faqActionSupport, actionRoute: 'new_ticket'),
        FaqItem(question: t.faqQBetaalmethoden, answer: t.faqABetaalmethoden),
        FaqItem(question: t.faqQBetalingMislukt, answer: t.faqABetalingMislukt, actionLabel: t.faqActionNaarSessies, actionRoute: 'sessions'),
      ],
    ),
    FaqCategory(
      id: 'account',
      label: t.faqCatAccount,
      description: t.faqCatAccountDesc,
      icon: Icons.person_rounded,
      items: [
        FaqItem(question: t.faqQWijzigProfiel, answer: t.faqAWijzigProfiel, actionLabel: t.faqActionNaarProfiel, actionRoute: 'profile'),
        FaqItem(question: t.faqQWachtwoord, answer: t.faqAWachtwoord, actionLabel: t.faqActionNaarProfiel, actionRoute: 'profile'),
        FaqItem(question: t.faqQNietInloggen, answer: t.faqANietInloggen),
        FaqItem(question: t.faqQMeldingen, answer: t.faqAMeldingen, actionLabel: t.faqActionNaarMeldingen, actionRoute: 'notifications'),
        FaqItem(question: t.faqQDossier, answer: t.faqADossier, actionLabel: t.faqActionNaarDossier, actionRoute: 'dossier'),
        FaqItem(question: t.faqQUitloggen, answer: t.faqAUitloggen),
      ],
    ),
    FaqCategory(
      id: 'trainer',
      label: t.faqCatTrainer,
      description: t.faqCatTrainerDesc,
      icon: Icons.fitness_center_rounded,
      items: [
        FaqItem(question: t.faqQTrainerReageertNiet, answer: t.faqATrainerReageertNiet, actionLabel: t.faqActionSupport, actionRoute: 'new_ticket'),
        FaqItem(question: t.faqQReview, answer: t.faqAReview, actionLabel: t.faqActionNaarSessies, actionRoute: 'sessions'),
        FaqItem(question: t.faqQKlacht, answer: t.faqAKlacht, actionLabel: t.faqActionKlacht, actionRoute: 'new_ticket'),
      ],
    ),
    FaqCategory(
      id: 'safety',
      label: t.faqCatVeiligheid,
      description: t.faqCatVeiligheidDesc,
      icon: Icons.shield_rounded,
      items: [
        FaqItem(question: t.faqQOngepasteGedrag, answer: t.faqAOngepasteGedrag, actionLabel: t.faqActionIncident, actionRoute: 'new_ticket'),
        FaqItem(question: t.faqQGegevensVeilig, answer: t.faqAGegevensVeilig),
        FaqItem(question: t.faqQGegevensOpvragen, answer: t.faqAGegevensOpvragen, actionLabel: t.faqActionGegevens, actionRoute: 'new_ticket'),
      ],
    ),
    FaqCategory(
      id: 'technical',
      label: t.faqCatTechnisch,
      description: t.faqCatTechnischDesc,
      icon: Icons.build_rounded,
      items: [
        FaqItem(question: t.faqQCrash, answer: t.faqACrash),
        FaqItem(question: t.faqQWitScherm, answer: t.faqAWitScherm),
        FaqItem(question: t.faqQPushNotificaties, answer: t.faqAPushNotificaties, actionLabel: t.faqActionNaarMeldingen, actionRoute: 'notifications'),
        FaqItem(question: t.faqQQrScanner, answer: t.faqAQrScanner),
      ],
    ),
  ];
}
