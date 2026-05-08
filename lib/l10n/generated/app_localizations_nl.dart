import 'app_localizations.dart';

/// Dutch (NL) translations.
class SNl extends S {
  SNl() : super('nl');

  // ═══ NAVIGATIE ═══
  @override String get navHome => 'Home';
  @override String get navDiscover => 'Ontdekken';
  @override String get navTraining => 'Training';
  @override String get navInbox => 'Inbox';
  @override String get navMe => 'Me';
  @override String get navSessions => 'Sessies';
  @override String get navClients => 'Klanten';
  @override String get navMore => 'Meer';

  // ═══ BEGROETINGEN ═══
  @override String get greetingNight => 'Goedenacht';
  @override String get greetingMorning => 'Goedemorgen';
  @override String get greetingAfternoon => 'Goedemiddag';
  @override String get greetingEvening => 'Goedenavond';

  // ═══ LOGIN / REGISTRATIE ═══
  @override String get login => 'Inloggen';
  @override String get register => 'Registreren';
  @override String get logout => 'Uitloggen';
  @override String get logoutConfirmTitle => 'Uitloggen';
  @override String get logoutConfirmMessage => 'Weet je zeker dat je wilt uitloggen?';
  @override String get tagline => 'Vind jouw personal trainer\nen boek direct';
  @override String get email => 'E-mailadres';
  @override String get password => 'Wachtwoord';
  @override String get forgotPassword => 'Wachtwoord vergeten?';
  @override String get resetPassword => 'Wachtwoord resetten';
  @override String get name => 'Naam';
  @override String get displayName => 'Weergavenaam';
  @override String get phone => 'Telefoonnummer';
  @override String get verificationCode => 'Verificatiecode';
  @override String get enterCode => 'Voer de code in';
  @override String get verifyEmail => 'Verifieer je e-mail';
  @override String get resendCode => 'Code opnieuw versturen';
  @override String get invalidCode => 'Ongeldige code';
  @override String get accountCreated => 'Account aangemaakt';
  @override String get welcomeToGymies => 'Welkom bij Gymies!';
  @override String get loginFailed => 'Inloggen mislukt';
  @override String get registerFailed => 'Registratie mislukt';
  @override String get emailRequired => 'E-mailadres is verplicht';
  @override String get passwordRequired => 'Wachtwoord is verplicht';
  @override String get nameRequired => 'Naam is verplicht';
  @override String get invalidEmail => 'Ongeldig e-mailadres';
  @override String get passwordTooShort => 'Wachtwoord moet minimaal 8 tekens zijn';

  // ═══ ALGEMEEN ═══
  @override String get save => 'Opslaan';
  @override String get cancel => 'Annuleren';
  @override String get delete => 'Verwijderen';
  @override String get edit => 'Bewerken';
  @override String get confirm => 'Bevestigen';
  @override String get back => 'Terug';
  @override String get next => 'Volgende';
  @override String get done => 'Klaar';
  @override String get close => 'Sluiten';
  @override String get search => 'Zoeken';
  @override String get filter => 'Filter';
  @override String get sort => 'Sorteren';
  @override String get refresh => 'Vernieuwen';
  @override String get retry => 'Opnieuw proberen';
  @override String get loading => 'Laden...';
  @override String get noResults => 'Geen resultaten';
  @override String get viewAll => 'Alles bekijken';
  @override String get viewMore => 'Meer bekijken';
  @override String get showLess => 'Minder tonen';
  @override String get yes => 'Ja';
  @override String get no => 'Nee';
  @override String get ok => 'OK';
  @override String get send => 'Versturen';
  @override String get share => 'Delen';
  @override String get copy => 'Kopiëren';
  @override String get copied => 'Gekopieerd';
  @override String get today => 'Vandaag';
  @override String get tomorrow => 'Morgen';
  @override String get yesterday => 'Gisteren';
  @override String get thisWeek => 'Deze week';
  @override String get thisMonth => 'Deze maand';
  @override String get all => 'Alles';
  @override String get active => 'Actief';
  @override String get inactive => 'Inactief';
  @override String get pending => 'In afwachting';
  @override String get confirmed => 'Bevestigd';
  @override String get cancelled => 'Geannuleerd';
  @override String get completed => 'Afgerond';
  @override String get expired => 'Verlopen';
  @override String get newLabel => 'Nieuw';
  @override String get optional => 'Optioneel';
  @override String get required => 'Verplicht';
  @override String get unknown => 'Onbekend';
  @override String get none => 'Geen';
  @override String get other => 'Overig';
  @override String get total => 'Totaal';
  @override String get free => 'Gratis';
  @override String get per => 'per';
  @override String get minutes => 'minuten';
  @override String get hours => 'uur';
  @override String get days => 'dagen';
  @override String get weeks => 'weken';
  @override String get months => 'maanden';
  @override String get min => 'min';
  @override String get hour => 'uur';
  @override String get day => 'dag';
  @override String get week => 'week';
  @override String get month => 'maand';

  // ═══ INSTELLINGEN ═══
  @override String get settings => 'Instellingen';
  @override String get myProfile => 'Mijn profiel';
  @override String get myProfileSubtitle => 'Naam, e-mail, noodcontact';
  @override String get invoices => 'Facturen';
  @override String get invoicesSubtitle => 'Bekijk en download';
  @override String get security => 'BEVEILIGING';
  @override String get biometricEnabled => 'Ingeschakeld — log snel in';
  @override String get biometricDisabled => 'Schakel in voor snelle toegang';
  @override String biometricConfirmEnable(String label) => 'Bevestig $label om het in te schakelen';
  @override String biometricConfirmDisable(String label) => 'Bevestig $label om het uit te schakelen';
  @override String get account => 'ACCOUNT';
  @override String get help => 'HULP';
  @override String get support => 'Support';
  @override String get supportSubtitle => 'FAQ en contactformulier';
  @override String get tools => 'TOOLS';
  @override String get preferences => 'VOORKEUREN';
  @override String get subscription => 'Abonnement';
  @override String get documents => 'Documenten';
  @override String get verification => 'Verificatie';
  @override String get promoCodes => 'Promocodes';
  @override String get actionHistory => 'Actiegeschiedenis';
  @override String get agendaSync => 'Agenda sync';
  @override String get agendaSyncSubtitle => 'Nieuwe boekingen automatisch aan je kalender toevoegen';
  @override String get privacySafety => 'PRIVACY & VEILIGHEID';
  @override String get privacyData => 'Privacy & gegevens';
  @override String get privacyText => 'GYMIES verwerkt je persoonsgegevens conform de AVG (GDPR). Je data wordt niet met derden gedeeld en uitsluitend gebruikt voor het leveren van onze diensten. Je hebt te allen tijde het recht je gegevens in te zien, te corrigeren of te verwijderen.';
  @override String get requestMyData => 'Mijn gegevens opvragen';
  @override String get requestMyDataSubtitle => 'Ontvang een export van alle data die wij over je hebben';
  @override String get dataExportRequested => 'Gegevensexport aangevraagd — je ontvangt een e-mail';
  @override String get deleteAccount => 'Account verwijderen';
  @override String get deleteAccountSubtitle => 'Verwijder permanent je account en al je gegevens (AVG Art. 17)';
  @override String get deleteAccountWarning => 'Dit verwijdert je account en alle bijbehorende gegevens permanent. Deze actie kan niet ongedaan worden gemaakt.';
  @override String get deleteAccountRequested => 'Account verwijderaanvraag ingediend';
  @override String get language => 'Taal';
  @override String get languageSubtitle => 'Kies je voorkeurstaal';
  @override String get dutch => 'Nederlands';
  @override String get english => 'English';

  // ═══ SESSIES / BOEKINGEN ═══
  @override String get sessions => 'Sessies';
  @override String get session => 'Sessie';
  @override String get booking => 'Boeking';
  @override String get bookings => 'Boekingen';
  @override String get bookSession => 'Sessie boeken';
  @override String get bookNow => 'Nu boeken';
  @override String get upcomingSessions => 'Komende sessies';
  @override String get pastSessions => 'Eerdere sessies';
  @override String get noUpcomingSessions => 'Geen komende sessies';
  @override String get noPastSessions => 'Geen eerdere sessies';
  @override String get sessionConfirmed => 'Sessie bevestigd';
  @override String get sessionCancelled => 'Sessie geannuleerd';
  @override String get sessionCompleted => 'Sessie afgerond';
  @override String get cancelSession => 'Sessie annuleren';
  @override String get cancelSessionConfirm => 'Weet je zeker dat je deze sessie wilt annuleren?';
  @override String get rejectSession => 'Sessie afwijzen';
  @override String get rejectSessionConfirm => 'Weet je zeker dat je deze aanvraag wilt afwijzen?';
  @override String get reject => 'Afwijzen';
  @override String get sessionRejected => 'Sessie afgewezen';
  @override String get yesCancelSession => 'Ja, annuleren';
  @override String get sendStandbyPush => 'Stuur direct standby push';
  @override String get standbyPushSubtitle => 'Geinteresseerde klanten krijgen meteen een boekkans.';
  @override String get couldNotLoadSessions => 'Kon sessies niet laden.';
  @override String get couldNotLoadData => 'Kon gegevens niet laden. Probeer opnieuw.';
  @override String get nextSession => 'Volgende sessie';
  @override String get nextSessionIn => 'Volgende sessie over';
  @override String get duration => 'Duur';
  @override String durationMinutes(int count) => '$count minuten';
  @override String get date => 'Datum';
  @override String get time => 'Tijd';
  @override String get location => 'Locatie';
  @override String get online => 'Online';
  @override String get atClient => 'Bij de klant';
  @override String get atTrainer => 'Bij de trainer';
  @override String get outdoor => 'Buiten';
  @override String get gym => 'Sportschool';
  @override String get groupSession => 'Groepssessie';
  @override String get groupSessions => 'Groepssessies';
  @override String get privateSession => 'Privésessie';
  @override String get buddySession => 'Buddy sessie';
  @override String get trialSession => 'Proefles';
  @override String get recurringSession => 'Herhalende sessie';

  // ═══ TRAINER ═══
  @override String get trainer => 'Trainer';
  @override String get trainers => 'Trainers';
  @override String get myTrainers => 'Mijn trainers';
  @override String get findTrainer => 'Trainer zoeken';
  @override String get trainerProfile => 'Trainer profiel';
  @override String get about => 'Over';
  @override String get reviews => 'Beoordelingen';
  @override String get review => 'Beoordeling';
  @override String get rating => 'Score';
  @override String get prices => 'Tarieven';
  @override String get availability => 'Beschikbaarheid';
  @override String get specializations => 'Specialisaties';
  @override String get experience => 'Ervaring';
  @override String get certificates => 'Certificaten';
  @override String get km => 'km';
  @override String distanceAway(String distance) => '$distance km verderop';
  @override String get verified => 'Geverifieerd';
  @override String get topTrainer => 'Top trainer';
  @override String get proTrainer => 'Pro trainer';
  @override String get proPlus => 'Pro+';

  // ═══ KLANTEN ═══
  @override String get clients => 'Klanten';
  @override String get client => 'Klant';
  @override String get myClients => 'Mijn klanten';
  @override String get activeClients => 'Actieve klanten';
  @override String get newClient => 'Nieuwe klant';
  @override String get clientProfile => 'Klantprofiel';
  @override String get clientDossier => 'Klantdossier';
  @override String get couldNotLoadClients => 'Kon klantenoverzicht niet laden.';
  @override String get noClients => 'Nog geen klanten';
  @override String get addClient => 'Klant toevoegen';
  @override String get emergencyContact => 'Noodcontact';

  // ═══ BETALINGEN ═══
  @override String get payment => 'Betaling';
  @override String get payments => 'Betalingen';
  @override String get paymentReceived => 'Betaling ontvangen';
  @override String get paymentFailed => 'Betaling niet gelukt';
  @override String get paymentFailedRetry => 'Betaling niet gelukt. Je kunt het opnieuw proberen via de acties bij je boeking.';
  @override String get payNow => 'Nu betalen';
  @override String get price => 'Prijs';
  @override String get amount => 'Bedrag';
  @override String get payout => 'Uitbetaling';
  @override String get payouts => 'Uitbetalingen';
  @override String get balance => 'Saldo';
  @override String get revenue => 'Inkomsten';
  @override String get earnings => 'Verdiensten';
  @override String get commission => 'Commissie';
  @override String get fee => 'Kosten';
  @override String get vat => 'BTW';
  @override String get invoiceNumber => 'Factuurnummer';
  @override String get downloadInvoice => 'Factuur downloaden';
  @override String get invoiceLoadFailed => 'Facturen laden mislukt';
  @override String get creditBalance => 'Tegoed';
  @override String get lowCredit => 'Laag tegoed';
  @override String get topUp => 'Opwaarderen';
  @override String get perSession => 'per sessie';
  @override String get perMonth => 'per maand';
  @override String get perYear => 'per jaar';

  // ═══ BERICHTEN ═══
  @override String get messages => 'Berichten';
  @override String get message => 'Bericht';
  @override String get newMessage => 'Nieuw bericht';
  @override String get sendMessage => 'Bericht versturen';
  @override String get typeMessage => 'Typ een bericht...';
  @override String get noMessages => 'Geen berichten';
  @override String get conversations => 'Gesprekken';
  @override String get notifications => 'Meldingen';
  @override String get noNotifications => 'Geen meldingen';
  @override String get markAsRead => 'Markeer als gelezen';
  @override String get newsletter => 'Nieuwsbrief';

  // ═══ DASHBOARD ═══
  @override String get dashboard => 'Dashboard';
  @override String get overview => 'Overzicht';
  @override String get quickActions => 'Snelkoppelingen';
  @override String get todaySessions => 'Vandaag';
  @override String get actionRequired => 'Actie nodig';
  @override String get noActionRequired => 'Geen acties nodig';
  @override String get weekGoal => 'Weekdoel';
  @override String get weekGoalReached => 'Weekdoel bereikt!';
  @override String get sessionsThisWeek => 'Sessies deze week';
  @override String get revenueThisWeek => 'Inkomsten deze week';
  @override String get revenueThisMonth => 'Inkomsten deze maand';
  @override String get newClientsThisMonth => 'Nieuwe klanten deze maand';
  @override String get occupancyRate => 'Bezettingsgraad';
  @override String get averageRating => 'Gemiddelde beoordeling';
  @override String get totalSessions => 'Totaal sessies';
  @override String upcomingCount(int count) => '$count komende';
  @override String pendingCount(int count) => '$count in afwachting';

  // ═══ MEER SCHERM ═══
  @override String get more => 'Meer';
  @override String get marketing => 'Marketing';
  @override String get marketingTools => 'Marketing Tools';
  @override String get myStorefront => 'Mijn Etalage';
  @override String get profileAndBio => 'Profiel & Bio';
  @override String get pricesAndPayment => 'Tarieven & Betaling';
  @override String get logisticsAndCancellation => 'Logistiek & Annulering';
  @override String get socialAndGallery => 'Social Media & Gallerij';
  @override String get branding => 'Branding';
  @override String get seoAndVerification => 'SEO & Verificatie';
  @override String get finances => 'Financiën';
  @override String get agenda => 'Agenda';
  @override String get qrCode => 'QR-code';
  @override String get widget => 'Widget';

  // ═══ KLANT HOME ═══
  @override String get welcomeTip => 'Welkom bij Gymies! Boek je eerste sessie en begin je fitnessreis.';
  @override String get myGroupSessions => 'Mijn groepssessies';
  @override String get favorites => 'Favorieten';
  @override String get noFavorites => 'Nog geen favorieten';
  @override String get recentlyViewed => 'Recent bekeken';
  @override String get recommended => 'Aanbevolen';
  @override String get nearYou => 'Bij jou in de buurt';
  @override String get popular => 'Populair';
  @override String get categories => 'Categorieën';
  @override String get seeAll => 'Bekijk alles';

  // ═══ ZOEKEN / ONTDEKKEN ═══
  @override String get discover => 'Ontdekken';
  @override String get searchTrainer => 'Zoek trainer...';
  @override String get searchLocation => 'Zoek locatie...';
  @override String get noTrainersFound => 'Geen trainers gevonden';
  @override String get adjustFilters => 'Pas je filters aan voor meer resultaten';
  @override String get sortByDistance => 'Afstand';
  @override String get sortByRating => 'Beoordeling';
  @override String get sortByPrice => 'Prijs';
  @override String get filterDistance => 'Afstand';
  @override String get filterPrice => 'Prijs';
  @override String get filterCategory => 'Categorie';
  @override String get filterAvailability => 'Beschikbaarheid';
  @override String get applyFilters => 'Filters toepassen';
  @override String get clearFilters => 'Filters wissen';
  @override String get results => 'resultaten';
  @override String resultCount(int count) => '$count resultaten';

  // ═══ BEOORDELINGEN ═══
  @override String get writeReview => 'Beoordeling schrijven';
  @override String get yourRating => 'Jouw score';
  @override String get yourReview => 'Jouw beoordeling';
  @override String get submitReview => 'Beoordeling indienen';
  @override String get reviewSubmitted => 'Beoordeling ingediend';
  @override String get noReviews => 'Nog geen beoordelingen';

  // ═══ PROMO / REFERRAL ═══
  @override String get referral => 'Doorverwijzing';
  @override String get referralCode => 'Doorverwijscode';
  @override String get shareYourCode => 'Deel jouw code';
  @override String get inviteFriends => 'Vrienden uitnodigen';
  @override String get earnRewards => 'Verdien beloningen';

  // ═══ FOUTMELDINGEN ═══
  @override String get errorGeneric => 'Er is iets misgegaan';
  @override String get errorNetwork => 'Geen internetverbinding';
  @override String get errorServer => 'Serverfout — probeer het later opnieuw';
  @override String get errorTimeout => 'Verzoek verlopen — probeer opnieuw';
  @override String get errorUnauthorized => 'Sessie verlopen — log opnieuw in';
  @override String get errorNotFound => 'Niet gevonden';
  @override String get errorForbidden => 'Geen toegang';
  @override String get errorLoadFailed => 'Laden mislukt';
  @override String get errorSaveFailed => 'Opslaan mislukt';
  @override String get errorDeleteFailed => 'Verwijderen mislukt';
  @override String get errorSendFailed => 'Versturen mislukt';
  @override String get successSaved => 'Opgeslagen';
  @override String get successDeleted => 'Verwijderd';
  @override String get successSent => 'Verstuurd';
  @override String get successUpdated => 'Bijgewerkt';

  // ═══ SOS / VEILIGHEID ═══
  @override String get sos => 'SOS';
  @override String get sosAlert => 'SOS Melding';
  @override String get safeSession => 'Veilige sessie';
  @override String get safeSessionActive => 'Veilige sessie actief';
  @override String get safeSessionEnded => 'Veilige sessie beëindigd';
  @override String get iAmSafe => 'Ik ben veilig';
  @override String get sendSos => 'Stuur SOS';

  // ═══ ABONNEMENT ═══
  @override String get currentPlan => 'Huidig plan';
  @override String get upgradePlan => 'Upgrade plan';
  @override String get downgradePlan => 'Downgrade plan';
  @override String get freePlan => 'Gratis';
  @override String get starterPlan => 'Starter';
  @override String get proPlan => 'Pro';
  @override String get proPlusPlan => 'Pro+';
  @override String get suitePlan => 'Suite';
  @override String get featuresIncluded => 'Inbegrepen features';
  @override String get perMonthLabel => '/maand';
  @override String trialDaysLeft(int count) => '$count proefdagen over';
  @override String get trialExpired => 'Proefperiode verlopen';

  // ═══ AGENDA ═══
  @override String get calendar => 'Kalender';
  @override String get availabilitySlots => 'Beschikbaarheid';
  @override String get setAvailability => 'Beschikbaarheid instellen';
  @override String get dayOff => 'Vrije dag';
  @override String get exception => 'Uitzondering';
  @override String get addException => 'Uitzondering toevoegen';
  @override String get recurringSlot => 'Terugkerend tijdslot';

  // ═══ CHECK-IN ═══
  @override String get checkIn => 'Inchecken';
  @override String get scanQr => 'Scan QR-code';
  @override String get showQr => 'Toon QR-code';
  @override String get checkedIn => 'Ingecheckt';
  @override String get checkInSuccess => 'Succesvol ingecheckt!';

  // ═══ INVAL ═══
  @override String get substitute => 'Invaller';
  @override String get substituteRequest => 'Invalverzoek';
  @override String get urgentSubstitute => 'Spoedinval';
  @override String get lookingForSubstitute => 'Zoekt invaller';
  @override String get acceptSubstitute => 'Inval accepteren';

  // ═══ WACHTLIJST ═══
  @override String get waitlist => 'Wachtlijst';
  @override String get joinWaitlist => 'Op wachtlijst zetten';
  @override String get leaveWaitlist => 'Van wachtlijst verwijderen';
  @override String get waitlistPosition => 'Positie op wachtlijst';
  @override String get spotAvailable => 'Plek beschikbaar!';

  // ═══ OVERIG ═══
  @override String get appVersion => 'App versie';
  @override String get termsOfService => 'Algemene voorwaarden';
  @override String get privacyPolicy => 'Privacybeleid';
  @override String get contactUs => 'Neem contact op';
  @override String get faq => 'Veelgestelde vragen';
  @override String get rateApp => 'Beoordeel de app';
  @override String get shareApp => 'Deel de app';
  @override String get updateAvailable => 'Update beschikbaar';
  @override String get updateNow => 'Nu updaten';
  @override String get forceUpdateTitle => 'Update vereist';
  @override String get forceUpdateMessage => 'Er is een nieuwe versie beschikbaar. Update de app om door te gaan.';
  @override String get biometric => 'Biometrie';
  @override String get faceId => 'Face ID';
  @override String get touchId => 'Touch ID';
  @override String get fingerprint => 'Vingerafdruk';

  /// Factory constructor for English — avoids a separate file during bootstrapping.
  factory SNl.en() = _SEn;

  // ═══ EXTRA SCREEN STRINGS ═══
  @override String get createAccount => 'Account aanmaken';
  @override String get almostDone => 'Bijna klaar!';
  @override String get checkEmailForInstructions => 'Check je e-mail voor instructies om je wachtwoord te resetten.';
  @override String get theseFieldsAreOptional => 'Deze velden zijn optioneel';
  @override String get gender => 'Geslacht';
  @override String get mustAgreeTerms => 'Je moet akkoord gaan met de Algemene voorwaarden.';
  @override String get mustAgreePrivacy => 'Je moet akkoord gaan met het Privacybeleid.';
  @override String get chooseYourRole => 'Kies je rol om te beginnen';
  @override String get chooseGender => 'Kies of je als man of vrouw geregistreerd staat.';
  @override String get rememberMe => 'Onthoud mij';
  @override String get connectionFailed => 'Verbinding mislukt. Controleer je internet en probeer opnieuw.';
  @override String get forgotten => 'Vergeten?';
  @override String get taglineText => 'Vind jouw personal trainer\nen boek direct';
  @override String get enterEmailAndPassword => 'Vul je e-mail en wachtwoord in';
  @override String get enterEmailForReset => 'Vul je e-mailadres in. We sturen je een link om je wachtwoord te resetten.';
  @override String get whoAreYou => 'Wie ben je?';
  @override String get repeatPassword => 'Herhaal wachtwoord';
  @override String get canNowLoginNewPassword => 'Je kunt nu inloggen met je nieuwe wachtwoord.';
  @override String get chooseStrongPassword => 'Kies een sterk wachtwoord van minimaal 8 tekens.';
  @override String get minimum8Characters => 'Minimaal 8 tekens';
  @override String get goToLogin => 'Naar inloggen';
  @override String get newPassword => 'Nieuw wachtwoord';
  @override String get setNewPassword => 'Stel een nieuw wachtwoord in';
  @override String get passwordChanged => 'Wachtwoord gewijzigd';
  @override String get savePassword => 'Wachtwoord opslaan';
  @override String get resetPasswordTitle => 'Wachtwoord resetten';
  @override String get code => 'Code';
  @override String get resendCodeAction => 'Code opnieuw sturen';
  @override String get verifyEmailTitle => 'E-mail verifi\u00ebren';
  @override String get verify => 'Verifi\u00ebren';
  @override String get viewTrainer => 'Bekijk trainer';
  @override String get goToDiscoverToBook => 'Ga naar Ontdekken om een trainer te boeken';
  @override String get howManySessions => 'Hoeveel sessies per week?';
  @override String get discoverTrainers => 'Ontdek trainers';
  @override String get quickNav => 'Snel naar';
  @override String get streak => 'Streak';
  @override String get tipLabel => 'TIP';
  @override String get totalLabel => 'Totaal';
  @override String get setWeekGoal => 'Weekdoel instellen';
  @override String get ifTrainerFullyBooked => 'Als een trainer volgeboekt is, kun je je op de wachtlijst plaatsen.';
  @override String get viewMySessions => 'Bekijk mijn sessies';
  @override String get describeSituation => 'Beschrijf de situatie in detail...';
  @override String get describeIssueClearly => 'Beschrijf het probleem zo duidelijk mogelijk. We nemen het zo snel mogelijk in behandeling.';
  @override String get payNowAction => 'Betaal nu';
  @override String get paymentMethod => 'Betaalmethode';
  @override String get paymentSuccessful => 'Betaling gelukt!';
  @override String get exampleNoShow => 'Bijv. No-show, kwaliteitsprobleem...';
  @override String get cashAtTrainer => 'Cash bij trainer';
  @override String get downloadPdfDirectly => 'Download de PDF direct na openen.';
  @override String get useCode => 'Gebruik code';
  @override String get noEnrollments => 'Geen inschrijvingen';
  @override String get noWaitlists => 'Geen wachtlijsten';
  @override String get fileDispute => 'Geschil indienen';
  @override String get notEnrolledGroupSession => 'Je hebt je nog niet ingeschreven voor een groepsles.';
  @override String get sessionIsConfirmed => 'Je sessie is bevestigd';
  @override String get couldNotFileDispute => 'Kon geschil niet indienen.';
  @override String get moreActions => 'Meer acties';
  @override String get onlineMollie => 'Online (Mollie)';
  @override String get promoCodeOptional => 'Promocode (optioneel)';
  @override String get reason => 'Reden';
  @override String get referralBenefitAvailable => 'Referral voordeel beschikbaar';
  @override String get explanationOptional => 'Toelichting (optioneel)';
  @override String get training => 'Training';
  @override String get confirmCancelSession => 'Weet je zeker dat je deze sessie wilt annuleren?';
  @override String get findATrainer => 'Zoek een trainer';
  @override String get exampleName => 'Bijv. Jan Jansen';
  @override String get exampleCity => 'Bijv. Rotterdam, Amsterdam';
  @override String get emailEmergencyContact => 'E-mail noodcontact';
  @override String get repeatNewPassword => 'Herhaal nieuw wachtwoord';
  @override String get currentPassword => 'Huidig wachtwoord';
  @override String get myProfileTitle => 'Mijn profiel';
  @override String get myCity => 'Mijn stad';
  @override String get nameLabel => 'Naam';
  @override String get emergencyContactName => 'Naam noodcontact';
  @override String get retryAction => 'Opnieuw proberen';
  @override String get saveAction => 'Opslaan';
  @override String get personalDetails => 'Persoonlijke gegevens';
  @override String get profileSaved => 'Profiel opgeslagen';
  @override String get phoneLabel => 'Telefoon';
  @override String get emergencyContactPhone => 'Telefoonnummer noodcontact';
  @override String get passwordSuccessfullyChanged => 'Wachtwoord succesvol gewijzigd';
  @override String get changePassword => 'Wachtwoord wijzigen';
  @override String get emergencyContactInfo => 'Wordt ge\u00efnformeerd bij een SOS-alert';
  @override String get emergencyContactPlaceholder => 'noodcontact@voorbeeld.nl';
  @override String get nameIsRequired => 'Naam is verplicht';
  @override String get enterMinimum10Digits => 'Voer minimaal 10 cijfers in';
  @override String get phoneNumberTooLong => 'Telefoonnummer is te lang';
  @override String get enterCurrentPassword => 'Vul je huidige wachtwoord in';
  @override String get minimumCharacters => 'Minimaal 8 tekens';
  @override String get passwordsDoNotMatch => 'Wachtwoorden komen niet overeen';
  @override String get couldNotLoadProfile => 'Kon profiel niet laden.';
  @override String get emergencyContactLabel => 'Noodcontact';
  @override String get messageLabel => 'Bericht';
  @override String get describeProblemClearly => 'Beschrijf het probleem zo duidelijk mogelijk';
  @override String get bookingId => 'Boeking-ID';
  @override String get contactLabel => 'Contact';
  @override String get checkInternetRetry => 'Controleer je internet en probeer opnieuw.';
  @override String get ticketNoLongerExists => 'Dit ticket bestaat niet meer';
  @override String get ticketResolved => 'Dit ticket is opgelost';
  @override String get invoiceIdLabel => 'Factuur-ID';
  @override String get avgResponseTime => 'Gemiddelde reactietijd: ~2 uur';
  @override String get ticketsAppearHere => 'Hier verschijnen je tickets wanneer\nje contact opneemt.';
  @override String get howCanWeHelp => 'Hoe kunnen we je helpen?';
  @override String get cantFigureItOut => 'Kom je er niet uit?';
  @override String get couldNotLoadTicket => 'Kon ticket niet laden';
  @override String get briefSummary => 'Korte samenvatting';
  @override String get notFoundWhatLooking => 'Niet gevonden wat je zocht?';
  @override String get newSupportRequest => 'Nieuw supportverzoek';
  @override String get createNewRequest => 'Nieuw verzoek aanmaken';
  @override String get noSupportRequests => 'Nog geen supportverzoeken';
  @override String get subjectLabel => 'Onderwerp';
  @override String get againLabel => 'Opnieuw';
  @override String get startConversation => 'Start een gesprek met ons team';
  @override String get sendUsMessage => 'Stuur ons een bericht';
  @override String get supportContextNote => 'Support blijft gekoppeld aan de trainer/sessie-context van je verzoek.';
  @override String get supportRequestCreated => 'Supportverzoek aangemaakt!';
  @override String get supportRequestFailed => 'Supportverzoek mislukt';
  @override String get ticketClosedNoReply => 'Ticket is afgerond en kan niet meer worden beantwoord.';
  @override String get typeLabel => 'Type';
  @override String get submitRequest => 'Verstuur verzoek';
  @override String get findAnswerOrContact => 'Vind een antwoord of neem contact op';
  @override String get waitingForReply => 'Wacht op reactie van support';
  @override String get backupCode => 'Backup code';
  @override String get backupCodeCopied => 'Backup code gekopieerd';
  @override String get checkInLabel => 'Check-in';
  @override String get cantScanQr => 'Kan de QR niet gescand worden? Geef deze code aan je trainer.';
  @override String get letTrainerScanQr => 'Laat deze QR-code scannen door je trainer';
  @override String get generateNewQr => 'Nieuwe QR genereren';
  @override String get generatingQr => 'QR-code genereren...';
  @override String get disputeMessages => 'BERICHTEN';
  @override String get disputeResolvedNoMessages => 'Dit geschil is opgelost. Je kunt geen berichten meer versturen.';
  @override String get dispute => 'Geschil';
  @override String get couldNotSendMessage => 'Kon bericht niet versturen.';
  @override String get noMessagesYet => 'Nog geen berichten';
  @override String get typeAMessage => 'Typ een bericht...';
  @override String get noDisputes => 'Geen geschillen';
  @override String get disputes => 'Geschillen';
  @override String get ifYouHaveBookingIssue => 'Mocht je ooit een probleem hebben met een boeking,';
  @override String get attendance => 'Aanwezigheid';
  @override String get coachNotes => 'Coach notes';
  @override String get goalsLabel => 'Doelen';
  @override String get feedbackFromTrainer => 'Feedback en notities van je trainer na een sessie.';
  @override String get noChartData => 'Geen grafiekdata voor deze metriek.';
  @override String get weightLabel => 'Gewicht';
  @override String get instructionVideo => 'Instructievideo\'s';
  @override String get noProgressShared => 'Je trainer deelt nog geen progressie.';
  @override String get myDossier => 'Mijn dossier';
  @override String get noCoachNotesYet => 'Nog geen coach notes.';
  @override String get noGoalsSetYet => 'Nog geen doelen ingesteld door je trainer.';
  @override String get achievementLabel => 'Prestatie';
  @override String get progressAndRhythm => 'Progressie & ritme';
  @override String get videoLabel => 'Video\'s';
  @override String get favoritesTitle => 'Favorieten';
  @override String get searchByNameSpeciality => 'Zoek op naam, specialiteit of regio';
  @override String get cancelLabel => 'Annuleren';
  @override String get descriptionLabel => 'Beschrijving';
  @override String get lessonCancelled => 'Deze les is geannuleerd';
  @override String get groupSessionLabel => 'Groepsles';
  @override String get enrolledLabel => 'Ingeschreven';
  @override String get cancelEnrollment => 'Inschrijving annuleren';
  @override String get enrollmentCancelled => 'Inschrijving geannuleerd';
  @override String get spotReserved => 'Je plek is gereserveerd.';
  @override String get noGroupSessionsPlanned => 'Er zijn momenteel geen groepslessen gepland in de gekozen periode.';
  @override String get goingAhead => 'Gaat door!';
  @override String get noGroupSessionsFound => 'Geen groepslessen gevonden';
  @override String get groupSessionsTitle => 'Groepslessen';
  @override String get viewAction => 'Bekijk';
  @override String get paymentProof => 'Betaalbewijs';
  @override String get downloadPdf => 'Download PDF';
  @override String get downloadInvoiceAsPdf => 'Download de factuur direct als PDF.';
  @override String get noDownloadLink => 'Geen downloadlink beschikbaar.';
  @override String get copyLink => 'Kopieer link';
  @override String get myInvoices => 'Mijn facturen';
  @override String get pdfDownload => 'PDF downloaden';
  @override String get requestInvoice => 'Vraag aan';
  @override String get conversationDeleted => 'Gesprek verwijderd';
  @override String get inboxLabel => 'Inbox';
  @override String get couldNotDeleteConversation => 'Kon gesprek niet verwijderen';
  @override String get discoverTrainersNearYou => 'Ontdek trainers bij jou in de buurt';
  @override String get sessionStartsSoon => 'Sessie begint zo';
  @override String get rescheduleSession => 'Sessie verplaatsen';
  @override String get tapToResend => 'Tik om opnieuw te versturen';
  @override String get rescheduleAnyway => 'Toch verplaatsen';
  @override String get trainerIdMissing => 'Trainer-ID ontbreekt';
  @override String get rescheduleAction => 'Verplaats';
  @override String get rescheduleFailed => 'Verplaatsen mislukt. Probeer het opnieuw.';
  @override String get searchConversations => 'Zoek gesprekken...';
  @override String get typingIndicator => 'aan het typen...';
  @override String get getStarted => 'Aan de slag';
  @override String get youAreReady => 'Je bent klaar!';
  @override String get fitnessJourneyStarts => 'Jouw persoonlijke fitness journey begint hier.';
  @override String get skipLabel => 'Overslaan';
  @override String get tellAboutYourself => 'Vertel iets over jezelf';
  @override String get nextAction => 'Volgende';
  @override String get trainersCanFindYou => 'Zo kunnen trainers je beter vinden.';
  @override String get accountDeleteRequested => 'Account verwijderaanvraag ingediend';
  @override String get calendarSync => 'Agenda synchronisatie';
  @override String get autoSyncDescription => 'Nieuwe sessies worden automatisch aan je kalender toegevoegd.';
  @override String get autoAdd => 'Automatisch toevoegen';
  @override String get confirmNewPassword => 'Bevestig nieuw wachtwoord';
  @override String get gdprNote => 'GYMIES verwerkt je persoonsgegevens conform de AVG (GDPR).';
  @override String get dataExportRequestedEmail => 'Gegevensexport aangevraagd \u2014 je ontvangt een e-mail';
  @override String get strongPasswordHint => 'Kies een sterk wachtwoord van minimaal 8 tekens met letters en cijfers.';
  @override String get couldNotRequestExport => 'Kon export niet aanvragen. Probeer later opnieuw.';
  @override String get couldNotRequestDeletion => 'Kon verwijderaanvraag niet indienen. Probeer later opnieuw.';
  @override String get couldNotChangePassword => 'Kon wachtwoord niet wijzigen. Probeer later opnieuw.';
  @override String get supportedCalendars => 'Ondersteunde kalenders:';
  @override String get privacyAndData => 'Privacy & gegevens';
  @override String get quietHours => 'Stille uren';
  @override String get tapToAdjust => 'Tik om aan te passen';
  @override String get tipManualCalendar => 'Tip: Je kunt ook handmatig een sessie aan je agenda toevoegen.';
  @override String get whatIsYourGoal => 'Wat is je doel?';
  @override String get subscriptionsAndPackages => 'Abonnementen & pakketten';
  @override String get viewAllReviews => 'Alle reviews bekijken';
  @override String get thankYouForReport => 'Bedankt voor je melding.';
  @override String get viewAllAction => 'Bekijk alle';
  @override String get viewPackages => 'Bekijk pakketten';
  @override String get viewFullProfile => 'Bekijk volledig profiel';
  @override String get availabilityLabel => 'Beschikbaarheid';
  @override String get payCashOnDay => 'Betaal contant op de dag zelf';
  @override String get securedViaMollie => 'Beveiligd via Mollie \u2014 directe bevestiging';
  @override String get confirmBooking => 'Bevestig boeking';
  @override String get bookingInProgress => 'Bezig met boeken...';
  @override String get bookSessionAction => 'Boek sessie';
  @override String get bookingCreatedPaymentFailed => 'Boeking aangemaakt maar betaling kon niet worden gestart.';
  @override String get bookingCreatedOpen => 'Boeking aangemaakt!';
  @override String get bookingConfirmedCash => 'Boeking bevestigd! Betaal cash bij je trainer.';
  @override String get finalPriceOnBooking => 'Definitieve prijs bij het boeken.';
  @override String get chosenPackage => 'GEKOZEN PAKKET';
  @override String get galleryLabel => 'Galerij';
  @override String get onStandbyList => 'Je staat nu op de standby-lijst';
  @override String get redirectedToPayment => 'Je wordt doorgestuurd naar de betaalpagina...';
  @override String get onlyPublicInfo => 'Je ziet hier alleen openbare profielinformatie.';
  @override String get chooseDate => 'KIES EEN DATUM';
  @override String get chooseTime => 'KIES EEN TIJDSTIP';
  @override String get choosePackage => 'Kies een pakket';
  @override String get couldNotOpenMaps => 'Kon kaarten-app niet openen.';
  @override String get lastReview => 'Laatste review';
  @override String get locationLabel => 'Locatie';
  @override String get singleSession => 'Losse sessie';
  @override String get moreDates => 'Meer data';
  @override String get reportAction => 'Melden';
  @override String get afternoonLabel => 'Middag';
  @override String get noBioAdded => 'Nog geen bio toegevoegd.';
  @override String get noMediaAdded => 'Nog geen media toegevoegd.';
  @override String get noPublicAvailability => 'Nog geen publieke beschikbaarheid.';
  @override String get noPublicPackages => 'Nog geen publieke pakketten.';
  @override String get noReviewsAvailable => 'Nog geen reviews beschikbaar.';
  @override String get addNoteForTrainer => 'Notitie voor trainer toevoegen...';
  @override String get morningLabel => 'Ochtend';
  @override String get onlineHomeGym => 'Online / thuis / gym afhankelijk van afspraak';
  @override String get payOnline => 'Online betalen';
  @override String get onStandbyListLabel => 'Op standby-lijst';
  @override String get aboutMe => 'Over mij';
  @override String get packageLabel => 'Pakket';
  @override String get planRoute => 'Plan route';
  @override String get shareProfile => 'Profiel delen';
  @override String get reportProfile => 'Profiel melden';
  @override String get reviewsGalleryMore => 'Reviews, galerij, pakketten en meer';
  @override String get specializationsLabel => 'Specialisaties';
  @override String get storiesLabel => 'Stories';
  @override String get ratesIndication => 'Tarieven (indicatie)';
  @override String get backLabel => 'Terug';
  @override String get fromPrice => 'Vanaf';
  @override String get removeFromMyTrainers => 'Verwijder uit mijn trainers';
  @override String get videoCannotBePlayed => 'Video kan niet worden afgespeeld';
  @override String get nextWeek => 'Volgende week';
  @override String get idealCreditcardApplePay => 'iDEAL, creditcard, Apple Pay';
  @override String get noReviewsYet => 'Nog geen reviews';
  @override String get beFirstToReview => 'Wees de eerste die een beoordeling achterlaat na een sessie.';
  @override String get noStandbyEnrollments => 'Geen standby-inschrijvingen';
  @override String get myWaitlists => 'Mijn wachtlijsten';
  @override String get standbyEnrollmentRemoved => 'Standby-inschrijving verwijderd';
  @override String get historyLabel => 'GESCHIEDENIS';
  @override String get howToEarnPoints => 'HOE VERDIEN JE PUNTEN?';
  @override String get currentBalance => 'Huidig saldo';
  @override String get loadMore => 'Meer laden';
  @override String get myCredit => 'Mijn Tegoed';
  @override String get noTransactions => 'Nog geen transacties';
  @override String get pointsRedeemed => 'Punten ingewisseld!';
  @override String get redeemPoints => 'Punten inwisselen';
  @override String get notificationPreferences => 'Melding voorkeuren';
  @override String get notificationsTitle => 'Meldingen';
  @override String get openRelatedPage => 'Open gerelateerde pagina';
  @override String get smartReminders => 'Slimme reminders: T-24u, T-2u, check-in en gemiste check-in.';
  @override String get myGroupSessionsTitle => 'Mijn groepslessen';
  @override String get distanceLabel => 'Afstand';
  @override String get clearAllFilters => 'Alle filters wissen';
  @override String get clearAllAction => 'Alles wissen';
  @override String get noGroupSessionsInNext60Days => 'Er zijn momenteel geen groepslessen gepland\nin de komende 60 dagen.';
  @override String get filtersLabel => 'Filters';
  @override String get noDistanceFilter => 'Geen afstandsfilter';
  @override String get chooseSessionType => 'Kies lesvorm';
  @override String get chooseSpeciality => 'Kies specialiteit';
  @override String get chooseCity => 'Kies stad';
  @override String get logInAgain => 'Log opnieuw in';
  @override String get maxPricePerSession => 'Max. prijs per sessie';
  @override String get myEnrollments => 'Mijn inschrijvingen';
  @override String get myTrainersLabel => 'Mijn trainers';
  @override String get minRating => 'Min. beoordeling';
  @override String get discoverTitle => 'Ontdekken';
  @override String get searchAgain => 'Opnieuw zoeken';
  @override String get priceOnRequest => 'Prijs op aanvraag';
  @override String get sortAction => 'Sorteer';
  @override String get sortByLabel => 'Sorteren op';
  @override String get searchTrainerSpecialism => 'Zoek trainer, specialisme of stad...';
  @override String get actionNeeded => 'Actie nodig';
  @override String get activateAccount => 'Activeer je account';
  @override String get declineAction => 'Afwijs';
  @override String get viewAllAction2 => 'Alles bekijken';
  @override String get confirmAction => 'Bevestig';
  @override String get laterLabel => 'Later';
  @override String get activateNow => 'Nu activeren';
  @override String get revenueThisMonthLabel => 'OMZET DEZE MAAND';
  @override String get respondAction => 'Reageer';
  @override String get quickActionsLabel => 'SNELLE ACTIES';
  @override String get storiesProFeature => 'Stories is een Pro feature. Upgrade je abonnement.';
  @override String get storyPosted => 'Story geplaatst!';
  @override String get toConfirmLabel => 'TE BEVESTIGEN';
  @override String get nextSessionLabel => 'VOLGENDE SESSIE';
  @override String get completeOnboarding => 'Voltooi je onboarding om sessies aan te bieden.';
  @override String get weekGoalLabel => 'WEEKDOEL';
  @override String get allClientsActive => 'Alle klanten zijn actief!';
  @override String get allFilter => 'Alles';
  @override String get analyticsLabel => 'Analytics';
  @override String get autoRebook => 'Auto-herboekingen';
  @override String get describeUrgentIssue => 'Beschrijf kort het urgente probleem';
  @override String get bookingRefOptional => 'Booking reference (optioneel)';
  @override String get bulkMessageSend => 'Bulk bericht versturen';
  @override String get communicationLabel => 'Communicatie';
  @override String get noClientsForFilter => 'Geen klanten gevonden voor dit filter.';
  @override String get remindAction => 'Herinner';
  @override String get inactiveClientsLabel => 'INACTIEVE KLANTEN';
  @override String get issueLabel => 'Issue';
  @override String get addClientComingSoon => 'Klant toevoegen komt binnenkort';
  @override String get clientIdMissing => 'Klant-ID ontbreekt.';
  @override String get howManyDaysInactivity => 'Na hoeveel dagen inactiviteit ontvangen klanten automatisch een herinnering?';
  @override String get noHealthScoreData => 'Nog geen health score data beschikbaar.';
  @override String get noUpsellSuggestions => 'Nog geen upsell suggesties beschikbaar.';
  @override String get openPriorityLane => 'Open priority lane';
  @override String get packagesExpiringSoon => 'PAKKETTEN BIJNA VERLOPEN';
  @override String get sendActionLabel => 'Stuur';
  @override String get sendMessageToAllClients => 'Stuur een bericht naar al je klanten tegelijk.';
  @override String get sendingLabel => 'Versturen\u2026';
  @override String get forUrgentIssues => 'Voor urgente operationele issues.';
  @override String get searchClient => 'Zoek klant...';
  @override String get clientInsightsCouldNotLoad => 'Kon inzichten niet laden.';
  @override String get clientAnalyticsCouldNotLoad => 'Kon analytics niet laden.';
  @override String get activeStatusLabel => 'Actief';
  @override String get riskLabel => 'Risico';
  @override String get inactiveStatusLabel => 'Inactief';
  @override String get newStatusLabel => 'Nieuw';
  @override String get todayDateLabel => 'Vandaag';
  @override String get yesterdayDateLabel => 'Gisteren';
  @override String get clientSingle => 'Klant';
  @override String get noSessionsLabel => 'Geen sessies';
  @override String get rebookInterval => 'Herboek-interval';
  @override String get sendAllReminders => 'Alle herinneringen versturen?';
  @override String get bulkMessageLabel => 'Bulk bericht';
  @override String get prioritySupportLane => 'Priority support lane';
  @override String get healthScoresLabel => 'Health Scores';
  @override String get upsellSuggestionsLabel => 'Upsell suggesties';
  @override String get smartRebook => 'Smart Rebook';
  @override String get sessionsCountLabel => 'Sessies';
  @override String get revenueCountLabel => 'Omzet';
  @override String get searchClientTooltip => 'Zoek klant';
  @override String get addClientTooltip => 'Klant toevoegen';
  @override String get overviewTab => 'Overzicht';
  @override String get insightsTab => 'Inzichten';
  @override String get moreTab => 'Meer';
  @override String get clientInsightsFeature => 'Klantinzichten';
  @override String get analyticsCommsFeature => 'Analytics & Communicatie';
  @override String get noClientsFoundTitle => 'Geen klanten gevonden';
  @override String get clientsAppearAfterBooking => 'Klanten verschijnen hier zodra ze een sessie boeken.';
  @override String get packageUpgrade => 'Pakket-upgrade';
  @override String get expiredStatusLabel => 'Verlopen';
  @override String get longerThan7DaysInactive => 'Langer dan 7 dagen inactief';
  @override String get createAction => 'Aanmaken';
  @override String get viewPdf => 'Bekijk de PDF';
  @override String get descriptionOptional => 'Beschrijving (optioneel)';
  @override String get evidenceUrlOptional => 'Bewijs URL (optioneel)';
  @override String get endSession => 'Be\u00ebindig sessie';
  @override String get endSessionAction => 'Be\u00ebindigen';
  @override String get exampleClientNoShow => 'Bijv. klant niet verschenen';
  @override String get checkInQueued => 'Check-in in wachtrij geplaatst.';
  @override String get registerCheckIn => 'Check-in registreren';
  @override String get dateAndTime => 'Datum & tijd';
  @override String get serviceLabel => 'Dienst';
  @override String get documentsNotComplete => 'Documenten nog niet compleet opgeslagen.';
  @override String get durationLabel => 'Duur';
  @override String get invoiceCreatedNoPdf => 'Factuur aangemaakt maar PDF-link ontbreekt.';
  @override String get invoiceAmountMustBePositive => 'Factuurbedrag moet groter zijn dan 0';
  @override String get groupSessionCreated => 'Groepsles aangemaakt!';
  @override String get heartbeatActive => 'Heartbeat actief';
  @override String get chooseDateAndTime => 'Kies een datum en tijd';
  @override String get couldNotOpenPdf => 'Kon PDF niet openen.';
  @override String get maxParticipants => 'Max deelnemers';
  @override String get registerNoShow => 'No-show registreren';
  @override String get noteOptional => 'Notitie (optioneel)';
  @override String get composeAndSend => 'Opstellen & versturen';
  @override String get optionalNote => 'Optionele notitie...';
  @override String get pdfLinkInvalid => 'PDF link is ongeldig.';
  @override String get pdfMissingOnServer => 'PDF ontbreekt op server.';
  @override String get priceInclVat => 'Prijs incl. BTW (EUR)';
  @override String get safeSessionActiveLabel => 'Safe session actief';
  @override String get startSafeSession => 'Safe session starten';
  @override String get serviceDate => 'Service datum';
  @override String get sessionSingle => 'Sessie';
  @override String get endSessionQuestion => 'Sessie be\u00ebindigen?';
  @override String get moveAction => 'Verplaatsen';
  @override String get elapsedTime => 'Verstreken tijd';
  @override String get expiryDate => 'Vervaldatum';
  @override String get completeAction => 'Voltooien';
  @override String get availabilitySettings => 'Beschikbaarheid-instellingen';
  @override String get blockingLabel => 'Blokkering';
  @override String get bookInAdvance => 'Boeken van tevoren';
  @override String get dayLabel => 'Dag';
  @override String get dateInputLabel => 'Datum';
  @override String get settingsShownOnProfile => 'Deze instellingen worden getoond op je profiel.';
  @override String get endTimeLabel => 'Eind';
  @override String get endTimeMustBeLater => 'Eindtijd moet later zijn dan starttijd.';
  @override String get blockedExceptionLabel => 'Geblokkeerd (uitzondering)';
  @override String get blockedDays => 'Geblokkeerde dagen';
  @override String get howManyDaysAdvance => 'Hoeveel dagen van tevoren kan een klant boeken?';
  @override String get chooseDayAndTimes => 'Kies de dag en tijden.';
  @override String get copyForUpcoming => 'Kopieer voor de aankomende';
  @override String get notAvailable => 'Niet beschikbaar';
  @override String get reasonOptional => 'Reden (optioneel)';
  @override String get startTimeLabel => 'Start';
  @override String get setOnceApplyAll => 'Stel \u00e9\u00e9n keer in en pas toe op alle dagen.';
  @override String get timesLabel => 'Tijden';
  @override String get timeSlot => 'Tijdslot';
  @override String get enterValidTimes => 'Voer eerst geldige tijden in.';
  @override String get whatShowOnProfile => 'Wat toon je op je profiel?';
  @override String get weeklyTimeSlots => 'Wekelijkse tijdslots';
  @override String get getStorefrontPromoMore => 'Krijg etalage, promo codes en meer';
  @override String get logoutAction => 'Uitloggen';
  @override String get upgradeToProAction => 'Upgrade naar Pro';
  @override String get actionRequiredArrow => 'Actie vereist \u2192';
  @override String get reachAllClients => 'Bereik al je klanten met \u00e9\u00e9n druk op de knop.';
  @override String get readStatusLabel => 'Gelezen';
  @override String get newConversationComingSoon => 'Nieuw gesprek starten komt binnenkort';
  @override String get newsletterLabel => 'Nieuwsbrief';
  @override String get unreadStatusLabel => 'Ongelezen';
  @override String get noInternetConnection => 'Geen internetverbinding';
  @override String get haveACode => 'Heb je een code?';
  @override String get applyAction => 'Toepassen';
  @override String get upgradeAction => 'Upgrade';
  @override String get shareThePower => 'Deel de kracht van fitness';
  @override String get shareVia => 'Deel via';
  @override String get howDoesItWork => 'Hoe werkt het?';
  @override String get yourPersonalLink => 'Jouw persoonlijke link';
  @override String get letFriendsScanQr => 'Laat vrienden deze QR-code scannen';
  @override String get linkCopied => 'Link gekopieerd!';
  @override String get inviteFriendsGymies => 'Nodig vrienden uit voor GYMIES en ontvang';
  @override String get orShareViaQr => 'Of deel via QR';
  @override String get timerExtended30Min => 'Bedankt! Timer verlengd met 30 minuten.';
  @override String get emergencyContactAutoNotified => 'Je noodcontact wordt automatisch ge\u00efnformeerd';
  @override String get sessionTakingLonger => 'Je sessie duurt langer dan verwacht.';
  @override String get sosHelpNeeded => 'SOS \u2013 Hulp nodig';
  @override String get closeApp => 'App sluiten';
  @override String get securityWarning => 'Beveiligingswaarschuwing';
  @override String get gymiesProtects => 'Gymies beschermt je persoonlijke gegevens en betalingen.';
  @override String get waitingForTrainerReply => 'Wacht op reactie van de trainer...';
  @override String get noAvailableMoments => 'Geen beschikbare momenten gevonden';
  @override String get noTimesAvailable => 'Geen tijden beschikbaar op deze dag';
  @override String get postAnonymously => 'Anoniem plaatsen';
  @override String get giveRating => 'Beoordeling geven';
  @override String get cameraLabel => 'Camera';
  @override String get complimentOptional => 'Compliment of opmerking (optioneel)';
  @override String get photoLabel => 'Foto';
  @override String get howWasYourSession => 'Hoe was je sessie?';
  @override String get nameNotShownOnReview => 'Je naam wordt niet getoond bij de review';
  @override String get submitActionLabel => 'Versturen';
  @override String get actionHistoryTitle => 'Actiegeschiedenis';
  @override String get escalateAction => 'Escaleren';
  @override String get noEventsYet => 'Nog geen events';
  @override String get recentEvents => 'Recente events';
  @override String get retryNow => 'Retry nu';
  @override String get executedActionsAppear => 'Uitgevoerde en gequeue-de acties verschijnen hier.';
  @override String get queueLabel => 'Wachtrij';


  // ═══ EXTRA SCREEN STRINGS (PHASE 2) ═══
  @override
  String get safeSessionStarted => 'Safe session gestart';
  @override
  String get clientAutoCheckedOut => 'de klant wordt automatisch uitgecheckt.';
  @override
  String get clientCheckedOutSessionCompleted => 'De klant wordt uitgecheckt en de sessie wordt voltooid.';
  @override
  String get heartbeatsLabel => 'Heartbeats';
  @override
  String get successfulLabel => 'succesvol';
  @override
  String get escalationsLabel => 'Escalaties';
  @override
  String get sessionEnded => 'Sessie beëindigd';
  @override
  String get adminNotifiedImmediately => 'Admin wordt direct op de hoogte gesteld.';
  @override
  String get checkInRegistered => 'Check-in geregistreerd';
  @override
  String get fillInReason => 'Vul een reden in';
  @override
  String get noShowRegistered => 'No-show geregistreerd';
  @override
  String get personalTrainingSession => 'Personal training sessie';
  @override
  String get directSuccess => 'Direct gelukt';
  @override
  String get sessionConfirmedPayCash => 'Sessie bevestigd! Betaal contant bij je trainer.';
  @override
  String get redirectingToPayment => 'Je wordt doorgestuurd naar de betaalpagina...';
  @override
  String get couldNotSubmitDispute => 'Kon geschil niet indienen.';
  @override
  String get cancelSessionQuestion => 'Weet je zeker dat je deze sessie wilt annuleren?';
  @override
  String get howManySessionsPerWeek => 'Hoeveel sessies per week?';
  @override
  String get goToDiscoverToBookTrainer => 'Ga naar Ontdekken om een trainer te boeken';
  @override
  String get quickTo => 'Snel naar';
  @override
  String get tipManualCalendarAdd => 'Tip: Je kunt ook handmatig een sessie aan je agenda toevoegen via de actie-knop bij elke boeking.';
  @override
  String get quietHoursLabel => 'Stille uren';
  @override
  String get sessionStartingSoon => 'Sessie begint zo';
  @override
  String get couldNotLoadSessions2 => 'Kon sessies niet laden';
  @override
  String get allLabel => 'Alles';
  @override
  String get remindLabel => 'Herinner';
  @override
  String get sendLabel => 'Stuur';
  @override
  String get sending => 'Versturen…';
  @override
  String get autoRebookings => 'Auto-herboekingen';
  @override
  String get afterHowManyDaysInactivity => 'Na hoeveel dagen inactiviteit ontvangen klanten automatisch een herinnering?';
  @override
  String get inactiveClients => 'INACTIEVE KLANTEN';
  @override
  String get describeUrgentProblem => 'Beschrijf kort het urgente probleem';
  @override
  String get bookingReferenceOptional => 'Booking reference (optioneel)';
  @override
  String get forUrgentOperationalIssues => 'Voor urgente operationele issues met contextpakket.';
  @override
  String get readLabel => 'Gelezen';
  @override
  String get unreadLabel => 'Ongelezen';
  @override
  String get reachAllClientsOneClick => 'Bereik al je klanten met één druk op de knop. Deel tips, aanbiedingen en updates.';
  @override
  String get getStorefrontPromoCodesMore => 'Krijg etalage, promo codes en meer';
  @override
  String get logoutLabel => 'Uitloggen';
  @override
  String get upgradeToProLabel => 'Upgrade naar Pro';
  @override
  String get rejectLabel => 'Afwijs';
  @override
  String get confirmLabel => 'Bevestig';
  @override
  String get respondLabel => 'Reageer';
  @override
  String get toConfirm => 'TE BEVESTIGEN';
  @override
  String get clearAll => 'Wis alles';
  @override
  String get retryLabel => 'Opnieuw';
  @override
  String get applyLabel => 'Toepassen';
  @override
  String get upgradeLabel => 'Upgrade';
  @override
  String get waitingForTrainerResponse => 'Wacht op reactie van de trainer...';
  @override
  String get noAvailableMomentsFound => 'Geen beschikbare momenten gevonden';
  @override
  String get noTimesAvailableOnThisDay => 'Geen tijden beschikbaar op deze dag';
  @override
  String get complimentOrRemarkOptional => 'Compliment of opmerking (optioneel)';
  @override
  String get nameNotShownInReview => 'Je naam wordt niet getoond bij de review';
  @override
  String get submitLabel => 'Versturen';
  @override
  String get thankYouTimerExtended => 'Bedankt! Timer verlengd met 30 minuten.';
  @override
  String get emergencyContactNotifiedIfNoResponse => 'Je noodcontact wordt automatisch geïnformeerd als je niet';
  @override
  String get sessionTakingLongerThanExpected => 'Je sessie duurt langer dan verwacht.';
  @override
  String get sosNeedHelp => 'SOS – Hulp nodig';
  @override
  String get gymiesProtectsData => 'Gymies beschermt je persoonlijke gegevens en betalingen.';

  // ═══ EXTRA SCREEN STRINGS (PHASE 3 — BULK) ═══
  @override
  String get 0GeenRestitutie => '0% — Geen restitutie';
  @override
  String get 100VolledigeRestitutie => '100% — Volledige restitutie';
  @override
  String get 120Min => '120 min';
  @override
  String get 12UurVanTevoren => '12 uur van tevoren';
  @override
  String get 1LinkPerRegel => '1 link per regel';
  @override
  String get 1WeekVanTevoren => '1 week van tevoren';
  @override
  String get 24UurVanTevoren => '24 uur van tevoren';
  @override
  String get 25Restitutie => '25% restitutie';
  @override
  String get 48Uur2Dagen => '48 uur (2 dagen)';
  @override
  String get 50Restitutie => '50% restitutie';
  @override
  String get 60Min => '60 min';
  @override
  String get 72Uur3Dagen => '72 uur (3 dagen)';
  @override
  String get 75Restitutie => '75% restitutie';
  @override
  String get 90Min => '90 min';
  @override
  String get aanHetTypen => 'aan het typen...';
  @override
  String get aandachtspunt => 'Aandachtspunt';
  @override
  String get aanmaken => 'Aanmaken';
  @override
  String get aantalSessies => 'Aantal sessies';
  @override
  String get aanvragen => 'Aanvragen';
  @override
  String get aanwezigheid => 'Aanwezigheid';
  @override
  String get abonnement => 'Abonnement';
  @override
  String get abonnementFeatures => 'Abonnement features';
  @override
  String get abonnementKiezen => 'Abonnement kiezen';
  @override
  String get abonnementenPakketten => 'Abonnementen & pakketten';
  @override
  String get accentkleur => 'Accentkleur';
  @override
  String get accountAanmaken => 'Account aanmaken';
  @override
  String get accountVerwijderaanvraagIngediend => 'Account verwijderaanvraag ingediend';
  @override
  String get accountVerwijderaanvraagIngediendJeOntvangtEenBevestigingPerEmail => 'Account verwijderaanvraag ingediend — je ontvangt een bevestiging per e-mail';
  @override
  String get actieVereist => 'Actie vereist →';
  @override
  String get actief => 'Actief';
  @override
  String get adres => 'Adres';
  @override
  String get adresregel1 => 'Adresregel 1';
  @override
  String get afstand => 'Afstand';
  @override
  String get agendaSynchronisatie => 'Agenda synchronisatie';
  @override
  String get alle => 'Alle';
  @override
  String get alleDocumentenIngediend => 'Alle documenten ingediend!';
  @override
  String get alleFiltersWissen => 'Alle filters wissen';
  @override
  String get alleKlantenZijnActief => 'Alle klanten zijn actief!';
  @override
  String get allePakketten => 'Alle pakketten';
  @override
  String get allePlans => 'Alle plans';
  @override
  String get alleReviewsBekijken => 'Alle reviews bekijken';
  @override
  String get alleStatussen => 'Alle statussen';
  @override
  String get alleenOngelezen => 'Alleen ongelezen';
  @override
  String get alles => 'Alles';
  @override
  String get allesGelezen => 'Alles gelezen';
  @override
  String get allesWissen => 'Alles wissen';
  @override
  String get alsEenTrainerVolgeboektIsKunJeJeOpDeWachtlijstPlaatsen => 'Als een trainer volgeboekt is, kun je je op de wachtlijst plaatsen.';
  @override
  String get alsJeAutosyncInschakeltWordenNieuweSessiesAutomatischAanJeDevicekalenderToegevoegdZodraZeBevestigdZijn => 'Als je auto-sync inschakelt, worden nieuwe sessies automatisch aan je device-kalender toegevoegd zodra ze bevestigd zijn.';
  @override
  String get alsJeEenAbonnementWiltWijzigenBekijkDeFeaturesEnVeranderJeAbonnementJeAbonnementGaatInBijDeVolgendeFactuurdatum => 'Als je een abonnement wilt wijzigen, bekijk de features en verander je abonnement. Je abonnement gaat in bij de volgende factuurdatum.';
  @override
  String get altijdAnnuleerbaar => 'Altijd annuleerbaar';
  @override
  String get analytics => 'Analytics';
  @override
  String get annuleer => 'Annuleer';
  @override
  String get annuleren => 'Annuleren';
  @override
  String get annuleringsbeleid => 'Annuleringsbeleid';
  @override
  String get annuleringstermijn => 'Annuleringstermijn';
  @override
  String get autoherboekingen => 'Auto-herboekingen';
  @override
  String get automatischToevoegen => 'Automatisch toevoegen';
  @override
  String get backupCodeGekopieerd => 'Backup code gekopieerd';
  @override
  String get banner => 'Banner';
  @override
  String get bedanktVoorJeMeldingWeBekijkenDitZoSnelMogelijk => 'Bedankt voor je melding. We bekijken dit zo snel mogelijk.';
  @override
  String get bedrijfsnaamvoorFactuur => 'Bedrijfsnaam (voor factuur)';
  @override
  String get begrepen => 'Begrepen';
  @override
  String get beheerHoeKlantenJouZienOpGymies => 'Beheer hoe klanten jou zien op Gymies';
  @override
  String get beindigSessie => 'Beëindig sessie';
  @override
  String get beindigen => 'Beëindigen';
  @override
  String get bekijk => 'Bekijk';
  @override
  String get bekijkAlle => 'Bekijk alle';
  @override
  String get bekijkDePdf => 'Bekijk de PDF';
  @override
  String get bekijkInDossier => 'Bekijk in dossier';
  @override
  String get bekijkMijnSessies => 'Bekijk mijn sessies';
  @override
  String get bekijkPakketten => 'Bekijk pakketten';
  @override
  String get bekijkTrainer => 'Bekijk trainer';
  @override
  String get bekijkVolledigProfiel => 'Bekijk volledig profiel';
  @override
  String get bepaalOnderWelkeVoorwaardenKlantenKunnenAnnuleren => 'Bepaal onder welke voorwaarden klanten kunnen annuleren';
  @override
  String get bereikAlJeKlantenMetnDrukOpDeKnopDeelTipsAanbiedingenEnUpdates => 'Bereik al je klanten met één druk op de knop. Deel tips, aanbiedingen en updates.';
  @override
  String get bericht => 'Bericht';
  @override
  String get berichten => 'BERICHTEN';
  @override
  String get berichtencentrum => 'Berichtencentrum';
  @override
  String get beschikbaarheid => 'Beschikbaarheid';
  @override
  String get beschikbaarheidinstellingen => 'Beschikbaarheid-instellingen';
  @override
  String get beschrijfDeSituatieInDetail => 'Beschrijf de situatie in detail...';
  @override
  String get beschrijfHetProbleemZoDuidelijkMogelijk => 'Beschrijf het probleem zo duidelijk mogelijk';
  @override
  String get beschrijfHetProbleemZoDuidelijkMogelijkWeNemenHetZoSnelMogelijkInBehandeling => 'Beschrijf het probleem zo duidelijk mogelijk. We nemen het zo snel mogelijk in behandeling.';
  @override
  String get beschrijfJeIntroductiekorting => 'Beschrijf je introductiekorting...';
  @override
  String get beschrijfJeProbleemZoDuidelijkMogelijk => 'Beschrijf je probleem zo duidelijk mogelijk';
  @override
  String get beschrijfKortHetUrgenteProbleem => 'Beschrijf kort het urgente probleem';
  @override
  String get beschrijfSpecialeGevallenOfUitzonderingen => 'Beschrijf speciale gevallen of uitzonderingen...';
  @override
  String get beschrijving => 'Beschrijving';
  @override
  String get beschrijvingoptioneel => 'Beschrijving (optioneel)';
  @override
  String get bestandKonNietWordenGelezen => 'Bestand kon niet worden gelezen.';
  @override
  String get betaalContantOpDeDagZelf => 'Betaal contant op de dag zelf';
  @override
  String get betaalNu => 'Betaal nu';
  @override
  String get betaalbewijs => 'Betaalbewijs';
  @override
  String get betaaldeSessiesVanDezeKlantVerschijnenHier => 'Betaalde sessies van deze klant verschijnen hier.';
  @override
  String get betaaldonline => 'Betaald (online)';
  @override
  String get betaalmethode => 'Betaalmethode';
  @override
  String get betalingBevestigen => 'Betaling bevestigen';
  @override
  String get betalingGelukt => 'Betaling gelukt!';
  @override
  String get beveiligdViaMollieDirecteBevestiging => 'Beveiligd via Mollie — directe bevestiging';
  @override
  String get beveiliging => 'BEVEILIGING';
  @override
  String get bevestigBoeking => 'Bevestig boeking';
  @override
  String get bevestigNieuwWachtwoord => 'Bevestig nieuw wachtwoord';
  @override
  String get bewerken => 'Bewerken';
  @override
  String get bewerkenWordtBinnenkortBeschikbaar => 'Bewerken wordt binnenkort beschikbaar';
  @override
  String get bewerku203a => 'Bewerk \u203A';
  @override
  String get bewijsUrloptioneel => 'Bewijs URL (optioneel)';
  @override
  String get bezigMetBoeken => 'Bezig met boeken...';
  @override
  String get bijnaKlaar => 'Bijna klaar!';
  @override
  String get bijv30 => 'bijv. 30';
  @override
  String get bijv42 => 'Bijv. 42';
  @override
  String get bijv4999 => 'bijv. 49.99';
  @override
  String get bijv50 => 'bijv. 50';
  @override
  String get bijvCentrumNoordZuid => 'bijv. Centrum, Noord, Zuid';
  @override
  String get bijvJohnfitness => 'bijv. john-fitness';
  @override
  String get bijvKlantNietVerschenen => 'Bijv. klant niet verschenen';
  @override
  String get bijvNoshowKwaliteitsprobleem => 'Bijv. No-show, kwaliteitsprobleem...';
  @override
  String get blokkering => 'Blokkering';
  @override
  String get boekNu => 'Boek nu';
  @override
  String get boekSessie => 'Boek sessie';
  @override
  String get boekenVanTevoren => 'Boeken van tevoren';
  @override
  String get boekingBevestigdBetaalCashBijJeTrainer => 'Boeking bevestigd! Betaal cash bij je trainer.';
  @override
  String get boekingid => 'Boeking-ID';
  @override
  String get boekingstermijndagen => 'Boekingstermijn (dagen)';
  @override
  String get bookingReferenceoptioneel => 'Booking reference (optioneel)';
  @override
  String get bookingWidget => 'Booking Widget';
  @override
  String get brandKleur => 'Brand kleur';
  @override
  String get brandingOpgeslagen => 'Branding opgeslagen';
  @override
  String get btwnummer => 'BTW-nummer';
  @override
  String get bulkBerichtVersturen => 'Bulk bericht versturen';
  @override
  String get camera => 'Camera';
  @override
  String get capaciteit => 'Capaciteit';
  @override
  String get cashBijTrainer => 'Cash bij trainer';
  @override
  String get checkJeEmailVoorInstructiesOmJeWachtwoordTeResetten => 'Check je e-mail voor instructies om je wachtwoord te resetten.';
  @override
  String get checkin => 'Check-in';
  @override
  String get checkinRegistreren => 'Check-in registreren';
  @override
  String get checkinScanner => 'Check-in scanner';
  @override
  String get coachRadar => 'Coach radar';
  @override
  String get communicatie => 'Communicatie';
  @override
  String get contact => 'Contact';
  @override
  String get contant => 'Contant';
  @override
  String get contantBetaald => 'Contant betaald';
  @override
  String get controlTower => 'Control Tower';
  @override
  String get controleerJeInternetEnProbeerOpnieuw => 'Controleer je internet en probeer opnieuw.';
  @override
  String get csvGexporteerd => 'CSV geëxporteerd';
  @override
  String get dag => 'Dag';
  @override
  String get datum => 'Datum';
  @override
  String get datumTijd => 'Datum & tijd';
  @override
  String get deadlineurenVoorAanvang => 'Deadline (uren voor aanvang)';
  @override
  String get deelMetKlant => 'Deel met klant';
  @override
  String get deelnemers => 'Deelnemers';
  @override
  String get definitievePrijsBijHetBoeken => 'Definitieve prijs bij het boeken.';
  @override
  String get delen => 'Delen';
  @override
  String get dezeInstellingenWordenGetoondOpJeProfielZodatKlantenWetenHoeVerZeKunnenBoekenEnHoeZeKunnenBetalen => 'Deze instellingen worden getoond op je profiel zodat klanten weten hoe ver ze kunnen boeken en hoe ze kunnen betalen.';
  @override
  String get dezeLesIsGeannuleerd => 'Deze les is geannuleerd';
  @override
  String get dezeSpecialisatieBestaatAl => 'Deze specialisatie bestaat al';
  @override
  String get dezeVeldenZijnOptioneel => 'Deze velden zijn optioneel';
  @override
  String get dezeWeek => 'Deze week';
  @override
  String get dienst => 'Dienst';
  @override
  String get diplomaLinksoptioneel => 'Diploma links (optioneel)';
  @override
  String get ditDocumentIsAfgekeurdUploadEenNieuwDocument => 'Dit document is afgekeurd. Upload een nieuw document.';
  @override
  String get ditGeschilIsOpgelostJeKuntGeenBerichtenMeerVersturen => 'Dit geschil is opgelost. Je kunt geen berichten meer versturen.';
  @override
  String get ditTicketBestaatNietMeer => 'Dit ticket bestaat niet meer';
  @override
  String get ditTicketIsOpgelost => 'Dit ticket is opgelost';
  @override
  String get documentGepload => 'Document geüpload.';
  @override
  String get documentGeploadWeControlerenHetZoSnelMogelijk => 'Document geüpload! We controleren het zo snel mogelijk.';
  @override
  String get documentenNogNietCompleetOpgeslagenVulVerplichteVeldenIn => 'Documenten nog niet compleet opgeslagen. Vul verplichte velden in.';
  @override
  String get doelen => 'Doelen';
  @override
  String get doelenstatus => 'Doelenstatus';
  @override
  String get doorgangGarantie => 'Doorgang garantie';
  @override
  String get dossierIsAlleenlezenUpgradeNaarProOmTeBewerken => 'Dossier is alleen-lezen. Upgrade naar Pro om te bewerken.';
  @override
  String get dossierStatus => 'Dossier status';
  @override
  String get downloadDeFactuurDirectAlsPdfDeLinkKanNaVerloopVanTijdVerlopen => 'Download de factuur direct als PDF. De link kan na verloop van tijd verlopen.';
  @override
  String get downloadDePdfDirectNaOpenen => 'Download de PDF direct na openen.';
  @override
  String get downloadQr => 'Download QR';
  @override
  String get duoTraining => 'Duo training';
  @override
  String get duur => 'Duur';
  @override
  String get duurminuten => 'Duur (minuten)';
  @override
  String get egFf6b6b => 'e.g. FF6B6B';
  @override
  String get eind => 'Eind';
  @override
  String get embedCode => 'Embed code';
  @override
  String get energie15 => 'Energie (1-5)';
  @override
  String get erZijnMomenteelGeenGroepslessenGeplandInDeGekozenPeriode => 'Er zijn momenteel geen groepslessen gepland in de gekozen periode.';
  @override
  String get erZijnMomenteelGeenGroepslessenGeplandninDeKomende60Dagen => 'Er zijn momenteel geen groepslessen gepland\nin de komende 60 dagen.';
  @override
  String get etalageOpgeslagen => 'Etalage opgeslagen';
  @override
  String get factuurIsAangemaaktMaarPdflinkOntbreektVersturenIsGeblokkeerdTotPdfBeschikbaarIs => 'Factuur is aangemaakt maar PDF-link ontbreekt. Versturen is geblokkeerd tot PDF beschikbaar is.';
  @override
  String get factuurbedragMoetGroterZijnDan0 => 'Factuurbedrag moet groter zijn dan 0';
  @override
  String get factuurid => 'Factuur-ID';
  @override
  String get failedToSaveBranding => 'Failed to save branding';
  @override
  String get favorieten => 'Favorieten';
  @override
  String get featuresOpgeslagen => 'Features opgeslagen';
  @override
  String get feeType => 'Fee type';
  @override
  String get feebeheer => 'Fee-beheer';
  @override
  String get feedbackEnNotitiesVanJeTrainerNaEenSessie => 'Feedback en notities van je trainer na een sessie.';
  @override
  String get filters => 'Filters';
  @override
  String get focusVanSessie => 'Focus van sessie';
  @override
  String get foutBijLadenGeschiedenis => 'Fout bij laden geschiedenis';
  @override
  String get foutBijLadenStatistieken => 'Fout bij laden statistieken';
  @override
  String get foutBijVerstureninplannenNieuwsbrief => 'Fout bij versturen/inplannen nieuwsbrief';
  @override
  String get gaNaarOntdekkenOmEenTrainerTeBoeken => 'Ga naar Ontdekken om een trainer te boeken';
  @override
  String get gaatDoor => 'Gaat door!';
  @override
  String get galerij => 'Galerij';
  @override
  String get geannuleerd => 'Geannuleerd';
  @override
  String get geblokkeerdeDagen => 'Geblokkeerde dagen';
  @override
  String get geblokkeerduitzondering => 'Geblokkeerd (uitzondering)';
  @override
  String get gebruikCode => 'Gebruik code';
  @override
  String get geenAfstandsfilter => 'Geen afstandsfilter';
  @override
  String get geenBetaaldeSessies => 'Geen betaalde sessies';
  @override
  String get geenBetaalurlOntvangenProbeerOpnieuw => 'Geen betaal-URL ontvangen. Probeer opnieuw.';
  @override
  String get geenDownloadlinkBeschikbaar => 'Geen downloadlink beschikbaar.';
  @override
  String get geenGeschillen => 'Geen geschillen';
  @override
  String get geenGrafiekdataVoorDezeMetriekJeTrainerKanDitInvullenViaHetDossier => 'Geen grafiekdata voor deze metriek. Je trainer kan dit invullen via het dossier.';
  @override
  String get geenGroepslessenGevonden => 'Geen groepslessen gevonden';
  @override
  String get geenInschrijvingen => 'Geen inschrijvingen';
  @override
  String get geenKlantenGevonden => 'Geen klanten gevonden';
  @override
  String get geenKlantenGevondenVoorDitFilter => 'Geen klanten gevonden voor dit filter.';
  @override
  String get geenNieuwsbrievenVerzonden => 'Geen nieuwsbrieven verzonden';
  @override
  String get geenNotities => 'Geen notities';
  @override
  String get geenOpenTickets => 'Geen open tickets';
  @override
  String get geenPlannenBeschikbaarLaadOpnieuw => 'Geen plannen beschikbaar. Laad opnieuw.';
  @override
  String get geenSmartRebookAlertsnklantenVerschijnenHierAlsZeLangerDan7DagenGeenSessieHadden => 'Geen Smart Rebook alerts.\nKlanten verschijnen hier als ze langer dan 7 dagen geen sessie hadden.';
  @override
  String get geenSpecialisatiesToegevoegd => 'Geen specialisaties toegevoegd';
  @override
  String get geenStandbyinschrijvingen => 'Geen standby-inschrijvingen';
  @override
  String get geenTrainersGevonden => 'Geen trainers gevonden';
  @override
  String get geenUitbetalingsgeschiedenis => 'Geen uitbetalingsgeschiedenis';
  @override
  String get geenWachtlijsten => 'Geen wachtlijsten';
  @override
  String get gegevensexportAangevraagdJeOntvangtEenEmail => 'Gegevensexport aangevraagd — je ontvangt een e-mail';
  @override
  String get gekozenPakket => 'GEKOZEN PAKKET';
  @override
  String get geldigTot => 'Geldig tot';
  @override
  String get geldigVoor => 'Geldig voor';
  @override
  String get geldigheiddagen => 'Geldigheid (dagen)';
  @override
  String get gelezen => 'Gelezen';
  @override
  String get gemiddeldeReactietijd2Uur => 'Gemiddelde reactietijd: ~2 uur';
  @override
  String get geschiedenis => 'GESCHIEDENIS';
  @override
  String get geschil => 'Geschil';
  @override
  String get geschilIndienen => 'Geschil indienen';
  @override
  String get geschillen => 'Geschillen';
  @override
  String get gesprekVerwijderd => 'Gesprek verwijderd';
  @override
  String get gewicht => 'Gewicht';
  @override
  String get googlePreview => 'Google Preview';
  @override
  String get groepsles => 'Groepsles';
  @override
  String get groepslesAangemaakt => 'Groepsles aangemaakt!';
  @override
  String get groepslessen => 'Groepslessen';
  @override
  String get gymnaam => 'Gym-naam';
  @override
  String get handmatigeCheckin => 'Handmatige check-in';
  @override
  String get heartbeatActiefElke2Min => 'Heartbeat actief · elke 2 min';
  @override
  String get hebJeEenKortingscode => 'Heb je een kortingscode?';
  @override
  String get herinner => 'Herinner';
  @override
  String get hierVerschijnenJeTicketsWanneernjeContactOpneemt => 'Hier verschijnen je tickets wanneer\nje contact opneemt.';
  @override
  String get hoeKunnenWeJeHelpen => 'Hoe kunnen we je helpen?';
  @override
  String get hoeVerdienJePunten => 'HOE VERDIEN JE PUNTEN?';
  @override
  String get hoekafronding => 'Hoekafronding';
  @override
  String get hoeveelDagenVanTevorenKanEenKlantEenSessieBoeken => 'Hoeveel dagen van tevoren kan een klant een sessie boeken?';
  @override
  String get hoeveelSessiesPerWeek => 'Hoeveel sessies per week?';
  @override
  String get https => 'https://...';
  @override
  String get httpsyoutubecomwatchv => 'https://youtube.com/watch?v=...';
  @override
  String get huidigSaldo => 'Huidig saldo';
  @override
  String get huidigWachtwoord => 'Huidig wachtwoord';
  @override
  String get huiswerkActiepunt => 'Huiswerk / actiepunt';
  @override
  String get inactief => 'Inactief';
  @override
  String get inactieveKlanten => 'INACTIEVE KLANTEN';
  @override
  String get inbox => 'Inbox';
  @override
  String get inchecken => 'Inchecken';
  @override
  String get ingecheckt => 'Ingecheckt!';
  @override
  String get ingeschreven => 'Ingeschreven';
  @override
  String get inplannen => 'Inplannen';
  @override
  String get inschrijvingAnnuleren => 'Inschrijving annuleren';
  @override
  String get inschrijvingGeannuleerd => 'Inschrijving geannuleerd';
  @override
  String get instellingen => 'Instellingen';
  @override
  String get instellingenOpgeslagen => 'Instellingen opgeslagen';
  @override
  String get instellingenOpslaan => 'Instellingen opslaan';
  @override
  String get interneTrainernotities => 'Interne trainernotities';
  @override
  String get introVideo => 'Intro Video';
  @override
  String get issue => 'Issue';
  @override
  String get jaBetaald => 'Ja, betaald';
  @override
  String get jeAccountIsKlaarJeKuntNuSessiesAanbieden => 'Je account is klaar. Je kunt nu sessies aanbieden.';
  @override
  String get jeHebtJeNogNietIngeschrevenVoorEenGroepsles => 'Je hebt je nog niet ingeschreven voor een groepsles.';
  @override
  String get jeMoetAkkoordGaanMetDeAlgemeneVoorwaarden => 'Je moet akkoord gaan met de Algemene voorwaarden.';
  @override
  String get jeMoetAkkoordGaanMetHetPrivacybeleid => 'Je moet akkoord gaan met het Privacybeleid.';
  @override
  String get jePlekIsGereserveerdJeOntvangtEenMeldingZodraDeLesDoorgaat => 'Je plek is gereserveerd. Je ontvangt een melding zodra de les doorgaat.';
  @override
  String get jeProfiteertAlVanDezeActie => 'Je profiteert al van deze actie!';
  @override
  String get jeSessieIsBevestigd => 'Je sessie is bevestigd';
  @override
  String get jeStaatNuOpDeStandbylijstVoorDezeTrainer => 'Je staat nu op de standby-lijst voor deze trainer';
  @override
  String get jeStaatOpDeStandbylijstVanDeVolgendeTrainersZodraErPlekVrijkomtKrijgJeEenMelding => 'Je staat op de standby-lijst van de volgende trainer(s). Zodra er plek vrijkomt, krijg je een melding.';
  @override
  String get jeTrainerDeeltNogGeenProgressieBijProtrainersZieJeHierJeStreakDoelenEnOntwikkeling => 'Je trainer deelt nog geen progressie. Bij Pro-trainers zie je hier je streak, doelen en ontwikkeling.';
  @override
  String get jeWordtDoorgestuurdNaarDeBetaalpagina => 'Je wordt doorgestuurd naar de betaalpagina...';
  @override
  String get jeWordtDoorgestuurdNaarDeBetaalpaginaNaBetalingKeerJeTerugNaarDeApp => 'Je wordt doorgestuurd naar de betaalpagina. Na betaling keer je terug naar de app.';
  @override
  String get jeZietHierAlleenOpenbareProfielinformatie => 'Je ziet hier alleen openbare profielinformatie.';
  @override
  String get jouwPersoonlijkeFitnessJourneyBegintHiern => 'Jouw persoonlijke fitness journey begint hier.\n';
  @override
  String get jouwPubliekeProfiel => 'Jouw publieke profiel';
  @override
  String get jouwSlug => 'Jouw slug';
  @override
  String get jouwnaam => 'jouwnaam';
  @override
  String get kanDeQrNietGescandWordenGeefDezeCodeAanJeTrainer => 'Kan de QR niet gescand worden? Geef deze code aan je trainer.';
  @override
  String get kies => 'Kies';
  @override
  String get kiesDeDagEnTijdenJeBeschikbaarheidGeldtAutomatischVoorAlleWeken => 'Kies de dag en tijden. Je beschikbaarheid geldt automatisch voor alle weken.';
  @override
  String get kiesEenDatum => 'KIES EEN DATUM';
  @override
  String get kiesEenDatumEnTijd => 'Kies een datum en tijd';
  @override
  String get kiesEenPakket => 'Kies een pakket';
  @override
  String get kiesEenPlan => 'Kies een plan';
  @override
  String get kiesEenSterkWachtwoordVanMinimaal8TekensMetLettersEnCijfers => 'Kies een sterk wachtwoord van minimaal 8 tekens met letters en cijfers.';
  @override
  String get kiesEenTemplate => 'Kies een template';
  @override
  String get kiesEenTijdstip => 'KIES EEN TIJDSTIP';
  @override
  String get kiesHoeKlantenJeKunnenBetalen => 'Kies hoe klanten je kunnen betalen';
  @override
  String get kiesJeGymiesplan => 'Kies je Gymies-plan';
  @override
  String get kiesKlantVoorDossier => 'Kies klant voor dossier';
  @override
  String get kiesLesvorm => 'Kies lesvorm';
  @override
  String get kiesSpecialiteit => 'Kies specialiteit';
  @override
  String get kiesStad => 'Kies stad';
  @override
  String get kiesUitJeFotorol => 'Kies uit je fotorol';
  @override
  String get klantToevoegenKomtBinnenkort => 'Klant toevoegen komt binnenkort';
  @override
  String get klanten => 'Klanten';
  @override
  String get klantidOntbreekt => 'Klant-ID ontbreekt.';
  @override
  String get komJeErNietUit => 'Kom je er niet uit?';
  @override
  String get konBerichtNietVersturen => 'Kon bericht niet versturen.';
  @override
  String get konBoekingenNietLaden => 'Kon boekingen niet laden';
  @override
  String get konExportNietAanvragenProbeerLaterOpnieuw => 'Kon export niet aanvragen. Probeer later opnieuw.';
  @override
  String get konGeschilNietIndienen => 'Kon geschil niet indienen.';
  @override
  String get konGesprekNietVerwijderen => 'Kon gesprek niet verwijderen';
  @override
  String get konKaartenappNietOpenen => 'Kon kaarten-app niet openen.';
  @override
  String get konPdfNietOpenen => 'Kon PDF niet openen.';
  @override
  String get konSessiesNietLaden => 'Kon sessies niet laden';
  @override
  String get konTicketNietLaden => 'Kon ticket niet laden';
  @override
  String get konVerwijderaanvraagNietIndienenProbeerLaterOpnieuw => 'Kon verwijderaanvraag niet indienen. Probeer later opnieuw.';
  @override
  String get konWachtwoordNietWijzigenProbeerLaterOpnieuw => 'Kon wachtwoord niet wijzigen. Probeer later opnieuw.';
  @override
  String get kopieerEmbed => 'Kopieer embed';
  @override
  String get kopieerEmbedCode => 'Kopieer embed code';
  @override
  String get kopieerLink => 'Kopieer link';
  @override
  String get kopieerProfielUrl => 'Kopieer profiel URL';
  @override
  String get kopieerVoorDeAankomende => 'Kopieer voor de aankomende';
  @override
  String get kopieerWidgetUrl => 'Kopieer widget URL';
  @override
  String get koppelJeMollieaccountZodatKlantenDirectAanJouKunnenBetalen => 'Koppel je Mollie-account zodat klanten direct aan jou kunnen betalen.';
  @override
  String get korteSamenvatting => 'Korte samenvatting';
  @override
  String get krijgEtalagePromoCodesEnMeer => 'Krijg etalage, promo codes en meer';
  @override
  String get kvknummer => 'KVK-nummer';
  @override
  String get kwartaalZipExport => 'Kwartaal ZIP export';
  @override
  String get laatDezeQrcodeScannenDoorJeTrainer => 'Laat deze QR-code scannen door je trainer';
  @override
  String get laatsteReview => 'Laatste review';
  @override
  String get land => 'Land';
  @override
  String get lestype => 'Lestype';
  @override
  String get locatie => 'Locatie';
  @override
  String get locatieToevoegen => 'Locatie toevoegen';
  @override
  String get locaties => 'Locaties';
  @override
  String get logOpnieuwIn => 'Log opnieuw in';
  @override
  String get logistiek => 'Logistiek';
  @override
  String get logo => 'Logo';
  @override
  String get logoBanner => 'Logo & Banner';
  @override
  String get losseSessie => 'Losse sessie';
  @override
  String get maakEenNieuweFoto => 'Maak een nieuwe foto';
  @override
  String get max10mbJpgPngGifWebp => 'Max 10MB · JPG, PNG, GIF, WebP';
  @override
  String get max20mbJpgPngGifWebp => 'Max 20MB · JPG, PNG, GIF, WebP';
  @override
  String get maxDeelnemers => 'Max deelnemers';
  @override
  String get maxInwisselingenleegOnbeperkt => 'Max. inwisselingen (leeg = onbeperkt)';
  @override
  String get maxPrijsPerSessie => 'Max. prijs per sessie';
  @override
  String get maximaal20Specialisaties => 'Maximaal 20 specialisaties';
  @override
  String get maximaal20SpecialisatiesBereikt => 'Maximaal 20 specialisaties bereikt';
  @override
  String get maximumVan20SpecialisatiesBereikt => 'Maximum van 20 specialisaties bereikt.';
  @override
  String get mediaAlsFeaturedIngesteld => 'Media als featured ingesteld';
  @override
  String get mediaFeaturesZijnAlleenBeschikbaarVoorProEnProPlannen => 'Media features zijn alleen beschikbaar voor Pro en Pro+ plannen.';
  @override
  String get mediaIsNietBeschikbaarVoorStarterPlanUpgradeNaarPro => 'Media is niet beschikbaar voor Starter plan. Upgrade naar Pro.';
  @override
  String get mediaToegevoegd => 'Media toegevoegd';
  @override
  String get mediaVerwijderd => 'Media verwijderd';
  @override
  String get meerActies => 'Meer acties';
  @override
  String get meerData => 'Meer data';
  @override
  String get meerLaden => 'Meer laden';
  @override
  String get melden => 'Melden';
  @override
  String get meldingVoorkeuren => 'Melding voorkeuren';
  @override
  String get meldingen => 'Meldingen';
  @override
  String get metaBeschrijving => 'Meta beschrijving';
  @override
  String get metaTitel => 'Meta titel';
  @override
  String get middag => 'Middag';
  @override
  String get mijnDossier => 'Mijn dossier';
  @override
  String get mijnFacturen => 'Mijn facturen';
  @override
  String get mijnGroepslessen => 'Mijn groepslessen';
  @override
  String get mijnInschrijvingen => 'Mijn inschrijvingen';
  @override
  String get mijnTegoed => 'Mijn Tegoed';
  @override
  String get mijnTrainers => 'Mijn trainers';
  @override
  String get mijnWachtlijsten => 'Mijn wachtlijsten';
  @override
  String get min3TekensKleineLettersCijfersEnStreepjes => 'Min. 3 tekens. Kleine letters, cijfers en streepjes.';
  @override
  String get minBeoordeling => 'Min. beoordeling';
  @override
  String get minDeelnemersVoorDoorgang => 'Min. deelnemers voor doorgang';
  @override
  String get minimaal8Tekens => 'Minimaal 8 tekens';
  @override
  String get mollieConnect => 'Mollie connect';
  @override
  String get mollieConnectStarten => 'Mollie Connect starten';
  @override
  String get mollieKoppelen => 'Mollie koppelen';
  @override
  String get naHoeveelDagenInactiviteitOntvangenKlantenAutomatischEenHerinnering => 'Na hoeveel dagen inactiviteit ontvangen klanten automatisch een herinnering?';
  @override
  String get naVersturenMoetDeKlantDePdfDirectDownloaden => 'Na versturen moet de klant de PDF direct downloaden.';
  @override
  String get naam => 'Naam *';
  @override
  String get naamIsVerplichtVoorEenLocatie => 'Naam is verplicht voor een locatie.';
  @override
  String get naarDashboard => 'Naar Dashboard';
  @override
  String get nietBeschikbaar => 'Niet beschikbaar';
  @override
  String get nietGevondenWatJeZocht => 'Niet gevonden wat je zocht?';
  @override
  String get nietIngesteld => 'Niet ingesteld';
  @override
  String get nietopgeslagenWijzigingen => 'Niet-opgeslagen wijzigingen';
  @override
  String get nieuwGesprekStartenKomtBinnenkort => 'Nieuw gesprek starten komt binnenkort';
  @override
  String get nieuwSupportverzoek => 'Nieuw supportverzoek';
  @override
  String get nieuwVerzoekAanmaken => 'Nieuw verzoek aanmaken';
  @override
  String get nieuwWachtwoord => 'Nieuw wachtwoord';
  @override
  String get nieuweBoekingenAutomatischAanJeKalenderToevoegen => 'Nieuwe boekingen automatisch aan je kalender toevoegen';
  @override
  String get nieuweQrGenereren => 'Nieuwe QR genereren';
  @override
  String get nieuwsbrief => 'Nieuwsbrief';
  @override
  String get nogGeenBerichten => 'Nog geen berichten';
  @override
  String get nogGeenBioToegevoegd => 'Nog geen bio toegevoegd.';
  @override
  String get nogGeenCoachNotesJeTrainerKanNaEenSessieNotitiesMetJeDelen => 'Nog geen coach notes. Je trainer kan na een sessie notities met je delen.';
  @override
  String get nogGeenDoelenIngesteldDoorJeTrainerDoelenVerschijnenHierZodraJeTrainerZeVoorJeInvult => 'Nog geen doelen ingesteld door je trainer. Doelen verschijnen hier zodra je trainer ze voor je invult.';
  @override
  String get nogGeenDossiers => 'Nog geen dossiers';
  @override
  String get nogGeenHealthScoreDataBeschikbaar => 'Nog geen health score data beschikbaar.';
  @override
  String get nogGeenLocaties => 'Nog geen locaties';
  @override
  String get nogGeenMediaToegevoegd => 'Nog geen media toegevoegd.';
  @override
  String get nogGeenPubliekeBeschikbaarheid => 'Nog geen publieke beschikbaarheid.';
  @override
  String get nogGeenPubliekePakketten => 'Nog geen publieke pakketten.';
  @override
  String get nogGeenReviews => 'Nog geen reviews';
  @override
  String get nogGeenReviewsBeschikbaar => 'Nog geen reviews beschikbaar.';
  @override
  String get nogGeenScans => 'Nog geen scans';
  @override
  String get nogGeenSessieentries => 'Nog geen sessie-entries.';
  @override
  String get nogGeenSupportverzoeken => 'Nog geen supportverzoeken';
  @override
  String get nogGeenTransacties => 'Nog geen transacties';
  @override
  String get nogGeenUpsellSuggestiesBeschikbaar => 'Nog geen upsell suggesties beschikbaar.';
  @override
  String get nogGeenVerkopen => 'Nog geen verkopen';
  @override
  String get nogNiemandOpDeWachtlijst => 'Nog niemand op de wachtlijst';
  @override
  String get nogNietGepload => 'Nog niet geüpload';
  @override
  String get noshowRegistreren => 'No-show registreren';
  @override
  String get notitieVoorTrainerToevoegen => 'Notitie voor trainer toevoegen...';
  @override
  String get notitieoptioneel => 'Notitie (optioneel)';
  @override
  String get nuVersturen => 'Nu versturen';
  @override
  String get ochtend => 'Ochtend';
  @override
  String get ofVoerJeEigenKleurIn => 'Of voer je eigen kleur in:';
  @override
  String get omzetVerdeling => 'Omzet verdeling';
  @override
  String get onboardingStatus => 'Onboarding status';
  @override
  String get onboardingVoltooid => 'Onboarding voltooid!';
  @override
  String get ondersteundeKalenders => 'Ondersteunde kalenders:';
  @override
  String get onderwerp => 'ONDERWERP';
  @override
  String get ongeldigeSlugGebruikKleineLettersCijfersEnStreepjes => 'Ongeldige slug. Gebruik kleine letters, cijfers en streepjes.';
  @override
  String get ongelezen => 'Ongelezen';
  @override
  String get onlineBetalen => 'Online betalen';
  @override
  String get onlineSessie => 'Online sessie';
  @override
  String get onlineThuisGymAfhankelijkVanAfspraak => 'Online / thuis / gym afhankelijk van afspraak';
  @override
  String get onlinemollie => 'Online (Mollie)';
  @override
  String get ontdekTrainers => 'Ontdek trainers';
  @override
  String get ontdekTrainersBijJouInDeBuurt => 'Ontdek trainers bij jou in de buurt';
  @override
  String get ontdekken => 'Ontdekken';
  @override
  String get ontvangBetalingenDirectOpJeRekening => 'Ontvang betalingen direct op je rekening';
  @override
  String get opStandbylijst => 'Op standby-lijst';
  @override
  String get openEenKlantEnMaakDeEersteSessieentryprogressAan => 'Open een klant en maak de eerste sessie-entry/progress aan.';
  @override
  String get openGerelateerdePagina => 'Open gerelateerde pagina';
  @override
  String get openstaand => 'Openstaand';
  @override
  String get opgesteldeDossiers => 'Opgestelde dossiers';
  @override
  String get opnieuw => 'Opnieuw';
  @override
  String get opnieuwProberen => 'Opnieuw proberen';
  @override
  String get opnieuwZoeken => 'Opnieuw zoeken';
  @override
  String get opslaan => 'Opslaan';
  @override
  String get opslaanMisluktControleerBackend => 'Opslaan mislukt. Controleer backend.';
  @override
  String get opslaanMisluktProbeerHetOpnieuw => 'Opslaan mislukt. Probeer het opnieuw.';
  @override
  String get opstellenVersturen => 'Opstellen & versturen';
  @override
  String get optioneel => 'Optioneel';
  @override
  String get optioneleNotitie => 'Optionele notitie...';
  @override
  String get opzeggen => 'Opzeggen';
  @override
  String get overMij => 'Over mij';
  @override
  String get overslaanMag => 'Overslaan mag';
  @override
  String get overslaanVoorNu => 'Overslaan voor nu';
  @override
  String get overzichtVoorVandaag => 'Overzicht voor vandaag';
  @override
  String get pakket => 'Pakket';
  @override
  String get pakketPrestaties => 'Pakket prestaties';
  @override
  String get pakkettenBijnaVerlopen => 'PAKKETTEN BIJNA VERLOPEN';
  @override
  String get pdfDownloaden => 'PDF downloaden';
  @override
  String get pdfLinkIsOngeldig => 'PDF link is ongeldig.';
  @override
  String get pdfOntbreektOpServerEerstPdfLatenGenererenDaarnaVersturen => 'PDF ontbreekt op server. Eerst PDF laten genereren, daarna versturen.';
  @override
  String get percentage => 'Percentage';
  @override
  String get performanceScore => 'Performance score';
  @override
  String get performanceSummary => 'Performance summary';
  @override
  String get periode => 'Periode';
  @override
  String get personalTraining => 'Personal training';
  @override
  String get plan => 'Plan';
  @override
  String get postcode => 'Postcode';
  @override
  String get prestatie => 'Prestatie';
  @override
  String get prijsInclBtweur => 'Prijs incl. BTW (EUR)';
  @override
  String get prijsOpAanvraag => 'Prijs op aanvraag';
  @override
  String get prijsPerPersoon => 'Prijs per persoon (€)';
  @override
  String get prijseur => 'Prijs (EUR)';
  @override
  String get privacyGegevens => 'Privacy & gegevens';
  @override
  String get pro => 'Pro';
  @override
  String get profielDelen => 'Profiel delen';
  @override
  String get profielMelden => 'Profiel melden';
  @override
  String get profielOpgeslagen => 'Profiel opgeslagen';
  @override
  String get profielOpslaan => 'Profiel opslaan';
  @override
  String get profielfotoBijgewerkt => 'Profielfoto bijgewerkt';
  @override
  String get profielfotoKiezen => 'Profielfoto kiezen';
  @override
  String get profielgegevens => 'Profielgegevens';
  @override
  String get profielurl => 'Profiel-URL';
  @override
  String get profileUrlUseOnlyLowercaseLettersNumbersAndHyphens => 'Profile URL: use only lowercase letters, numbers, and hyphens';
  @override
  String get progressieRitme => 'Progressie & ritme';
  @override
  String get promocode => 'Promocode';
  @override
  String get promocodeoptioneel => 'Promocode (optioneel)';
  @override
  String get publiceren => 'Publiceren';
  @override
  String get puntenIngewisseld => 'Punten ingewisseld!';
  @override
  String get puntenInwisselen => 'Punten inwisselen';
  @override
  String get qrCodeNietBeschikbaar => 'QR code niet beschikbaar';
  @override
  String get qrcodeDownloadKomendeVersie => 'QR-code download komende versie';
  @override
  String get qrcodeGenereren => 'QR-code genereren...';
  @override
  String get recent => 'Recent';
  @override
  String get recenteScans => 'Recente scans';
  @override
  String get reden => 'Reden';
  @override
  String get redenoptioneel => 'Reden (optioneel)';
  @override
  String get referralVoordeelBeschikbaar => 'Referral voordeel beschikbaar';
  @override
  String get restitutiepercentage => 'Restitutiepercentage';
  @override
  String get reviewsGalerijPakkettenEnMeer => 'Reviews, galerij, pakketten en meer';
  @override
  String get safeSessionActief => 'Safe session actief';
  @override
  String get safeSessionStarten => 'Safe session starten';
  @override
  String get scanDeQrcodeVanJeKlant => 'Scan de QR-code van je klant';
  @override
  String get schrijfMinimaal10Tekens => 'Schrijf minimaal 10 tekens';
  @override
  String get selecteer => 'Selecteer';
  @override
  String get seoOpgeslagen => 'SEO opgeslagen';
  @override
  String get seoScore => 'SEO Score';
  @override
  String get serviceDatum => 'Service datum';
  @override
  String get sessie => '/sessie';
  @override
  String get sessieBegintZo => 'Sessie begint zo';
  @override
  String get sessieBeindigen => 'Sessie beëindigen?';
  @override
  String get sessieVerplaatsen => 'Sessie verplaatsen';
  @override
  String get sessieentryOpgeslagen => 'Sessie-entry opgeslagen';
  @override
  String get sleepItemsOmDeVolgordeTeWijzigen => 'Sleep items om de volgorde te wijzigen';
  @override
  String get slimmeRemindersT24uT2uCheckinVensterOpenEnGemisteCheckin => 'Slimme reminders: T-24u, T-2u, check-in venster open en gemiste check-in.';
  @override
  String get snelNaar => 'Snel naar';
  @override
  String get socialMediaOpgeslagen => 'Social media opgeslagen';
  @override
  String get sorteer => 'Sorteer';
  @override
  String get sorterenOp => 'Sorteren op';
  @override
  String get sosHulpNodig => 'SOS – Hulp nodig';
  @override
  String get specialisaties => 'Specialisaties';
  @override
  String get specialiteitenTariefBioEnMediaKunJeAanpassenInDeEtalageeditor => 'Specialiteiten, tarief, bio en media kun je aanpassen in de Etalage-editor.';
  @override
  String get stad => 'Stad';
  @override
  String get standbyinschrijvingVerwijderd => 'Standby-inschrijving verwijderd';
  @override
  String get start => 'Start';
  @override
  String get startEenGesprekMetOnsTeam => 'Start een gesprek met ons team';
  @override
  String get startEerstEenChatOfSessieMetEenKlant => 'Start eerst een chat of sessie met een klant.';
  @override
  String get startMetEenVoorgeschrevenMail => 'Start met een voorgeschreven mail';
  @override
  String get starter => 'Starter';
  @override
  String get status => 'Status';
  @override
  String get statusWijzigen => 'Status wijzigen';
  @override
  String get stelJeTrainingslocatieTrainingsvormenEnAanbiedingenIn => 'Stel je trainingslocatie, trainingsvormen en aanbiedingen in';
  @override
  String get stelJeUurtariefInVoorIndividueleSessies => 'Stel je uurtarief in voor individuele sessies';
  @override
  String get stelnKeerInEnPasToeOpAlleDagenGeldtVoorAlleWeken => 'Stel één keer in en pas toe op alle dagen. Geldt voor alle weken.';
  @override
  String get stilleUren => 'Stille uren';
  @override
  String get stories => 'Stories';
  @override
  String get storiesIsEenProFeatureUpgradeJeAbonnement => 'Stories is een Pro feature. Upgrade je abonnement.';
  @override
  String get storyGeplaatstZichtbaarVoor24Uur => 'Story geplaatst! Zichtbaar voor 24 uur.';
  @override
  String get straatEnHuisnummer => 'Straat en huisnummer';
  @override
  String get studio => 'Studio';
  @override
  String get stuur => 'Stuur';
  @override
  String get stuurEenBerichtNaarAlJeKlantenTegelijk => 'Stuur een bericht naar al je klanten tegelijk.';
  @override
  String get stuurOnsEenBericht => 'Stuur ons een bericht';
  @override
  String get stuurVoorstel => 'Stuur voorstel';
  @override
  String get supportBlijftGekoppeldAanDeTrainersessiecontextVanJeVerzoek => 'Support blijft gekoppeld aan de trainer/sessie-context van je verzoek.';
  @override
  String get supportverzoekAangemaakt => 'Supportverzoek aangemaakt!';
  @override
  String get supportverzoekMislukt => 'Supportverzoek mislukt';
  @override
  String get tarievenOpgeslagen => 'Tarieven opgeslagen';
  @override
  String get tarievenindicatie => 'Tarieven (indicatie)';
  @override
  String get terug => 'Terug';
  @override
  String get ticketIsAfgerondEnKanNietMeerWordenBeantwoord => 'Ticket is afgerond en kan niet meer worden beantwoord.';
  @override
  String get ticketsVanKlantenEnTrainersBeantwoorden => 'Tickets van klanten en trainers beantwoorden';
  @override
  String get tijd => 'Tijd';
  @override
  String get tijden => 'Tijden';
  @override
  String get tijdslot => 'Tijdslot';
  @override
  String get tikOmAanTePassen => 'Tik om aan te passen';
  @override
  String get tikOmFotoTeWijzigen => 'Tik om foto te wijzigen';
  @override
  String get tikOmOpnieuwTeVersturen => 'Tik om opnieuw te versturen';
  @override
  String get tikOmTeBewerkenu00b7LangIndrukkenOmTeVerwijderen => 'Tik om te bewerken \u00B7 lang indrukken om te verwijderen';
  @override
  String get tip => 'TIP';
  @override
  String get tipJeKuntOokHandmatigEenSessieAanJeAgendaToevoegenViaDeActieknopBijElkeBoeking => 'Tip: Je kunt ook handmatig een sessie aan je agenda toevoegen via de actie-knop bij elke boeking.';
  @override
  String get titel => 'Titel';
  @override
  String get tochVerplaatsen => 'Toch verplaatsen';
  @override
  String get toegestaneFormatenPdfJpgPngmax10mbPerBestand => 'Toegestane formaten: PDF, JPG, PNG (max 10MB per bestand)';
  @override
  String get toelaten => 'Toelaten';
  @override
  String get toelichtingoptioneel => 'Toelichting (optioneel)';
  @override
  String get toevoegen => 'Toevoegen';
  @override
  String get toonBeschikbaarheid => 'Toon beschikbaarheid';
  @override
  String get toonEenIntroductievideoOpJeProfielOndersteuntYoutubeEnVimeo => 'Toon een introductievideo op je profiel. Ondersteunt YouTube en Vimeo.';
  @override
  String get toonMeer => 'Toon meer';
  @override
  String get toonPrijs => 'Toon prijs';
  @override
  String get toonReviews => 'Toon reviews';
  @override
  String get topKlanten => 'Top klanten';
  @override
  String get totaal => 'Totaal';
  @override
  String get trainerUitbetalingen => 'Trainer Uitbetalingen';
  @override
  String get trainerUserId => 'Trainer user ID';
  @override
  String get traineridOntbreekt => 'Trainer-ID ontbreekt';
  @override
  String get trends => 'Trends';
  @override
  String get typEenBericht => 'Typ een bericht...';
  @override
  String get typJeAntwoord => 'Typ je antwoord...';
  @override
  String get typJeOnderwerpHier => 'Typ je onderwerp hier...';
  @override
  String get type => 'Type';
  @override
  String get uitInternTraineronlyNotitie => 'Uit = intern trainer-only notitie';
  @override
  String get uitloggen => 'Uitloggen';
  @override
  String get uitzonderingenoptioneel => 'Uitzonderingen (optioneel)';
  @override
  String get upgradeNaarPro => 'Upgrade naar Pro';
  @override
  String get uploadMisluktProbeerOpnieuw => 'Upload mislukt. Probeer opnieuw.';
  @override
  String get uurtarief => 'Uurtarief';
  @override
  String get vanaf => 'Vanaf';
  @override
  String get vastBedrag => 'Vast bedrag';
  @override
  String get verificatie => 'Verificatie';
  @override
  String get verificatieAangevraagd => 'Verificatie aangevraagd!';
  @override
  String get verificatieAanvragenMisluktProbeerHetLaterOpnieuw => 'Verificatie aanvragen mislukt. Probeer het later opnieuw.';
  @override
  String get verificatieStatus => 'Verificatie status';
  @override
  String get verlopendePakketten => 'Verlopende pakketten';
  @override
  String get verplaats => 'Verplaats';
  @override
  String get verplaatsen => 'Verplaatsen';
  @override
  String get verplaatsenMisluktProbeerHetOpnieuw => 'Verplaatsen mislukt. Probeer het opnieuw.';
  @override
  String get verstrekenTijd => 'Verstreken tijd';
  @override
  String get versturen => 'Versturen';
  @override
  String get versturenMisluktProbeerOpnieuw => 'Versturen mislukt, probeer opnieuw.';
  @override
  String get verstuurVerzoek => 'Verstuur verzoek';
  @override
  String get vervaldatum => 'Vervaldatum';
  @override
  String get verwijderUitMijnTrainers => 'Verwijder uit mijn trainers';
  @override
  String get verwijderen => 'Verwijderen';
  @override
  String get verwijderenMisluktProbeerOpnieuw => 'Verwijderen mislukt. Probeer opnieuw.';
  @override
  String get verzendtijd => 'Verzendtijd';
  @override
  String get videoKanNietWordenAfgespeeld => 'Video kan niet worden afgespeeld';
  @override
  String get videoKonNietWordenGelezenKiesEenAndere => 'Video kon niet worden gelezen. Kies een andere.';
  @override
  String get videoMagMax30SecondenZijnOpJeProfiel => 'Video mag max. 30 seconden zijn op je profiel.';
  @override
  String get videoToegevoegd => 'Video toegevoegd';
  @override
  String get videoVerwijderd => 'Video verwijderd';
  @override
  String get vindEenAntwoordOfNeemContactOp => 'Vind een antwoord of neem contact op';
  @override
  String get voegDoelenToeViaBackendOfVolgendeIteratieUi => 'Voeg doelen toe via backend of volgende iteratie UI.';
  @override
  String get voegVestigingenToeWaarJeGymActiefIs => 'Voeg vestigingen toe waar je gym actief is.';
  @override
  String get voerDe6cijferigeBackupCodeInDieDeKlantOpHetSchermHeeftStaan => 'Voer de 6-cijferige backup code in die de klant op het scherm heeft staan.';
  @override
  String get voerEenGeldigeYoutubeOfVimeoUrlIn => 'Voer een geldige YouTube of Vimeo URL in.';
  @override
  String get voerEenSpecialisatieIn => 'Voer een specialisatie in';
  @override
  String get vogLinkoptioneel => 'VOG link (optioneel)';
  @override
  String get vol => 'VOL';
  @override
  String get volgendeWeek => 'Volgende week';
  @override
  String get voltooien => 'Voltooien';
  @override
  String get voorUrgenteOperationeleIssuesMetContextpakket => 'Voor urgente operationele issues met contextpakket.';
  @override
  String get voorUrgenteOperationeleIssuesMetContextpakketissueBookingRefs => 'Voor urgente operationele issues met contextpakket (issue + booking refs).';
  @override
  String get voorbeeld => 'Voorbeeld';
  @override
  String get voorbeeldBekijken => 'Voorbeeld bekijken';
  @override
  String get voorbeeldEmail => 'Voorbeeld e-mail';
  @override
  String get vraagAan => 'Vraag aan';
  @override
  String get vulEenOnderwerpIn => 'Vul een onderwerp in';
  @override
  String get vulJeEmailEnWachtwoordIn => 'Vul je e-mail en wachtwoord in';
  @override
  String get vulJeEmailadresInWeSturenJeEenLinkOmJeWachtwoordTeResetten => 'Vul je e-mailadres in. We sturen je een link om je wachtwoord te resetten.';
  @override
  String get vulNaamEenGeldigAantalSessiesEnEenGeldigePrijsInbijv4999 => 'Vul naam, een geldig aantal sessies en een geldige prijs in (bijv. 49.99)';
  @override
  String get waaromVerificatie => 'Waarom verificatie?';
  @override
  String get wachtOpReactieVanSupport => 'Wacht op reactie van support';
  @override
  String get wachtlijst => 'Wachtlijst';
  @override
  String get wachtwoordSuccesvolGewijzigd => 'Wachtwoord succesvol gewijzigd';
  @override
  String get wachtwoordWijzigen => 'Wachtwoord wijzigen';
  @override
  String get watGingGoed => 'Wat ging goed?';
  @override
  String get watIsJeDoel => 'Wat is je doel?';
  @override
  String get watToonJeOpJeProfiel => 'Wat toon je op je profiel?';
  @override
  String get weMissenJe => 'We missen je';
  @override
  String get weekdoelInstellen => 'Weekdoel instellen';
  @override
  String get weergavenaam => 'Weergavenaam';
  @override
  String get weesDeEersteDieEenBeoordelingAchterlaatNaEenSessie => 'Wees de eerste die een beoordeling achterlaat na een sessie.';
  @override
  String get weetJeZekerDatJeDezeFeeSettingWiltVerwijderen => 'Weet je zeker dat je deze fee setting wilt verwijderen?';
  @override
  String get weetJeZekerDatJeDezeSessieWiltAnnuleren => 'Weet je zeker dat je deze sessie wilt annuleren?';
  @override
  String get wekelijkseTijdslots => 'Wekelijkse tijdslots';
  @override
  String get widgetAanpassen => 'Widget aanpassen';
  @override
  String get widgetHoogte => 'Widget hoogte';
  @override
  String get widgetInstellingenOpgeslagen => 'Widget instellingen opgeslagen!';
  @override
  String get widgetPreview => 'Widget preview';
  @override
  String get widgetStatistieken => 'Widget statistieken';
  @override
  String get wieBetaaltDeFee => 'Wie betaalt de fee?';
  @override
  String get wis => 'Wis';
  @override
  String get wisAlles => 'Wis alles';
  @override
  String get youtubeOfVimeoUrl => 'YouTube of Vimeo URL';
  @override
  String get zichtbaarheidElementen => 'Zichtbaarheid elementen';
  @override
  String get zoKunnenTrainersJeBeterVindennditIsOptioneelJeKuntHetLaterAanpassen => 'Zo kunnen trainers je beter vinden.\nDit is optioneel — je kunt het later aanpassen.';
  @override
  String get zoekEenTrainer => 'Zoek een trainer';
  @override
  String get zoekGebruikeremailNaam => 'Zoek gebruiker (e-mail, naam)';
  @override
  String get zoekGesprekken => 'Zoek gesprekken...';
  @override
  String get zoekInNotities => 'Zoek in notities...';
  @override
  String get zoekKlant => 'Zoek klant...';
  @override
  String get zoekKlantOpNaamOfEmail => 'Zoek klant op naam of e-mail';
  @override
  String get zoekOpKlantOfLaatsteBericht => 'Zoek op klant of laatste bericht';
  @override
  String get zoekOpNaamSpecialiteitOfRegio => 'Zoek op naam, specialiteit of regio';
  @override
  String get zoekTrainerSpecialismeOfStad => 'Zoek trainer, specialisme of stad...';
  @override
  String get zoekenOpTrainernaam => 'Zoeken op trainernaam...';

  // ═══ APOSTROPHE VARIANTS ═══
  @override
  String get alleenDezeKlantKanDezeVideos => 'Alleen deze klant kan deze video\'s zien';
  @override
  String get fotos => 'Foto\'s';
  @override
  String get instructievideos => 'Instructievideo\'s';
  @override
  String get nogGeenVideos => 'Nog geen video\'s';
  @override
  String get ontdekTrainersInJouwBuurtEnBoeknjeEersteSessieLets => 'Ontdek trainers in jouw buurt en boek\nje eerste sessie. Let\'s go!';
  @override
  String get videos => 'Video\'s';
  @override
  String get voegFotos => 'Voeg foto\'s toe';
  @override
  String get voegInstructievideos => 'Voeg instructievideo\'s toe';

  // ═══ PHASE 3 BULK KEYS ═══
  @override
  String get aanmeldenVoorNieuwsbrief => 'Aanmelden voor nieuwsbrief';
  @override
  String get abonnementOpgezegd => 'Abonnement opgezegd';
  @override
  String get abonnementOpzeggen => 'Abonnement opzeggen?';
  @override
  String get accepteertAlleenCash => 'Accepteert alleen cash';
  @override
  String get accepteertAlleenOverboekingen => 'Accepteert alleen overboekingen';
  @override
  String get accepteertOverboekingenCash => 'Accepteert overboekingen & cash';
  @override
  String get actieMisluktProbeerOpnieuw => 'Actie mislukt. Probeer opnieuw.';
  @override
  String get adresIsVerplicht => 'Adres is verplicht';
  @override
  String get afgerondeSessiesVerschijnenHierAlsHistorie => 'Afgeronde sessies verschijnen hier als historie.';
  @override
  String get agendaIsLeeg => 'Agenda is leeg';
  @override
  String get alEenAccount => 'Al een account? ';
  @override
  String get alleAchtergrondactiesZijnGesynchroniseerd => 'Alle achtergrondacties zijn gesynchroniseerd.';
  @override
  String get alleMeldingenZijnGelezen => 'Alle meldingen zijn gelezen.';
  @override
  String get allebeiEenBeloningWanneerZijStarten => 'allebei een beloning wanneer zij starten!';
  @override
  String get alleenCash => 'Alleen cash';
  @override
  String get alleenDezeDag => 'Alleen deze dag';
  @override
  String get alleenOverboekingen => 'Alleen overboekingen';
  @override
  String get allesVanPro => 'Alles van Pro';
  @override
  String get allesVanStarter => 'Alles van Starter';
  @override
  String get alsDankVoorJeVertrouwenEn => 'Als dank voor je vertrouwen en inzet bieden we deze week:</p>';
  @override
  String get alsHetMinimumNietBereiktIs => 'Als het minimum niet bereikt is voor deze deadline, wordt de les automatisch geannuleerd.';
  @override
  String get amstelveen => 'amstelveen';
  @override
  String get annuleringsEnRestitutieregels => 'Annulerings- en restitutieregels';
  @override
  String get appIsGemanipuleerd => 'App is gemanipuleerd';
  @override
  String get autoherboekingenIngeschakeld => 'Auto-herboekingen ingeschakeld';
  @override
  String get autoherboekingenUitgeschakeld => 'Auto-herboekingen uitgeschakeld';
  @override
  String get backendEndpointNietBeschikbaarToonDefaults => 'Backend endpoint niet beschikbaar. Toon defaults.';
  @override
  String get basisVoorStartenAlsTrainer => 'Basis voor starten als trainer';
  @override
  String get bedanktDatJeGymiesGebruikt => 'Bedankt dat je GYMIES gebruikt!';
  @override
  String get bedanktVoorJeBeoordeling => 'Bedankt voor je beoordeling!';
  @override
  String get bedanktVoorVandaag => 'Bedankt voor vandaag!';
  @override
  String get bedrijfsnaamIsVerplicht => 'Bedrijfsnaam is verplicht';
  @override
  String get beheerAanbod => 'Beheer aanbod';
  @override
  String get beheerJeSessiepakkettenEnStrippenkaarten => 'Beheer je sessie-pakketten en strippenkaarten';
  @override
  String get bekijkDeUpdatesEnZorgDat => 'Bekijk de updates en zorg dat je goed bent voorbereid voor je volgende sessies.</p>';
  @override
  String get bekijkTrendsOmzetverdelingEnExporteerData => 'Bekijk trends, omzetverdeling en exporteer data.';
  @override
  String get belangrijkUpdateVanJeTrainer => 'Belangrijk update van je trainer 📢';
  @override
  String get belangrijkUpdateVanJeTrainer2 => 'Belangrijk update van je trainer';
  @override
  String get beoordelingHoogNaarLaag => 'Beoordeling: hoog naar laag';
  @override
  String get beoordelingVersturenMisluktProbeerLaterOpnieuw => 'Beoordeling versturen mislukt. Probeer later opnieuw.';
  @override
  String get bereikJeDoelenMetPersoonlijkeBegeleiding => 'Bereik je doelen met persoonlijke begeleiding';
  @override
  String get berichtMagNietLangerZijnDan => 'Bericht mag niet langer zijn dan 2000 tekens';
  @override
  String get berichtMoetMinstens10TekensLang => 'Bericht moet minstens 10 tekens lang zijn';
  @override
  String get beschikbaarheidEnUitzonderingen => 'Beschikbaarheid en uitzonderingen';
  @override
  String get beschikbarePlannen => 'Beschikbare plannen';
  @override
  String get betaalEnAfronden => 'Betaal en afronden';
  @override
  String get betaald => 'Betaald';
  @override
  String get betaaldOp => 'Betaald op';
  @override
  String get betaaldeFacturenVerschijnenHierMetBetaalmethode => 'Betaalde facturen verschijnen hier met betaalmethode en referentie.';
  @override
  String get betaalstatusControleren => 'Betaalstatus controleren';
  @override
  String get betaling => 'betaling';
  @override
  String get betalingMislukt => 'Betaling mislukt';
  @override
  String get betalingWordtVerwerktDeStatusWordt => 'Betaling wordt verwerkt. De status wordt zo bijgewerkt.';
  @override
  String get bezig => 'Bezig…';
  @override
  String get bezig2 => 'Bezig...';
  @override
  String get bijvBijZiekteMetBewijsIs => 'bijv. Bij ziekte met bewijs is annulering gratis';
  @override
  String get bijvEersteSessie50Korting => 'bijv. Eerste sessie 50% korting';
  @override
  String get bijvPersonalTrainerAmsterdam => 'bijv. Personal trainer Amsterdam';
  @override
  String get bijvoorbeeldNieuwTrainingsschemaBeschikbaar => 'Bijvoorbeeld: "Nieuw trainingsschema beschikbaar"';
  @override
  String get blauwVinkjeOpJeProfiel => 'Blauw vinkje op je profiel';
  @override
  String get blijDatTeHorenJeMaakt => 'Blij dat te horen! Je maakt goede progressie.';
  @override
  String get blijTeHoren => 'Blij te horen!';
  @override
  String get blijfOpDeHoogteVanTips => 'Blijf op de hoogte van tips en aanbiedingen';
  @override
  String get blokkeringVerwijderd => 'Blokkering verwijderd';
  @override
  String get boekNuEenTrainingEnBegin => 'Boek nu een training en begin je fitnessreis. Je trainer zal contact opnemen om alles in te plannen.';
  @override
  String get boekenViaStandbyMislukt => 'Boeken via standby mislukt.';
  @override
  String get boeking => 'boeking';
  @override
  String get boekingAangemaaktMaarBetalingKonNiet => 'Boeking aangemaakt maar betaling kon niet worden gestart. ';
  @override
  String get boekingAangemaaktMaarGeenIdOntvangen => 'Boeking aangemaakt maar geen ID ontvangen.';
  @override
  String get boekingAangemaaktOpenMijnSessiesOm => 'Boeking aangemaakt! Open "Mijn Sessies" om te betalen.';
  @override
  String get boekingBevestigen => 'Boeking bevestigen';
  @override
  String get boekingMisluktProbeerOpnieuw => 'Boeking mislukt. Probeer opnieuw.';
  @override
  String get boekingenViaJeEigenSite => 'Boekingen via je eigen site';
  @override
  String get boekingenViaWidget => 'Boekingen via widget';
  @override
  String get boekingidOntbreekt => 'Boeking-ID ontbreekt.';
  @override
  String get boekingidOntbreektVernieuwDeLijstEn => 'Boeking-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.';
  @override
  String get boekingswidget => 'Boekingswidget';
  @override
  String get boekingswidgetVoorJeWebsite => 'Boekingswidget voor je website';
  @override
  String get brandedProfiel => 'Branded profiel';
  @override
  String get cashBetalingGemarkeerdBevestigBetalingBij => 'Cash betaling gemarkeerd. Bevestig betaling bij trainer.';
  @override
  String get chatBroadcastingNietEnabledOpBackend => '[Chat] Broadcasting niet enabled op backend, alleen polling';
  @override
  String get chatKonMyuseridNietCachen => '[Chat] Kon myUserId niet cachen';
  @override
  String get checkinDirectGelukt => 'Check-in direct gelukt';
  @override
  String get checkinMislukt => 'Check-in mislukt';
  @override
  String get checkinOfflineOpgeslagen => 'Check-in offline opgeslagen';
  @override
  String get controleerDeFactuurgegevensVoordatJeVerstuurt => 'Controleer de factuurgegevens voordat je verstuurt.';
  @override
  String get danKunJeHierEenGeschil => 'dan kun je hier een geschil indienen.';
  @override
  String get deAppToontDezeInstellingenAan => 'De app toont deze instellingen aan trainers.';
  @override
  String get deBackupCodeIsOngeldigOf => 'De backup code is ongeldig of verlopen. ';
  @override
  String get deSafeSessionMonitoringWordtGestopt => 'De safe session monitoring wordt gestopt en ';
  @override
  String get deelDezeQrcodeOpFlyersVisitekaartjes => 'Deel deze QR-code op flyers, visitekaartjes ';
  @override
  String get deelJeLink => 'Deel je link';
  @override
  String get deelJePersoonlijkeLink => 'Deel je persoonlijke link';
  @override
  String get deelJeProfielOffline => 'Deel je profiel offline';
  @override
  String get deelnemeridOntbreektVoorDezeRegel => 'Deelnemer-ID ontbreekt voor deze regel.';
  @override
  String get dezeActieKanNietOngedaanWorden => 'Deze actie kan niet ongedaan worden gemaakt.';
  @override
  String get dezeFactuurWordtOpnieuwNaarDe => 'Deze factuur wordt opnieuw naar de klant gestuurd voor deze boeking.';
  @override
  String get dezeQrcodeBevatGeenGeldigeCheckin => 'Deze QR-code bevat geen geldige check-in data. ';
  @override
  String get dezeSessieBegintOverMinderDan => 'Deze sessie begint over minder dan een uur. Weet je zeker dat je wilt verplaatsen?';
  @override
  String get dezeSessieIsVandaagWeetJe => 'Deze sessie is vandaag. Weet je zeker dat je wilt verplaatsen?';
  @override
  String get dezeStandbyaanbiedingIsVerlopen => 'Deze standby-aanbieding is verlopen.';
  @override
  String get directContactMetJeKlanten => 'Direct contact met je klanten';
  @override
  String get directVanuitJouwSiteTeLaten => 'direct vanuit jouw site te laten boeken.';
  @override
  String get ditGeschilIsOpgelost => 'Dit geschil is opgelost.';
  @override
  String get ditTijdslotIsHelaasNietMeer => 'Dit tijdslot is helaas niet meer beschikbaar. Kies een ander moment.';
  @override
  String get ditVerwijdertJeAccountEnAlle => 'Dit verwijdert je account en alle bijbehorende gegevens permanent. ';
  @override
  String get ditZalJeAccountEnAlle => 'Dit zal je account en alle bijbehorende gegevens permanent verwijderen. ';
  @override
  String get documentenOpgeslagen => 'Documenten opgeslagen';
  @override
  String get documentenWordenVertrouwelijkBehandeldEnAlleen => 'Documenten worden vertrouwelijk behandeld en alleen door ons team bekeken.';
  @override
  String get doelenPerKlant => 'Doelen per klant';
  @override
  String get doorgaanNaarBetaling => 'Doorgaan naar betaling';
  @override
  String get dossierOpstellen => 'Dossier opstellen';
  @override
  String get dossierPerKlant => 'Dossier per klant';
  @override
  String get duoSessie => 'Duo sessie';
  @override
  String get eigenBrandedProfiel => 'Eigen branded profiel';
  @override
  String get eigenBrandedProfielpagina => 'Eigen branded profielpagina';
  @override
  String get eigenProfielOpGymies => 'Eigen profiel op Gymies';
  @override
  String get embedCodeNietBeschikbaar => 'Embed code niet beschikbaar';
  @override
  String get erGingIetsMis => 'Er ging iets mis.';
  @override
  String get erGingIetsMisProbeerHet => 'Er ging iets mis. Probeer het opnieuw.';
  @override
  String get erGingIetsMisProbeerOpnieuw => 'Er ging iets mis. Probeer opnieuw.';
  @override
  String get erGingIetsMisProbeerOpnieuw2 => 'Er ging iets mis. Probeer opnieuw te scannen of ';
  @override
  String get erIsEenBeveiligingsprobleemGedetecteerd => 'Er is een beveiligingsprobleem gedetecteerd.';
  @override
  String get erZijnMomenteelGeenTrainersBeschikbaarnprobeer => 'Er zijn momenteel geen trainers beschikbaar.\nProbeer het later opnieuw of pas je zoekopdracht aan.';
  @override
  String get erZijnNogGeenBoekingenIn => 'Er zijn nog geen boekingen in dit overzicht.';
  @override
  String get erZijnNogGeenKlantenGekoppeld => 'Er zijn nog geen klanten gekoppeld aan deze gym.';
  @override
  String get erZijnNogGeenTrainersGekoppeld => 'Er zijn nog geen trainers gekoppeld aan deze gym.';
  @override
  String get exclusieveActieVoorOnzeKlanten => 'Exclusieve actie voor onze klanten! 🎉';
  @override
  String get exclusieveActieVoorOnzeKlanten2 => 'Exclusieve actie voor onze klanten!';
  @override
  String get facturenVerschijnenHierZodraJeTrainer => 'Facturen verschijnen hier zodra je trainer ze verstuurt.';
  @override
  String get facturenWordenAutomatischAangemaaktBijVoltooide => 'Facturen worden automatisch aangemaakt bij voltooide sessies.';
  @override
  String get factuur => 'factuur';
  @override
  String get factuur2 => 'Factuur';
  @override
  String get factuurBeschikbaar => 'Factuur beschikbaar';
  @override
  String get factuurIsOpgesteldJeKuntLater => 'Factuur is opgesteld. Je kunt later reviewen en versturen.';
  @override
  String get factuurNogNietBeschikbaar => 'Factuur nog niet beschikbaar.';
  @override
  String get factuurOpnieuw => 'Factuur opnieuw';
  @override
  String get factuurOpnieuwVersturen => 'Factuur opnieuw versturen';
  @override
  String get factuurOpstellen => 'Factuur opstellen';
  @override
  String get factuurReview => 'Factuur review';
  @override
  String get factuurReviewOpnieuwVersturen => 'Factuur review (opnieuw versturen)';
  @override
  String get factuurSectieOpstellenEnReview => 'Factuur sectie: opstellen en review';
  @override
  String get factuurSectieReviewEnOpnieuwVersturen => 'Factuur sectie: review en opnieuw versturen';
  @override
  String get factuurgegevensOntbreken => 'Factuurgegevens ontbreken';
  @override
  String get factuurlinkIsOngeldig => 'Factuurlink is ongeldig.';
  @override
  String get factuurlinkOntbreekt => 'Factuurlink ontbreekt.';
  @override
  String get factuurverzoek => 'Factuurverzoek';
  @override
  String get factuurverzoekGeregistreerd => 'Factuurverzoek geregistreerd';
  @override
  String get factuurverzoekVoorSessie => 'Factuurverzoek voor sessie';
  @override
  String get fitnesstipVanDeWeek => 'FitnessTip van de week 💪';
  @override
  String get fitnesstipVanDeWeek2 => 'Fitnesstip van de week';
  @override
  String get focusIsVerplicht => 'Focus is verplicht';
  @override
  String get fotoIsTeGrootMax5 => 'Foto is te groot (max 5 MB). Kies een kleinere foto of ';
  @override
  String get fotosEnVideosOpJeProfiel => 'Foto\\'s en video\\'s op je profiel';
  @override
  String get foutBijLadenVanMarketinggegevens => 'Fout bij laden van marketinggegevens';
  @override
  String get gaNaarBetaling => 'Ga naar betaling';
  @override
  String get gaNaarMijnSessiesOmAlsnog => 'Ga naar "Mijn Sessies" om alsnog te betalen.';
  @override
  String get gebruikPromoCodesBijSeizoenswisselingenVoor => 'Gebruik promo codes bij seizoenswisselingen voor meer boekingen';
  @override
  String get gecertificeerdeTrainers => 'Gecertificeerde trainers';
  @override
  String get geefGroepslessenBeheerCapaciteitEnLaat => 'Geef groepslessen, beheer capaciteit en laat meerdere klanten ';
  @override
  String get geenBlokkeringen => 'Geen blokkeringen';
  @override
  String get geenBoekingen => 'Geen boekingen';
  @override
  String get geenEinddatum => 'Geen einddatum';
  @override
  String get geenExtraDetails => 'Geen extra details';
  @override
  String get geenFacturen => 'Geen facturen';
  @override
  String get geenFeaturesVanBackend => 'Geen features van backend';
  @override
  String get geenKlanten => 'Geen klanten';
  @override
  String get geenLimiet => 'Geen limiet';
  @override
  String get geenMeldingenInDitFilter => 'Geen meldingen in dit filter';
  @override
  String get geenMollielinkOntvangenConfigureerMollieclientidOp => 'Geen Mollie-link ontvangen. Configureer MOLLIE_CLIENT_ID op de server.';
  @override
  String get geenNaam => 'Geen naam';
  @override
  String get geenNieuweAanvragen => 'Geen nieuwe aanvragen';
  @override
  String get geenOnderwerp => 'Geen onderwerp';
  @override
  String get geenOngelezenMeldingen => 'Geen ongelezen meldingen';
  @override
  String get geenOpenstaandeUitbetalingen => 'Geen openstaande uitbetalingen';
  @override
  String get geenOptiesIngesteld => 'Geen opties ingesteld';
  @override
  String get geenPlanDefaultsIngesteld => 'Geen plan defaults ingesteld';
  @override
  String get geenProbleem => 'Geen probleem';
  @override
  String get geenProbleemLaatMeWetenWanneer => 'Geen probleem! Laat me weten wanneer het je wel schikt.';
  @override
  String get geenRedenOpgegeven => 'Geen reden opgegeven';
  @override
  String get geenResultatenGevonden => 'Geen resultaten gevonden';
  @override
  String get geenSlotsBeschikbaarOpDezeDag => 'Geen slots beschikbaar op deze dag';
  @override
  String get geenTrainerOverrides => 'Geen trainer overrides';
  @override
  String get geenTrainers => 'Geen trainers';
  @override
  String get geenTransacties => 'Geen transacties';
  @override
  String get geenTransactiesMetDezeStatus => 'Geen transacties met deze status.';
  @override
  String get geenVerbindingDeCheckinIsOpgeslagen => 'Geen verbinding. De check-in is opgeslagen en wordt ';
  @override
  String get geenWijzigbareVoorkeurveldenGevonden => 'Geen wijzigbare voorkeurvelden gevonden.';
  @override
  String get geenWijzigbareVoorkeurveldenGevondenInNotificationspreferences => 'Geen wijzigbare voorkeurvelden gevonden in notifications/preferences.';
  @override
  String get geverifieerdeTrainersKrijgenEenBadgeOp => 'Geverifieerde trainers krijgen een badge op hun profiel, ';
  @override
  String get goedGedaanDatJeHebtDoorgezet => 'Goed gedaan dat je hebt doorgezet! Het wordt makkelijker.';
  @override
  String get goeieVraagIkLegHetEven => 'Goeie vraag! Ik leg het even uit...';
  @override
  String get gratisSessie => 'Gratis sessie';
  @override
  String get groepslesAanmaken => 'Groepsles aanmaken';
  @override
  String get groepslesBewerken => 'Groepsles bewerken';
  @override
  String get groepslesBijgewerkt => 'Groepsles bijgewerkt';
  @override
  String get groepslesGeannuleerd => 'Groepsles geannuleerd';
  @override
  String get groepslesGepubliceerd => 'Groepsles gepubliceerd';
  @override
  String get groepslesToegevoegd => 'Groepsles toegevoegd';
  @override
  String get groepslesToevoegen => 'Groepsles toevoegen';
  @override
  String get groepslesidOntbreekt => 'Groepsles-ID ontbreekt.';
  @override
  String get groepslesidOntbreektVernieuwDeLijstEn => 'Groepsles-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.';
  @override
  String get groepslessenBeheer => 'Groepslessen beheer';
  @override
  String get gymiesJePersoonlijkeFitnessCoachnn => 'GYMIES – Je persoonlijke fitness coach.\n\n';
  @override
  String get gymiesVerwerktJePersoonsgegevensConformDe => 'GYMIES verwerkt je persoonsgegevens conform de AVG (GDPR). ';
  @override
  String get gymiesfavoritetrainerids => 'gymies_favorite_trainer_ids';
  @override
  String get gymiesremovedfrommytrainersids => 'gymies_removed_from_my_trainers_ids';
  @override
  String get gyminstellingen => 'Gym-instellingen';
  @override
  String get hallonndezeWeekDelenWeEenWaardevolle => 'Hallo!\n\nDeze week delen we een waardevolle fitnessTip met je:\n\n📌 [Tip/advies]\n\nWaarom is dit belangrijk?\n[Uitleg van het voordeel]\n\nHoe pas je dit toe?\n[Praktische stappen]\n\nVragen? Laat het weten! Je trainer is altijd beschikbaar.\n\nGroeten,\nJe trainer';
  @override
  String get hallonnjeNieuweTrainingsschemaIsNuBeschikbaar => 'Hallo!\n\nJe nieuwe trainingsschema is nu beschikbaar in de app. Bekijk de updates en zorg dat je goed bent voorbereid voor je volgende sessies.\n\nBijzonderheden:\n• Aangepast aan jouw doelen\n• Progressieve oefeningen\n• Flexibel in te delen\n\nBen je klaar? Laten we aan de slag gaan!\n\nGroeten,\nJe trainer';
  @override
  String get hallonnweHebbenEenSpecialeAanbiedingVoor => 'Hallo!\n\nWe hebben een speciale aanbieding voor jou! Als dank voor je vertrouwen en inzet bieden we dit week:\n\n🎁 [Beschrijving van aanbieding]\n💰 [Voordeel voor jou]\n⏰ Geldig tot [datum]\n\nNot gemist! Dit aanbod is exclusief voor onze vaste klanten.\n\nGroeten,\nJe trainer';
  @override
  String get hallonnweOrganiserenEenSpeciaalEventEn => 'Hallo!\n\nWe organiseren een speciaal event en je bent van harte uitgenodigd!\n\n📅 Datum: [datum en tijd]\n📍 Locatie: [adres]\n👥 Wat te verwachten:\n   • [Activiteit 1]\n   • [Activiteit 2]\n   • [Activiteit 3]\n\nSnel aanmelden! Beperkt aantal plaatsen beschikbaar.\n\nGroeten,\nJe trainer';
  @override
  String get hallonnweWillenJeGraagInformerenDat => 'Hallo!\n\nWe willen je graag informeren dat onze studio gesloten is van [datum] tot [datum] vanwege vakantie.\n\nWij zijn dan niet beschikbaar voor sessies, maar je kunt je trainingsplan volgen via de app.\n\nWe kijken ernaar uit je binnenkort weer te zien!\n\nGroeten,\nJe trainer';
  @override
  String get hallonnweWillenJeGraagOpDe => 'Hallo!\n\nWe willen je graag op de hoogte stellen van de volgende updates:\n\n✅ [Update 1]\n✅ [Update 2]\n✅ [Update 3]\n\nDeze veranderingen helpen ons om je beter van dienst te zijn. Heb je vragen? Neem gerust contact op!\n\nGroeten,\nJe trainer';
  @override
  String get hebJeVragenNeemGerustContact => 'Heb je vragen? Neem gerust contact op!</p>';
  @override
  String get herhaalJeWachtwoord => 'Herhaal je wachtwoord';
  @override
  String get herstel => 'Herstel';
  @override
  String get herstellen => 'Herstellen';
  @override
  String get hetIsGeluktOmTeVerbinden => 'Het is gelukt om te verbinden met Mollie. Je kunt nu betalingen ontvangen van klanten.';
  @override
  String get hetRechtJeGegevensInTe => 'het recht je gegevens in te zien, te corrigeren of te verwijderen.';
  @override
  String get hetSysteemStuurtElke2Minuten => 'Het systeem stuurt elke 2 minuten een heartbeat. ';
  @override
  String get hoeGaatHet => 'Hoe gaat het?';
  @override
  String get hoeGing => 'hoe ging';
  @override
  String get hoeGoedVindbaarBenJe => 'Hoe goed vindbaar ben je?';
  @override
  String get hoeMogenWeJeNoemen => 'Hoe mogen we je noemen?';
  @override
  String get hoeVerVooruitGeboektKanWorden => 'Hoe ver vooruit geboekt kan worden';
  @override
  String get hoeVondJe => 'hoe vond je';
  @override
  String get hoeWas => 'hoe was';
  @override
  String get hoeWasDeLes => 'Hoe was de les?';
  @override
  String get hoeWasDeLesVandaag => 'Hoe was de les vandaag?';
  @override
  String get hoeveelKrijgtDeKlantTerug => 'Hoeveel krijgt de klant terug?';
  @override
  String get hogerInDeLijstVoorKlanten => 'Hoger in de lijst voor klanten';
  @override
  String get hulpViaEmail => 'Hulp via e-mail';
  @override
  String get ikCheckHetEvenVoorJe => 'Ik check het even voor je en laat het weten.';
  @override
  String get ikGaAkkoordMetHet => 'Ik ga akkoord met het ';
  @override
  String get ikHebEenVraagje => 'Ik heb een vraagje...';
  @override
  String get ikHebHierNogEenVraagje => 'Ik heb hier nog een vraagje over...';
  @override
  String get ikMoetHelaasAfzeggenVoorVandaag => 'Ik moet helaas afzeggen voor vandaag, sorry!';
  @override
  String get ikTrainMetGymiesEnVind => 'Ik train met GYMIES en vind het top! ';
  @override
  String get inschrijvenBetalen => 'Inschrijven & betalen';
  @override
  String get inschrijvingVoltooid => 'Inschrijving voltooid';
  @override
  String get introvideoOpJeProfiel => 'Intro-video op je profiel';
  @override
  String get inzichtInJeVerdiensten => 'Inzicht in je verdiensten';
  @override
  String get jeDataWordtNietMetDerden => 'Je data wordt niet met derden gedeeld en uitsluitend gebruikt ';
  @override
  String get jeEigenTrainerspagina => 'Je eigen trainerspagina';
  @override
  String get jeFiltersLeverenGeenResultatenOpnpas => 'Je filters leveren geen resultaten op.\nPas je filters aan of zoek in een andere stad.';
  @override
  String get jeHebtEenVastePlekVoor => 'Je hebt een vaste plek voor klanten';
  @override
  String get jeHebtHetLimietBereiktMaximaal => 'Je hebt het limiet bereikt. Maximaal 2 nieuwsbrieven per week.';
  @override
  String get jeHuisstijlOpGymies => 'Je huisstijl op Gymies';
  @override
  String get jeNieuweTrainingsschemaIsKlaar => 'Je nieuwe trainingsschema is klaar!';
  @override
  String get jeNoodcontactEnHetPlatformWorden => 'Je noodcontact en het platform worden direct op de hoogte gesteld.';
  @override
  String get jeNoodcontactWordtAutomatischGenformeerdAls => 'Je noodcontact wordt automatisch geïnformeerd als je niet ';
  @override
  String get jeOntvangtEenMeldingZodraDe => 'Je ontvangt een melding zodra de les doorgaat.';
  @override
  String get jeProfielHeeftEenBlauwVerificatievinkje => 'Je profiel heeft een blauw verificatievinkje.';
  @override
  String get jeProfielHeeftEenBlauwVinkje => 'Je profiel heeft een blauw vinkje.';
  @override
  String get jeReserveertEenPlekJeBetaalt => 'Je reserveert een plek. Je betaalt pas als het minimum aantal deelnemers bereikt is.';
  @override
  String get jeSessieDuurtLangerDanVerwacht => 'Je sessie duurt langer dan verwacht. ';
  @override
  String get jeStaatNogOpGeenWachtlijst => 'Je staat nog op geen wachtlijst. Ga naar het profiel van een trainer en klik op "Wachtlijst" om je in te schrijven als er geen plek is.';
  @override
  String get jeTrainingsplanVolgenViaDeAppp => 'je trainingsplan volgen via de app.</p>';
  @override
  String get jeVoltooideTrainingenEnBeoordelingenZullen => 'Je voltooide trainingen en beoordelingen zullen hier verschijnen na je eerste sessie.';
  @override
  String get jeVriendMaaktEenAccountAan => 'Je vriend maakt een account aan via jouw link en boekt een sessie.';
  @override
  String get jeWordtDoorgestuurdNaarDeBetaalpagina2 => 'Je wordt doorgestuurd naar de betaalpagina.';
  @override
  String get jeWordtNuDoorgestuurdNaarDe => 'Je wordt nu doorgestuurd naar de betaalpagina. Na betaling keer je terug naar de app.';
  @override
  String get jouwhandleOfUrl => '@jouwhandle of URL';
  @override
  String get jullieKrijgenAllebeiEenBeloningZodra => 'Jullie krijgen allebei een beloning zodra de eerste sessie voltooid is!';
  @override
  String get kanIkStuurJeEenVerplaatsingsverzoek => 'Kan! Ik stuur je een verplaatsingsverzoek.';
  @override
  String get kanNiet => 'kan niet';
  @override
  String get kiesDatumEnTijd => 'Kies datum en tijd';
  @override
  String get kiesEenNieuwTijdstip => 'Kies een nieuw tijdstip';
  @override
  String get kiesEenNieuweDatum => 'Kies een nieuwe datum';
  @override
  String get kiesEerstEenBeschikbaarTijdslot => 'Kies eerst een beschikbaar tijdslot.';
  @override
  String get klaarOmTeScannen => 'Klaar om te scannen';
  @override
  String get klant => 'klant';
  @override
  String get klantAnalytics => 'Klant analytics';
  @override
  String get klantAnalytics2 => 'Klant Analytics';
  @override
  String get klantGepromoveerdVanWachtlijst => 'Klant gepromoveerd van wachtlijst';
  @override
  String get klantanalytics => 'Klantanalytics';
  @override
  String get klantbeheerTagsEnSegmenten => 'Klantbeheer, tags en segmenten';
  @override
  String get klantenBoekenViaJouwProfielZorg => 'Klanten boeken via jouw profiel. Zorg dat je beschikbaarheid klopt zodat ze je kunnen vinden.';
  @override
  String get klantenKunnenDirectBoeken => 'Klanten kunnen direct boeken';
  @override
  String get klantenLatenReviewsAchter => 'Klanten laten reviews achter';
  @override
  String get klantenZienAlleenJouwVrijeTijdslots => 'Klanten zien alleen jouw vrije tijdslots als je ze hier instelt. Tik op "+ Tijdslot" hieronder om te beginnen.';
  @override
  String get klantenbestandCrm => 'Klantenbestand (CRM)';
  @override
  String get klanttagslabels => 'Klanttags/labels';
  @override
  String get klikOmDatumtijdTeSelecteren => 'Klik om datum/tijd te selecteren';
  @override
  String get komNaarOnsEvent => 'Kom naar ons event! 🎪';
  @override
  String get komNaarOnsEvent2 => 'Kom naar ons event!';
  @override
  String get konAgendaNietLaden => 'Kon agenda niet laden.';
  @override
  String get konBerichtenNietLaden => 'Kon berichten niet laden.';
  @override
  String get konBeschikbaarheidNietLaden => 'Kon beschikbaarheid niet laden';
  @override
  String get konBetaalpaginaNietOpenen => 'Kon betaalpagina niet openen.';
  @override
  String get konBoekingenNietLaden2 => 'Kon boekingen niet laden.';
  @override
  String get konBrandinginstellingenNietLaden => 'Kon branding-instellingen niet laden.';
  @override
  String get konChatNietLaden => 'Kon chat niet laden.';
  @override
  String get konControlTowerNietLaden => 'Kon Control Tower niet laden.';
  @override
  String get konDocumentenNietLaden => 'Kon documenten niet laden.';
  @override
  String get konDossierDataNietLaden => 'Kon dossier data niet laden.';
  @override
  String get konDossierNietLaden => 'Kon dossier niet laden.';
  @override
  String get konEtalageNietLaden => 'Kon etalage niet laden.';
  @override
  String get konFacturenNietLaden => 'Kon facturen niet laden.';
  @override
  String get konFactuurNietOpenen => 'Kon factuur niet openen.';
  @override
  String get konFavorietenNietLaden => 'Kon favorieten niet laden.';
  @override
  String get konFeaturesNietLadenToonDefaults => 'Kon features niet laden. Toon defaults.';
  @override
  String get konFeesNietLaden => 'Kon fees niet laden.';
  @override
  String get konGebruikerNietLaden => 'Kon gebruiker niet laden.';
  @override
  String get konGeenGesprekOpenen => 'Kon geen gesprek openen.';
  @override
  String get konGegevensNietLaden => 'Kon gegevens niet laden.';
  @override
  String get konGeschilNietLaden => 'Kon geschil niet laden.';
  @override
  String get konGeschillenNietLaden => 'Kon geschillen niet laden.';
  @override
  String get konGesprekkenNietLaden => 'Kon gesprekken niet laden.';
  @override
  String get konGroepslesNietLaden => 'Kon groepsles niet laden.';
  @override
  String get konGroepslessenNietLaden => 'Kon groepslessen niet laden.';
  @override
  String get konGymdashboardNietLaden => 'Kon gym-dashboard niet laden.';
  @override
  String get konInschrijvingenNietLaden => 'Kon inschrijvingen niet laden.';
  @override
  String get konInstellingenNietLaden => 'Kon instellingen niet laden.';
  @override
  String get konKlantAnalyticsNietLaden => 'Kon klant analytics niet laden.';
  @override
  String get konKlantenNietLaden => 'Kon klanten niet laden.';
  @override
  String get konLinkNietOpenen => 'Kon link niet openen.';
  @override
  String get konLogistiekNietLaden => 'Kon logistiek niet laden.';
  @override
  String get konMediaNietLaden => 'Kon media niet laden.';
  @override
  String get konMeldingenNietLaden => 'Kon meldingen niet laden.';
  @override
  String get konPakkettenNietLaden => 'Kon pakketten niet laden.';
  @override
  String get konProHubNietLaden => 'Kon Pro Hub niet laden.';
  @override
  String get konProfielNietLaden => 'Kon profiel niet laden';
  @override
  String get konProfielNietLadenProbeerOpnieuw => 'Kon profiel niet laden. Probeer opnieuw.';
  @override
  String get konProfielNietOpslaan => 'Kon profiel niet opslaan';
  @override
  String get konPromotiecodesNietLaden => 'Kon promotiecodes niet laden.';
  @override
  String get konQrcodeNietLadenControleerJe => 'Kon QR-code niet laden. Controleer je internetverbinding.';
  @override
  String get konReviewsNietLaden => 'Kon reviews niet laden.';
  @override
  String get konSeogegevensNietLaden => 'Kon SEO-gegevens niet laden.';
  @override
  String get konSessieNietToevoegenAanAgenda => 'Kon sessie niet toevoegen aan agenda';
  @override
  String get konSocialMediaNietLaden => 'Kon social media niet laden.';
  @override
  String get konStudioonboardingNietLaden => 'Kon studio/onboarding niet laden.';
  @override
  String get konTarievenNietLaden => 'Kon tarieven niet laden.';
  @override
  String get konTegoedNietLaden => 'Kon tegoed niet laden.';
  @override
  String get konTicketsNietLaden => 'Kon tickets niet laden.';
  @override
  String get konTrainerprofielNietLaden => 'Kon trainerprofiel niet laden.';
  @override
  String get konTrainersNietLaden => 'Kon trainers niet laden.';
  @override
  String get konVerzoekNietVersturenProbeerOpnieuw => 'Kon verzoek niet versturen. Probeer opnieuw.';
  @override
  String get konWachtlijstenNietLaden => 'Kon wachtlijsten niet laden.';
  @override
  String get korteBeschrijvingVoorZoekmachines => 'Korte beschrijving voor zoekmachines';
  @override
  String get korteBeschrijvingVoorZoekmachines2 => 'Korte beschrijving voor zoekmachines...';
  @override
  String get kortingscodesVoorKlanten => 'Kortingscodes voor klanten';
  @override
  String get krijgEenBlauwVinkjeOpJe => 'Krijg een blauw vinkje op je profiel';
  @override
  String get kunJeMeMeerInfoGeven => 'Kun je me meer info geven over de opties?';
  @override
  String get kunnenWeEenNieuweAfspraakInplannen => 'Kunnen we een nieuwe afspraak inplannen?';
  @override
  String get kvkIsVerplicht => 'KVK is verplicht';
  @override
  String get laatZienWieJeBent => 'Laat zien wie je bent';
  @override
  String get laatsteSessieMeerDan7Dagen => 'Laatste sessie meer dan 7 dagen geleden';
  @override
  String get landIsVerplicht => 'Land is verplicht';
  @override
  String get lesGaatNietDoor => 'Les gaat niet door';
  @override
  String get lieverNietKanHetOpDe => 'Liever niet, kan het op de huidige tijd?';
  @override
  String get liflexibelInTeDelenliul => '<li>Flexibel in te delen</li></ul>';
  @override
  String get linkGekopieerdNaarKlembord => 'Link gekopieerd naar klembord';
  @override
  String get linkInMeldingIsOngeldig => 'Link in melding is ongeldig.';
  @override
  String get livoordeelVoorJouli => '<li>[Voordeel voor jou]</li>';
  @override
  String get loadingscreenBiometricAuthGelukt => '[LoadingScreen] Biometric auth gelukt ✓';
  @override
  String get loadingscreenBiometricAuthMisluktLoginScherm => '[LoadingScreen] Biometric auth mislukt → login scherm';
  @override
  String get locatieDuotrainingEnAanbiedingen => 'Locatie, duo-training en aanbiedingen';
  @override
  String get logoKleurOpJeProfiel => 'Logo & kleur op je profiel';
  @override
  String get maakJeEersteGroepslesAanEn => 'Maak je eerste groepsles aan en laat meerdere klanten tegelijk boeken.';
  @override
  String get maakJeProfielHerkenbaar => 'Maak je profiel herkenbaar';
  @override
  String get maakKortingscodesEnVolgGebruik => 'Maak kortingscodes en volg gebruik';
  @override
  String get maakPromotiesVoorKlanten => 'Maak promoties voor klanten.';
  @override
  String get maxActieveKlanten => 'Max actieve klanten';
  @override
  String get meestGekozenDoorStartendeTrainers => 'Meest gekozen door startende trainers';
  @override
  String get meldJeAanViaMijnPersoonlijke => 'Meld je aan via mijn persoonlijke link en ';
  @override
  String get meldingslinkKanNietWordenGeopendOnbekend => 'Meldingslink kan niet worden geopend (onbekend domein of ongeldige URL).';
  @override
  String get meldingslinkKanNietWordenGeopendOnbekend2 => 'Meldingslink kan niet worden geopend (onbekend domein).';
  @override
  String get mijnSessies => 'Mijn sessies';
  @override
  String get mijnTrainer => 'Mijn trainer';
  @override
  String get mochtJeOoitEenProbleemHebben => 'Mocht je ooit een probleem hebben met een boeking, ';
  @override
  String get mollieConnectKanNuNietGestart => 'Mollie Connect kan nu niet gestart worden.';
  @override
  String get mooiVolgendeKeerGaanWeEen => 'Mooi! Volgende keer gaan we een stapje verder.';
  @override
  String get n100Punten1GratisSessie => '100 punten → 1 gratis sessie';
  @override
  String get n48Uur2DagenVanTevoren => '48 uur (2 dagen) van tevoren';
  @override
  String get n72Uur3DagenVanTevoren => '72 uur (3 dagen) van tevoren';
  @override
  String get naEenSessieKunJeHier => 'Na een sessie kun je hier je factuur bekijken en downloaden. Boekingen en facturen verschijnen automatisch.';
  @override
  String get neemVoldoendeRustJeLichaamHeeft => 'Neem voldoende rust, je lichaam heeft het nodig na zo\\'n sessie.';
  @override
  String get nepProfiel => 'Nep profiel';
  @override
  String get nietDoorgaan => 'niet doorgaan';
  @override
  String get nieuwSupportverzoekAangemaakt => 'Nieuw supportverzoek aangemaakt.';
  @override
  String get nieuwTrainingsschemaBeschikbaar => 'Nieuw trainingsschema beschikbaar! 📅';
  @override
  String get nieuwTrainingsschemaBeschikbaar2 => 'Nieuw trainingsschema beschikbaar!';
  @override
  String get nieuweBoekingenVerschijnenAutomatischZodraEen => 'Nieuwe boekingen verschijnen automatisch zodra een klant boekt.';
  @override
  String get nieuweChatsVanKlantenVerschijnenHier => 'Nieuwe chats van klanten verschijnen hier zodra er een bericht binnenkomt.';
  @override
  String get nieuweKlanten => 'Nieuwe klanten';
  @override
  String get nieuweKlantenKrijgenKorting => 'Nieuwe klanten krijgen korting';
  @override
  String get nieuweSessieentry => 'Nieuwe sessie-entry';
  @override
  String get nieuwensessie => 'Nieuwe\nsessie';
  @override
  String get nieuwsbriefNaarKlantenSturen => 'Nieuwsbrief naar klanten sturen';
  @override
  String get nodigVriendenUitVoorGymiesEn => 'Nodig vrienden uit voor GYMIES en ontvang ';
  @override
  String get nogGeenAccount => 'Nog geen account? ';
  @override
  String get nogGeenAfgerondeSessies => 'Nog geen afgeronde sessies';
  @override
  String get nogGeenBeschikbaarheidIngesteld => 'Nog geen beschikbaarheid ingesteld';
  @override
  String get nogGeenBetaalbewijzen => 'Nog geen betaalbewijzen';
  @override
  String get nogGeenBioIngesteld => 'Nog geen bio ingesteld';
  @override
  String get nogGeenDoelenIngesteld => 'Nog geen doelen ingesteld.';
  @override
  String get nogGeenDossier => 'Nog geen dossier';
  @override
  String get nogGeenFacturen => 'Nog geen facturen';
  @override
  String get nogGeenGesprekken => 'Nog geen gesprekken';
  @override
  String get nogGeenGroepslessen => 'Nog geen groepslessen';
  @override
  String get nogGeenHuiswerkGeregistreerd => 'Nog geen huiswerk geregistreerd.';
  @override
  String get nogGeenInterneNotities => 'Nog geen interne notities.';
  @override
  String get nogGeenKomendeSessies => 'Nog geen komende sessies';
  @override
  String get nogGeenNieuwsbrieven => 'Nog geen nieuwsbrieven';
  @override
  String get nogGeenPakketten => 'Nog geen pakketten';
  @override
  String get nogGeenPromotiecodes => 'Nog geen promotiecodes';
  @override
  String get nogGeenSessies => 'Nog geen sessies';
  @override
  String get nogGeenTariefIngesteld => 'Nog geen tarief ingesteld';
  @override
  String get nogGeenVisibilityPolicy => 'Nog geen visibility policy.';
  @override
  String get nogGeenVoltooideSessies => 'Nog geen voltooide sessies';
  @override
  String get nogNietGeconfigureerd => 'Nog niet geconfigureerd';
  @override
  String get nogNietGeverifieerd => 'Nog niet geverifieerd';
  @override
  String get ofInJeSportschool => 'of in je sportschool.';
  @override
  String get omzetDezeMaand => 'Omzet deze maand';
  @override
  String get onbeperkteBoekingen => 'Onbeperkte boekingen';
  @override
  String get onderwerpMagNietLangerZijnDan => 'Onderwerp mag niet langer zijn dan 200 tekens';
  @override
  String get ontvangEenExportVanAlleData => 'Ontvang een export van alle data';
  @override
  String get opDeHoogteVanNieuweLessen => 'op de hoogte van nieuwe lessen, aanbiedingen en tips.';
  @override
  String get openMijnSessies => 'Open mijn sessies';
  @override
  String get opgelostInHetVoordeelVanDe => 'Opgelost in het voordeel van de klant';
  @override
  String get opgelostInHetVoordeelVanDe2 => 'Opgelost in het voordeel van de trainer';
  @override
  String get opgelostMetEenCompromisSplit => 'Opgelost met een compromis (split)';
  @override
  String get opnieuwUploaden => 'Opnieuw uploaden';
  @override
  String get opnieuwVersturen => 'Opnieuw versturen';
  @override
  String get opslaan2 => 'Opslaan...';
  @override
  String get opslaan3 => 'Opslaan…';
  @override
  String get opslaanGeluktMaarControleerVerplichteVelden => 'Opslaan gelukt, maar controleer verplichte velden opnieuw.';
  @override
  String get overboekingenCash => 'Overboekingen & cash';
  @override
  String get pakketVerwijderd => 'Pakket verwijderd';
  @override
  String get pakketidOntbreektVernieuwDeLijstEn => 'Pakket-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.';
  @override
  String get pasAanWelkeFeaturesBijStarter => 'Pas aan welke features bij Starter, Pro, Pro+ of Studio horen. ';
  @override
  String get pasDeResolutieAan => 'pas de resolutie aan.';
  @override
  String get pasJeBookingWidgetAanEn => 'Pas je booking widget aan en deel je profiel met een QR-code.';
  @override
  String get pasJeZoektermOfFilterAan => 'Pas je zoekterm of filter aan.';
  @override
  String get paspoortIdkaartOfRijbewijsGeldigWe => 'Paspoort, ID-kaart of rijbewijs (geldig). We verwerken dit volgens de AVG.';
  @override
  String get paspoortRijbewijsOfIdkaart => 'Paspoort, rijbewijs of ID-kaart';
  @override
  String get pbdatumbDatumEnTijdbr => '<p><b>Datum:</b> [datum en tijd]<br>';
  @override
  String get pbenJeKlaarLatenWeAan => '<p>Ben je klaar? Laten we aan de slag gaan!</p>';
  @override
  String get pbhoePasJeDitToebbrpraktischeStappenp => '<p><b>Hoe pas je dit toe?</b><br>[Praktische stappen]</p>';
  @override
  String get pbwaaromIsDitBelangrijkbbruitlegVanHet => '<p><b>Waarom is dit belangrijk?</b><br>[Uitleg van het voordeel]</p>';
  @override
  String get pbwatTeVerwachtenbp => '<p><b>Wat te verwachten:</b></p>';
  @override
  String get pdezeVeranderingenHelpenOnsOmJe => '<p>Deze veranderingen helpen ons om je beter van dienst te zijn. ';
  @override
  String get pdezeWeekDelenWeEenWaardevolle => '<p>Deze week delen we een waardevolle fitnesstip met je:</p>';
  @override
  String get perTrainerEenCustomFee => 'Per trainer een custom fee';
  @override
  String get percentageMagNietHogerZijnDan => 'Percentage mag niet hoger zijn dan 100%';
  @override
  String get personalTrainerAmsterdam => 'Personal trainer Amsterdam';
  @override
  String get pgroetenbrjeTrainerp => '<p>Groeten,<br>Je trainer</p>';
  @override
  String get pittigMaarGoedVoelHetNog => 'Pittig maar goed! Voel het nog 😅';
  @override
  String get pjeNieuweTrainingsschemaIsNuBeschikbaar => '<p>Je nieuwe trainingsschema is nu beschikbaar in de app. ';
  @override
  String get plakDezeCodeOpJeWebsite => 'Plak deze code op je website om klanten ';
  @override
  String get planEenSessieOpHetMoment => 'Plan een sessie op het moment dat jou uitkomt';
  @override
  String get planEnBeheerGroepssessies => 'Plan en beheer groepssessies';
  @override
  String get plekGereserveerdJeOntvangtBerichtAls => 'Plek gereserveerd! Je ontvangt bericht als de les doorgaat.';
  @override
  String get pnietGemistDitAanbodIsExclusief => '<p>Niet gemist! Dit aanbod is exclusief voor onze vaste klanten.</p>';
  @override
  String get postcodeIsVerplicht => 'Postcode is verplicht';
  @override
  String get prijsHoogNaarLaag => 'Prijs: hoog naar laag';
  @override
  String get prijsLaagNaarHoog => 'Prijs: laag naar hoog';
  @override
  String get prijsPerSessie => 'Prijs per sessie';
  @override
  String get primaDatIsGoed => 'Prima, dat is goed!';
  @override
  String get prioriteitInZoekresultaten => 'Prioriteit in zoekresultaten';
  @override
  String get probeerEenAndereCategorie => 'Probeer een andere categorie.';
  @override
  String get probeerGymiesMijnTip => 'Probeer GYMIES — mijn tip!';
  @override
  String get profielBewerken => 'Profiel bewerken';
  @override
  String get profielBranding => 'Profiel branding';
  @override
  String get profielQrcode => 'Profiel QR-code';
  @override
  String get profielUrl => 'Profiel URL';
  @override
  String get promocodeVerwijderd => 'Promocode verwijderd';
  @override
  String get promocodeidOntbreektVernieuwDeLijstEn => 'Promocode-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.';
  @override
  String get promocodesAanmaken => 'Promo-codes aanmaken';
  @override
  String get promotieEnKlantwerving => 'Promotie en klantwerving';
  @override
  String get psnelAanmeldenBeperktAantalPlaatsenBeschikbaarp => '<p>Snel aanmelden! Beperkt aantal plaatsen beschikbaar.</p>';
  @override
  String get pvragenLaatHetWetenJeTrainer => '<p>Vragen? Laat het weten! Je trainer is altijd beschikbaar.</p>';
  @override
  String get pweHebbenEenSpecialeAanbiedingVoor => '<p>We hebben een speciale aanbieding voor jou! ';
  @override
  String get pweKijkenErnaarUitJeBinnenkort => '<p>We kijken ernaar uit je binnenkort weer te zien!</p>';
  @override
  String get pweOrganiserenEenSpeciaalEventEn => '<p>We organiseren een speciaal event en je bent van harte uitgenodigd!</p>';
  @override
  String get pweWillenJeGraagInformerenDat => '<p>We willen je graag informeren dat onze studio gesloten is ';
  @override
  String get pweWillenJeGraagOpDe => '<p>We willen je graag op de hoogte stellen van de volgende updates:</p>';
  @override
  String get pwijZijnDanNietBeschikbaarVoor => '<p>Wij zijn dan niet beschikbaar voor sessies, maar je kunt ';
  @override
  String get qrcodeVoorJeProfiel => 'QR-code voor je profiel';
  @override
  String get reageertNaHetVerwachteEindeVan => 'reageert na het verwachte einde van de sessie.';
  @override
  String get reminder24UurVooraf => 'Reminder 24 uur vooraf';
  @override
  String get reminder2UurVooraf => 'Reminder 2 uur vooraf';
  @override
  String get reminderSessie => 'Reminder sessie';
  @override
  String get reviewFactuur => 'Review factuur';
  @override
  String get sNietBeschikbaar => 's niet beschikbaar';
  @override
  String get sOpJeProfiel => 's op je profiel';
  @override
  String get sToeVoorJeStoryEn => 's toe voor je Story en de Media Gallery. Video\\'s max. 30 sec. Klanten zien dit op je openbare profiel.';
  @override
  String get schakelInVoorAutomatischeHerinneringen => 'Schakel in voor automatische herinneringen';
  @override
  String get schrijfEnVerstuurJeEersteNieuwsbrief => 'Schrijf en verstuur je eerste nieuwsbrief via het tabblad "Nieuw"';
  @override
  String get schrijfJeBerichtHier => 'Schrijf je bericht hier. ';
  @override
  String get schrijfJeNieuwsbrief => 'Schrijf je nieuwsbrief...';
  @override
  String get segmenteerJeKlantenEnStuurBulk => 'Segmenteer je klanten en stuur bulk berichten.';
  @override
  String get segoeUi => 'Segoe UI';
  @override
  String get selecteerEenDatumEnTijd => 'Selecteer een datum en tijd';
  @override
  String get seoinstellingen => 'SEO-instellingen';
  @override
  String get sessie2 => ' /sessie';
  @override
  String get sessie3 => 'sessie';
  @override
  String get sessieEindeBereikt => 'Sessie einde bereikt';
  @override
  String get sessieInDeAfgelopen60Dagen => '(sessie in de afgelopen 60 dagen). Maximaal 2 per week.';
  @override
  String get sessieTegoed => 'Sessie tegoed';
  @override
  String get sessieToegevoegdAanJeAgenda => 'Sessie toegevoegd aan je agenda';
  @override
  String get sessieVerplaatst => 'Sessie verplaatst';
  @override
  String get sessieVoltooid => 'Sessie voltooid';
  @override
  String get sessiebeheer => 'Sessiebeheer';
  @override
  String get sessieentry => 'Sessie-entry';
  @override
  String get sessieinkomsten => 'Sessie-inkomsten';
  @override
  String get sessies => 'sessies';
  @override
  String get snellereReactieVanOnsTeam => 'Snellere reactie van ons team';
  @override
  String get spamOfMisleiding => 'Spam of misleiding';
  @override
  String get stadIsVerplicht => 'Stad is verplicht';
  @override
  String get standbyActiefJeKrijgtEenMelding => 'Standby actief – je krijgt een melding bij vrije plek';
  @override
  String get standbyPlekBeschikbaar => 'Standby plek beschikbaar';
  @override
  String get standbySessieGeboekt => 'Standby sessie geboekt';
  @override
  String get standbyaanmeldingMisluktProbeerOpnieuw => 'Standby-aanmelding mislukt. Probeer opnieuw.';
  @override
  String get startBetaling => 'Start betaling';
  @override
  String get startJeBusiness => 'Start je business';
  @override
  String get statusGewijzigd => 'Status gewijzigd';
  @override
  String get stelJezelfVoorAanKlanten => 'Stel jezelf voor aan klanten';
  @override
  String get stuurEenBerichtOmHetGesprek => 'Stuur een bericht om het gesprek te starten.';
  @override
  String get stuurEenNieuwsbriefNaarAlJe => 'Stuur een nieuwsbrief naar al je actieve klanten ';
  @override
  String get stuurJeEersteNieuwsbriefNaarAl => 'Stuur je eerste nieuwsbrief naar al je klanten. Deel tips, aanbiedingen of updates.';
  @override
  String get stuurJePersoonlijkeLinkNaarVrienden => 'Stuur je persoonlijke link naar vrienden via WhatsApp, e-mail of deel de QR-code.';
  @override
  String get stuurNieuwsbrievenNaarAlJeKlanten => 'Stuur nieuwsbrieven naar al je klanten tegelijk. Houd ze ';
  @override
  String get stuurNieuwsbrievenNaarJeKlantenMet => 'Stuur nieuwsbrieven naar je klanten met templates en analytics.';
  @override
  String get supportverzoek => 'Supportverzoek';
  @override
  String get tarievenBetaling => 'Tarieven & betaling';
  @override
  String get tegelijkBoekenVerhoogJeOmzetPer => 'tegelijk boeken. Verhoog je omzet per uur met groepstraining.';
  @override
  String get ticketIsAfgerond => 'Ticket is afgerond';
  @override
  String get tijdslotVerwijderd => 'Tijdslot verwijderd';
  @override
  String get titelEnBeschrijvingVoorZoekmachines => 'Titel en beschrijving voor zoekmachines';
  @override
  String get toonEenYoutubeOfVimeoVideo => 'Toon een YouTube of Vimeo video op je profiel';
  @override
  String get toonJeSocialsOpJeProfiel => 'Toon je socials op je profiel';
  @override
  String get totDeVolgendeSessie => 'Tot de volgende sessie!';
  @override
  String get trainMetMijMee => 'Train met mij mee!';
  @override
  String get trainMinstens3xPerWeekVoor => 'Train minstens 3x per week voor optimaal resultaat. Plan je eerste sessie van de week!';
  @override
  String get trainer2 => 'trainer';
  @override
  String get trainerBetaalt => 'Trainer betaalt';
  @override
  String get trainerNietGevonden => 'Trainer niet gevonden';
  @override
  String get trainerOnboarding => 'Trainer Onboarding';
  @override
  String get trainerOverride => 'Trainer override';
  @override
  String get trainerOverrides => 'Trainer overrides';
  @override
  String get trainerTrainerslugOfTraineridVereist => 'trainer, trainerSlug of trainerId vereist';
  @override
  String get traineraddressline1 => 'trainer_address_line1';
  @override
  String get trainerapprovedat => 'trainer_approved_at';
  @override
  String get traineravatar => 'trainer_avatar';
  @override
  String get traineravatar2 => 'trainerAvatar';
  @override
  String get trainerchat => 'TrainerChat';
  @override
  String get trainerchatWebsocketVerbindingGesloten => '[TrainerChat] WebSocket verbinding gesloten';
  @override
  String get trainerchatWebsocketVerbonden => '[TrainerChat] WebSocket verbonden';
  @override
  String get trainercheckin => 'trainer_check_in';
  @override
  String get trainercity => 'trainer_city';
  @override
  String get trainercountry => 'trainer_country';
  @override
  String get trainerdashboard => 'TrainerDashboard';
  @override
  String get trainerdashboardGeenSetauthtokenAuthtokenIsLeeg => '[TrainerDashboard] GEEN setAuthToken – auth.token is leeg of null';
  @override
  String get trainerdashboardGetTrainersummary => '[TrainerDashboard] GET trainer/summary...';
  @override
  String get trainerdashboardGettrainersummaryOk => '[TrainerDashboard] getTrainerSummary OK';
  @override
  String get trainerid => 'trainer_id';
  @override
  String get traineridOntbreekt2 => 'Trainer-ID ontbreekt.';
  @override
  String get trainerincomeFallbackLeegOverzicht => '[TrainerIncome] Fallback: leeg overzicht';
  @override
  String get trainerinvoicenumber => 'trainer_invoice_number';
  @override
  String get trainername => 'trainer_name';
  @override
  String get trainername2 => 'trainerName';
  @override
  String get trainernoshow => 'trainer_no_show';
  @override
  String get trainerpostcode => 'trainer_postcode';
  @override
  String get trainerprofileFallbackProfielGebruiktNaFout => '[TrainerProfile] Fallback profiel gebruikt na fout';
  @override
  String get trainerprofileFallbackProfielGebruiktVanuitAuthservice => '[TrainerProfile] Fallback profiel gebruikt vanuit AuthService';
  @override
  String get trainerprofileProfielLaden => '[TrainerProfile] Profiel laden...';
  @override
  String get trainers2 => 'trainers';
  @override
  String get trainerscan => 'trainer_scan';
  @override
  String get trainertextcontains => ') || trainerText.contains(';
  @override
  String get traineruserid => 'trainer_user_id';
  @override
  String get traineruserid2 => 'trainerUserId';
  @override
  String get trainerverifiedat => 'trainer_verified_at';
  @override
  String get trainingVoor2PersonenTegelijk => 'Training voor 2 personen tegelijk';
  @override
  String get trainingsabonnementenAanbieden => 'Trainingsabonnementen aanbieden';
  @override
  String get transactiesVerschijnenNaBevestigdeEnAfgeronde => 'Transacties verschijnen na bevestigde en afgeronde sessies.';
  @override
  String get transactiesVerschijnenNaBevestigdeSessies => 'Transacties verschijnen na bevestigde sessies.';
  @override
  String get ulliaangepastAanJouwDoelenli => '<ul><li>Aangepast aan jouw doelen</li>';
  @override
  String get ullibbeschrijvingVanAanbiedingbli => '<ul><li><b>[Beschrijving van aanbieding]</b></li>';
  @override
  String get uploadJeFitnesscertificeringOfDiploma => 'Upload je fitness-certificering of diploma';
  @override
  String get uploadJeFitnesscertificeringOfDiploma2 => 'Upload je fitness-certificering of diploma.';
  @override
  String get uploadJeKamerVanKoophandelUittreksel => 'Upload je Kamer van Koophandel uittreksel (PDF of afbeelding).';
  @override
  String get uploadJeRecenteKvkuittrekselMax6 => 'Upload je recente KvK-uittreksel (max 6 maanden oud)';
  @override
  String get uploadMislukt => 'Upload mislukt';
  @override
  String get vanBdatumbTotBdatumbVanwegeVakantiep => 'van <b>[datum]</b> tot <b>[datum]</b> vanwege vakantie.</p>';
  @override
  String get veiligheidssessieActief => 'Veiligheidssessie actief';
  @override
  String get verbeterJeVindbaarheid => 'Verbeter je vindbaarheid';
  @override
  String get vergeetJeSessieNietVandaagTot => 'Vergeet je sessie niet vandaag! Tot zo.';
  @override
  String get verifiedTrainerBadge => 'Verified trainer badge';
  @override
  String get verklaringOmtrentHetGedrag => 'Verklaring Omtrent het Gedrag';
  @override
  String get verklaringOmtrentHetGedragNietVerplicht => 'Verklaring Omtrent het Gedrag — niet verplicht, wel aanbevolen.';
  @override
  String get verplaatsSessie => 'Verplaats sessie';
  @override
  String get verplaatsingsverzoek => 'Verplaatsingsverzoek';
  @override
  String get versturen2 => 'Versturen...';
  @override
  String get versturenMisluktTikOmOpnieuwTe => 'Versturen mislukt. Tik om opnieuw te proberen.';
  @override
  String get verstuurMaandelijksEenNieuwsbriefOmKlanten => 'Verstuur maandelijks een nieuwsbrief om klanten betrokken te houden';
  @override
  String get verstuurNaarKlant => 'Verstuur naar klant';
  @override
  String get verstuurUpdatesNaarJeKlanten => 'Verstuur updates naar je klanten';
  @override
  String get vertelWieJeBentWatJe => 'Vertel wie je bent, wat je drijft en hoe je klanten helpt...';
  @override
  String get verversBerichten => 'Ververs berichten';
  @override
  String get verwijderPermanentAvgArt17 => 'Verwijder permanent (AVG Art. 17)';
  @override
  String get verzoekAfgewezen => 'Verzoek afgewezen';
  @override
  String get videosOpProfiel => 'Videos op profiel';
  @override
  String get vindDePerfecteTrainerBijJou => 'Vind de perfecte trainer bij jou in de buurt';
  @override
  String get voegEenBlokkeringToeVoorDagen => 'Voeg een blokkering toe voor dagen dat je niet beschikbaar bent, zoals vakantie of ziekte.';
  @override
  String get voegJeSocialMediaLinksToe => 'Voeg je social media links toe zodat klanten je kunnen volgen';
  @override
  String get voegPakkettenToeVoorKlantenOm => 'Voeg pakketten toe voor klanten om te boeken.';
  @override
  String get voegTrainersToeAanJeFavorieten => 'Voeg trainers toe aan je favorieten via hun profiel.';
  @override
  String get volledigGepersonaliseerdProfiel => 'Volledig gepersonaliseerd profiel';
  @override
  String get voorDeSerieuzeTrainer => 'Voor de serieuze trainer';
  @override
  String get voorHetLeverenVanOnzeDiensten => 'voor het leveren van onze diensten. Je hebt te allen tijde ';
  @override
  String get voorkeurenOpgeslagen => 'Voorkeuren opgeslagen';
  @override
  String get vraagDeKlantEenNieuweCode => 'Vraag de klant een nieuwe code op te vragen.';
  @override
  String get vraagDeKlantOmEenNieuwe => 'Vraag de klant om een nieuwe QR-code te genereren in de app.';
  @override
  String get vraagVerificatieAanOmEenBlauw => 'Vraag verificatie aan om een blauw vinkje op je profiel te krijgen. Gymies beoordeelt je aanvraag.';
  @override
  String get vraagVerificatieAanVoorEenBlauw => 'Vraag verificatie aan voor een blauw vinkje.';
  @override
  String get vraagjeHierover => 'Vraagje hierover';
  @override
  String get vriendMeldtZichAan => 'Vriend meldt zich aan';
  @override
  String get vulEenAandachtspuntIn => 'Vul een aandachtspunt in';
  @override
  String get vulEenBerichtIn => 'Vul een bericht in';
  @override
  String get vulEenDienstnaamIn => 'Vul een dienstnaam in';
  @override
  String get vulEenGeldigBedragIn => 'Vul een geldig bedrag in';
  @override
  String get vulEenGeldigBedragInBijv => 'Vul een geldig bedrag in (bijv. 5.00)';
  @override
  String get vulEenGeldigEmailadresIn => 'Vul een geldig e-mailadres in';
  @override
  String get vulEenGeldigPercentageIn1100 => 'Vul een geldig percentage in (1-100)';
  @override
  String get vulEenNaamIn => 'Vul een naam in';
  @override
  String get vulEenPromocodeIn => 'Vul een promocode in';
  @override
  String get vulEenTitelInEnEen => 'Vul een titel in en een capaciteit van minimaal 1.';
  @override
  String get vulEenWachtwoordIn => 'Vul een wachtwoord in';
  @override
  String get vulJeEmailIn => 'Vul je e-mail in';
  @override
  String get vulJeEmailadresIn => 'Vul je e-mailadres in.';
  @override
  String get vulJeWachtwoordIn => 'Vul je wachtwoord in';
  @override
  String get vulMinimaal1PositiefPuntIn => 'Vul minimaal 1 positief punt in';
  @override
  String get wachtOpBetaling => 'Wacht op betaling';
  @override
  String get wachtwoordTeZwakGebruikLettersN => 'Wachtwoord te zwak. Gebruik letters én cijfers.';
  @override
  String get wachtwoordenKomenNietOvereen => 'Wachtwoorden komen niet overeen.';
  @override
  String get wanneerEenKlantEenSessieAanvraagt => 'Wanneer een klant een sessie aanvraagt, zie je het hier direct.';
  @override
  String get wanneerIsDeVolgendeSessie => 'Wanneer is de volgende sessie?';
  @override
  String get watKostEenSessieEnHoe => 'Wat kost een sessie en hoe wordt betaald?';
  @override
  String get watMoet => 'wat moet';
  @override
  String get weKrijgenAllebeiEenBeloningNn => 'we krijgen allebei een beloning 💪\n\n';
  @override
  String get weMissenJePlanJeVolgende => 'We missen je! Plan je volgende sessie via Mijn afspraken in de app.';
  @override
  String get weergavenaamIsVerplicht => 'Weergavenaam is verplicht';
  @override
  String get weetJeZekerDatJeDeze => 'Weet je zeker dat je deze promocode wilt verwijderen? Dit kan niet ongedaan worden.';
  @override
  String get weetJeZekerDatJeDeze2 => 'Weet je zeker dat je deze video wilt verwijderen?';
  @override
  String get weetJeZekerDatJeDit => 'Weet je zeker dat je dit wilt verwijderen?';
  @override
  String get weetJeZekerDatJeEen => 'Weet je zeker dat je een noodalert wilt versturen?\n\n';
  @override
  String get weetJeZekerDatJeEen2 => 'Weet je zeker dat je een noodalert wilt versturen? ';
  @override
  String get weetJeZekerDatJeEen3 => 'Weet je zeker dat je een noodalert wilt versturen?\n\nJe noodcontact en het platform worden direct op de hoogte gesteld.';
  @override
  String get weetJeZekerDatJeJe => 'Weet je zeker dat je je inschrijving wilt annuleren?';
  @override
  String get weetJeZekerDatJeJe2 => 'Weet je zeker dat je je abonnement wilt opzeggen? Je verliest toegang tot de bijbehorende features.';
  @override
  String get weetJeZekerDatJeJe3 => 'Weet je zeker dat je je standby-inschrijving wilt verwijderen? Je verliest je plek op de wachtlijst.';
  @override
  String get weetJeZekerDatJeVan => 'Weet je zeker dat je van abonnement wilt veranderen?';
  @override
  String get weetJeZekerDatJeWilt => 'Weet je zeker dat je wilt downgraden?';
  @override
  String get weetJeZekerDatJeZonder => 'Weet je zeker dat je zonder opslaan wilt sluiten?';
  @override
  String get welkeTijdenHebJeBeschikbaar => 'Welke tijden heb je beschikbaar?';
  @override
  String get wijzigingenNietOpgeslagen => 'Wijzigingen niet opgeslagen';
  @override
  String get wordenHogerGetoondInZoekresultatenEn => 'worden hoger getoond in zoekresultaten en winnen meer vertrouwen bij klanten. ';
  @override
  String get zalIkHetEvenTelefonischUitleggen => 'Zal ik het even telefonisch uitleggen? Dat gaat sneller.';
  @override
  String get zieJeZo => 'zie je zo';
  @override
  String get zieWelkeKlantenDreigenAfTe => 'Zie welke klanten dreigen af te haken en krijg AI-suggesties voor upsells en herboekingen.';
  @override
  String get zipKlaarVoorDownload => 'ZIP klaar voor download';
  @override
  String get zoZienMensenJouInZoekresultaten => 'Zo zien mensen jou in zoekresultaten';
  @override
  String get zodraEenSessieIsGeweestZie => 'Zodra een sessie is geweest zie je hier het overzicht.';
  @override
  String get zodraJeEenTrainerBerichtVerschijnt => 'Zodra je een trainer bericht, verschijnt het gesprek hier.';
  @override
  String get zoekEnBoekTrainers => 'Zoek en boek trainers';
  @override
  String get zoekTrainer => 'Zoek trainer';
  @override
  String get zorgErvoorDatJeKlantenGoed => 'Zorg ervoor dat je klanten goed begrijpen wat je wilt communiceren.';

  // ═══ PHASE 4 — REMAINING STRINGS ═══
  @override
  String get actiefLower => 'actief';
  @override
  String beschikbaarMet(String tier) => 'Beschikbaar met \$tier';
  @override
  String beschikbaarVanaf(String requiredTier) => 'Beschikbaar vanaf \$requiredTier';
  @override
  String betalingGeluktTier(String tier) => 'Betaling gelukt! Je \$tier-abonnement is nu actief.';
  @override
  String betalingStartenVoor(String label) => 'Betaling starten voor \$label';
  @override
  String get bevestigIdentiteitBetaling => 'Bevestig je identiteit om de betaling te voltooien';
  @override
  String get bevestigIdentiteitProfiel => 'Bevestig je identiteit om je profiel te wijzigen';
  @override
  String get bevestigen => 'Bevestigen';
  @override
  String get blokkeringVerwijderen => 'Blokkering verwijderen';
  @override
  String get boekingBevestigd => 'Boeking bevestigd';
  @override
  String boekingNummer(String id) => 'Boeking #\$id';
  @override
  String get dezeFunctieIsNietBeschikbaar => 'Deze functie is momenteel niet beschikbaar. Probeer later opnieuw.';
  @override
  String get dezeMaand => 'Deze maand';
  @override
  String doelBoekingen(String target) => '\$target boekingen!';
  @override
  String get eersteBetaling => 'Eerste betaling!';
  @override
  String get eersteSessie => 'Eerste sessie!';
  @override
  String get facturen => 'Facturen';
  @override
  String factuurVoorSessie(String bookingId, String trainerName) => 'Ik wil graag een factuur voor sessie \$bookingId bij \$trainerName.';
  @override
  String geenGesprekkenGevondenVoor(String query) => 'Geen gesprekken gevonden voor "\$query".';
  @override
  String geenOpenTicketsVan(String roleLabel) => 'Geen open tickets van \$roleLabel';
  @override
  String geenResultatenVoor(String query) => 'Geen resultaten voor "\$query"';
  @override
  String get geenTokenOntvangenVanServer => 'Geen token ontvangen van de server.';
  @override
  String get geenVerbindingControleerInternet => 'Geen verbinding. Controleer je internet en probeer het later opnieuw.';
  @override
  String get geenVerbindingProbeerOpnieuw => 'Geen verbinding. Controleer je internet en probeer opnieuw.';
  @override
  String geenVerplaatsbareSessiesBij(String name) => 'Geen verplaatsbare sessies bij \$name';
  @override
  String geenVerplaatsbareSessiesMet(String name) => 'Geen verplaatsbare sessies met \$name';
  @override
  String get geschilOpgelost => 'Geschil opgelost';
  @override
  String get gisteren => 'Gisteren';
  @override
  String get gisterenLower => 'gisteren';
  @override
  String get goedemorgen => 'Goedemorgen';
  @override
  String get gymiesLiveMeldingen => 'GYMIES live meldingen';
  @override
  String get inactiefLower => 'inactief';
  @override
  String get jaAnnuleren => 'Ja, annuleren';
  @override
  String get jaVerwijderen => 'Ja, verwijderen';
  @override
  String kiesEenBeschikbaarMomentVan(String trainerName) => 'Kies een beschikbaar moment van \$trainerName';
  @override
  String laatsteSessieWasDagenGeleden(String daysSince) => 'Je laatste sessie was \$daysSince dagen geleden. Tijd om weer te starten!';
  @override
  String get mediaVerwijderen => 'Media verwijderen';
  @override
  String mediaVerwijderenCount(String count) => 'Weet je zeker dat je \$count item(s) wilt verwijderen?';
  @override
  String get mijnProfiel => 'MIJN PROFIEL';
  @override
  String get morgenLower => 'morgen';
  @override
  String get neeTochAnnuleren => 'Nee, toch annuleren';
  @override
  String nogSessionsTotMilestone(String remaining, String nextMilestone) => 'Nog \$remaining sessie(s) tot je volgende milestone (\$nextMilestone)!';
  @override
  String onbekendActieType(String type) => 'Onbekend actie-type: \$type';
  @override
  String get onbekendDomein => 'Onbekend domein';
  @override
  String get onbekendeDatum => 'Onbekende datum';
  @override
  String get ongeldigeOfVerlopenSessieLogOpnieuwIn => 'Ongeldige of verlopen sessie. Log opnieuw in.';
  @override
  String get onveiligeVerbindingGeenHttps => 'Onveilige verbinding (geen HTTPS). Betaling geannuleerd.';
  @override
  String perSessie(String price) => '\$price / sessie';
  @override
  String get planSessie => 'Plan sessie';
  @override
  String profielMeldingTrainer(String trainerName) => 'Profiel melding: \$trainerName';
  @override
  String get promotieActief => 'Promotie actief';
  @override
  String get realtimeUpdatesEnBroadcast => 'Realtime updates en broadcast meldingen';
  @override
  String sessieBij(String trainerName) => 'Sessie bij \$trainerName';
  @override
  String get sessieGeannuleerd => 'Sessie geannuleerd';
  @override
  String sessieMet(String name) => 'Gymies sessie – \$name';
  @override
  String get sessieboeking => 'Sessieboeking';
  @override
  String sessiesVoltooid(String count) => '\$count sessies voltooid!';
  @override
  String get standbyVerwijderen => 'Standby verwijderen';
  @override
  String get statusAfgerond => 'Afgerond';
  @override
  String get statusInBehandeling => 'In behandeling';
  @override
  String get statusOnbekend => 'Onbekend';
  @override
  String get tarievenEnBetaling => 'Tarieven & Betaling';
  @override
  String get teBevestigen => 'Te bevestigen';
  @override
  String get terugbetaald => 'Terugbetaald';
  @override
  String get tijdslotVerwijderen => 'Tijdslot verwijderen';
  @override
  String trainerBoekingContext(String trainerName, String bookingId) => 'Trainer: \$trainerName · Boeking \$bookingId';
  @override
  String get typeBetaling => 'Betaling';
  @override
  String get typeGeschil => 'Geschil';
  @override
  String get typeIncident => 'Incident';
  @override
  String get typeOverig => 'Overig';
  @override
  String get uitzonderingToevoegen => 'Uitzondering toevoegen';
  @override
  String get vandaag => 'Vandaag';
  @override
  String get vandaagLower => 'vandaag';

  // ═══ FAQ CONTENT STRINGS ═══
  @override
  String get faqCatBoekingen => 'Boekingen';
  @override
  String get faqCatBoekDesc => 'Wijzigen, annuleren, herschedulen';
  @override
  String get faqCatBetalingen => 'Betalingen';
  @override
  String get faqCatBetalDesc => 'Facturen, terugbetalingen, abonnement';
  @override
  String get faqCatAccount => 'Mijn Account';
  @override
  String get faqCatAccountDesc => 'Profiel, wachtwoord, instellingen';
  @override
  String get faqCatTrainer => 'Mijn Trainer';
  @override
  String get faqCatTrainerDesc => 'Contact, reviews, klachten';
  @override
  String get faqCatVeiligheid => 'Veiligheid';
  @override
  String get faqCatVeiligheidDesc => 'Melden, blokkeren, privacy';
  @override
  String get faqCatTechnisch => 'Technisch';
  @override
  String get faqCatTechnischDesc => 'Bugs, crashes, app problemen';
  @override
  String get faqQWijzigBoeking => 'Hoe wijzig ik mijn boeking?';
  @override
  String get faqAWijzigBoeking => 'Ga naar het tabblad "Sessies" onderaan de app. Tik op de sessie die je wilt wijzigen en kies de gewenste actie in het menu. Je kunt tot 24 uur van tevoren kosteloos wijzigen.';
  @override
  String get faqActionNaarSessies => 'Naar Mijn Sessies';
  @override
  String get faqQAnnuleerSessie => 'Kan ik een sessie annuleren?';
  @override
  String get faqAAnnuleerSessie => 'Ja, annuleren kan tot 12 uur voor de sessie. Ga naar het tabblad "Sessies", tik op de boeking en kies "Annuleren" in het actiemenu. Bij late annulering kunnen kosten in rekening worden gebracht.';
  @override
  String get faqQTrainerAfgezegd => 'Mijn trainer heeft afgezegd, wat nu?';
  @override
  String get faqATrainerAfgezegd => 'Je ontvangt automatisch een volledige terugbetaling. Je kunt direct een nieuwe sessie boeken bij dezelfde trainer of via het tabblad "Ontdekken" een andere trainer zoeken.';
  @override
  String get faqQGroepssessie => 'Hoe boek ik een groepssessie?';
  @override
  String get faqAGroepssessie => 'Ga naar je Profiel → Groepslessen om beschikbare groepssessies te bekijken. Je kunt ook via het trainerprofiel zien welke groepslessen worden aangeboden.';
  @override
  String get faqActionNaarGroepslessen => 'Naar Groepslessen';
  @override
  String get faqQBoekingsgeschiedenis => 'Waar vind ik mijn boekingsgeschiedenis?';
  @override
  String get faqABoekingsgeschiedenis => 'Ga naar het tabblad "Sessies". Onder "Geweest" zie je al je afgelopen sessies. Voor facturen ga je naar Profiel → Facturen.';
  @override
  String get faqQFacturen => 'Waar vind ik mijn facturen?';
  @override
  String get faqAFacturen => 'Ga naar je Profiel (tabblad rechtsonder) → tik op "Facturen" onder "Mijn activiteit". Hier kun je al je facturen bekijken, filteren op status en details opvragen.';
  @override
  String get faqActionNaarFacturen => 'Naar Facturen';
  @override
  String get faqQTerugbetaling => 'Hoe vraag ik een terugbetaling aan?';
  @override
  String get faqATerugbetaling => 'Bij annulering binnen de termijn wordt automatisch terugbetaald via Mollie. Voor andere gevallen kun je een supportverzoek aanmaken met type "Betaling".';
  @override
  String get faqActionSupport => 'Supportverzoek aanmaken';
  @override
  String get faqQBetaalmethoden => 'Welke betaalmethoden worden geaccepteerd?';
  @override
  String get faqABetaalmethoden => 'We accepteren iDEAL, creditcard (Visa/Mastercard), Bancontact en Apple Pay. De betaalmethode kies je bij elke boeking via onze betaalpartner Mollie.';
  @override
  String get faqQBetalingMislukt => 'Mijn betaling is mislukt, wat nu?';
  @override
  String get faqABetalingMislukt => 'Controleer je bankrekening en probeer opnieuw via het tabblad "Sessies". Als het probleem aanhoudt, neem contact op met je bank of probeer een andere betaalmethode bij de volgende boeking.';
  @override
  String get faqQWijzigProfiel => 'Hoe wijzig ik mijn profiel?';
  @override
  String get faqAWijzigProfiel => 'Ga naar Profiel (tabblad rechtsonder) → Instellingen → "Mijn profiel". Hier kun je je naam, telefoonnummer, stad en bio aanpassen.';
  @override
  String get faqActionNaarProfiel => 'Naar Mijn Profiel';
  @override
  String get faqQWachtwoord => 'Hoe verander ik mijn wachtwoord?';
  @override
  String get faqAWachtwoord => 'Ga naar Profiel → Instellingen → "Mijn profiel". Tik onderaan op "Wachtwoord wijzigen". Je hebt je huidige wachtwoord nodig plus een nieuw wachtwoord van minimaal 8 tekens.';
  @override
  String get faqQNietInloggen => 'Ik kan niet inloggen';
  @override
  String get faqANietInloggen => 'Gebruik "Wachtwoord vergeten" op het loginscherm. Je ontvangt een e-mail met een reset-link. Controleer ook je spam-map en of je het juiste e-mailadres gebruikt.';
  @override
  String get faqQMeldingen => 'Waar zie ik mijn meldingen?';
  @override
  String get faqAMeldingen => 'Ga naar Profiel → "Meldingen" onder "Mijn activiteit". Hier vind je al je notificaties over boekingen, berichten en updates.';
  @override
  String get faqActionNaarMeldingen => 'Naar Meldingen';
  @override
  String get faqQDossier => 'Hoe zie ik mijn trainingsdossier?';
  @override
  String get faqADossier => 'Ga naar Profiel → "Mijn dossier" onder "Mijn activiteit". Hier vind je je persoonlijke trainingsdossier met notities van je trainer.';
  @override
  String get faqActionNaarDossier => 'Naar Mijn Dossier';
  @override
  String get faqQUitloggen => 'Hoe log ik uit?';
  @override
  String get faqAUitloggen => 'Ga naar Profiel (tabblad rechtsonder) en scroll naar beneden. Tik op de "Uitloggen" knop onderaan de pagina.';
  @override
  String get faqQTrainerReageertNiet => 'Mijn trainer reageert niet op berichten';
  @override
  String get faqQReview => 'Hoe laat ik een review achter?';
  @override
  String get faqAReview => 'Na elke afgeronde sessie ontvang je een melding om een review achter te laten. Je kunt ook naar het tabblad "Sessies" gaan, een afgelopen sessie openen en daar je review schrijven.';
  @override
  String get faqQKlacht => 'Ik wil een klacht indienen over mijn trainer';
  @override
  String get faqAKlacht => 'Het spijt ons dat je een slechte ervaring hebt gehad. Maak een supportverzoek aan met type "Geschil". Beschrijf de situatie zo duidelijk mogelijk en we behandelen dit met prioriteit.';
  @override
  String get faqActionKlacht => 'Klacht indienen';
  @override
  String get faqQOngepasteGedrag => 'Hoe meld ik ongepast gedrag?';
  @override
  String get faqAOngepasteGedrag => 'Maak een supportverzoek aan met type "Incident" en beschrijf wat er is gebeurd. Vermeld de naam van de trainer en eventueel de sessie-datum. Meldingen worden binnen 24 uur behandeld.';
  @override
  String get faqActionIncident => 'Incident melden';
  @override
  String get faqQGegevensVeilig => 'Worden mijn gegevens veilig bewaard?';
  @override
  String get faqAGegevensVeilig => 'Ja, we voldoen volledig aan de AVG/GDPR. Je data wordt opgeslagen op beveiligde EU-servers. Betalingen worden veilig verwerkt via Mollie, een gecertificeerde betaalprovider.';
  @override
  String get faqQGegevensOpvragen => 'Hoe kan ik mijn gegevens opvragen?';
  @override
  String get faqAGegevensOpvragen => 'Je kunt een verzoek indienen via support met type "Overig". Wij sturen je een overzicht van al je opgeslagen gegevens binnen 30 dagen, conform de AVG.';
  @override
  String get faqActionGegevens => 'Gegevensverzoek indienen';
  @override
  String get faqQCrash => 'De app crasht steeds';
  @override
  String get faqACrash => 'Probeer de app te updaten naar de nieuwste versie in de App Store of Google Play Store. Als het probleem aanhoudt: verwijder de app, herstart je telefoon en installeer de app opnieuw. Je data blijft behouden via je account.';
  @override
  String get faqQWitScherm => 'Ik zie een wit of leeg scherm';
  @override
  String get faqAWitScherm => 'Dit komt meestal door een verouderde app-versie of slecht internet. Update de app en controleer je wifi- of mobiele-dataverbinding. Probeer de app volledig te sluiten en opnieuw te openen.';
  @override
  String get faqQPushNotificaties => 'Push-notificaties werken niet';
  @override
  String get faqAPushNotificaties => 'Controleer je telefooninstellingen → Apps → GYMIES → Notificaties en zorg dat alles is ingeschakeld. Controleer ook in de app bij Profiel → Meldingen of je meldingen ontvangt.';
  @override
  String get faqQQrScanner => 'QR-code scanner werkt niet';
  @override
  String get faqAQrScanner => 'Zorg dat je de camera-toestemming hebt gegeven aan de GYMIES-app. Ga naar je telefooninstellingen → Apps → GYMIES → Rechten → Camera → Toestaan. Herstart daarna de app.';

  // ═══ RESTORED KEYS ═══
  @override
  String get automatischVerstuurdZodraJeWeerOnline => 'Automatisch verstuurd zodra je weer online';
  @override
  String get berichtVerstuurd => 'Bericht verstuurd';
  @override
  String get berichtenWordenAutomatischVerstuurdJeKuntDitAltijdUitschakelen => 'Berichten worden automatisch verstuurd. Je kunt dit altijd uitschakelen';
  @override
  String get bulkBerichtVerstuurd => 'Bulk bericht verstuurd';
  @override
  String get bulkMessageSent => 'Bulk bericht verstuurd';
  @override
  String get checkinInWachtrijGeplaatstWordtOpnieuwVerstuurd => 'Check-in in wachtrij geplaatst, wordt opnieuw verstuurd';
  @override
  String get codeSent => 'Code verstuurd';
  @override
  String get deFactuurIsVerstuurdNaarJe => 'De factuur is verstuurd naar je';
  @override
  String get factuurNietVerstuurd => 'Factuur niet verstuurd';
  @override
  String get factuurNogNietVerstuurd => 'Factuur nog niet verstuurd';
  @override
  String get factuurOpgesteldEnVerstuurdNaarKlant => 'Factuur opgesteld en verstuurd naar klant';
  @override
  String get factuurVerstuurd => 'Factuur verstuurd';
  @override
  String get factuurverzoekVerstuurdNaarTrainer => 'Factuurverzoek verstuurd naar trainer';
  @override
  String get nieuwsbriefVerstuurd => 'Nieuwsbrief verstuurd';
  @override
  String get reactieVerstuurd => 'Reactie verstuurd';
  @override
  String get tegenvoorstelVerstuurd => 'Tegenvorstel verstuurd';

  // ═══ RESTORED KEYS (BATCH 2) ═══
  @override
  String get faqATrainerReageertNiet => 'Trainers reageren meestal binnen 24 uur. Controleer het tabblad "Berichten" of je bericht is verstuurd. Als je na 48 uur nog niets hebt gehoord, maak dan een supportverzoek aan zodat wij contact opnemen met de trainer.';
  @override
  String get feedbackVerstuurd => 'Feedback verstuurd';
  @override
  String get hetBerichtIsVerstuurd => 'Het bericht is verstuurd';
  @override
  String get ifNoResponseEmergencyNotificationSent => 'Als er geen reactie is, wordt een noodmelding verstuurd';
  @override
  String get incidentMeldingVerstuurd => 'Incident melding verstuurd';
  @override
  String get invoiceSentToClient => 'Factuur verstuurd naar klant';
  @override
  String get klantenReserverenEenPlekPasAlsHetMinimumBereiktIsWordtDeBetaallinkVerstuurd => 'Klanten reserveren een plek. Pas als het minimum bereikt is, wordt de betaallink verstuurd';
  @override
  String get laatsteSupportverzoekAlsnogVerstuurd => 'Laatste supportverzoek alsnog verstuurd';
  @override
  String get lastSupportRequestSent => 'Laatste supportverzoek verstuurd';
  @override
  String get linkVerstuurd => 'Link verstuurd';
  @override
  String get meldingenGemarkeerdAlsGelezen => 'Meldingen gemarkeerd als gelezen';
  @override
  String get messageVerstuurd => 'Message Verstuurd';
  @override
  String get messagesAutoSentNote => 'Berichten worden automatisch verstuurd';
  @override
  String get messagesSentAutomatically => 'Berichten worden automatisch verstuurd';
  @override
  String get newCodeSent => 'Nieuwe code verstuurd';
  @override
  String get noshowInWachtrijGeplaatstWordtOpnieuwVerstuurd => 'No-show in wachtrij geplaatst, wordt opnieuw verstuurd';
  @override
  String get prioritySupportSent => 'Prioriteit support verstuurd';
  @override
  String get prioritySupportTicketSent => 'Prioriteit support ticket verstuurd';
  @override
  String get prioritySupportTicketVerstuurd => 'Prioriteit support ticket verstuurd';
  @override
  String get replySubmitted => 'Reactie verstuurd';
  @override
  String get requestNotSent => 'Verzoek niet verstuurd';
  @override
  String get rescheduleRequestSent => 'Verplaatsingsverzoek verstuurd';
  @override
  String get rescheduleRequestSentToClient => 'Verplaatsingsverzoek verstuurd naar klant';
  @override
  String get resetLinkVerstuurd => 'Reset Link Verstuurd';
  @override
  String get reviewVerstuurd => 'Review Verstuurd';
  @override
  String get sessionCancelledStandbyPushSent => 'Sessie geannuleerd, standby push verstuurd';
  @override
  String get sosAlertSent => 'SOS alert verstuurd';
  @override
  String get sosEmergencyContactNotified => 'SOS noodcontact is op de hoogte gebracht';
  @override
  String get sosalertVerstuurdJeNoodcontactIsOpDeHoogte => 'SOS alert verstuurd. Je noodcontact is op de hoogte';
  @override
  String get uitnodigingVerstuurd => 'Uitnodiging Verstuurd';
  @override
  String get upsellProposalSent => 'Upsell voorstel verstuurd';
  @override
  String get upsellVoorstelVerstuurd => 'Upsell voorstel verstuurd';
  @override
  String get verificatieCodeVerstuurd => 'Verificatie Code Verstuurd';
  @override
  String get verificatieaanvraagVerstuurdGymiesBeoordeeltJeProfiel => 'Verificatieaanvraag verstuurd. GYMIES beoordeelt je profiel';
  @override
  String get verplaatsingsverzoekVerstuurd => 'Verplaatsingsverzoek verstuurd';
  @override
  String get verzoekNietVerstuurd => 'Verzoek niet verstuurd';
  @override
  String get verzoekVerstuurd => 'Verzoek Verstuurd';
  @override
  String get waarschuwingVerstuurd => 'Waarschuwing Verstuurd';
  @override
  String get weMissYouMessageSent => 'We-missen-je bericht verstuurd';
  @override
  String get weMissenJeberichtVerstuurd => 'We-missen-je bericht verstuurd';

  // ═══ PHASE 4D — INTERPOLATED STRINGS ═══
  @override
  String get goedGetraindVandaag => 'Goed getraind vandaag. Tot de volgende!';
  @override
  String get mediaVerwijderenTitle => 'Media verwijderen';
  @override
  String get onbekendBedrag => 'Onbekend bedrag';
  @override
  String get toekomst => 'Toekomst';
  @override
  String get toevoegenMax20Tags => 'Toevoegen max 20 tags';
  @override
  String get totMorgen => 'Tot morgen!';
  @override
  String get videoToevoegen => 'Video toevoegen';
  @override
  String get volgendeStapLogin => 'Volgende stap';
  @override
  String get vorigeWeek => 'Vorige week';
  @override
  String vandaagTijd(String time) => 'Vandaag $time';
  @override
  String morgenTijd(String time) => 'Morgen $time';
  @override
  String vandaagTijdFormatted(String hour, String min) => 'Vandaag $hour:$min';
  @override
  String gisterenTijdFormatted(String hour, String min) => 'Gisteren $hour:$min';
  @override
  String voorSessie(String date) => 'Voor sessie: $date';
  @override
  String foutBijOpslaan(String error) => 'Fout bij opslaan: $error';
  @override
  String foutBijOpslaanStatus(String statusCode) => 'Fout bij opslaan ($statusCode)';
  @override
  String opslaanMislukt(String error) => 'Opslaan mislukt: $error';
  @override
  String foutBijLadenStats(String error) => 'Fout bij laden stats: $error';
  @override
  String foutBijLadenOpenstaande(String error) => 'Fout bij laden openstaande: $error';
  @override
  String foutBijLadenGeschiedenis(String error) => 'Fout bij laden geschiedenis: $error';
  @override
  String betalingGemarkeerd(String info) => 'Betaling gemarkeerd als betaald';
  @override
  String snellerInloggenMet(String label) => 'Log sneller in met $label. Je kunt dit later altijd wijzigen in Instellingen.';
  @override
  String sessiesEnRevenue(String sessions, String revenue) => '$sessions sessies · €$revenue';
  @override
  String prijsPerSessie(String price) => '€$price/sessie';

  // ═══ PHASE 4 FIX — MISSING KEYS ═══
  @override
  String get accountVerwijderen => 'Account verwijderen';
  @override
  String get pakketToevoegen => 'Pakket toevoegen';
  @override
  String get pakketVerwijderen => 'Pakket verwijderen';
  @override
  String get promocodeToevoegen => 'Promocode toevoegen';
  @override
  String get promocodeVerwijderenVraag => 'Promocode verwijderen?';
  @override
  String get verstuurd => 'verstuurd';
  @override
  String get videoVerwijderen => 'Video verwijderen';

  // ── PHASE 5: FINAL CLEANUP ──
  @override
  String get fout => 'Fout';
  // PHASE 5B: ONBOARDING FEATURES
  // PHASE 5C: ONBOARDING REMAINING
  @override
  String get kvkUittreksel => 'KvK-uittreksel';
  @override
  String get idVerificatie => 'ID-verificatie';
  @override
  String get certificering => 'Certificering';
  @override
  String get vogOptional => 'VOG (optioneel)';
  @override
  String get volgende => 'Volgende';
  @override
  String get geverifieerdCheck => 'Geverifieerd ✓';
  @override
  String get afgekeurdX => 'Afgekeurd ✗';
  @override
  String get geupload => 'Geüpload';
  @override
  String get documentUploaden => 'Document uploaden';
  @override
  String get vogUploaden => 'VOG uploaden';
  @override
  String get optioneel => 'optioneel';
  @override
  String get alleBasisfeatures => 'Alle basisfeatures';
  @override
  String get planSelecterenOfBetalenMislukt => 'Plan selecteren of betalen mislukt';
  @override
  String redenMsg(String reason) => 'Reden: \$reason';
  @override
  String mollieConnectMisluktCode(String code) => 'Mollie Connect mislukt (\$code).';
  @override
  String get basisAgendaBeheer => 'Basis agenda beheer';
  @override
  String get emailSupport => 'E-mail support';
  @override
  String get strippenkaartenEnPakketten => 'Strippenkaarten & pakketten';
  @override
  String get crmEnMarketingTools => 'CRM & marketing tools';
  @override
  String get prioriteitSupport => 'Prioriteit support';
  @override
  String get eigenUrl => 'Eigen URL';
  @override
  String get verder => 'Verder';
  @override
  String get retryKlaar => 'Retry klaar';
  @override
  String get actiesVerstuurd => 'actie(s) verstuurd';
  @override
  String get retryWachtrij => 'Retry wachtrij';
  @override
  String get perAbonnementsPlan => 'Per abonnements-plan';
  @override
  String get vergoedingen => 'Vergoedingen';
  @override
  String get mijnInschrijvingen => 'Mijn inschrijvingen';
  @override
  String get voltooid => 'Voltooid';
  @override
  String get referraltegoed => 'Referraltegoed';
  @override
  String get wasGoed => 'Was goed';
  @override
  String get goedemorgen => 'Goedemorgen!';
  @override
  String get goedeLes => 'Goede les!';
  @override
  String get bevestigd => 'Bevestigd';
  @override
  String get actie => 'Actie';
  @override
  String get nieuweUpdatesVerschijnenHier => 'Nieuwe updates verschijnen hier.';
  @override
  String get puntenEnTegoed => 'Punten & tegoed';
  @override
  String get bekijkOverzicht => 'Bekijk overzicht';
  @override
  String get mijnDossier => 'Mijn dossier';
  @override
  String get mijnGegevensOpvragen => 'Mijn gegevens opvragen';
  @override
  String get annuleringsoverzicht => 'Annuleringsoverzicht';
  @override
  String get betalingStarten => 'Betaling starten';
  @override
  String get actiepunten => 'Actiepunten';
  @override
  String get wachtwoordVergeten => 'Wachtwoord vergeten';
  @override
  String get mijnBranding => 'Mijn Branding';
  @override
  String get graagGedaan => 'Graag gedaan!';
  @override
  String get goedBezig => 'Goed bezig!';
  @override
  String get ikStaKlaar => 'Ik sta klaar';
  @override
  String get totZoChat => 'Tot zo!';
  @override
  String get totMorgen => 'Tot morgen!';
  @override
  String get exportMislukt => 'Export mislukt';
  @override
  String get bulkBericht => 'Bulk bericht';
  @override
  String get verstuur => 'Verstuur';
  @override
  String get actief => 'Actief';
  @override
  String get inactief => 'Inactief';
  @override
  String get storyUploadMislukt => 'Story upload mislukt';
  @override
  String get nieuweOpzetKlaar => 'Nieuwe opzet klaar';
  @override
  String get ontvangen2 => 'Ontvangen';
  @override
  String get transacties => 'Transacties';
  @override
  String get nieuwBericht => 'Nieuw bericht';
  @override
  String get bulkVersturen => 'Bulk versturen';
  @override
  String get nieuweNieuwsbrief => 'Nieuwe nieuwsbrief';
  @override
  String get actievePromo => 'Actieve promo';
  @override
  String get mijnEtalage => 'Mijn Etalage';
  @override
  String get gymDashboard => 'Gym Dashboard';
  @override
  String get actieVereist => 'Actie vereist';
  @override
  String get mollieGekoppeld => 'Mollie gekoppeld';
  @override
  String get onboarding => 'Onboarding';
  @override
  String get actieveCodes => 'Actieve codes';
  @override
  String get nieuweGroepsles => 'Nieuwe groepsles';
  @override
  String get branding => 'Branding';
  @override
  String get studioEnOnboarding => 'Studio & Onboarding';
  @override
  String get mediaVerwijderen => 'Media verwijderen';
  @override
  String get zoek2 => 'Zoek';
  @override
  String retryKlaarActies(String sent) => 'Retry klaar: \$sent actie(s) verstuurd';
  @override
  String actiesInRetryQueue(String count) => '\$count actie(s) in retry queue';
  @override
  String geenVerplaatsbareSessiesMet(String name) => 'Geen verplaatsbare sessies met \$name';
  @override
  String geenVerplaatsbareSessiesBij(String name) => 'Geen verplaatsbare sessies bij \$name';
  @override
  String goedBezigNaam(String name) => 'Goed bezig \$name! Ga zo door 💪';
  @override
  String betalingStartenMislukt(String error) => 'Betaling starten mislukt: \$error';
  @override
  String konAbonnementNietWijzigen(String error) => 'Kon abonnement niet wijzigen: \$error';
  @override
  String storyUploadMisluktMsg(String error) => 'Story upload mislukt: \$error';
  @override
  String exportMisluktMsg(String error) => 'Export mislukt: \$error';
  @override
  String uploadMisluktMsg(String error) => 'Upload mislukt: \$error';
  @override
  String mollieConnectMislukt(String error) => 'Mollie Connect mislukt: \$error';
  @override
  String foutMsg(String error) => 'Fout: \$error';
  @override
  String opslaanMisluktMsg(String error) => 'Opslaan mislukt: \$error';
  @override
  String foutBijOpslaanMsg(String error) => 'Fout bij opslaan: \$error';
  @override
  String konFotoNietUploaden(String error) => 'Kon foto niet uploaden: \$error';
  @override
  String klantenCount(String count) => 'Klanten: \$count';
  @override
  String beschikbaarVanaf(String tier) => 'Beschikbaar vanaf \$tier';
  @override
  String mediaItemsVerwijderd(String count) => '\$count item(s) verwijderd';
  @override
  String weetJeZekerVerwijderen(String count) => 'Weet je zeker dat je \$count item(s) wilt verwijderen?';
  @override
  String logSnellerInMet(String label) => 'Log sneller in met \$label. Je kunt dit later altijd wijzigen in Instellingen.';
  @override
  String tegoedSuggested(String amount) => 'Tegoed: \$amount';
  @override
  String waaromWilJeMelden(String name) => 'Waarom wil je \$name melden?';

}

/// English (EN) translations.
class _SEn extends SNl {
  _SEn() : super();
  @override String get localeName => 'en';

  // ═══ NAVIGATIE ═══
  @override String get navHome => 'Home';
  @override String get navDiscover => 'Discover';
  @override String get navTraining => 'Training';
  @override String get navInbox => 'Inbox';
  @override String get navMe => 'Me';
  @override String get navSessions => 'Sessions';
  @override String get navClients => 'Clients';
  @override String get navMore => 'More';

  // ═══ BEGROETINGEN ═══
  @override String get greetingNight => 'Good night';
  @override String get greetingMorning => 'Good morning';
  @override String get greetingAfternoon => 'Good afternoon';
  @override String get greetingEvening => 'Good evening';

  // ═══ LOGIN / REGISTRATIE ═══
  @override String get login => 'Log in';
  @override String get register => 'Sign up';
  @override String get logout => 'Log out';
  @override String get logoutConfirmTitle => 'Log out';
  @override String get logoutConfirmMessage => 'Are you sure you want to log out?';
  @override String get tagline => 'Find your personal trainer\nand book instantly';
  @override String get email => 'Email address';
  @override String get password => 'Password';
  @override String get forgotPassword => 'Forgot password?';
  @override String get resetPassword => 'Reset password';
  @override String get name => 'Name';
  @override String get displayName => 'Display name';
  @override String get phone => 'Phone number';
  @override String get verificationCode => 'Verification code';
  @override String get enterCode => 'Enter the code';
  @override String get verifyEmail => 'Verify your email';
  @override String get resendCode => 'Resend code';
  @override String get codeSent => 'Code sent';
  @override String get invalidCode => 'Invalid code';
  @override String get accountCreated => 'Account created';
  @override String get welcomeToGymies => 'Welcome to Gymies!';
  @override String get loginFailed => 'Login failed';
  @override String get registerFailed => 'Registration failed';
  @override String get emailRequired => 'Email address is required';
  @override String get passwordRequired => 'Password is required';
  @override String get nameRequired => 'Name is required';
  @override String get invalidEmail => 'Invalid email address';
  @override String get passwordTooShort => 'Password must be at least 8 characters';

  // ═══ ALGEMEEN ═══
  @override String get save => 'Save';
  @override String get cancel => 'Cancel';
  @override String get delete => 'Delete';
  @override String get edit => 'Edit';
  @override String get confirm => 'Confirm';
  @override String get back => 'Back';
  @override String get next => 'Next';
  @override String get done => 'Done';
  @override String get close => 'Close';
  @override String get search => 'Search';
  @override String get filter => 'Filter';
  @override String get sort => 'Sort';
  @override String get refresh => 'Refresh';
  @override String get retry => 'Try again';
  @override String get loading => 'Loading...';
  @override String get noResults => 'No results';
  @override String get viewAll => 'View all';
  @override String get viewMore => 'View more';
  @override String get showLess => 'Show less';
  @override String get yes => 'Yes';
  @override String get no => 'No';
  @override String get ok => 'OK';
  @override String get send => 'Send';
  @override String get share => 'Share';
  @override String get copy => 'Copy';
  @override String get copied => 'Copied';
  @override String get today => 'Today';
  @override String get tomorrow => 'Tomorrow';
  @override String get yesterday => 'Yesterday';
  @override String get thisWeek => 'This week';
  @override String get thisMonth => 'This month';
  @override String get all => 'All';
  @override String get active => 'Active';
  @override String get inactive => 'Inactive';
  @override String get pending => 'Pending';
  @override String get confirmed => 'Confirmed';
  @override String get cancelled => 'Cancelled';
  @override String get completed => 'Completed';
  @override String get expired => 'Expired';
  @override String get newLabel => 'New';
  @override String get optional => 'Optional';
  @override String get required => 'Required';
  @override String get unknown => 'Unknown';
  @override String get none => 'None';
  @override String get other => 'Other';
  @override String get total => 'Total';
  @override String get free => 'Free';
  @override String get per => 'per';
  @override String get minutes => 'minutes';
  @override String get hours => 'hours';
  @override String get days => 'days';
  @override String get weeks => 'weeks';
  @override String get months => 'months';
  @override String get min => 'min';
  @override String get hour => 'hour';
  @override String get day => 'day';
  @override String get week => 'week';
  @override String get month => 'month';

  // ═══ INSTELLINGEN ═══
  @override String get settings => 'Settings';
  @override String get myProfile => 'My profile';
  @override String get myProfileSubtitle => 'Name, email, emergency contact';
  @override String get invoices => 'Invoices';
  @override String get invoicesSubtitle => 'View and download';
  @override String get security => 'SECURITY';
  @override String get biometricEnabled => 'Enabled — log in quickly';
  @override String get biometricDisabled => 'Enable for quick access';
  @override String biometricConfirmEnable(String label) => 'Confirm $label to enable it';
  @override String biometricConfirmDisable(String label) => 'Confirm $label to disable it';
  @override String get account => 'ACCOUNT';
  @override String get help => 'HELP';
  @override String get support => 'Support';
  @override String get supportSubtitle => 'FAQ and contact form';
  @override String get tools => 'TOOLS';
  @override String get preferences => 'PREFERENCES';
  @override String get subscription => 'Subscription';
  @override String get documents => 'Documents';
  @override String get verification => 'Verification';
  @override String get promoCodes => 'Promo codes';
  @override String get actionHistory => 'Action history';
  @override String get agendaSync => 'Calendar sync';
  @override String get agendaSyncSubtitle => 'Automatically add new bookings to your calendar';
  @override String get privacySafety => 'PRIVACY & SAFETY';
  @override String get privacyData => 'Privacy & data';
  @override String get privacyText => 'GYMIES processes your personal data in accordance with GDPR. Your data is not shared with third parties and is exclusively used to deliver our services. You have the right to access, correct, or delete your data at any time.';
  @override String get requestMyData => 'Request my data';
  @override String get requestMyDataSubtitle => 'Receive an export of all data we have about you';
  @override String get dataExportRequested => 'Data export requested — you will receive an email';
  @override String get deleteAccount => 'Delete account';
  @override String get deleteAccountSubtitle => 'Permanently delete your account and all your data (GDPR Art. 17)';
  @override String get deleteAccountWarning => 'This will permanently delete your account and all associated data. This action cannot be undone.';
  @override String get deleteAccountRequested => 'Account deletion request submitted';
  @override String get language => 'Language';
  @override String get languageSubtitle => 'Choose your preferred language';
  @override String get dutch => 'Nederlands';
  @override String get english => 'English';

  // ═══ SESSIES / BOEKINGEN ═══
  @override String get sessions => 'Sessions';
  @override String get session => 'Session';
  @override String get booking => 'Booking';
  @override String get bookings => 'Bookings';
  @override String get bookSession => 'Book session';
  @override String get bookNow => 'Book now';
  @override String get upcomingSessions => 'Upcoming sessions';
  @override String get pastSessions => 'Past sessions';
  @override String get noUpcomingSessions => 'No upcoming sessions';
  @override String get noPastSessions => 'No past sessions';
  @override String get sessionConfirmed => 'Session confirmed';
  @override String get sessionCancelled => 'Session cancelled';
  @override String get sessionCompleted => 'Session completed';
  @override String get cancelSession => 'Cancel session';
  @override String get cancelSessionConfirm => 'Are you sure you want to cancel this session?';
  @override String get rejectSession => 'Reject session';
  @override String get rejectSessionConfirm => 'Are you sure you want to reject this request?';
  @override String get reject => 'Reject';
  @override String get sessionRejected => 'Session rejected';
  @override String get yesCancelSession => 'Yes, cancel';
  @override String get sendStandbyPush => 'Send standby push immediately';
  @override String get standbyPushSubtitle => 'Interested clients will receive a booking opportunity right away.';
  @override String get couldNotLoadSessions => 'Could not load sessions.';
  @override String get couldNotLoadData => 'Could not load data. Please try again.';
  @override String get nextSession => 'Next session';
  @override String get nextSessionIn => 'Next session in';
  @override String get duration => 'Duration';
  @override String durationMinutes(int count) => '$count minutes';
  @override String get date => 'Date';
  @override String get time => 'Time';
  @override String get location => 'Location';
  @override String get online => 'Online';
  @override String get atClient => 'At the client';
  @override String get atTrainer => 'At the trainer';
  @override String get outdoor => 'Outdoor';
  @override String get gym => 'Gym';
  @override String get groupSession => 'Group session';
  @override String get groupSessions => 'Group sessions';
  @override String get privateSession => 'Private session';
  @override String get buddySession => 'Buddy session';
  @override String get trialSession => 'Trial session';
  @override String get recurringSession => 'Recurring session';

  // ═══ TRAINER ═══
  @override String get trainer => 'Trainer';
  @override String get trainers => 'Trainers';
  @override String get myTrainers => 'My trainers';
  @override String get findTrainer => 'Find trainer';
  @override String get trainerProfile => 'Trainer profile';
  @override String get about => 'About';
  @override String get reviews => 'Reviews';
  @override String get review => 'Review';
  @override String get rating => 'Rating';
  @override String get prices => 'Prices';
  @override String get availability => 'Availability';
  @override String get specializations => 'Specializations';
  @override String get experience => 'Experience';
  @override String get certificates => 'Certificates';
  @override String get km => 'km';
  @override String distanceAway(String distance) => '$distance km away';
  @override String get verified => 'Verified';
  @override String get topTrainer => 'Top trainer';
  @override String get proTrainer => 'Pro trainer';
  @override String get proPlus => 'Pro+';

  // ═══ KLANTEN ═══
  @override String get clients => 'Clients';
  @override String get client => 'Client';
  @override String get myClients => 'My clients';
  @override String get activeClients => 'Active clients';
  @override String get newClient => 'New client';
  @override String get clientProfile => 'Client profile';
  @override String get clientDossier => 'Client dossier';
  @override String get couldNotLoadClients => 'Could not load clients.';
  @override String get noClients => 'No clients yet';
  @override String get addClient => 'Add client';
  @override String get emergencyContact => 'Emergency contact';

  // ═══ BETALINGEN ═══
  @override String get payment => 'Payment';
  @override String get payments => 'Payments';
  @override String get paymentReceived => 'Payment received';
  @override String get paymentFailed => 'Payment failed';
  @override String get paymentFailedRetry => 'Payment failed. You can try again via the actions on your booking.';
  @override String get payNow => 'Pay now';
  @override String get price => 'Price';
  @override String get amount => 'Amount';
  @override String get payout => 'Payout';
  @override String get payouts => 'Payouts';
  @override String get balance => 'Balance';
  @override String get revenue => 'Revenue';
  @override String get earnings => 'Earnings';
  @override String get commission => 'Commission';
  @override String get fee => 'Fee';
  @override String get vat => 'VAT';
  @override String get invoiceNumber => 'Invoice number';
  @override String get downloadInvoice => 'Download invoice';
  @override String get invoiceLoadFailed => 'Failed to load invoices';
  @override String get creditBalance => 'Credit balance';
  @override String get lowCredit => 'Low credit';
  @override String get topUp => 'Top up';
  @override String get perSession => 'per session';
  @override String get perMonth => 'per month';
  @override String get perYear => 'per year';

  // ═══ BERICHTEN ═══
  @override String get messages => 'Messages';
  @override String get message => 'Message';
  @override String get newMessage => 'New message';
  @override String get sendMessage => 'Send message';
  @override String get typeMessage => 'Type a message...';
  @override String get noMessages => 'No messages';
  @override String get conversations => 'Conversations';
  @override String get notifications => 'Notifications';
  @override String get noNotifications => 'No notifications';
  @override String get markAsRead => 'Mark as read';
  @override String get newsletter => 'Newsletter';

  // ═══ DASHBOARD ═══
  @override String get dashboard => 'Dashboard';
  @override String get overview => 'Overview';
  @override String get quickActions => 'Quick actions';
  @override String get todaySessions => 'Today';
  @override String get actionRequired => 'Action required';
  @override String get noActionRequired => 'No actions required';
  @override String get weekGoal => 'Weekly goal';
  @override String get weekGoalReached => 'Weekly goal reached!';
  @override String get sessionsThisWeek => 'Sessions this week';
  @override String get revenueThisWeek => 'Revenue this week';
  @override String get revenueThisMonth => 'Revenue this month';
  @override String get newClientsThisMonth => 'New clients this month';
  @override String get occupancyRate => 'Occupancy rate';
  @override String get averageRating => 'Average rating';
  @override String get totalSessions => 'Total sessions';
  @override String upcomingCount(int count) => '$count upcoming';
  @override String pendingCount(int count) => '$count pending';

  // ═══ MEER SCHERM ═══
  @override String get more => 'More';
  @override String get marketing => 'Marketing';
  @override String get marketingTools => 'Marketing tools';
  @override String get myStorefront => 'My storefront';
  @override String get profileAndBio => 'Profile & bio';
  @override String get pricesAndPayment => 'Prices & payment';
  @override String get logisticsAndCancellation => 'Logistics & cancellation';
  @override String get socialAndGallery => 'Social media & gallery';
  @override String get branding => 'Branding';
  @override String get seoAndVerification => 'SEO & verification';
  @override String get finances => 'Finances';
  @override String get agenda => 'Schedule';
  @override String get qrCode => 'QR code';
  @override String get widget => 'Widget';

  // ═══ KLANT HOME ═══
  @override String get welcomeTip => 'Welcome to Gymies! Book your first session and start your fitness journey.';
  @override String get myGroupSessions => 'My group sessions';
  @override String get favorites => 'Favorites';
  @override String get noFavorites => 'No favorites yet';
  @override String get recentlyViewed => 'Recently viewed';
  @override String get recommended => 'Recommended';
  @override String get nearYou => 'Near you';
  @override String get popular => 'Popular';
  @override String get categories => 'Categories';
  @override String get seeAll => 'See all';

  // ═══ ZOEKEN / ONTDEKKEN ═══
  @override String get discover => 'Discover';
  @override String get searchTrainer => 'Search trainer...';
  @override String get searchLocation => 'Search location...';
  @override String get noTrainersFound => 'No trainers found';
  @override String get adjustFilters => 'Adjust your filters for more results';
  @override String get sortByDistance => 'Distance';
  @override String get sortByRating => 'Rating';
  @override String get sortByPrice => 'Price';
  @override String get filterDistance => 'Distance';
  @override String get filterPrice => 'Price';
  @override String get filterCategory => 'Category';
  @override String get filterAvailability => 'Availability';
  @override String get applyFilters => 'Apply filters';
  @override String get clearFilters => 'Clear filters';
  @override String get results => 'results';
  @override String resultCount(int count) => '$count results';

  // ═══ BEOORDELINGEN ═══
  @override String get writeReview => 'Write a review';
  @override String get yourRating => 'Your rating';
  @override String get yourReview => 'Your review';
  @override String get submitReview => 'Submit review';
  @override String get reviewSubmitted => 'Review submitted';
  @override String get noReviews => 'No reviews yet';

  // ═══ PROMO / REFERRAL ═══
  @override String get referral => 'Referral';
  @override String get referralCode => 'Referral code';
  @override String get shareYourCode => 'Share your code';
  @override String get inviteFriends => 'Invite friends';
  @override String get earnRewards => 'Earn rewards';

  // ═══ FOUTMELDINGEN ═══
  @override String get errorGeneric => 'Something went wrong';
  @override String get errorNetwork => 'No internet connection';
  @override String get errorServer => 'Server error — please try again later';
  @override String get errorTimeout => 'Request timed out — please try again';
  @override String get errorUnauthorized => 'Session expired — please log in again';
  @override String get errorNotFound => 'Not found';
  @override String get errorForbidden => 'Access denied';
  @override String get errorLoadFailed => 'Failed to load';
  @override String get errorSaveFailed => 'Failed to save';
  @override String get errorDeleteFailed => 'Failed to delete';
  @override String get errorSendFailed => 'Failed to send';
  @override String get successSaved => 'Saved';
  @override String get successDeleted => 'Deleted';
  @override String get successSent => 'Sent';
  @override String get successUpdated => 'Updated';

  // ═══ SOS / VEILIGHEID ═══
  @override String get sos => 'SOS';
  @override String get sosAlert => 'SOS alert';
  @override String get safeSession => 'Safe session';
  @override String get safeSessionActive => 'Safe session active';
  @override String get safeSessionEnded => 'Safe session ended';
  @override String get iAmSafe => 'I am safe';
  @override String get sendSos => 'Send SOS';

  // ═══ ABONNEMENT ═══
  @override String get currentPlan => 'Current plan';
  @override String get upgradePlan => 'Upgrade plan';
  @override String get downgradePlan => 'Downgrade plan';
  @override String get freePlan => 'Free';
  @override String get starterPlan => 'Starter';
  @override String get proPlan => 'Pro';
  @override String get proPlusPlan => 'Pro+';
  @override String get suitePlan => 'Suite';
  @override String get featuresIncluded => 'Features included';
  @override String get perMonthLabel => '/month';
  @override String trialDaysLeft(int count) => '$count trial days left';
  @override String get trialExpired => 'Trial expired';

  // ═══ AGENDA ═══
  @override String get calendar => 'Calendar';
  @override String get availabilitySlots => 'Availability';
  @override String get setAvailability => 'Set availability';
  @override String get dayOff => 'Day off';
  @override String get exception => 'Exception';
  @override String get addException => 'Add exception';
  @override String get recurringSlot => 'Recurring time slot';

  // ═══ CHECK-IN ═══
  @override String get checkIn => 'Check in';
  @override String get scanQr => 'Scan QR code';
  @override String get showQr => 'Show QR code';
  @override String get checkedIn => 'Checked in';
  @override String get checkInSuccess => 'Successfully checked in!';

  // ═══ INVAL ═══
  @override String get substitute => 'Substitute';
  @override String get substituteRequest => 'Substitute request';
  @override String get urgentSubstitute => 'Urgent substitute';
  @override String get lookingForSubstitute => 'Looking for substitute';
  @override String get acceptSubstitute => 'Accept substitute';

  // ═══ WACHTLIJST ═══
  @override String get waitlist => 'Waitlist';
  @override String get joinWaitlist => 'Join waitlist';
  @override String get leaveWaitlist => 'Leave waitlist';
  @override String get waitlistPosition => 'Waitlist position';
  @override String get spotAvailable => 'Spot available!';

  // ═══ OVERIG ═══
  @override String get appVersion => 'App version';
  @override String get termsOfService => 'Terms of service';
  @override String get privacyPolicy => 'Privacy policy';
  @override String get contactUs => 'Contact us';
  @override String get faq => 'FAQ';
  @override String get rateApp => 'Rate the app';
  @override String get shareApp => 'Share the app';
  @override String get updateAvailable => 'Update available';
  @override String get updateNow => 'Update now';
  @override String get forceUpdateTitle => 'Update required';
  @override String get forceUpdateMessage => 'A new version is available. Please update the app to continue.';
  @override String get biometric => 'Biometrics';
  @override String get faceId => 'Face ID';
  @override String get touchId => 'Touch ID';
  @override String get fingerprint => 'Fingerprint';

  // ═══ EXTRA SCREEN STRINGS ═══
  @override String get createAccount => 'Create account';
  @override String get almostDone => 'Almost done!';
  @override String get checkEmailForInstructions => 'Check your email for instructions to reset your password.';
  @override String get theseFieldsAreOptional => 'These fields are optional';
  @override String get gender => 'Gender';
  @override String get mustAgreeTerms => 'You must agree to the Terms and Conditions.';
  @override String get mustAgreePrivacy => 'You must agree to the Privacy Policy.';
  @override String get chooseYourRole => 'Choose your role to get started';
  @override String get chooseGender => 'Choose whether you are registered as male or female.';
  @override String get rememberMe => 'Remember me';
  @override String get connectionFailed => 'Connection failed. Check your internet and try again.';
  @override String get forgotten => 'Forgot?';
  @override String get taglineText => 'Find your personal trainer\nand book directly';
  @override String get enterEmailAndPassword => 'Enter your email and password';
  @override String get enterEmailForReset => 'Enter your email. We\'ll send you a link to reset your password.';
  @override String get whoAreYou => 'Who are you?';
  @override String get repeatPassword => 'Repeat password';
  @override String get canNowLoginNewPassword => 'You can now log in with your new password.';
  @override String get chooseStrongPassword => 'Choose a strong password of at least 8 characters.';
  @override String get minimum8Characters => 'Minimum 8 characters';
  @override String get goToLogin => 'Go to login';
  @override String get newPassword => 'New password';
  @override String get setNewPassword => 'Set a new password';
  @override String get passwordChanged => 'Password changed';
  @override String get savePassword => 'Save password';
  @override String get resetPasswordTitle => 'Reset password';
  @override String get code => 'Code';
  @override String get resendCodeAction => 'Resend code';
  @override String get verifyEmailTitle => 'Verify email';
  @override String get newCodeSent => 'New code sent. Check your email.';
  @override String get verify => 'Verify';
  @override String get viewTrainer => 'View trainer';
  @override String get goToDiscoverToBook => 'Go to Discover to book a trainer';
  @override String get howManySessions => 'How many sessions per week?';
  @override String get discoverTrainers => 'Discover trainers';
  @override String get quickNav => 'Quick navigation';
  @override String get streak => 'Streak';
  @override String get tipLabel => 'TIP';
  @override String get totalLabel => 'Total';
  @override String get setWeekGoal => 'Set week goal';
  @override String get ifTrainerFullyBooked => 'If a trainer is fully booked, you can join the waitlist.';
  @override String get viewMySessions => 'View my sessions';
  @override String get describeSituation => 'Describe the situation in detail...';
  @override String get describeIssueClearly => 'Describe the issue as clearly as possible. We will handle it as soon as possible.';
  @override String get payNowAction => 'Pay now';
  @override String get paymentMethod => 'Payment method';
  @override String get paymentSuccessful => 'Payment successful!';
  @override String get exampleNoShow => 'E.g. No-show, quality issue...';
  @override String get cashAtTrainer => 'Cash at trainer';
  @override String get downloadPdfDirectly => 'Download the PDF directly after opening.';
  @override String get useCode => 'Use code';
  @override String get noEnrollments => 'No enrollments';
  @override String get noWaitlists => 'No waitlists';
  @override String get fileDispute => 'File dispute';
  @override String get notEnrolledGroupSession => 'You haven\'t enrolled in a group session yet.';
  @override String get sessionIsConfirmed => 'Your session is confirmed';
  @override String get couldNotFileDispute => 'Could not file dispute.';
  @override String get moreActions => 'More actions';
  @override String get onlineMollie => 'Online (Mollie)';
  @override String get promoCodeOptional => 'Promo code (optional)';
  @override String get reason => 'Reason';
  @override String get referralBenefitAvailable => 'Referral benefit available';
  @override String get explanationOptional => 'Explanation (optional)';
  @override String get training => 'Training';
  @override String get confirmCancelSession => 'Are you sure you want to cancel this session?';
  @override String get findATrainer => 'Find a trainer';
  @override String get exampleName => 'E.g. John Smith';
  @override String get exampleCity => 'E.g. London, Manchester';
  @override String get emailEmergencyContact => 'Emergency contact email';
  @override String get repeatNewPassword => 'Repeat new password';
  @override String get currentPassword => 'Current password';
  @override String get myProfileTitle => 'My profile';
  @override String get myCity => 'My city';
  @override String get nameLabel => 'Name';
  @override String get emergencyContactName => 'Emergency contact name';
  @override String get retryAction => 'Try again';
  @override String get saveAction => 'Save';
  @override String get personalDetails => 'Personal details';
  @override String get profileSaved => 'Profile saved';
  @override String get phoneLabel => 'Phone';
  @override String get emergencyContactPhone => 'Emergency contact phone';
  @override String get passwordSuccessfullyChanged => 'Password successfully changed';
  @override String get changePassword => 'Change password';
  @override String get emergencyContactInfo => 'Will be informed during an SOS alert';
  @override String get emergencyContactPlaceholder => 'emergency@example.com';
  @override String get nameIsRequired => 'Name is required';
  @override String get enterMinimum10Digits => 'Enter at least 10 digits';
  @override String get phoneNumberTooLong => 'Phone number is too long';
  @override String get enterCurrentPassword => 'Enter your current password';
  @override String get minimumCharacters => 'Minimum 8 characters';
  @override String get passwordsDoNotMatch => 'Passwords do not match';
  @override String get couldNotLoadProfile => 'Could not load profile.';
  @override String get emergencyContactLabel => 'Emergency contact';
  @override String get messageLabel => 'Message';
  @override String get describeProblemClearly => 'Describe the problem as clearly as possible';
  @override String get bookingId => 'Booking ID';
  @override String get contactLabel => 'Contact';
  @override String get checkInternetRetry => 'Check your internet and try again.';
  @override String get ticketNoLongerExists => 'This ticket no longer exists';
  @override String get ticketResolved => 'This ticket is resolved';
  @override String get invoiceIdLabel => 'Invoice ID';
  @override String get avgResponseTime => 'Average response time: ~2 hours';
  @override String get ticketsAppearHere => 'Your tickets will appear here\nwhen you contact us.';
  @override String get howCanWeHelp => 'How can we help you?';
  @override String get cantFigureItOut => 'Can\'t figure it out?';
  @override String get couldNotLoadTicket => 'Could not load ticket';
  @override String get briefSummary => 'Brief summary';
  @override String get lastSupportRequestSent => 'Last support request sent after all';
  @override String get notFoundWhatLooking => 'Didn\'t find what you were looking for?';
  @override String get newSupportRequest => 'New support request';
  @override String get createNewRequest => 'Create new request';
  @override String get noSupportRequests => 'No support requests yet';
  @override String get subjectLabel => 'Subject';
  @override String get againLabel => 'Again';
  @override String get replySubmitted => 'Reply submitted';
  @override String get startConversation => 'Start a conversation with our team';
  @override String get sendUsMessage => 'Send us a message';
  @override String get supportContextNote => 'Support stays linked to the trainer/session context of your request.';
  @override String get supportRequestCreated => 'Support request created!';
  @override String get supportRequestFailed => 'Support request failed';
  @override String get ticketClosedNoReply => 'Ticket is closed and can no longer be replied to.';
  @override String get typeLabel => 'Type';
  @override String get submitRequest => 'Submit request';
  @override String get requestNotSent => 'Request not sent';
  @override String get findAnswerOrContact => 'Find an answer or contact us';
  @override String get waitingForReply => 'Waiting for support reply';
  @override String get backupCode => 'Backup code';
  @override String get backupCodeCopied => 'Backup code copied';
  @override String get checkInLabel => 'Check-in';
  @override String get cantScanQr => 'Can\'t scan the QR? Give this code to your trainer.';
  @override String get letTrainerScanQr => 'Let your trainer scan this QR code';
  @override String get generateNewQr => 'Generate new QR';
  @override String get generatingQr => 'Generating QR code...';
  @override String get sosAlertSent => 'SOS alert sent. Your emergency contact has been notified.';
  @override String get disputeMessages => 'MESSAGES';
  @override String get disputeResolvedNoMessages => 'This dispute is resolved. You can no longer send messages.';
  @override String get dispute => 'Dispute';
  @override String get couldNotSendMessage => 'Could not send message.';
  @override String get noMessagesYet => 'No messages yet';
  @override String get typeAMessage => 'Type a message...';
  @override String get noDisputes => 'No disputes';
  @override String get disputes => 'Disputes';
  @override String get ifYouHaveBookingIssue => 'If you ever have an issue with a booking,';
  @override String get attendance => 'Attendance';
  @override String get coachNotes => 'Coach notes';
  @override String get goalsLabel => 'Goals';
  @override String get feedbackFromTrainer => 'Feedback and notes from your trainer after a session.';
  @override String get noChartData => 'No chart data for this metric.';
  @override String get weightLabel => 'Weight';
  @override String get instructionVideo => 'Instruction videos';
  @override String get noProgressShared => 'Your trainer hasn\'t shared progress yet.';
  @override String get myDossier => 'My dossier';
  @override String get noCoachNotesYet => 'No coach notes yet.';
  @override String get noGoalsSetYet => 'No goals set by your trainer yet.';
  @override String get achievementLabel => 'Achievement';
  @override String get progressAndRhythm => 'Progress & rhythm';
  @override String get videoLabel => 'Videos';
  @override String get favoritesTitle => 'Favorites';
  @override String get searchByNameSpeciality => 'Search by name, speciality or region';
  @override String get cancelLabel => 'Cancel';
  @override String get descriptionLabel => 'Description';
  @override String get lessonCancelled => 'This lesson has been cancelled';
  @override String get groupSessionLabel => 'Group session';
  @override String get enrolledLabel => 'Enrolled';
  @override String get cancelEnrollment => 'Cancel enrollment';
  @override String get enrollmentCancelled => 'Enrollment cancelled';
  @override String get spotReserved => 'Your spot is reserved.';
  @override String get noGroupSessionsPlanned => 'There are currently no group sessions planned in the selected period.';
  @override String get goingAhead => 'Going ahead!';
  @override String get noGroupSessionsFound => 'No group sessions found';
  @override String get groupSessionsTitle => 'Group sessions';
  @override String get viewAction => 'View';
  @override String get paymentProof => 'Payment proof';
  @override String get downloadPdf => 'Download PDF';
  @override String get downloadInvoiceAsPdf => 'Download the invoice as PDF.';
  @override String get noDownloadLink => 'No download link available.';
  @override String get copyLink => 'Copy link';
  @override String get myInvoices => 'My invoices';
  @override String get pdfDownload => 'PDF download';
  @override String get requestInvoice => 'Request';
  @override String get conversationDeleted => 'Conversation deleted';
  @override String get inboxLabel => 'Inbox';
  @override String get couldNotDeleteConversation => 'Could not delete conversation';
  @override String get discoverTrainersNearYou => 'Discover trainers near you';
  @override String get sessionStartsSoon => 'Session starting soon';
  @override String get rescheduleSession => 'Reschedule session';
  @override String get tapToResend => 'Tap to resend';
  @override String get rescheduleAnyway => 'Reschedule anyway';
  @override String get trainerIdMissing => 'Trainer ID missing';
  @override String get rescheduleAction => 'Reschedule';
  @override String get rescheduleFailed => 'Reschedule failed. Please try again.';
  @override String get rescheduleRequestSent => 'Reschedule request sent';
  @override String get searchConversations => 'Search conversations...';
  @override String get typingIndicator => 'typing...';
  @override String get getStarted => 'Get started';
  @override String get youAreReady => 'You\'re ready!';
  @override String get fitnessJourneyStarts => 'Your personal fitness journey starts here.';
  @override String get skipLabel => 'Skip';
  @override String get tellAboutYourself => 'Tell us about yourself';
  @override String get nextAction => 'Next';
  @override String get trainersCanFindYou => 'This way trainers can find you better.';
  @override String get accountDeleteRequested => 'Account deletion request submitted';
  @override String get calendarSync => 'Calendar synchronization';
  @override String get autoSyncDescription => 'New sessions are automatically added to your calendar.';
  @override String get autoAdd => 'Auto add';
  @override String get confirmNewPassword => 'Confirm new password';
  @override String get gdprNote => 'GYMIES processes your personal data in accordance with GDPR.';
  @override String get dataExportRequestedEmail => 'Data export requested \u2014 you will receive an email';
  @override String get strongPasswordHint => 'Choose a strong password of at least 8 characters with letters and numbers.';
  @override String get couldNotRequestExport => 'Could not request export. Please try again later.';
  @override String get couldNotRequestDeletion => 'Could not submit deletion request. Please try again later.';
  @override String get couldNotChangePassword => 'Could not change password. Please try again later.';
  @override String get supportedCalendars => 'Supported calendars:';
  @override String get privacyAndData => 'Privacy & data';
  @override String get quietHours => 'Quiet hours';
  @override String get tapToAdjust => 'Tap to adjust';
  @override String get tipManualCalendar => 'Tip: You can also manually add a session to your calendar.';
  @override String get whatIsYourGoal => 'What is your goal?';
  @override String get subscriptionsAndPackages => 'Subscriptions & packages';
  @override String get viewAllReviews => 'View all reviews';
  @override String get thankYouForReport => 'Thank you for your report.';
  @override String get viewAllAction => 'View all';
  @override String get viewPackages => 'View packages';
  @override String get viewFullProfile => 'View full profile';
  @override String get availabilityLabel => 'Availability';
  @override String get payCashOnDay => 'Pay cash on the day';
  @override String get securedViaMollie => 'Secured via Mollie \u2014 instant confirmation';
  @override String get confirmBooking => 'Confirm booking';
  @override String get bookingInProgress => 'Booking in progress...';
  @override String get bookSessionAction => 'Book session';
  @override String get bookingCreatedPaymentFailed => 'Booking created but payment could not be started.';
  @override String get bookingCreatedOpen => 'Booking created!';
  @override String get bookingConfirmedCash => 'Booking confirmed! Pay cash at your trainer.';
  @override String get finalPriceOnBooking => 'Final price on booking.';
  @override String get chosenPackage => 'CHOSEN PACKAGE';
  @override String get galleryLabel => 'Gallery';
  @override String get onStandbyList => 'You are now on the standby list';
  @override String get redirectedToPayment => 'You are being redirected to the payment page...';
  @override String get onlyPublicInfo => 'You only see public profile information here.';
  @override String get chooseDate => 'CHOOSE A DATE';
  @override String get chooseTime => 'CHOOSE A TIME';
  @override String get choosePackage => 'Choose a package';
  @override String get couldNotOpenMaps => 'Could not open maps app.';
  @override String get lastReview => 'Latest review';
  @override String get locationLabel => 'Location';
  @override String get singleSession => 'Single session';
  @override String get moreDates => 'More dates';
  @override String get reportAction => 'Report';
  @override String get afternoonLabel => 'Afternoon';
  @override String get noBioAdded => 'No bio added yet.';
  @override String get noMediaAdded => 'No media added yet.';
  @override String get noPublicAvailability => 'No public availability yet.';
  @override String get noPublicPackages => 'No public packages yet.';
  @override String get noReviewsAvailable => 'No reviews available yet.';
  @override String get addNoteForTrainer => 'Add note for trainer...';
  @override String get morningLabel => 'Morning';
  @override String get onlineHomeGym => 'Online / home / gym depending on appointment';
  @override String get payOnline => 'Pay online';
  @override String get onStandbyListLabel => 'On standby list';
  @override String get aboutMe => 'About me';
  @override String get packageLabel => 'Package';
  @override String get planRoute => 'Plan route';
  @override String get shareProfile => 'Share profile';
  @override String get reportProfile => 'Report profile';
  @override String get reviewsGalleryMore => 'Reviews, gallery, packages and more';
  @override String get specializationsLabel => 'Specializations';
  @override String get storiesLabel => 'Stories';
  @override String get ratesIndication => 'Rates (indication)';
  @override String get backLabel => 'Back';
  @override String get fromPrice => 'From';
  @override String get removeFromMyTrainers => 'Remove from my trainers';
  @override String get videoCannotBePlayed => 'Video cannot be played';
  @override String get nextWeek => 'Next week';
  @override String get idealCreditcardApplePay => 'iDEAL, credit card, Apple Pay';
  @override String get noReviewsYet => 'No reviews yet';
  @override String get beFirstToReview => 'Be the first to leave a review after a session.';
  @override String get noStandbyEnrollments => 'No standby enrollments';
  @override String get myWaitlists => 'My waitlists';
  @override String get standbyEnrollmentRemoved => 'Standby enrollment removed';
  @override String get historyLabel => 'HISTORY';
  @override String get howToEarnPoints => 'HOW DO YOU EARN POINTS?';
  @override String get currentBalance => 'Current balance';
  @override String get loadMore => 'Load more';
  @override String get myCredit => 'My Credit';
  @override String get noTransactions => 'No transactions yet';
  @override String get pointsRedeemed => 'Points redeemed!';
  @override String get redeemPoints => 'Redeem points';
  @override String get notificationPreferences => 'Notification preferences';
  @override String get notificationsTitle => 'Notifications';
  @override String get openRelatedPage => 'Open related page';
  @override String get smartReminders => 'Smart reminders: T-24h, T-2h, check-in and missed check-in.';
  @override String get myGroupSessionsTitle => 'My group sessions';
  @override String get distanceLabel => 'Distance';
  @override String get clearAllFilters => 'Clear all filters';
  @override String get clearAllAction => 'Clear all';
  @override String get noGroupSessionsInNext60Days => 'There are currently no group sessions planned\nin the next 60 days.';
  @override String get filtersLabel => 'Filters';
  @override String get noDistanceFilter => 'No distance filter';
  @override String get chooseSessionType => 'Choose session type';
  @override String get chooseSpeciality => 'Choose speciality';
  @override String get chooseCity => 'Choose city';
  @override String get logInAgain => 'Log in again';
  @override String get maxPricePerSession => 'Max. price per session';
  @override String get myEnrollments => 'My enrollments';
  @override String get myTrainersLabel => 'My trainers';
  @override String get minRating => 'Min. rating';
  @override String get discoverTitle => 'Discover';
  @override String get searchAgain => 'Search again';
  @override String get priceOnRequest => 'Price on request';
  @override String get sortAction => 'Sort';
  @override String get sortByLabel => 'Sort by';
  @override String get searchTrainerSpecialism => 'Search trainer, specialism or city...';
  @override String get actionNeeded => 'Action needed';
  @override String get activateAccount => 'Activate your account';
  @override String get declineAction => 'Decline';
  @override String get viewAllAction2 => 'View all';
  @override String get confirmAction => 'Confirm';
  @override String get laterLabel => 'Later';
  @override String get activateNow => 'Activate now';
  @override String get revenueThisMonthLabel => 'REVENUE THIS MONTH';
  @override String get respondAction => 'Respond';
  @override String get quickActionsLabel => 'QUICK ACTIONS';
  @override String get storiesProFeature => 'Stories is a Pro feature. Upgrade your plan.';
  @override String get storyPosted => 'Story posted!';
  @override String get toConfirmLabel => 'TO CONFIRM';
  @override String get nextSessionLabel => 'NEXT SESSION';
  @override String get completeOnboarding => 'Complete your onboarding to start offering sessions.';
  @override String get weekGoalLabel => 'WEEK GOAL';
  @override String get allClientsActive => 'All clients are active!';
  @override String get allFilter => 'All';
  @override String get analyticsLabel => 'Analytics';
  @override String get autoRebook => 'Auto rebook';
  @override String get messagesSentAutomatically => 'Messages are sent automatically.';
  @override String get describeUrgentIssue => 'Briefly describe the urgent issue';
  @override String get bookingRefOptional => 'Booking reference (optional)';
  @override String get bulkMessageSend => 'Send bulk message';
  @override String get bulkMessageSent => 'Bulk message sent';
  @override String get communicationLabel => 'Communication';
  @override String get noClientsForFilter => 'No clients found for this filter.';
  @override String get remindAction => 'Remind';
  @override String get inactiveClientsLabel => 'INACTIVE CLIENTS';
  @override String get issueLabel => 'Issue';
  @override String get addClientComingSoon => 'Add client coming soon';
  @override String get clientIdMissing => 'Client ID missing.';
  @override String get howManyDaysInactivity => 'After how many days of inactivity do clients automatically receive a reminder?';
  @override String get noHealthScoreData => 'No health score data available yet.';
  @override String get noUpsellSuggestions => 'No upsell suggestions available yet.';
  @override String get openPriorityLane => 'Open priority lane';
  @override String get packagesExpiringSoon => 'PACKAGES EXPIRING SOON';
  @override String get prioritySupportSent => 'Priority support ticket sent';
  @override String get sendActionLabel => 'Send';
  @override String get sendMessageToAllClients => 'Send a message to all your clients at once.';
  @override String get upsellProposalSent => 'Upsell proposal sent';
  @override String get sendingLabel => 'Sending...';
  @override String get forUrgentIssues => 'For urgent operational issues.';
  @override String get weMissYouMessageSent => 'We miss you message sent';
  @override String get searchClient => 'Search client...';
  @override String get clientInsightsCouldNotLoad => 'Could not load insights.';
  @override String get clientAnalyticsCouldNotLoad => 'Could not load analytics.';
  @override String get activeStatusLabel => 'Active';
  @override String get riskLabel => 'At risk';
  @override String get inactiveStatusLabel => 'Inactive';
  @override String get newStatusLabel => 'New';
  @override String get todayDateLabel => 'Today';
  @override String get yesterdayDateLabel => 'Yesterday';
  @override String get clientSingle => 'Client';
  @override String get noSessionsLabel => 'No sessions';
  @override String get rebookInterval => 'Rebook interval';
  @override String get sendAllReminders => 'Send all reminders?';
  @override String get bulkMessageLabel => 'Bulk message';
  @override String get prioritySupportLane => 'Priority support lane';
  @override String get healthScoresLabel => 'Health Scores';
  @override String get upsellSuggestionsLabel => 'Upsell suggestions';
  @override String get smartRebook => 'Smart Rebook';
  @override String get sessionsCountLabel => 'Sessions';
  @override String get revenueCountLabel => 'Revenue';
  @override String get searchClientTooltip => 'Search client';
  @override String get addClientTooltip => 'Add client';
  @override String get overviewTab => 'Overview';
  @override String get insightsTab => 'Insights';
  @override String get moreTab => 'More';
  @override String get clientInsightsFeature => 'Client insights';
  @override String get analyticsCommsFeature => 'Analytics & Communication';
  @override String get noClientsFoundTitle => 'No clients found';
  @override String get clientsAppearAfterBooking => 'Clients will appear here once they book a session.';
  @override String get packageUpgrade => 'Package upgrade';
  @override String get expiredStatusLabel => 'Expired';
  @override String get longerThan7DaysInactive => 'Inactive for more than 7 days';
  @override String get createAction => 'Create';
  @override String get viewPdf => 'View the PDF';
  @override String get descriptionOptional => 'Description (optional)';
  @override String get evidenceUrlOptional => 'Evidence URL (optional)';
  @override String get endSession => 'End session';
  @override String get endSessionAction => 'End';
  @override String get exampleClientNoShow => 'E.g. client no-show';
  @override String get checkInQueued => 'Check-in queued.';
  @override String get registerCheckIn => 'Register check-in';
  @override String get dateAndTime => 'Date & time';
  @override String get serviceLabel => 'Service';
  @override String get documentsNotComplete => 'Documents not fully saved.';
  @override String get durationLabel => 'Duration';
  @override String get invoiceCreatedNoPdf => 'Invoice created but PDF link is missing.';
  @override String get invoiceAmountMustBePositive => 'Invoice amount must be greater than 0';
  @override String get groupSessionCreated => 'Group session created!';
  @override String get heartbeatActive => 'Heartbeat active';
  @override String get chooseDateAndTime => 'Choose a date and time';
  @override String get couldNotOpenPdf => 'Could not open PDF.';
  @override String get maxParticipants => 'Max participants';
  @override String get registerNoShow => 'Register no-show';
  @override String get noteOptional => 'Note (optional)';
  @override String get composeAndSend => 'Compose & send';
  @override String get optionalNote => 'Optional note...';
  @override String get pdfLinkInvalid => 'PDF link is invalid.';
  @override String get pdfMissingOnServer => 'PDF missing on server.';
  @override String get priceInclVat => 'Price incl. VAT (EUR)';
  @override String get safeSessionActiveLabel => 'Safe session active';
  @override String get startSafeSession => 'Start safe session';
  @override String get serviceDate => 'Service date';
  @override String get sessionSingle => 'Session';
  @override String get endSessionQuestion => 'End session?';
  @override String get moveAction => 'Move';
  @override String get elapsedTime => 'Elapsed time';
  @override String get expiryDate => 'Expiry date';
  @override String get completeAction => 'Complete';
  @override String get availabilitySettings => 'Availability settings';
  @override String get blockingLabel => 'Block';
  @override String get bookInAdvance => 'Book in advance';
  @override String get dayLabel => 'Day';
  @override String get dateInputLabel => 'Date';
  @override String get settingsShownOnProfile => 'These settings are shown on your profile.';
  @override String get endTimeLabel => 'End';
  @override String get endTimeMustBeLater => 'End time must be later than start time.';
  @override String get blockedExceptionLabel => 'Blocked (exception)';
  @override String get blockedDays => 'Blocked days';
  @override String get howManyDaysAdvance => 'How many days in advance can a client book?';
  @override String get chooseDayAndTimes => 'Choose the day and times.';
  @override String get copyForUpcoming => 'Copy for the upcoming';
  @override String get notAvailable => 'Not available';
  @override String get reasonOptional => 'Reason (optional)';
  @override String get startTimeLabel => 'Start';
  @override String get setOnceApplyAll => 'Set once and apply to all days.';
  @override String get timesLabel => 'Times';
  @override String get timeSlot => 'Time slot';
  @override String get enterValidTimes => 'Enter valid times first.';
  @override String get whatShowOnProfile => 'What do you show on your profile?';
  @override String get weeklyTimeSlots => 'Weekly time slots';
  @override String get getStorefrontPromoMore => 'Get storefront, promo codes and more';
  @override String get logoutAction => 'Log out';
  @override String get upgradeToProAction => 'Upgrade to Pro';
  @override String get actionRequiredArrow => 'Action required \u2192';
  @override String get reachAllClients => 'Reach all your clients with one tap.';
  @override String get readStatusLabel => 'Read';
  @override String get newConversationComingSoon => 'New conversation coming soon';
  @override String get newsletterLabel => 'Newsletter';
  @override String get unreadStatusLabel => 'Unread';
  @override String get noInternetConnection => 'No internet connection';
  @override String get haveACode => 'Have a code?';
  @override String get applyAction => 'Apply';
  @override String get upgradeAction => 'Upgrade';
  @override String get shareThePower => 'Share the power of fitness';
  @override String get shareVia => 'Share via';
  @override String get howDoesItWork => 'How does it work?';
  @override String get yourPersonalLink => 'Your personal link';
  @override String get letFriendsScanQr => 'Let friends scan this QR code';
  @override String get linkCopied => 'Link copied!';
  @override String get inviteFriendsGymies => 'Invite friends to GYMIES and receive';
  @override String get orShareViaQr => 'Or share via QR';
  @override String get timerExtended30Min => 'Thank you! Timer extended by 30 minutes.';
  @override String get emergencyContactAutoNotified => 'Your emergency contact will be automatically notified';
  @override String get sessionTakingLonger => 'Your session is taking longer than expected.';
  @override String get sosHelpNeeded => 'SOS \u2013 Need help';
  @override String get closeApp => 'Close app';
  @override String get securityWarning => 'Security warning';
  @override String get gymiesProtects => 'Gymies protects your personal data and payments.';
  @override String get waitingForTrainerReply => 'Waiting for trainer\'s reply...';
  @override String get noAvailableMoments => 'No available moments found';
  @override String get noTimesAvailable => 'No times available on this day';
  @override String get postAnonymously => 'Post anonymously';
  @override String get giveRating => 'Give rating';
  @override String get cameraLabel => 'Camera';
  @override String get complimentOptional => 'Compliment or comment (optional)';
  @override String get photoLabel => 'Photo';
  @override String get howWasYourSession => 'How was your session?';
  @override String get nameNotShownOnReview => 'Your name will not be shown on the review';
  @override String get submitActionLabel => 'Submit';
  @override String get actionHistoryTitle => 'Action history';
  @override String get escalateAction => 'Escalate';
  @override String get noEventsYet => 'No events yet';
  @override String get recentEvents => 'Recent events';
  @override String get retryNow => 'Retry now';
  @override String get executedActionsAppear => 'Executed and queued actions appear here.';
  @override String get queueLabel => 'Queue';


  // ═══ EXTRA SCREEN STRINGS (PHASE 2) ═══
  @override
  String get sessionCancelledStandbyPushSent => 'Session cancelled and standby push sent';
  @override
  String get ifNoResponseEmergencyNotificationSent => 'If no response is received, an emergency notification will be sent.';
  @override
  String get safeSessionStarted => 'Safe session started';
  @override
  String get clientAutoCheckedOut => 'the client will be automatically checked out.';
  @override
  String get clientCheckedOutSessionCompleted => 'The client will be checked out and the session will be completed.';
  @override
  String get heartbeatsLabel => 'Heartbeats';
  @override
  String get successfulLabel => 'successful';
  @override
  String get escalationsLabel => 'Escalations';
  @override
  String get sessionEnded => 'Session ended';
  @override
  String get adminNotifiedImmediately => 'Admin will be notified immediately.';
  @override
  String get checkInRegistered => 'Check-in registered';
  @override
  String get fillInReason => 'Please enter a reason';
  @override
  String get noShowRegistered => 'No-show registered';
  @override
  String get rescheduleRequestSentToClient => 'Reschedule request sent to the client. The client can respond in their messages.';
  @override
  String get personalTrainingSession => 'Personal training session';
  @override
  String get invoiceSentToClient => 'Invoice sent to client';
  @override
  String get directSuccess => 'Directly successful';
  @override
  String get sessionConfirmedPayCash => 'Session confirmed! Pay cash at your trainer.';
  @override
  String get redirectingToPayment => 'You are being redirected to the payment page...';
  @override
  String get couldNotSubmitDispute => 'Could not submit dispute.';
  @override
  String get cancelSessionQuestion => 'Are you sure you want to cancel this session?';
  @override
  String get howManySessionsPerWeek => 'How many sessions per week?';
  @override
  String get goToDiscoverToBookTrainer => 'Go to Discover to book a trainer';
  @override
  String get quickTo => 'Quick access';
  @override
  String get tipManualCalendarAdd => 'Tip: You can also manually add a session to your calendar via the action button on each booking.';
  @override
  String get quietHoursLabel => 'Quiet hours';
  @override
  String get sessionStartingSoon => 'Session starting soon';
  @override
  String get couldNotLoadSessions2 => 'Could not load sessions';
  @override
  String get allLabel => 'All';
  @override
  String get remindLabel => 'Remind';
  @override
  String get sendLabel => 'Send';
  @override
  String get sending => 'Sending…';
  @override
  String get autoRebookings => 'Auto-rebookings';
  @override
  String get messagesAutoSentNote => 'Messages are sent automatically. You can always disable this.';
  @override
  String get afterHowManyDaysInactivity => 'After how many days of inactivity do clients automatically receive a reminder?';
  @override
  String get inactiveClients => 'INACTIVE CLIENTS';
  @override
  String get prioritySupportTicketSent => 'Priority support ticket sent';
  @override
  String get describeUrgentProblem => 'Briefly describe the urgent problem';
  @override
  String get bookingReferenceOptional => 'Booking reference (optional)';
  @override
  String get forUrgentOperationalIssues => 'For urgent operational issues with context package.';
  @override
  String get readLabel => 'Read';
  @override
  String get unreadLabel => 'Unread';
  @override
  String get reachAllClientsOneClick => 'Reach all your clients with one click. Share tips, offers and updates.';
  @override
  String get getStorefrontPromoCodesMore => 'Get storefront, promo codes and more';
  @override
  String get logoutLabel => 'Log out';
  @override
  String get upgradeToProLabel => 'Upgrade to Pro';
  @override
  String get rejectLabel => 'Reject';
  @override
  String get confirmLabel => 'Confirm';
  @override
  String get respondLabel => 'Respond';
  @override
  String get toConfirm => 'TO CONFIRM';
  @override
  String get clearAll => 'Clear all';
  @override
  String get retryLabel => 'Retry';
  @override
  String get applyLabel => 'Apply';
  @override
  String get upgradeLabel => 'Upgrade';
  @override
  String get waitingForTrainerResponse => 'Waiting for trainer response...';
  @override
  String get noAvailableMomentsFound => 'No available moments found';
  @override
  String get noTimesAvailableOnThisDay => 'No times available on this day';
  @override
  String get complimentOrRemarkOptional => 'Compliment or remark (optional)';
  @override
  String get nameNotShownInReview => 'Your name will not be shown in the review';
  @override
  String get submitLabel => 'Submit';
  @override
  String get thankYouTimerExtended => 'Thank you! Timer extended by 30 minutes.';
  @override
  String get emergencyContactNotifiedIfNoResponse => 'Your emergency contact will be automatically notified if you don\'t';
  @override
  String get sessionTakingLongerThanExpected => 'Your session is taking longer than expected.';
  @override
  String get sosEmergencyContactNotified => 'SOS sent. Your emergency contact has been notified.';
  @override
  String get sosNeedHelp => 'SOS – Need help';
  @override
  String get gymiesProtectsData => 'Gymies protects your personal data and payments.';

  // ═══ EXTRA SCREEN STRINGS (PHASE 3 — BULK) ═══
  @override
  String get 0GeenRestitutie => '0% — No refund';
  @override
  String get 100VolledigeRestitutie => '100% — Full refund';
  @override
  String get 120Min => '120 min';
  @override
  String get 12UurVanTevoren => '12 hours in advance';
  @override
  String get 1LinkPerRegel => '1 link per line';
  @override
  String get 1WeekVanTevoren => '1 week in advance';
  @override
  String get 24UurVanTevoren => '24 hours in advance';
  @override
  String get 25Restitutie => '25% refund';
  @override
  String get 48Uur2Dagen => '48 hours (2 days)';
  @override
  String get 50Restitutie => '50% refund';
  @override
  String get 60Min => '60 min';
  @override
  String get 72Uur3Dagen => '72 hours (3 days)';
  @override
  String get 75Restitutie => '75% refund';
  @override
  String get 90Min => '90 min';
  @override
  String get aanHetTypen => 'typing...';
  @override
  String get aandachtspunt => 'Attention point';
  @override
  String get aanmaken => 'Create';
  @override
  String get aantalSessies => 'Number of sessions';
  @override
  String get aanvragen => 'Request';
  @override
  String get aanwezigheid => 'Attendance';
  @override
  String get abonnement => 'Abonnement';
  @override
  String get abonnementFeatures => 'Subscription features';
  @override
  String get abonnementKiezen => 'Choose subscription';
  @override
  String get abonnementenPakketten => 'Subscriptions & packages';
  @override
  String get accentkleur => 'Accent color';
  @override
  String get accountAanmaken => 'Account aanmaken';
  @override
  String get accountVerwijderaanvraagIngediend => 'Account deletion request submitted';
  @override
  String get accountVerwijderaanvraagIngediendJeOntvangtEenBevestigingPerEmail => 'Account deletion request submitted — you will receive a confirmation email';
  @override
  String get actieVereist => 'Actie vereist →';
  @override
  String get actief => 'Active';
  @override
  String get adres => 'Address';
  @override
  String get adresregel1 => 'Address line 1';
  @override
  String get afstand => 'Distance';
  @override
  String get agendaSynchronisatie => 'Calendar sync';
  @override
  String get alle => 'All ›';
  @override
  String get alleDocumentenIngediend => 'All documents submitted!';
  @override
  String get alleFiltersWissen => 'Clear all filters';
  @override
  String get alleKlantenZijnActief => 'All clients are active!';
  @override
  String get allePakketten => 'All packages';
  @override
  String get allePlans => 'All plans';
  @override
  String get alleReviewsBekijken => 'View all reviews';
  @override
  String get alleStatussen => 'All statuses';
  @override
  String get alleenOngelezen => 'Unread only';
  @override
  String get alles => 'All';
  @override
  String get allesGelezen => 'All read';
  @override
  String get allesWissen => 'Clear all';
  @override
  String get alsEenTrainerVolgeboektIsKunJeJeOpDeWachtlijstPlaatsen => 'If a trainer is fully booked, you can join the waiting list.';
  @override
  String get alsJeAutosyncInschakeltWordenNieuweSessiesAutomatischAanJeDevicekalenderToegevoegdZodraZeBevestigdZijn => 'When you enable auto-sync, new sessions are automatically added to your device calendar once confirmed.';
  @override
  String get alsJeEenAbonnementWiltWijzigenBekijkDeFeaturesEnVeranderJeAbonnementJeAbonnementGaatInBijDeVolgendeFactuurdatum => 'If you want to change a subscription, view the features and change your plan. Your subscription starts at the next billing date.';
  @override
  String get altijdAnnuleerbaar => 'Always cancellable';
  @override
  String get analytics => 'Analytics';
  @override
  String get annuleer => 'Cancel';
  @override
  String get annuleren => 'Cancel';
  @override
  String get annuleringsbeleid => 'Cancellation policy';
  @override
  String get annuleringstermijn => 'Cancellation period';
  @override
  String get autoherboekingen => 'Auto-rebookings';
  @override
  String get automatischToevoegen => 'Automatically add';
  @override
  String get backupCodeGekopieerd => 'Backup code copied';
  @override
  String get banner => 'Banner';
  @override
  String get bedanktVoorJeMeldingWeBekijkenDitZoSnelMogelijk => 'Thank you for your report. We will review it as soon as possible.';
  @override
  String get bedrijfsnaamvoorFactuur => 'Company name (for invoice)';
  @override
  String get begrepen => 'Understood';
  @override
  String get beheerHoeKlantenJouZienOpGymies => 'Manage how clients see you on Gymies';
  @override
  String get beindigSessie => 'End session';
  @override
  String get beindigen => 'End';
  @override
  String get bekijk => 'View';
  @override
  String get bekijkAlle => 'View all';
  @override
  String get bekijkDePdf => 'View the PDF';
  @override
  String get bekijkInDossier => 'View in dossier';
  @override
  String get bekijkMijnSessies => 'View my sessions';
  @override
  String get bekijkPakketten => 'View packages';
  @override
  String get bekijkTrainer => 'View trainer';
  @override
  String get bekijkVolledigProfiel => 'View full profile';
  @override
  String get bepaalOnderWelkeVoorwaardenKlantenKunnenAnnuleren => 'Determine under which conditions clients can cancel';
  @override
  String get bereikAlJeKlantenMetnDrukOpDeKnopDeelTipsAanbiedingenEnUpdates => 'Bereik al je klanten met één druk op de knop. Deel tips, aanbiedingen en updates.';
  @override
  String get bericht => 'Message';
  @override
  String get berichtVerstuurd => 'Message sent';
  @override
  String get berichten => 'BERICHTEN';
  @override
  String get berichtenWordenAutomatischVerstuurdJeKuntDitAltijdUitschakelen => 'Messages are sent automatically. You can always disable this.';
  @override
  String get berichtencentrum => 'Message center';
  @override
  String get beschikbaarheid => 'Availability';
  @override
  String get beschikbaarheidinstellingen => 'Availability settings';
  @override
  String get beschrijfDeSituatieInDetail => 'Describe the situation in detail...';
  @override
  String get beschrijfHetProbleemZoDuidelijkMogelijk => 'Describe the problem as clearly as possible';
  @override
  String get beschrijfHetProbleemZoDuidelijkMogelijkWeNemenHetZoSnelMogelijkInBehandeling => 'Describe the problem as clearly as possible. We will handle it as soon as possible.';
  @override
  String get beschrijfJeIntroductiekorting => 'Describe your introductory discount...';
  @override
  String get beschrijfJeProbleemZoDuidelijkMogelijk => 'Describe your problem as clearly as possible';
  @override
  String get beschrijfKortHetUrgenteProbleem => 'Briefly describe the urgent problem';
  @override
  String get beschrijfSpecialeGevallenOfUitzonderingen => 'Describe special cases or exceptions...';
  @override
  String get beschrijving => 'Description';
  @override
  String get beschrijvingoptioneel => 'Description (optional)';
  @override
  String get bestandKonNietWordenGelezen => 'File could not be read.';
  @override
  String get betaalContantOpDeDagZelf => 'Pay cash on the day itself';
  @override
  String get betaalNu => 'Pay now';
  @override
  String get betaalbewijs => 'Payment receipt';
  @override
  String get betaaldeSessiesVanDezeKlantVerschijnenHier => 'Paid sessions of this client appear here.';
  @override
  String get betaaldonline => 'Paid (online)';
  @override
  String get betaalmethode => 'Payment method';
  @override
  String get betalingBevestigen => 'Confirm payment';
  @override
  String get betalingGelukt => 'Betaling gelukt!';
  @override
  String get beveiligdViaMollieDirecteBevestiging => 'Secured via Mollie — instant confirmation';
  @override
  String get beveiliging => 'BEVEILIGING';
  @override
  String get bevestigBoeking => 'Confirm booking';
  @override
  String get bevestigNieuwWachtwoord => 'Confirm new password';
  @override
  String get bewerken => 'Edit';
  @override
  String get bewerkenWordtBinnenkortBeschikbaar => 'Editing will be available soon';
  @override
  String get bewerku203a => 'Edit ›';
  @override
  String get bewijsUrloptioneel => 'Evidence URL (optional)';
  @override
  String get bezigMetBoeken => 'Booking...';
  @override
  String get bijnaKlaar => 'Bijna klaar!';
  @override
  String get bijv30 => 'e.g. 30';
  @override
  String get bijv42 => 'Eg. 42';
  @override
  String get bijv4999 => 'e.g. 49.99';
  @override
  String get bijv50 => 'e.g. 50';
  @override
  String get bijvCentrumNoordZuid => 'e.g. Center, North, South';
  @override
  String get bijvJohnfitness => 'e.g. john-fitness';
  @override
  String get bijvKlantNietVerschenen => 'E.g. client did not show up';
  @override
  String get bijvNoshowKwaliteitsprobleem => 'E.g. No-show, quality issue...';
  @override
  String get blokkering => 'Block';
  @override
  String get boekNu => 'Book now';
  @override
  String get boekSessie => 'Book session';
  @override
  String get boekenVanTevoren => 'Booking in advance';
  @override
  String get boekingBevestigdBetaalCashBijJeTrainer => 'Booking confirmed! Pay cash at your trainer.';
  @override
  String get boekingid => 'Booking ID';
  @override
  String get boekingstermijndagen => 'Booking period (days)';
  @override
  String get bookingReferenceoptioneel => 'Booking reference (optional)';
  @override
  String get bookingWidget => 'Booking Widget';
  @override
  String get brandKleur => 'Brand color';
  @override
  String get brandingOpgeslagen => 'Branding saved!';
  @override
  String get btwnummer => 'VAT number';
  @override
  String get bulkBerichtVersturen => 'Send bulk message';
  @override
  String get bulkBerichtVerstuurd => 'Bulk message sent';
  @override
  String get camera => 'Camera';
  @override
  String get capaciteit => 'Capacity';
  @override
  String get cashBijTrainer => 'Cash at trainer';
  @override
  String get checkJeEmailVoorInstructiesOmJeWachtwoordTeResetten => 'Check je e-mail voor instructies om je wachtwoord te resetten.';
  @override
  String get checkin => 'Check-in';
  @override
  String get checkinInWachtrijGeplaatstWordtOpnieuwVerstuurd => 'Check-in queued. Will be resent.';
  @override
  String get checkinRegistreren => 'Register check-in';
  @override
  String get checkinScanner => 'Check-in scanner';
  @override
  String get coachRadar => 'Coach radar';
  @override
  String get communicatie => 'Communication';
  @override
  String get contact => 'Contact';
  @override
  String get contant => 'Cash';
  @override
  String get contantBetaald => 'Paid in cash';
  @override
  String get controlTower => 'Control Tower';
  @override
  String get controleerJeInternetEnProbeerOpnieuw => 'Check your internet and try again.';
  @override
  String get csvGexporteerd => 'CSV exported';
  @override
  String get dag => 'Day';
  @override
  String get datum => 'Date';
  @override
  String get datumTijd => 'Date & time';
  @override
  String get deadlineurenVoorAanvang => 'Deadline (hours before start)';
  @override
  String get deelMetKlant => 'Share with client';
  @override
  String get deelnemers => 'Participants';
  @override
  String get definitievePrijsBijHetBoeken => 'Final price when booking.';
  @override
  String get delen => 'Share';
  @override
  String get dezeInstellingenWordenGetoondOpJeProfielZodatKlantenWetenHoeVerZeKunnenBoekenEnHoeZeKunnenBetalen => 'These settings are shown on your profile so clients know how far in advance they can book and how they can pay.';
  @override
  String get dezeLesIsGeannuleerd => 'This session has been cancelled';
  @override
  String get dezeSpecialisatieBestaatAl => 'This specialization already exists';
  @override
  String get dezeVeldenZijnOptioneel => 'Deze velden zijn optioneel';
  @override
  String get dezeWeek => 'This week';
  @override
  String get dienst => 'Service';
  @override
  String get diplomaLinksoptioneel => 'Diploma links (optional)';
  @override
  String get ditDocumentIsAfgekeurdUploadEenNieuwDocument => 'This document was rejected. Upload a new document.';
  @override
  String get ditGeschilIsOpgelostJeKuntGeenBerichtenMeerVersturen => 'This dispute has been resolved. You can no longer send messages.';
  @override
  String get ditTicketBestaatNietMeer => 'This ticket no longer exists';
  @override
  String get ditTicketIsOpgelost => 'This ticket has been resolved';
  @override
  String get documentGepload => 'Document uploaded.';
  @override
  String get documentGeploadWeControlerenHetZoSnelMogelijk => 'Document uploaded! We will review it as soon as possible.';
  @override
  String get documentenNogNietCompleetOpgeslagenVulVerplichteVeldenIn => 'Documents not yet fully saved. Fill in required fields.';
  @override
  String get doelen => 'Goals';
  @override
  String get doelenstatus => 'Goal status';
  @override
  String get doorgangGarantie => 'Continuation guarantee';
  @override
  String get dossierIsAlleenlezenUpgradeNaarProOmTeBewerken => 'Dossier is alleen-lezen. Upgrade naar Pro om te bewerken.';
  @override
  String get dossierStatus => 'Dossier status';
  @override
  String get downloadDeFactuurDirectAlsPdfDeLinkKanNaVerloopVanTijdVerlopen => 'Download the invoice as PDF. The link may expire.';
  @override
  String get downloadDePdfDirectNaOpenen => 'Download the PDF immediately after opening.';
  @override
  String get downloadQr => 'Download QR';
  @override
  String get duoTraining => 'Duo training';
  @override
  String get duur => 'Duration';
  @override
  String get duurminuten => 'Duration (minutes)';
  @override
  String get egFf6b6b => 'e.g. FF6B6B';
  @override
  String get eind => 'End';
  @override
  String get embedCode => 'Embed code';
  @override
  String get energie15 => 'Energy (1-5)';
  @override
  String get erZijnMomenteelGeenGroepslessenGeplandInDeGekozenPeriode => 'There are currently no group sessions scheduled in the selected period.';
  @override
  String get erZijnMomenteelGeenGroepslessenGeplandninDeKomende60Dagen => 'There are currently no group sessions scheduled in the next 60 days.';
  @override
  String get etalageOpgeslagen => 'Storefront saved';
  @override
  String get factuurIsAangemaaktMaarPdflinkOntbreektVersturenIsGeblokkeerdTotPdfBeschikbaarIs => 'Invoice created but PDF link missing. Sending blocked until PDF is available.';
  @override
  String get factuurbedragMoetGroterZijnDan0 => 'Invoice amount must be greater than 0';
  @override
  String get factuurid => 'Invoice ID';
  @override
  String get failedToSaveBranding => 'Failed to save branding';
  @override
  String get favorieten => 'Favorites';
  @override
  String get featuresOpgeslagen => 'Features saved';
  @override
  String get feeType => 'Fee type';
  @override
  String get feebeheer => 'Fee management';
  @override
  String get feedbackEnNotitiesVanJeTrainerNaEenSessie => 'Feedback and notes from your trainer after a session.';
  @override
  String get filters => 'Filters';
  @override
  String get focusVanSessie => 'Session focus';
  @override
  String get foutBijLadenGeschiedenis => 'Error loading history';
  @override
  String get foutBijLadenStatistieken => 'Error loading statistics';
  @override
  String get foutBijVerstureninplannenNieuwsbrief => 'Error sending/scheduling newsletter';
  @override
  String get gaNaarOntdekkenOmEenTrainerTeBoeken => 'Ga naar Ontdekken om een trainer te boeken';
  @override
  String get gaatDoor => 'Goes ahead!';
  @override
  String get galerij => 'Gallery';
  @override
  String get geannuleerd => 'Cancelled';
  @override
  String get geblokkeerdeDagen => 'Blocked days';
  @override
  String get geblokkeerduitzondering => 'Blocked (exception)';
  @override
  String get gebruikCode => 'Use code';
  @override
  String get geenAfstandsfilter => 'No distance filter';
  @override
  String get geenBetaaldeSessies => 'No paid sessions';
  @override
  String get geenBetaalurlOntvangenProbeerOpnieuw => 'No payment URL received. Try again.';
  @override
  String get geenDownloadlinkBeschikbaar => 'No download link available.';
  @override
  String get geenGeschillen => 'No disputes';
  @override
  String get geenGrafiekdataVoorDezeMetriekJeTrainerKanDitInvullenViaHetDossier => 'Geen grafiekdata voor deze metriek. Je trainer kan dit invullen via het dossier.';
  @override
  String get geenGroepslessenGevonden => 'No group sessions found';
  @override
  String get geenInschrijvingen => 'No enrollments';
  @override
  String get geenKlantenGevonden => 'No clients found';
  @override
  String get geenKlantenGevondenVoorDitFilter => 'No clients found for this filter.';
  @override
  String get geenNieuwsbrievenVerzonden => 'No newsletters sent';
  @override
  String get geenNotities => 'No notes';
  @override
  String get geenOpenTickets => 'No open tickets';
  @override
  String get geenPlannenBeschikbaarLaadOpnieuw => 'No plans available. Reload.';
  @override
  String get geenSmartRebookAlertsnklantenVerschijnenHierAlsZeLangerDan7DagenGeenSessieHadden => 'No Smart Rebook alerts.\nClients appear here when they haven\'t had a session for more than 7 days.';
  @override
  String get geenSpecialisatiesToegevoegd => 'No specializations added';
  @override
  String get geenStandbyinschrijvingen => 'No standby enrollments';
  @override
  String get geenTrainersGevonden => 'No trainers found';
  @override
  String get geenUitbetalingsgeschiedenis => 'No payout history';
  @override
  String get geenWachtlijsten => 'No waiting lists';
  @override
  String get gegevensexportAangevraagdJeOntvangtEenEmail => 'Data export requested — you will receive an email';
  @override
  String get gekozenPakket => 'CHOSEN PACKAGE';
  @override
  String get geldigTot => 'Valid until';
  @override
  String get geldigVoor => 'Valid for';
  @override
  String get geldigheiddagen => 'Validity (days)';
  @override
  String get gelezen => 'Gelezen';
  @override
  String get gemiddeldeReactietijd2Uur => 'Average response time: ~2 hours';
  @override
  String get geschiedenis => 'History';
  @override
  String get geschil => 'Dispute';
  @override
  String get geschilIndienen => 'File dispute';
  @override
  String get geschillen => 'Disputes';
  @override
  String get gesprekVerwijderd => 'Conversation deleted';
  @override
  String get gewicht => 'Weight';
  @override
  String get googlePreview => 'Google Preview';
  @override
  String get groepsles => 'Group session';
  @override
  String get groepslesAangemaakt => 'Group session created!';
  @override
  String get groepslessen => 'Group sessions';
  @override
  String get gymnaam => 'Gym name';
  @override
  String get handmatigeCheckin => 'Manual check-in';
  @override
  String get heartbeatActiefElke2Min => 'Heartbeat active · every 2 min';
  @override
  String get hebJeEenKortingscode => 'Have a discount code?';
  @override
  String get herinner => 'Remind';
  @override
  String get hierVerschijnenJeTicketsWanneernjeContactOpneemt => 'Your tickets will appear here when\nyou contact us.';
  @override
  String get hoeKunnenWeJeHelpen => 'How can we help you?';
  @override
  String get hoeVerdienJePunten => 'HOW DO YOU EARN POINTS?';
  @override
  String get hoekafronding => 'Corner rounding';
  @override
  String get hoeveelDagenVanTevorenKanEenKlantEenSessieBoeken => 'How many days in advance can a client book a session?';
  @override
  String get hoeveelSessiesPerWeek => 'Hoeveel sessies per week?';
  @override
  String get https => 'https://...';
  @override
  String get httpsyoutubecomwatchv => 'https://youtube.com/watch?v=...';
  @override
  String get huidigSaldo => 'Current balance';
  @override
  String get huidigWachtwoord => 'Current password';
  @override
  String get huiswerkActiepunt => 'Homework / action point';
  @override
  String get inactief => 'Inactive';
  @override
  String get inactieveKlanten => 'INACTIVE CLIENTS';
  @override
  String get inbox => 'Inbox';
  @override
  String get inchecken => 'Check in';
  @override
  String get ingecheckt => 'Checked in!';
  @override
  String get ingeschreven => 'Enrolled';
  @override
  String get inplannen => 'Schedule';
  @override
  String get inschrijvingAnnuleren => 'Cancel enrollment';
  @override
  String get inschrijvingGeannuleerd => 'Enrollment cancelled';
  @override
  String get instellingen => 'Instellingen';
  @override
  String get instellingenOpgeslagen => 'Settings saved';
  @override
  String get instellingenOpslaan => 'Save settings';
  @override
  String get interneTrainernotities => 'Internal trainer notes';
  @override
  String get introVideo => 'Intro Video';
  @override
  String get issue => 'Issue';
  @override
  String get jaBetaald => 'Yes, paid';
  @override
  String get jeAccountIsKlaarJeKuntNuSessiesAanbieden => 'Your account is ready. You can now offer sessions.';
  @override
  String get jeHebtJeNogNietIngeschrevenVoorEenGroepsles => 'You have not yet enrolled in a group session.';
  @override
  String get jeMoetAkkoordGaanMetDeAlgemeneVoorwaarden => 'Je moet akkoord gaan met de Algemene voorwaarden.';
  @override
  String get jeMoetAkkoordGaanMetHetPrivacybeleid => 'Je moet akkoord gaan met het Privacybeleid.';
  @override
  String get jePlekIsGereserveerdJeOntvangtEenMeldingZodraDeLesDoorgaat => 'Your spot is reserved. You will receive a notification when the session takes place.';
  @override
  String get jeProfiteertAlVanDezeActie => 'You are already benefiting from this promotion!';
  @override
  String get jeSessieIsBevestigd => 'Je sessie is bevestigd';
  @override
  String get jeStaatNuOpDeStandbylijstVoorDezeTrainer => 'You are now on the standby list for this trainer';
  @override
  String get jeStaatOpDeStandbylijstVanDeVolgendeTrainersZodraErPlekVrijkomtKrijgJeEenMelding => 'You are on the standby list of the following trainer(s). When a spot opens up, you will be notified.';
  @override
  String get jeTrainerDeeltNogGeenProgressieBijProtrainersZieJeHierJeStreakDoelenEnOntwikkeling => 'Your trainer hasn\'t shared any progress yet. With Pro trainers, you\'ll see your streak, goals and development here.';
  @override
  String get jeWordtDoorgestuurdNaarDeBetaalpagina => 'You will be redirected to the payment page...';
  @override
  String get jeWordtDoorgestuurdNaarDeBetaalpaginaNaBetalingKeerJeTerugNaarDeApp => 'You will be redirected to the payment page. After payment, you return to the app.';
  @override
  String get jeZietHierAlleenOpenbareProfielinformatie => 'You only see public profile information here.';
  @override
  String get jouwPersoonlijkeFitnessJourneyBegintHiern => 'Your personal fitness journey starts here.\n';
  @override
  String get jouwPubliekeProfiel => 'Your public profile';
  @override
  String get jouwSlug => 'Your slug';
  @override
  String get jouwnaam => 'yourname';
  @override
  String get kanDeQrNietGescandWordenGeefDezeCodeAanJeTrainer => 'Can\'t scan the QR? Give this code to your trainer.';
  @override
  String get kies => 'Choose';
  @override
  String get kiesDeDagEnTijdenJeBeschikbaarheidGeldtAutomatischVoorAlleWeken => 'Choose the day and times. Your availability applies automatically to all weeks.';
  @override
  String get kiesEenDatum => 'CHOOSE A DATE';
  @override
  String get kiesEenDatumEnTijd => 'Choose a date and time';
  @override
  String get kiesEenPakket => 'Choose a package';
  @override
  String get kiesEenPlan => 'Choose a plan';
  @override
  String get kiesEenSterkWachtwoordVanMinimaal8TekensMetLettersEnCijfers => 'Choose a strong password of at least 8 characters with letters and numbers.';
  @override
  String get kiesEenTemplate => 'Choose a template';
  @override
  String get kiesEenTijdstip => 'CHOOSE A TIME';
  @override
  String get kiesHoeKlantenJeKunnenBetalen => 'Choose how clients can pay you';
  @override
  String get kiesJeGymiesplan => 'Choose your Gymies plan';
  @override
  String get kiesKlantVoorDossier => 'Choose client for dossier';
  @override
  String get kiesLesvorm => 'Choose session type';
  @override
  String get kiesSpecialiteit => 'Choose specialization';
  @override
  String get kiesStad => 'Choose city';
  @override
  String get kiesUitJeFotorol => 'Choose from your photo library';
  @override
  String get klantToevoegenKomtBinnenkort => 'Add client coming soon';
  @override
  String get klanten => 'Clients';
  @override
  String get klantenReserverenEenPlekPasAlsHetMinimumBereiktIsWordtDeBetaallinkVerstuurd => 'Clients reserve a spot. Only when the minimum is reached, the payment link is sent.';
  @override
  String get klantidOntbreekt => 'Client ID missing.';
  @override
  String get komJeErNietUit => 'Can\'t figure it out?';
  @override
  String get konBerichtNietVersturen => 'Could not send message.';
  @override
  String get konBoekingenNietLaden => 'Could not load bookings';
  @override
  String get konExportNietAanvragenProbeerLaterOpnieuw => 'Could not request export. Try again later.';
  @override
  String get konGeschilNietIndienen => 'Could not submit dispute.';
  @override
  String get konGesprekNietVerwijderen => 'Could not delete conversation';
  @override
  String get konKaartenappNietOpenen => 'Could not open maps app.';
  @override
  String get konPdfNietOpenen => 'Could not open PDF.';
  @override
  String get konSessiesNietLaden => 'Could not load sessions';
  @override
  String get konTicketNietLaden => 'Could not load ticket';
  @override
  String get konVerwijderaanvraagNietIndienenProbeerLaterOpnieuw => 'Could not submit deletion request. Try again later.';
  @override
  String get konWachtwoordNietWijzigenProbeerLaterOpnieuw => 'Could not change password. Try again later.';
  @override
  String get kopieerEmbed => 'Copy embed';
  @override
  String get kopieerEmbedCode => 'Copy embed code';
  @override
  String get kopieerLink => 'Copy link';
  @override
  String get kopieerProfielUrl => 'Copy profile URL';
  @override
  String get kopieerVoorDeAankomende => 'Copy for the upcoming';
  @override
  String get kopieerWidgetUrl => 'Copy widget URL';
  @override
  String get koppelJeMollieaccountZodatKlantenDirectAanJouKunnenBetalen => 'Connect your Mollie account so clients can pay you directly.';
  @override
  String get korteSamenvatting => 'Brief summary';
  @override
  String get krijgEtalagePromoCodesEnMeer => 'Krijg etalage, promo codes en meer';
  @override
  String get kvknummer => 'Chamber of Commerce number';
  @override
  String get kwartaalZipExport => 'Quarterly ZIP export';
  @override
  String get laatDezeQrcodeScannenDoorJeTrainer => 'Let your trainer scan this QR code';
  @override
  String get laatsteReview => 'Latest review';
  @override
  String get laatsteSupportverzoekAlsnogVerstuurd => 'Last support request sent after all';
  @override
  String get land => 'Country';
  @override
  String get lestype => 'Session type';
  @override
  String get locatie => 'Location';
  @override
  String get locatieToevoegen => 'Add location';
  @override
  String get locaties => 'Locations';
  @override
  String get logOpnieuwIn => 'Log in again';
  @override
  String get logistiek => 'Logistics';
  @override
  String get logo => 'Logo';
  @override
  String get logoBanner => 'Logo & Banner';
  @override
  String get losseSessie => 'Single session';
  @override
  String get maakEenNieuweFoto => 'Take a new photo';
  @override
  String get max10mbJpgPngGifWebp => 'Max 10MB · JPG, PNG, GIF, WebP';
  @override
  String get max20mbJpgPngGifWebp => 'Max 20MB · JPG, PNG, GIF, WebP';
  @override
  String get maxDeelnemers => 'Max participants';
  @override
  String get maxInwisselingenleegOnbeperkt => 'Max. redemptions (empty = unlimited)';
  @override
  String get maxPrijsPerSessie => 'Max. price per session';
  @override
  String get maximaal20Specialisaties => 'Maximum 20 specializations';
  @override
  String get maximaal20SpecialisatiesBereikt => 'Maximum 20 specializations reached';
  @override
  String get maximumVan20SpecialisatiesBereikt => 'Maximum of 20 specializations reached.';
  @override
  String get mediaAlsFeaturedIngesteld => 'Media set as featured';
  @override
  String get mediaFeaturesZijnAlleenBeschikbaarVoorProEnProPlannen => 'Media features are only available for Pro and Pro+ plans.';
  @override
  String get mediaIsNietBeschikbaarVoorStarterPlanUpgradeNaarPro => 'Media is not available for Starter plan. Upgrade to Pro.';
  @override
  String get mediaToegevoegd => 'Media added';
  @override
  String get mediaVerwijderd => 'Media removed';
  @override
  String get meerActies => 'More actions';
  @override
  String get meerData => 'More dates';
  @override
  String get meerLaden => 'Load more';
  @override
  String get melden => 'Report';
  @override
  String get meldingVoorkeuren => 'Notification preferences';
  @override
  String get meldingen => 'Notifications';
  @override
  String get metaBeschrijving => 'Meta description';
  @override
  String get metaTitel => 'Meta title';
  @override
  String get middag => 'Afternoon';
  @override
  String get mijnDossier => 'My dossier';
  @override
  String get mijnFacturen => 'My invoices';
  @override
  String get mijnGroepslessen => 'My group sessions';
  @override
  String get mijnInschrijvingen => 'My enrollments';
  @override
  String get mijnTegoed => 'My balance';
  @override
  String get mijnTrainers => 'My trainers';
  @override
  String get mijnWachtlijsten => 'My waiting lists';
  @override
  String get min3TekensKleineLettersCijfersEnStreepjes => 'Min. 3 characters. Lowercase letters, numbers and hyphens.';
  @override
  String get minBeoordeling => 'Min. rating';
  @override
  String get minDeelnemersVoorDoorgang => 'Min. participants for continuation';
  @override
  String get minimaal8Tekens => 'Minimum 8 characters';
  @override
  String get mollieConnect => 'Mollie connect';
  @override
  String get mollieConnectStarten => 'Start Mollie Connect';
  @override
  String get mollieKoppelen => 'Connect Mollie';
  @override
  String get naHoeveelDagenInactiviteitOntvangenKlantenAutomatischEenHerinnering => 'After how many days of inactivity do clients automatically receive a reminder?';
  @override
  String get naVersturenMoetDeKlantDePdfDirectDownloaden => 'After sending, the client must download the PDF immediately.';
  @override
  String get naam => 'Name';
  @override
  String get naamIsVerplichtVoorEenLocatie => 'Name is required for a location.';
  @override
  String get naarDashboard => 'To Dashboard';
  @override
  String get nietBeschikbaar => 'Not available';
  @override
  String get nietGevondenWatJeZocht => 'Didn\'t find what you were looking for?';
  @override
  String get nietIngesteld => 'Not set';
  @override
  String get nietopgeslagenWijzigingen => 'Unsaved changes';
  @override
  String get nieuwGesprekStartenKomtBinnenkort => 'Nieuw gesprek starten komt binnenkort';
  @override
  String get nieuwSupportverzoek => 'New support request';
  @override
  String get nieuwVerzoekAanmaken => 'Create new request';
  @override
  String get nieuwWachtwoord => 'New password';
  @override
  String get nieuweBoekingenAutomatischAanJeKalenderToevoegen => 'Automatically add new bookings to your calendar';
  @override
  String get nieuweQrGenereren => 'Generate new QR';
  @override
  String get nieuwsbrief => 'Nieuwsbrief';
  @override
  String get nogGeenBerichten => 'No messages yet';
  @override
  String get nogGeenBioToegevoegd => 'No bio added yet.';
  @override
  String get nogGeenCoachNotesJeTrainerKanNaEenSessieNotitiesMetJeDelen => 'No coach notes yet. Your trainer can share notes with you after a session.';
  @override
  String get nogGeenDoelenIngesteldDoorJeTrainerDoelenVerschijnenHierZodraJeTrainerZeVoorJeInvult => 'No goals set by your trainer yet. Goals appear here once your trainer fills them in for you.';
  @override
  String get nogGeenDossiers => 'No dossiers yet';
  @override
  String get nogGeenHealthScoreDataBeschikbaar => 'No health score data available yet.';
  @override
  String get nogGeenLocaties => 'No locations yet';
  @override
  String get nogGeenMediaToegevoegd => 'No media added yet.';
  @override
  String get nogGeenPubliekeBeschikbaarheid => 'No public availability yet.';
  @override
  String get nogGeenPubliekePakketten => 'No public packages yet.';
  @override
  String get nogGeenReviews => 'No reviews yet';
  @override
  String get nogGeenReviewsBeschikbaar => 'No reviews available yet.';
  @override
  String get nogGeenScans => 'No scans yet';
  @override
  String get nogGeenSessieentries => 'No session entries yet.';
  @override
  String get nogGeenSupportverzoeken => 'No support requests yet';
  @override
  String get nogGeenTransacties => 'No transactions yet';
  @override
  String get nogGeenUpsellSuggestiesBeschikbaar => 'No upsell suggestions available yet.';
  @override
  String get nogGeenVerkopen => 'No sales yet';
  @override
  String get nogNiemandOpDeWachtlijst => 'No one on the waiting list yet';
  @override
  String get nogNietGepload => 'Not yet uploaded';
  @override
  String get noshowInWachtrijGeplaatstWordtOpnieuwVerstuurd => 'No-show queued. Will be resent.';
  @override
  String get noshowRegistreren => 'Register no-show';
  @override
  String get notitieVoorTrainerToevoegen => 'Add note for trainer...';
  @override
  String get notitieoptioneel => 'Note (optional)';
  @override
  String get nuVersturen => 'Send now';
  @override
  String get ochtend => 'Morning';
  @override
  String get ofVoerJeEigenKleurIn => 'Or enter your own color:';
  @override
  String get omzetVerdeling => 'Revenue distribution';
  @override
  String get onboardingStatus => 'Onboarding status';
  @override
  String get onboardingVoltooid => 'Onboarding completed!';
  @override
  String get ondersteundeKalenders => 'Supported calendars:';
  @override
  String get onderwerp => 'Subject';
  @override
  String get ongeldigeSlugGebruikKleineLettersCijfersEnStreepjes => 'Invalid slug. Use lowercase letters, numbers and hyphens.';
  @override
  String get ongelezen => 'Ongelezen';
  @override
  String get onlineBetalen => 'Pay online';
  @override
  String get onlineSessie => 'Online session';
  @override
  String get onlineThuisGymAfhankelijkVanAfspraak => 'Online / home / gym depending on appointment';
  @override
  String get onlinemollie => 'Online (Mollie)';
  @override
  String get ontdekTrainers => 'Ontdek trainers';
  @override
  String get ontdekTrainersBijJouInDeBuurt => 'Ontdek trainers bij jou in de buurt';
  @override
  String get ontdekken => 'Discover';
  @override
  String get ontvangBetalingenDirectOpJeRekening => 'Receive payments directly in your account';
  @override
  String get opStandbylijst => 'On standby list';
  @override
  String get openEenKlantEnMaakDeEersteSessieentryprogressAan => 'Open a client and create the first session entry/progress.';
  @override
  String get openGerelateerdePagina => 'Open related page';
  @override
  String get openstaand => 'Outstanding';
  @override
  String get opgesteldeDossiers => 'Created dossiers';
  @override
  String get opnieuw => 'Retry';
  @override
  String get opnieuwProberen => 'Try again';
  @override
  String get opnieuwZoeken => 'Search again';
  @override
  String get opslaan => 'Save';
  @override
  String get opslaanMisluktControleerBackend => 'Save failed. Check backend.';
  @override
  String get opslaanMisluktProbeerHetOpnieuw => 'Save failed. Try again.';
  @override
  String get opstellenVersturen => 'Compose & send';
  @override
  String get optioneel => 'Optional';
  @override
  String get optioneleNotitie => 'Optional note...';
  @override
  String get opzeggen => 'Cancel subscription';
  @override
  String get overMij => 'About me';
  @override
  String get overslaanMag => 'Skipping is allowed';
  @override
  String get overslaanVoorNu => 'Skip for now';
  @override
  String get overzichtVoorVandaag => 'Overview for today';
  @override
  String get pakket => 'Package';
  @override
  String get pakketPrestaties => 'Package performance';
  @override
  String get pakkettenBijnaVerlopen => 'PACKAGES EXPIRING SOON';
  @override
  String get pdfDownloaden => 'Download PDF';
  @override
  String get pdfLinkIsOngeldig => 'PDF link is invalid.';
  @override
  String get pdfOntbreektOpServerEerstPdfLatenGenererenDaarnaVersturen => 'PDF missing on server. First generate PDF, then send.';
  @override
  String get percentage => 'Percentage';
  @override
  String get performanceScore => 'Performance score';
  @override
  String get performanceSummary => 'Performance summary';
  @override
  String get periode => 'Period';
  @override
  String get personalTraining => 'Personal training';
  @override
  String get plan => 'Plan';
  @override
  String get postcode => 'Postal code';
  @override
  String get prestatie => 'Achievement';
  @override
  String get prijsInclBtweur => 'Price incl. VAT (EUR)';
  @override
  String get prijsOpAanvraag => 'Price on request';
  @override
  String get prijsPerPersoon => 'Price per person (€)';
  @override
  String get prijseur => 'Price (EUR)';
  @override
  String get prioritySupportTicketVerstuurd => 'Priority support ticket sent';
  @override
  String get privacyGegevens => 'Privacy & data';
  @override
  String get pro => 'Pro';
  @override
  String get profielDelen => 'Share profile';
  @override
  String get profielMelden => 'Report profile';
  @override
  String get profielOpgeslagen => 'Profile saved';
  @override
  String get profielOpslaan => 'Save profile';
  @override
  String get profielfotoBijgewerkt => 'Profile photo updated';
  @override
  String get profielfotoKiezen => 'Choose profile photo';
  @override
  String get profielgegevens => 'Profile details';
  @override
  String get profielurl => 'Profile URL';
  @override
  String get profileUrlUseOnlyLowercaseLettersNumbersAndHyphens => 'Profile URL: use only lowercase letters, numbers, and hyphens';
  @override
  String get progressieRitme => 'Progress & rhythm';
  @override
  String get promocode => 'Promo code';
  @override
  String get promocodeoptioneel => 'Promo code (optional)';
  @override
  String get publiceren => 'Publish';
  @override
  String get puntenIngewisseld => 'Points redeemed!';
  @override
  String get puntenInwisselen => 'Redeem points';
  @override
  String get qrCodeNietBeschikbaar => 'QR code not available';
  @override
  String get qrcodeDownloadKomendeVersie => 'QR code download coming version';
  @override
  String get qrcodeGenereren => 'Generating QR code...';
  @override
  String get reactieVerstuurd => 'Reply sent';
  @override
  String get recent => 'Recent';
  @override
  String get recenteScans => 'Recent scans';
  @override
  String get reden => 'Reason';
  @override
  String get redenoptioneel => 'Reason (optional)';
  @override
  String get referralVoordeelBeschikbaar => 'Referral benefit available';
  @override
  String get restitutiepercentage => 'Refund percentage';
  @override
  String get reviewsGalerijPakkettenEnMeer => 'Reviews, gallery, packages and more';
  @override
  String get safeSessionActief => 'Safe session active';
  @override
  String get safeSessionStarten => 'Start safe session';
  @override
  String get scanDeQrcodeVanJeKlant => 'Scan your client\'s QR code';
  @override
  String get schrijfMinimaal10Tekens => 'Write at least 10 characters';
  @override
  String get selecteer => 'Select';
  @override
  String get seoOpgeslagen => 'SEO saved';
  @override
  String get seoScore => 'SEO Score';
  @override
  String get serviceDatum => 'Service date';
  @override
  String get sessie => 'Session';
  @override
  String get sessieBegintZo => 'Session starting soon';
  @override
  String get sessieBeindigen => 'End session?';
  @override
  String get sessieVerplaatsen => 'Reschedule session';
  @override
  String get sessieentryOpgeslagen => 'Session entry saved';
  @override
  String get sleepItemsOmDeVolgordeTeWijzigen => 'Drag items to change the order';
  @override
  String get slimmeRemindersT24uT2uCheckinVensterOpenEnGemisteCheckin => 'Smart reminders: T-24h, T-2h, check-in window open and missed check-in.';
  @override
  String get snelNaar => 'Snel naar';
  @override
  String get socialMediaOpgeslagen => 'Social media saved';
  @override
  String get sorteer => 'Sort';
  @override
  String get sorterenOp => 'Sort by';
  @override
  String get sosHulpNodig => 'SOS – Need help';
  @override
  String get sosalertVerstuurdJeNoodcontactIsOpDeHoogte => 'SOS alert sent. Your emergency contact has been notified.';
  @override
  String get specialisaties => 'Specializations';
  @override
  String get specialiteitenTariefBioEnMediaKunJeAanpassenInDeEtalageeditor => 'Specializations, rate, bio and media can be adjusted in the Storefront editor.';
  @override
  String get stad => 'Stad';
  @override
  String get standbyinschrijvingVerwijderd => 'Standby enrollment removed';
  @override
  String get start => 'Start';
  @override
  String get startEenGesprekMetOnsTeam => 'Start a conversation with our team';
  @override
  String get startEerstEenChatOfSessieMetEenKlant => 'Start a chat or session with a client first.';
  @override
  String get startMetEenVoorgeschrevenMail => 'Start with a pre-written email';
  @override
  String get starter => 'Starter';
  @override
  String get status => 'Status';
  @override
  String get statusWijzigen => 'Change status';
  @override
  String get stelJeTrainingslocatieTrainingsvormenEnAanbiedingenIn => 'Set your training location, training types and offers';
  @override
  String get stelJeUurtariefInVoorIndividueleSessies => 'Set your hourly rate for individual sessions';
  @override
  String get stelnKeerInEnPasToeOpAlleDagenGeldtVoorAlleWeken => 'Set once and apply to all days. Applies to all weeks.';
  @override
  String get stilleUren => 'Stille uren';
  @override
  String get stories => 'Stories';
  @override
  String get storiesIsEenProFeatureUpgradeJeAbonnement => 'Stories is a Pro feature. Upgrade your subscription.';
  @override
  String get storyGeplaatstZichtbaarVoor24Uur => 'Story posted! Visible for 24 hours.';
  @override
  String get straatEnHuisnummer => 'Street and house number';
  @override
  String get studio => 'Studio';
  @override
  String get stuur => 'Send';
  @override
  String get stuurEenBerichtNaarAlJeKlantenTegelijk => 'Send a message to all your clients at once.';
  @override
  String get stuurOnsEenBericht => 'Send us a message';
  @override
  String get stuurVoorstel => 'Send proposal';
  @override
  String get supportBlijftGekoppeldAanDeTrainersessiecontextVanJeVerzoek => 'Support remains linked to the trainer/session context of your request.';
  @override
  String get supportverzoekAangemaakt => 'Support request created!';
  @override
  String get supportverzoekMislukt => 'Support request failed';
  @override
  String get tarievenOpgeslagen => 'Rates saved';
  @override
  String get tarievenindicatie => 'Rates (indication)';
  @override
  String get terug => 'Back';
  @override
  String get ticketIsAfgerondEnKanNietMeerWordenBeantwoord => 'Ticket is completed and can no longer be answered.';
  @override
  String get ticketsVanKlantenEnTrainersBeantwoorden => 'Answer tickets from clients and trainers';
  @override
  String get tijd => 'Time';
  @override
  String get tijden => 'Times';
  @override
  String get tijdslot => 'Time slot';
  @override
  String get tikOmAanTePassen => 'Tap to adjust';
  @override
  String get tikOmFotoTeWijzigen => 'Tap to change photo';
  @override
  String get tikOmOpnieuwTeVersturen => 'Tap to resend';
  @override
  String get tikOmTeBewerkenu00b7LangIndrukkenOmTeVerwijderen => 'Tap to edit · long press to delete';
  @override
  String get tip => 'TIP';
  @override
  String get tipJeKuntOokHandmatigEenSessieAanJeAgendaToevoegenViaDeActieknopBijElkeBoeking => 'Tip: You can also manually add a session to your calendar via the action button on each booking.';
  @override
  String get titel => 'Title';
  @override
  String get tochVerplaatsen => 'Reschedule anyway';
  @override
  String get toegestaneFormatenPdfJpgPngmax10mbPerBestand => 'Allowed formats: PDF, JPG, PNG (max 10MB per file)';
  @override
  String get toelaten => 'Admit';
  @override
  String get toelichtingoptioneel => 'Explanation (optional)';
  @override
  String get toevoegen => 'Add';
  @override
  String get toonBeschikbaarheid => 'Show availability';
  @override
  String get toonEenIntroductievideoOpJeProfielOndersteuntYoutubeEnVimeo => 'Show an intro video on your profile. Supports YouTube and Vimeo.';
  @override
  String get toonMeer => 'Show more';
  @override
  String get toonPrijs => 'Show price';
  @override
  String get toonReviews => 'Show reviews';
  @override
  String get topKlanten => 'Top clients';
  @override
  String get totaal => 'Total';
  @override
  String get trainerUitbetalingen => 'Trainer Payouts';
  @override
  String get trainerUserId => 'Trainer user ID';
  @override
  String get traineridOntbreekt => 'Trainer-ID ontbreekt';
  @override
  String get trends => 'Trends';
  @override
  String get typEenBericht => 'Type a message...';
  @override
  String get typJeAntwoord => 'Type your answer...';
  @override
  String get typJeOnderwerpHier => 'Type your subject here...';
  @override
  String get type => 'Type';
  @override
  String get uitInternTraineronlyNotitie => 'Off = internal trainer-only note';
  @override
  String get uitloggen => 'Log out';
  @override
  String get uitzonderingenoptioneel => 'Exceptions (optional)';
  @override
  String get upgradeNaarPro => 'Upgrade to Pro';
  @override
  String get uploadMisluktProbeerOpnieuw => 'Upload failed. Try again.';
  @override
  String get upsellVoorstelVerstuurd => 'Upsell proposal sent';
  @override
  String get uurtarief => 'Hourly rate';
  @override
  String get vanaf => 'From';
  @override
  String get vastBedrag => 'Fixed amount';
  @override
  String get verificatie => 'Verification';
  @override
  String get verificatieAangevraagd => 'Verification requested!';
  @override
  String get verificatieAanvragenMisluktProbeerHetLaterOpnieuw => 'Verification request failed. Try again later.';
  @override
  String get verificatieStatus => 'Verification status';
  @override
  String get verificatieaanvraagVerstuurdGymiesBeoordeeltJeProfiel => 'Verification request sent! Gymies will review your profile.';
  @override
  String get verlopendePakketten => 'Expiring packages';
  @override
  String get verplaats => 'Reschedule';
  @override
  String get verplaatsen => 'Reschedule';
  @override
  String get verplaatsenMisluktProbeerHetOpnieuw => 'Reschedule failed. Try again.';
  @override
  String get verplaatsingsverzoekVerstuurd => 'Reschedule request sent';
  @override
  String get verstrekenTijd => 'Elapsed time';
  @override
  String get versturen => 'Sending…';
  @override
  String get versturenMisluktProbeerOpnieuw => 'Send failed, try again.';
  @override
  String get verstuurVerzoek => 'Submit request';
  @override
  String get vervaldatum => 'Expiry date';
  @override
  String get verwijderUitMijnTrainers => 'Remove from my trainers';
  @override
  String get verwijderen => 'Delete';
  @override
  String get verwijderenMisluktProbeerOpnieuw => 'Delete failed. Try again.';
  @override
  String get verzendtijd => 'Send time';
  @override
  String get verzoekNietVerstuurd => 'Request not sent';
  @override
  String get videoKanNietWordenAfgespeeld => 'Video cannot be played';
  @override
  String get videoKonNietWordenGelezenKiesEenAndere => 'Video could not be read. Choose another.';
  @override
  String get videoMagMax30SecondenZijnOpJeProfiel => 'Video may be max. 30 seconds on your profile.';
  @override
  String get videoToegevoegd => 'Video added';
  @override
  String get videoVerwijderd => 'Video removed';
  @override
  String get vindEenAntwoordOfNeemContactOp => 'Find an answer or contact us';
  @override
  String get voegDoelenToeViaBackendOfVolgendeIteratieUi => 'Add goals via backend or next iteration UI.';
  @override
  String get voegVestigingenToeWaarJeGymActiefIs => 'Add locations where your gym is active.';
  @override
  String get voerDe6cijferigeBackupCodeInDieDeKlantOpHetSchermHeeftStaan => 'Enter the 6-digit backup code shown on the client\'s screen.';
  @override
  String get voerEenGeldigeYoutubeOfVimeoUrlIn => 'Enter a valid YouTube or Vimeo URL.';
  @override
  String get voerEenSpecialisatieIn => 'Enter a specialization';
  @override
  String get vogLinkoptioneel => 'Background check link (optional)';
  @override
  String get vol => 'FULL';
  @override
  String get volgendeWeek => 'Next week';
  @override
  String get voltooien => 'Complete';
  @override
  String get voorUrgenteOperationeleIssuesMetContextpakket => 'For urgent operational issues with context package.';
  @override
  String get voorUrgenteOperationeleIssuesMetContextpakketissueBookingRefs => 'For urgent operational issues with context package (issue + booking refs).';
  @override
  String get voorbeeld => 'Example';
  @override
  String get voorbeeldBekijken => 'Preview';
  @override
  String get voorbeeldEmail => 'Example email';
  @override
  String get vraagAan => 'Request';
  @override
  String get vulEenOnderwerpIn => 'Enter a subject';
  @override
  String get vulJeEmailEnWachtwoordIn => 'Vul je e-mail en wachtwoord in';
  @override
  String get vulJeEmailadresInWeSturenJeEenLinkOmJeWachtwoordTeResetten => 'Vul je e-mailadres in. We sturen je een link om je wachtwoord te resetten.';
  @override
  String get vulNaamEenGeldigAantalSessiesEnEenGeldigePrijsInbijv4999 => 'Enter name, valid number of sessions and valid price (e.g. 49.99)';
  @override
  String get waaromVerificatie => 'Why verification?';
  @override
  String get wachtOpReactieVanSupport => 'Waiting for support response';
  @override
  String get wachtlijst => 'Wachtlijst';
  @override
  String get wachtwoordSuccesvolGewijzigd => 'Password successfully changed';
  @override
  String get wachtwoordWijzigen => 'Change password';
  @override
  String get watGingGoed => 'What went well?';
  @override
  String get watIsJeDoel => 'Wat is je doel?';
  @override
  String get watToonJeOpJeProfiel => 'What do you show on your profile?';
  @override
  String get weMissenJe => 'We miss you';
  @override
  String get weMissenJeberichtVerstuurd => 'We miss you message sent';
  @override
  String get weekdoelInstellen => 'Weekdoel instellen';
  @override
  String get weergavenaam => 'Display name';
  @override
  String get weesDeEersteDieEenBeoordelingAchterlaatNaEenSessie => 'Be the first to leave a review after a session.';
  @override
  String get weetJeZekerDatJeDezeFeeSettingWiltVerwijderen => 'Weet je zeker dat je deze fee setting wilt verwijderen?';
  @override
  String get weetJeZekerDatJeDezeSessieWiltAnnuleren => 'Weet je zeker dat je deze sessie wilt annuleren?';
  @override
  String get wekelijkseTijdslots => 'Weekly time slots';
  @override
  String get widgetAanpassen => 'Customize widget';
  @override
  String get widgetHoogte => 'Widget height';
  @override
  String get widgetInstellingenOpgeslagen => 'Widget settings saved!';
  @override
  String get widgetPreview => 'Widget preview';
  @override
  String get widgetStatistieken => 'Widget statistics';
  @override
  String get wieBetaaltDeFee => 'Who pays the fee?';
  @override
  String get wis => 'Clear';
  @override
  String get wisAlles => 'Clear all';
  @override
  String get youtubeOfVimeoUrl => 'YouTube or Vimeo URL';
  @override
  String get zichtbaarheidElementen => 'Element visibility';
  @override
  String get zoKunnenTrainersJeBeterVindennditIsOptioneelJeKuntHetLaterAanpassen => 'This way trainers can find you better.\nThis is optional — you can adjust it later.';
  @override
  String get zoekEenTrainer => 'Find a trainer';
  @override
  String get zoekGebruikeremailNaam => 'Search user (email, name)';
  @override
  String get zoekGesprekken => 'Search conversations...';
  @override
  String get zoekInNotities => 'Search in notes...';
  @override
  String get zoekKlant => 'Search client...';
  @override
  String get zoekKlantOpNaamOfEmail => 'Search client by name or email';
  @override
  String get zoekOpKlantOfLaatsteBericht => 'Search by client or last message';
  @override
  String get zoekOpNaamSpecialiteitOfRegio => 'Search by name, specialization or region';
  @override
  String get zoekTrainerSpecialismeOfStad => 'Search trainer, specialization or city...';
  @override
  String get zoekenOpTrainernaam => 'Search by trainer name...';

  // ═══ APOSTROPHE VARIANTS ═══
  @override
  String get alleenDezeKlantKanDezeVideos => 'Only this client can see these videos';
  @override
  String get fotos => 'Photos';
  @override
  String get instructievideos => 'Instruction videos';
  @override
  String get nogGeenVideos => 'No videos yet';
  @override
  String get ontdekTrainersInJouwBuurtEnBoeknjeEersteSessieLets => 'Discover trainers in your area and book\nyour first session. Let\'s go!';
  @override
  String get videos => 'Videos';
  @override
  String get voegFotos => 'Add photos';
  @override
  String get voegInstructievideos => 'Add instruction videos';

  // ═══ PHASE 3 BULK KEYS ═══
  @override
  String get aanmeldenVoorNieuwsbrief => 'Aanmelden voor nieuwsbrief';
  @override
  String get abonnementOpgezegd => 'Abonnement opgezegd';
  @override
  String get abonnementOpzeggen => 'Abonnement opzeggen?';
  @override
  String get accepteertAlleenCash => 'Accepteert alleen cash';
  @override
  String get accepteertAlleenOverboekingen => 'Accepteert alleen overboekingen';
  @override
  String get accepteertOverboekingenCash => 'Accepteert overboekingen & cash';
  @override
  String get actieMisluktProbeerOpnieuw => 'Actie mislukt. Probeer opnieuw.';
  @override
  String get adresIsVerplicht => 'Adres is required';
  @override
  String get afgerondeSessiesVerschijnenHierAlsHistorie => 'Afgeronde sessies verschijnen hier als historie.';
  @override
  String get agendaIsLeeg => 'Agenda is leeg';
  @override
  String get alEenAccount => 'Al een account? ';
  @override
  String get alleAchtergrondactiesZijnGesynchroniseerd => 'Alle achtergrondacties zijn gesynchroniseerd.';
  @override
  String get alleMeldingenZijnGelezen => 'Alle meldingen zijn gelezen.';
  @override
  String get allebeiEenBeloningWanneerZijStarten => 'allebei een beloning wanneer zij starten!';
  @override
  String get alleenCash => 'Alleen cash';
  @override
  String get alleenDezeDag => 'Alleen deze dag';
  @override
  String get alleenOverboekingen => 'Alleen overboekingen';
  @override
  String get allesVanPro => 'Alles van Pro';
  @override
  String get allesVanStarter => 'Alles van Starter';
  @override
  String get alsDankVoorJeVertrouwenEn => 'Als dank voor je vertrouwen en inzet bieden we deze week:</p>';
  @override
  String get alsHetMinimumNietBereiktIs => 'Als het minimum niet bereikt is voor deze deadline, wordt de les automatisch geannuleerd.';
  @override
  String get amstelveen => 'amstelveen';
  @override
  String get annuleringsEnRestitutieregels => 'Annulerings- en restitutieregels';
  @override
  String get appIsGemanipuleerd => 'App is gemanipuleerd';
  @override
  String get autoherboekingenIngeschakeld => 'Auto-herboekingen ingeschakeld';
  @override
  String get autoherboekingenUitgeschakeld => 'Auto-herboekingen uitgeschakeld';
  @override
  String get backendEndpointNietBeschikbaarToonDefaults => 'Backend endpoint not available. Toon defaults.';
  @override
  String get basisVoorStartenAlsTrainer => 'Basis voor starten als trainer';
  @override
  String get bedanktDatJeGymiesGebruikt => 'Bedankt dat je GYMIES gebruikt!';
  @override
  String get bedanktVoorJeBeoordeling => 'Bedankt voor je beoordeling!';
  @override
  String get bedanktVoorVandaag => 'Bedankt voor vandaag!';
  @override
  String get bedrijfsnaamIsVerplicht => 'Bedrijfsnaam is required';
  @override
  String get beheerAanbod => 'Beheer aanbod';
  @override
  String get beheerJeSessiepakkettenEnStrippenkaarten => 'Beheer je sessie-pakketten en strippenkaarten';
  @override
  String get bekijkDeUpdatesEnZorgDat => 'Bekijk de updates en zorg dat je goed bent voorbereid voor je volgende sessies.</p>';
  @override
  String get bekijkTrendsOmzetverdelingEnExporteerData => 'Bekijk trends, omzetverdeling en exporteer data.';
  @override
  String get belangrijkUpdateVanJeTrainer => 'Belangrijk update van je trainer 📢';
  @override
  String get belangrijkUpdateVanJeTrainer2 => 'Belangrijk update van je trainer';
  @override
  String get beoordelingHoogNaarLaag => 'Beoordeling: hoog naar laag';
  @override
  String get beoordelingVersturenMisluktProbeerLaterOpnieuw => 'Beoordeling versturen mislukt. Probeer later opnieuw.';
  @override
  String get bereikJeDoelenMetPersoonlijkeBegeleiding => 'Bereik je doelen met persoonlijke begeleiding';
  @override
  String get berichtMagNietLangerZijnDan => 'Bericht mag niet langer zijn dan 2000 tekens';
  @override
  String get berichtMoetMinstens10TekensLang => 'Bericht moet minstens 10 tekens lang zijn';
  @override
  String get beschikbaarheidEnUitzonderingen => 'Beschikbaarheid en uitzonderingen';
  @override
  String get beschikbarePlannen => 'Beschikbare plannen';
  @override
  String get betaalEnAfronden => 'Betaal en afronden';
  @override
  String get betaald => 'Betaald';
  @override
  String get betaaldOp => 'Betaald op';
  @override
  String get betaaldeFacturenVerschijnenHierMetBetaalmethode => 'Betaalde facturen verschijnen hier met betaalmethode en referentie.';
  @override
  String get betaalstatusControleren => 'Betaalstatus controleren';
  @override
  String get betaling => 'betaling';
  @override
  String get betalingMislukt => 'Payment mislukt';
  @override
  String get betalingWordtVerwerktDeStatusWordt => 'Payment wordt verwerkt. De status wordt zo bijgewerkt.';
  @override
  String get bezig => 'Bezig…';
  @override
  String get bezig2 => 'Bezig...';
  @override
  String get bijvBijZiekteMetBewijsIs => 'bijv. Bij ziekte met bewijs is annulering gratis';
  @override
  String get bijvEersteSessie50Korting => 'bijv. Eerste sessie 50% korting';
  @override
  String get bijvPersonalTrainerAmsterdam => 'bijv. Personal trainer Amsterdam';
  @override
  String get bijvoorbeeldNieuwTrainingsschemaBeschikbaar => 'Bijvoorbeeld: "Nieuw trainingsschema beschikbaar"';
  @override
  String get blauwVinkjeOpJeProfiel => 'Blauw vinkje op je profiel';
  @override
  String get blijDatTeHorenJeMaakt => 'Blij dat te horen! Je maakt goede progressie.';
  @override
  String get blijTeHoren => 'Blij te horen!';
  @override
  String get blijfOpDeHoogteVanTips => 'Blijf op de hoogte van tips en aanbiedingen';
  @override
  String get blokkeringVerwijderd => 'Blokkering verwijderd';
  @override
  String get boekNuEenTrainingEnBegin => 'Boek nu een training en begin je fitnessreis. Je trainer zal contact opnemen om alles in te plannen.';
  @override
  String get boekenViaStandbyMislukt => 'Boeken via standby mislukt.';
  @override
  String get boeking => 'boeking';
  @override
  String get boekingAangemaaktMaarBetalingKonNiet => 'Booking aangemaakt maar betaling kon niet worden gestart. ';
  @override
  String get boekingAangemaaktMaarGeenIdOntvangen => 'Booking aangemaakt maar geen ID ontvangen.';
  @override
  String get boekingAangemaaktOpenMijnSessiesOm => 'Booking aangemaakt! Open "Mijn Sessions" om te betalen.';
  @override
  String get boekingBevestigen => 'Booking bevestigen';
  @override
  String get boekingMisluktProbeerOpnieuw => 'Booking mislukt. Probeer opnieuw.';
  @override
  String get boekingenViaJeEigenSite => 'Bookingen via je eigen site';
  @override
  String get boekingenViaWidget => 'Bookingen via widget';
  @override
  String get boekingidOntbreekt => 'Booking-ID ontbreekt.';
  @override
  String get boekingidOntbreektVernieuwDeLijstEn => 'Booking-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.';
  @override
  String get boekingswidget => 'Bookingswidget';
  @override
  String get boekingswidgetVoorJeWebsite => 'Bookingswidget voor je website';
  @override
  String get brandedProfiel => 'Branded profiel';
  @override
  String get cashBetalingGemarkeerdBevestigBetalingBij => 'Cash betaling gemarkeerd. Bevestig betaling bij trainer.';
  @override
  String get chatBroadcastingNietEnabledOpBackend => '[Chat] Broadcasting niet enabled op backend, alleen polling';
  @override
  String get chatKonMyuseridNietCachen => '[Chat] Could not myUserId niet cachen';
  @override
  String get checkinDirectGelukt => 'Check-in direct gelukt';
  @override
  String get checkinMislukt => 'Check-in mislukt';
  @override
  String get checkinOfflineOpgeslagen => 'Check-in offline opgeslagen';
  @override
  String get controleerDeFactuurgegevensVoordatJeVerstuurt => 'Controleer de factuurgegevens voordat je verstuurt.';
  @override
  String get danKunJeHierEenGeschil => 'dan kun je hier een geschil indienen.';
  @override
  String get deAppToontDezeInstellingenAan => 'De app toont deze instellingen aan trainers.';
  @override
  String get deBackupCodeIsOngeldigOf => 'De backup code is invalid of verlopen. ';
  @override
  String get deSafeSessionMonitoringWordtGestopt => 'De safe session monitoring wordt gestopt en ';
  @override
  String get deelDezeQrcodeOpFlyersVisitekaartjes => 'Deel deze QR-code op flyers, visitekaartjes ';
  @override
  String get deelJeLink => 'Deel je link';
  @override
  String get deelJePersoonlijkeLink => 'Deel je persoonlijke link';
  @override
  String get deelJeProfielOffline => 'Deel je profiel offline';
  @override
  String get deelnemeridOntbreektVoorDezeRegel => 'Deelnemer-ID ontbreekt voor deze regel.';
  @override
  String get dezeActieKanNietOngedaanWorden => 'This actie kan niet ongedaan worden gemaakt.';
  @override
  String get dezeFactuurWordtOpnieuwNaarDe => 'This factuur wordt opnieuw naar de klant gestuurd voor deze boeking.';
  @override
  String get dezeQrcodeBevatGeenGeldigeCheckin => 'This QR-code bevat geen geldige check-in data. ';
  @override
  String get dezeSessieBegintOverMinderDan => 'This sessie begint over minder dan een uur. Are you sure dat je wilt verplaatsen?';
  @override
  String get dezeSessieIsVandaagWeetJe => 'This sessie is vandaag. Are you sure dat je wilt verplaatsen?';
  @override
  String get dezeStandbyaanbiedingIsVerlopen => 'This standby-aanbieding is verlopen.';
  @override
  String get directContactMetJeKlanten => 'Direct contact met je klanten';
  @override
  String get directVanuitJouwSiteTeLaten => 'direct vanuit jouw site te laten boeken.';
  @override
  String get ditGeschilIsOpgelost => 'This geschil is opgelost.';
  @override
  String get ditTijdslotIsHelaasNietMeer => 'This tijdslot is helaas niet meer beschikbaar. Kies een ander moment.';
  @override
  String get ditVerwijdertJeAccountEnAlle => 'This verwijdert je account en alle bijbehorende gegevens permanent. ';
  @override
  String get ditZalJeAccountEnAlle => 'This zal je account en alle bijbehorende gegevens permanent verwijderen. ';
  @override
  String get documentenOpgeslagen => 'Documenten opgeslagen';
  @override
  String get documentenWordenVertrouwelijkBehandeldEnAlleen => 'Documenten worden vertrouwelijk behandeld en alleen door ons team bekeken.';
  @override
  String get doelenPerKlant => 'Doelen per klant';
  @override
  String get doorgaanNaarBetaling => 'Doorgaan naar betaling';
  @override
  String get dossierOpstellen => 'Dossier opstellen';
  @override
  String get dossierPerKlant => 'Dossier per klant';
  @override
  String get duoSessie => 'Duo sessie';
  @override
  String get eigenBrandedProfiel => 'Eigen branded profiel';
  @override
  String get eigenBrandedProfielpagina => 'Eigen branded profielpagina';
  @override
  String get eigenProfielOpGymies => 'Eigen profiel op Gymies';
  @override
  String get embedCodeNietBeschikbaar => 'Embed code not available';
  @override
  String get erGingIetsMis => 'Er ging iets mis.';
  @override
  String get erGingIetsMisProbeerHet => 'Er ging iets mis. Probeer het opnieuw.';
  @override
  String get erGingIetsMisProbeerOpnieuw => 'Er ging iets mis. Probeer opnieuw.';
  @override
  String get erGingIetsMisProbeerOpnieuw2 => 'Er ging iets mis. Probeer opnieuw te scannen of ';
  @override
  String get erIsEenBeveiligingsprobleemGedetecteerd => 'There is een beveiligingsprobleem gedetecteerd.';
  @override
  String get erZijnMomenteelGeenTrainersBeschikbaarnprobeer => 'There are momenteel geen trainers beschikbaar.\nProbeer het later opnieuw of pas je zoekopdracht aan.';
  @override
  String get erZijnNogGeenBoekingenIn => 'There are nog geen boekingen in dit overzicht.';
  @override
  String get erZijnNogGeenKlantenGekoppeld => 'There are nog geen klanten gekoppeld aan deze gym.';
  @override
  String get erZijnNogGeenTrainersGekoppeld => 'There are nog geen trainers gekoppeld aan deze gym.';
  @override
  String get exclusieveActieVoorOnzeKlanten => 'Exclusieve actie voor onze klanten! 🎉';
  @override
  String get exclusieveActieVoorOnzeKlanten2 => 'Exclusieve actie voor onze klanten!';
  @override
  String get facturenVerschijnenHierZodraJeTrainer => 'Facturen verschijnen hier zodra je trainer ze verstuurt.';
  @override
  String get facturenWordenAutomatischAangemaaktBijVoltooide => 'Facturen worden automatisch aangemaakt bij voltooide sessies.';
  @override
  String get factuur => 'factuur';
  @override
  String get factuur2 => 'Invoice';
  @override
  String get factuurBeschikbaar => 'Invoice beschikbaar';
  @override
  String get factuurIsOpgesteldJeKuntLater => 'Invoice is opgesteld. You can later reviewen en versturen.';
  @override
  String get factuurNogNietBeschikbaar => 'Invoice nog not available.';
  @override
  String get factuurOpnieuw => 'Invoice opnieuw';
  @override
  String get factuurOpnieuwVersturen => 'Invoice opnieuw versturen';
  @override
  String get factuurOpstellen => 'Invoice opstellen';
  @override
  String get factuurReview => 'Invoice review';
  @override
  String get factuurReviewOpnieuwVersturen => 'Invoice review (opnieuw versturen)';
  @override
  String get factuurSectieOpstellenEnReview => 'Invoice sectie: opstellen en review';
  @override
  String get factuurSectieReviewEnOpnieuwVersturen => 'Invoice sectie: review en opnieuw versturen';
  @override
  String get factuurgegevensOntbreken => 'Invoicegegevens ontbreken';
  @override
  String get factuurlinkIsOngeldig => 'Invoicelink is invalid.';
  @override
  String get factuurlinkOntbreekt => 'Invoicelink ontbreekt.';
  @override
  String get factuurverzoek => 'Invoiceverzoek';
  @override
  String get factuurverzoekGeregistreerd => 'Invoiceverzoek geregistreerd';
  @override
  String get factuurverzoekVoorSessie => 'Invoiceverzoek voor sessie';
  @override
  String get fitnesstipVanDeWeek => 'FitnessTip van de week 💪';
  @override
  String get fitnesstipVanDeWeek2 => 'Fitnesstip van de week';
  @override
  String get focusIsVerplicht => 'Focus is required';
  @override
  String get fotoIsTeGrootMax5 => 'Foto is te groot (max 5 MB). Kies een kleinere foto of ';
  @override
  String get fotosEnVideosOpJeProfiel => 'Foto\\'s en video\\'s op je profiel';
  @override
  String get foutBijLadenVanMarketinggegevens => 'Fout bij laden van marketinggegevens';
  @override
  String get gaNaarBetaling => 'Ga naar betaling';
  @override
  String get gaNaarMijnSessiesOmAlsnog => 'Ga naar "Mijn Sessions" om alsnog te betalen.';
  @override
  String get gebruikPromoCodesBijSeizoenswisselingenVoor => 'Gebruik promo codes bij seizoenswisselingen voor meer boekingen';
  @override
  String get gecertificeerdeTrainers => 'Gecertificeerde trainers';
  @override
  String get geefGroepslessenBeheerCapaciteitEnLaat => 'Geef groepslessen, beheer capaciteit en laat meerdere klanten ';
  @override
  String get geenBlokkeringen => 'No blokkeringen';
  @override
  String get geenBoekingen => 'No boekingen';
  @override
  String get geenEinddatum => 'No einddatum';
  @override
  String get geenExtraDetails => 'No extra details';
  @override
  String get geenFacturen => 'No facturen';
  @override
  String get geenFeaturesVanBackend => 'No features van backend';
  @override
  String get geenKlanten => 'No klanten';
  @override
  String get geenLimiet => 'No limiet';
  @override
  String get geenMeldingenInDitFilter => 'No meldingen in dit filter';
  @override
  String get geenMollielinkOntvangenConfigureerMollieclientidOp => 'No Mollie-link ontvangen. Configureer MOLLIE_CLIENT_ID op de server.';
  @override
  String get geenNaam => 'No naam';
  @override
  String get geenNieuweAanvragen => 'No nieuwe aanvragen';
  @override
  String get geenOnderwerp => 'No onderwerp';
  @override
  String get geenOngelezenMeldingen => 'No ongelezen meldingen';
  @override
  String get geenOpenstaandeUitbetalingen => 'No openstaande uitbetalingen';
  @override
  String get geenOptiesIngesteld => 'No opties ingesteld';
  @override
  String get geenPlanDefaultsIngesteld => 'No plan defaults ingesteld';
  @override
  String get geenProbleem => 'No probleem';
  @override
  String get geenProbleemLaatMeWetenWanneer => 'No probleem! Laat me weten wanneer het je wel schikt.';
  @override
  String get geenRedenOpgegeven => 'No reden opgegeven';
  @override
  String get geenResultatenGevonden => 'No resultaten gevonden';
  @override
  String get geenSlotsBeschikbaarOpDezeDag => 'No slots beschikbaar op deze dag';
  @override
  String get geenTrainerOverrides => 'No trainer overrides';
  @override
  String get geenTrainers => 'No trainers';
  @override
  String get geenTransacties => 'No transacties';
  @override
  String get geenTransactiesMetDezeStatus => 'No transacties met deze status.';
  @override
  String get geenVerbindingDeCheckinIsOpgeslagen => 'No verbinding. De check-in is opgeslagen en wordt ';
  @override
  String get geenWijzigbareVoorkeurveldenGevonden => 'No wijzigbare voorkeurvelden gevonden.';
  @override
  String get geenWijzigbareVoorkeurveldenGevondenInNotificationspreferences => 'No wijzigbare voorkeurvelden gevonden in notifications/preferences.';
  @override
  String get geverifieerdeTrainersKrijgenEenBadgeOp => 'Geverifieerde trainers krijgen een badge op hun profiel, ';
  @override
  String get goedGedaanDatJeHebtDoorgezet => 'Goed gedaan dat je hebt doorgezet! Het wordt makkelijker.';
  @override
  String get goeieVraagIkLegHetEven => 'Goeie vraag! Ik leg het even uit...';
  @override
  String get gratisSessie => 'Gratis sessie';
  @override
  String get groepslesAanmaken => 'Groepsles aanmaken';
  @override
  String get groepslesBewerken => 'Groepsles bewerken';
  @override
  String get groepslesBijgewerkt => 'Groepsles bijgewerkt';
  @override
  String get groepslesGeannuleerd => 'Groepsles geannuleerd';
  @override
  String get groepslesGepubliceerd => 'Groepsles gepubliceerd';
  @override
  String get groepslesToegevoegd => 'Groepsles toegevoegd';
  @override
  String get groepslesToevoegen => 'Groepsles toevoegen';
  @override
  String get groepslesidOntbreekt => 'Groepsles-ID ontbreekt.';
  @override
  String get groepslesidOntbreektVernieuwDeLijstEn => 'Groepsles-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.';
  @override
  String get groepslessenBeheer => 'Groepslessen beheer';
  @override
  String get gymiesJePersoonlijkeFitnessCoachnn => 'GYMIES – Je persoonlijke fitness coach.\n\n';
  @override
  String get gymiesVerwerktJePersoonsgegevensConformDe => 'GYMIES verwerkt je persoonsgegevens conform de AVG (GDPR). ';
  @override
  String get gymiesfavoritetrainerids => 'gymies_favorite_trainer_ids';
  @override
  String get gymiesremovedfrommytrainersids => 'gymies_removed_from_my_trainers_ids';
  @override
  String get gyminstellingen => 'Gym-instellingen';
  @override
  String get hallonndezeWeekDelenWeEenWaardevolle => 'Hallo!\n\nThis week delen we een waardevolle fitnessTip met je:\n\n📌 [Tip/advies]\n\nWaarom is dit belangrijk?\n[Uitleg van het voordeel]\n\nHoe pas je dit toe?\n[Praktische stappen]\n\nVragen? Laat het weten! Je trainer is altijd beschikbaar.\n\nGroeten,\nJe trainer';
  @override
  String get hallonnjeNieuweTrainingsschemaIsNuBeschikbaar => 'Hallo!\n\nJe nieuwe trainingsschema is nu beschikbaar in de app. Bekijk de updates en zorg dat je goed bent voorbereid voor je volgende sessies.\n\nBijzonderheden:\n• Aangepast aan jouw doelen\n• Progressieve oefeningen\n• Flexibel in te delen\n\nBen je klaar? Laten we aan de slag gaan!\n\nGroeten,\nJe trainer';
  @override
  String get hallonnweHebbenEenSpecialeAanbiedingVoor => 'Hallo!\n\nWe hebben een speciale aanbieding voor jou! Als dank voor je vertrouwen en inzet bieden we dit week:\n\n🎁 [Beschrijving van aanbieding]\n💰 [Voordeel voor jou]\n⏰ Geldig tot [datum]\n\nNot gemist! This aanbod is exclusief voor onze vaste klanten.\n\nGroeten,\nJe trainer';
  @override
  String get hallonnweOrganiserenEenSpeciaalEventEn => 'Hallo!\n\nWe organiseren een speciaal event en je bent van harte uitgenodigd!\n\n📅 Datum: [datum en tijd]\n📍 Locatie: [adres]\n👥 Wat te verwachten:\n   • [Activiteit 1]\n   • [Activiteit 2]\n   • [Activiteit 3]\n\nSnel aanmelden! Beperkt aantal plaatsen beschikbaar.\n\nGroeten,\nJe trainer';
  @override
  String get hallonnweWillenJeGraagInformerenDat => 'Hallo!\n\nWe willen je graag informeren dat onze studio gesloten is van [datum] tot [datum] vanwege vakantie.\n\nWij zijn dan not available voor sessies, maar je kunt je trainingsplan volgen via de app.\n\nWe kijken ernaar uit je binnenkort weer te zien!\n\nGroeten,\nJe trainer';
  @override
  String get hallonnweWillenJeGraagOpDe => 'Hallo!\n\nWe willen je graag op de hoogte stellen van de volgende updates:\n\n✅ [Update 1]\n✅ [Update 2]\n✅ [Update 3]\n\nThis veranderingen helpen ons om je beter van dienst te zijn. Heb je vragen? Neem gerust contact op!\n\nGroeten,\nJe trainer';
  @override
  String get hebJeVragenNeemGerustContact => 'Heb je vragen? Neem gerust contact op!</p>';
  @override
  String get herhaalJeWachtwoord => 'Herhaal je wachtwoord';
  @override
  String get herstel => 'Herstel';
  @override
  String get herstellen => 'Herstellen';
  @override
  String get hetIsGeluktOmTeVerbinden => 'Het is gelukt om te verbinden met Mollie. You can nu betalingen ontvangen van klanten.';
  @override
  String get hetRechtJeGegevensInTe => 'het recht je gegevens in te zien, te corrigeren of te verwijderen.';
  @override
  String get hetSysteemStuurtElke2Minuten => 'Het systeem stuurt elke 2 minuten een heartbeat. ';
  @override
  String get hoeGaatHet => 'Hoe gaat het?';
  @override
  String get hoeGing => 'hoe ging';
  @override
  String get hoeGoedVindbaarBenJe => 'Hoe goed vindbaar ben je?';
  @override
  String get hoeMogenWeJeNoemen => 'Hoe mogen we je noemen?';
  @override
  String get hoeVerVooruitGeboektKanWorden => 'Hoe ver vooruit geboekt kan worden';
  @override
  String get hoeVondJe => 'hoe vond je';
  @override
  String get hoeWas => 'hoe was';
  @override
  String get hoeWasDeLes => 'Hoe was de les?';
  @override
  String get hoeWasDeLesVandaag => 'Hoe was de les vandaag?';
  @override
  String get hoeveelKrijgtDeKlantTerug => 'Hoeveel krijgt de klant terug?';
  @override
  String get hogerInDeLijstVoorKlanten => 'Hoger in de lijst voor klanten';
  @override
  String get hulpViaEmail => 'Hulp via e-mail';
  @override
  String get ikCheckHetEvenVoorJe => 'Ik check het even voor je en laat het weten.';
  @override
  String get ikGaAkkoordMetHet => 'Ik ga akkoord met het ';
  @override
  String get ikHebEenVraagje => 'Ik heb een vraagje...';
  @override
  String get ikHebHierNogEenVraagje => 'Ik heb hier nog een vraagje over...';
  @override
  String get ikMoetHelaasAfzeggenVoorVandaag => 'Ik moet helaas afzeggen voor vandaag, sorry!';
  @override
  String get ikTrainMetGymiesEnVind => 'Ik train met GYMIES en vind het top! ';
  @override
  String get inschrijvenBetalen => 'Inschrijven & betalen';
  @override
  String get inschrijvingVoltooid => 'Inschrijving voltooid';
  @override
  String get introvideoOpJeProfiel => 'Intro-video op je profiel';
  @override
  String get inzichtInJeVerdiensten => 'Inzicht in je verdiensten';
  @override
  String get jeDataWordtNietMetDerden => 'Je data wordt niet met derden gedeeld en uitsluitend gebruikt ';
  @override
  String get jeEigenTrainerspagina => 'Je eigen trainerspagina';
  @override
  String get jeFiltersLeverenGeenResultatenOpnpas => 'Je filters leveren geen resultaten op.\nPas je filters aan of zoek in een andere stad.';
  @override
  String get jeHebtEenVastePlekVoor => 'You have een vaste plek voor klanten';
  @override
  String get jeHebtHetLimietBereiktMaximaal => 'You have het limiet bereikt. Maximaal 2 nieuwsbrieven per week.';
  @override
  String get jeHuisstijlOpGymies => 'Je huisstijl op Gymies';
  @override
  String get jeNieuweTrainingsschemaIsKlaar => 'Je nieuwe trainingsschema is klaar!';
  @override
  String get jeNoodcontactEnHetPlatformWorden => 'Je noodcontact en het platform worden direct op de hoogte gesteld.';
  @override
  String get jeNoodcontactWordtAutomatischGenformeerdAls => 'Je noodcontact wordt automatisch geïnformeerd als je niet ';
  @override
  String get jeOntvangtEenMeldingZodraDe => 'Je ontvangt een melding zodra de les doorgaat.';
  @override
  String get jeProfielHeeftEenBlauwVerificatievinkje => 'Je profiel heeft een blauw verificatievinkje.';
  @override
  String get jeProfielHeeftEenBlauwVinkje => 'Je profiel heeft een blauw vinkje.';
  @override
  String get jeReserveertEenPlekJeBetaalt => 'Je reserveert een plek. Je betaalt pas als het minimum aantal deelnemers bereikt is.';
  @override
  String get jeSessieDuurtLangerDanVerwacht => 'Je sessie duurt langer dan verwacht. ';
  @override
  String get jeStaatNogOpGeenWachtlijst => 'Je staat nog op geen wachtlijst. Ga naar het profiel van een trainer en klik op "Wachtlijst" om je in te schrijven als er geen plek is.';
  @override
  String get jeTrainingsplanVolgenViaDeAppp => 'je trainingsplan volgen via de app.</p>';
  @override
  String get jeVoltooideTrainingenEnBeoordelingenZullen => 'Je voltooide trainingen en beoordelingen zullen hier verschijnen na je eerste sessie.';
  @override
  String get jeVriendMaaktEenAccountAan => 'Je vriend maakt een account aan via jouw link en boekt een sessie.';
  @override
  String get jeWordtDoorgestuurdNaarDeBetaalpagina2 => 'You will be doorgestuurd naar de betaalpagina.';
  @override
  String get jeWordtNuDoorgestuurdNaarDe => 'You will be nu doorgestuurd naar de betaalpagina. Na betaling keer je terug naar de app.';
  @override
  String get jouwhandleOfUrl => '@jouwhandle of URL';
  @override
  String get jullieKrijgenAllebeiEenBeloningZodra => 'Jullie krijgen allebei een beloning zodra de eerste sessie voltooid is!';
  @override
  String get kanIkStuurJeEenVerplaatsingsverzoek => 'Kan! Ik stuur je een verplaatsingsverzoek.';
  @override
  String get kanNiet => 'kan niet';
  @override
  String get kiesDatumEnTijd => 'Kies datum en tijd';
  @override
  String get kiesEenNieuwTijdstip => 'Kies een nieuw tijdstip';
  @override
  String get kiesEenNieuweDatum => 'Kies een nieuwe datum';
  @override
  String get kiesEerstEenBeschikbaarTijdslot => 'Kies eerst een beschikbaar tijdslot.';
  @override
  String get klaarOmTeScannen => 'Klaar om te scannen';
  @override
  String get klant => 'klant';
  @override
  String get klantAnalytics => 'Client analytics';
  @override
  String get klantAnalytics2 => 'Client Analytics';
  @override
  String get klantGepromoveerdVanWachtlijst => 'Client gepromoveerd van wachtlijst';
  @override
  String get klantanalytics => 'Clientanalytics';
  @override
  String get klantbeheerTagsEnSegmenten => 'Clientbeheer, tags en segmenten';
  @override
  String get klantenBoekenViaJouwProfielZorg => 'Clienten boeken via jouw profiel. Zorg dat je beschikbaarheid klopt zodat ze je kunnen vinden.';
  @override
  String get klantenKunnenDirectBoeken => 'Clienten kunnen direct boeken';
  @override
  String get klantenLatenReviewsAchter => 'Clienten laten reviews achter';
  @override
  String get klantenZienAlleenJouwVrijeTijdslots => 'Clienten zien alleen jouw vrije tijdslots als je ze hier instelt. Tik op "+ Tijdslot" hieronder om te beginnen.';
  @override
  String get klantenbestandCrm => 'Clientenbestand (CRM)';
  @override
  String get klanttagslabels => 'Clienttags/labels';
  @override
  String get klikOmDatumtijdTeSelecteren => 'Klik om datum/tijd te selecteren';
  @override
  String get komNaarOnsEvent => 'Kom naar ons event! 🎪';
  @override
  String get komNaarOnsEvent2 => 'Kom naar ons event!';
  @override
  String get konAgendaNietLaden => 'Could not agenda niet laden.';
  @override
  String get konBerichtenNietLaden => 'Could not berichten niet laden.';
  @override
  String get konBeschikbaarheidNietLaden => 'Could not beschikbaarheid niet laden';
  @override
  String get konBetaalpaginaNietOpenen => 'Could not betaalpagina niet openen.';
  @override
  String get konBoekingenNietLaden2 => 'Could not boekingen niet laden.';
  @override
  String get konBrandinginstellingenNietLaden => 'Could not branding-instellingen niet laden.';
  @override
  String get konChatNietLaden => 'Could not chat niet laden.';
  @override
  String get konControlTowerNietLaden => 'Could not Control Tower niet laden.';
  @override
  String get konDocumentenNietLaden => 'Could not documenten niet laden.';
  @override
  String get konDossierDataNietLaden => 'Could not dossier data niet laden.';
  @override
  String get konDossierNietLaden => 'Could not dossier niet laden.';
  @override
  String get konEtalageNietLaden => 'Could not etalage niet laden.';
  @override
  String get konFacturenNietLaden => 'Could not facturen niet laden.';
  @override
  String get konFactuurNietOpenen => 'Could not factuur niet openen.';
  @override
  String get konFavorietenNietLaden => 'Could not favorieten niet laden.';
  @override
  String get konFeaturesNietLadenToonDefaults => 'Could not features niet laden. Toon defaults.';
  @override
  String get konFeesNietLaden => 'Could not fees niet laden.';
  @override
  String get konGebruikerNietLaden => 'Could not gebruiker niet laden.';
  @override
  String get konGeenGesprekOpenen => 'Could not geen gesprek openen.';
  @override
  String get konGegevensNietLaden => 'Could not gegevens niet laden.';
  @override
  String get konGeschilNietLaden => 'Could not geschil niet laden.';
  @override
  String get konGeschillenNietLaden => 'Could not geschillen niet laden.';
  @override
  String get konGesprekkenNietLaden => 'Could not gesprekken niet laden.';
  @override
  String get konGroepslesNietLaden => 'Could not groepsles niet laden.';
  @override
  String get konGroepslessenNietLaden => 'Could not groepslessen niet laden.';
  @override
  String get konGymdashboardNietLaden => 'Could not gym-dashboard niet laden.';
  @override
  String get konInschrijvingenNietLaden => 'Could not inschrijvingen niet laden.';
  @override
  String get konInstellingenNietLaden => 'Could not instellingen niet laden.';
  @override
  String get konKlantAnalyticsNietLaden => 'Could not klant analytics niet laden.';
  @override
  String get konKlantenNietLaden => 'Could not klanten niet laden.';
  @override
  String get konLinkNietOpenen => 'Could not link niet openen.';
  @override
  String get konLogistiekNietLaden => 'Could not logistiek niet laden.';
  @override
  String get konMediaNietLaden => 'Could not media niet laden.';
  @override
  String get konMeldingenNietLaden => 'Could not meldingen niet laden.';
  @override
  String get konPakkettenNietLaden => 'Could not pakketten niet laden.';
  @override
  String get konProHubNietLaden => 'Could not Pro Hub niet laden.';
  @override
  String get konProfielNietLaden => 'Could not profiel niet laden';
  @override
  String get konProfielNietLadenProbeerOpnieuw => 'Could not profiel niet laden. Probeer opnieuw.';
  @override
  String get konProfielNietOpslaan => 'Could not profiel niet opslaan';
  @override
  String get konPromotiecodesNietLaden => 'Could not promotiecodes niet laden.';
  @override
  String get konQrcodeNietLadenControleerJe => 'Could not QR-code niet laden. Controleer je internetverbinding.';
  @override
  String get konReviewsNietLaden => 'Could not reviews niet laden.';
  @override
  String get konSeogegevensNietLaden => 'Could not SEO-gegevens niet laden.';
  @override
  String get konSessieNietToevoegenAanAgenda => 'Could not sessie niet toevoegen aan agenda';
  @override
  String get konSocialMediaNietLaden => 'Could not social media niet laden.';
  @override
  String get konStudioonboardingNietLaden => 'Could not studio/onboarding niet laden.';
  @override
  String get konTarievenNietLaden => 'Could not tarieven niet laden.';
  @override
  String get konTegoedNietLaden => 'Could not tegoed niet laden.';
  @override
  String get konTicketsNietLaden => 'Could not tickets niet laden.';
  @override
  String get konTrainerprofielNietLaden => 'Could not trainerprofiel niet laden.';
  @override
  String get konTrainersNietLaden => 'Could not trainers niet laden.';
  @override
  String get konVerzoekNietVersturenProbeerOpnieuw => 'Could not verzoek niet versturen. Probeer opnieuw.';
  @override
  String get konWachtlijstenNietLaden => 'Could not wachtlijsten niet laden.';
  @override
  String get korteBeschrijvingVoorZoekmachines => 'Korte beschrijving voor zoekmachines';
  @override
  String get korteBeschrijvingVoorZoekmachines2 => 'Korte beschrijving voor zoekmachines...';
  @override
  String get kortingscodesVoorKlanten => 'Kortingscodes voor klanten';
  @override
  String get krijgEenBlauwVinkjeOpJe => 'Krijg een blauw vinkje op je profiel';
  @override
  String get kunJeMeMeerInfoGeven => 'Kun je me meer info geven over de opties?';
  @override
  String get kunnenWeEenNieuweAfspraakInplannen => 'Kunnen we een nieuwe afspraak inplannen?';
  @override
  String get kvkIsVerplicht => 'KVK is required';
  @override
  String get laatZienWieJeBent => 'Laat zien wie je bent';
  @override
  String get laatsteSessieMeerDan7Dagen => 'Laatste sessie meer dan 7 dagen geleden';
  @override
  String get landIsVerplicht => 'Land is required';
  @override
  String get lesGaatNietDoor => 'Les gaat niet door';
  @override
  String get lieverNietKanHetOpDe => 'Liever niet, kan het op de huidige tijd?';
  @override
  String get liflexibelInTeDelenliul => '<li>Flexibel in te delen</li></ul>';
  @override
  String get linkGekopieerdNaarKlembord => 'Link gekopieerd naar klembord';
  @override
  String get linkInMeldingIsOngeldig => 'Link in melding is invalid.';
  @override
  String get livoordeelVoorJouli => '<li>[Voordeel voor jou]</li>';
  @override
  String get loadingscreenBiometricAuthGelukt => '[LoadingScreen] Biometric auth gelukt ✓';
  @override
  String get loadingscreenBiometricAuthMisluktLoginScherm => '[LoadingScreen] Biometric auth mislukt → login scherm';
  @override
  String get locatieDuotrainingEnAanbiedingen => 'Locatie, duo-training en aanbiedingen';
  @override
  String get logoKleurOpJeProfiel => 'Logo & kleur op je profiel';
  @override
  String get maakJeEersteGroepslesAanEn => 'Maak je eerste groepsles aan en laat meerdere klanten tegelijk boeken.';
  @override
  String get maakJeProfielHerkenbaar => 'Maak je profiel herkenbaar';
  @override
  String get maakKortingscodesEnVolgGebruik => 'Maak kortingscodes en volg gebruik';
  @override
  String get maakPromotiesVoorKlanten => 'Maak promoties voor klanten.';
  @override
  String get maxActieveKlanten => 'Max actieve klanten';
  @override
  String get meestGekozenDoorStartendeTrainers => 'Meest gekozen door startende trainers';
  @override
  String get meldJeAanViaMijnPersoonlijke => 'Meld je aan via mijn persoonlijke link en ';
  @override
  String get meldingslinkKanNietWordenGeopendOnbekend => 'Meldingslink kan niet worden geopend (onbekend domein of ongeldige URL).';
  @override
  String get meldingslinkKanNietWordenGeopendOnbekend2 => 'Meldingslink kan niet worden geopend (onbekend domein).';
  @override
  String get mijnSessies => 'Mijn sessies';
  @override
  String get mijnTrainer => 'Mijn trainer';
  @override
  String get mochtJeOoitEenProbleemHebben => 'Mocht je ooit een probleem hebben met een boeking, ';
  @override
  String get mollieConnectKanNuNietGestart => 'Mollie Connect kan nu niet gestart worden.';
  @override
  String get mooiVolgendeKeerGaanWeEen => 'Mooi! Volgende keer gaan we een stapje verder.';
  @override
  String get n100Punten1GratisSessie => '100 punten → 1 gratis sessie';
  @override
  String get n48Uur2DagenVanTevoren => '48 uur (2 dagen) van tevoren';
  @override
  String get n72Uur3DagenVanTevoren => '72 uur (3 dagen) van tevoren';
  @override
  String get naEenSessieKunJeHier => 'Na een sessie kun je hier je factuur bekijken en downloaden. Bookingen en facturen verschijnen automatisch.';
  @override
  String get neemVoldoendeRustJeLichaamHeeft => 'Neem voldoende rust, je lichaam heeft het nodig na zo\\'n sessie.';
  @override
  String get nepProfiel => 'Nep profiel';
  @override
  String get nietDoorgaan => 'niet doorgaan';
  @override
  String get nieuwSupportverzoekAangemaakt => 'Nieuw supportverzoek aangemaakt.';
  @override
  String get nieuwTrainingsschemaBeschikbaar => 'Nieuw trainingsschema beschikbaar! 📅';
  @override
  String get nieuwTrainingsschemaBeschikbaar2 => 'Nieuw trainingsschema beschikbaar!';
  @override
  String get nieuweBoekingenVerschijnenAutomatischZodraEen => 'Nieuwe boekingen verschijnen automatisch zodra een klant boekt.';
  @override
  String get nieuweChatsVanKlantenVerschijnenHier => 'Nieuwe chats van klanten verschijnen hier zodra er een bericht binnenkomt.';
  @override
  String get nieuweKlanten => 'Nieuwe klanten';
  @override
  String get nieuweKlantenKrijgenKorting => 'Nieuwe klanten krijgen korting';
  @override
  String get nieuweSessieentry => 'Nieuwe sessie-entry';
  @override
  String get nieuwensessie => 'Nieuwe\nsessie';
  @override
  String get nieuwsbriefNaarKlantenSturen => 'Nieuwsbrief naar klanten sturen';
  @override
  String get nodigVriendenUitVoorGymiesEn => 'Nodig vrienden uit voor GYMIES en ontvang ';
  @override
  String get nogGeenAccount => 'No account? ';
  @override
  String get nogGeenAfgerondeSessies => 'No afgeronde sessies';
  @override
  String get nogGeenBeschikbaarheidIngesteld => 'No beschikbaarheid ingesteld';
  @override
  String get nogGeenBetaalbewijzen => 'No betaalbewijzen';
  @override
  String get nogGeenBioIngesteld => 'No bio ingesteld';
  @override
  String get nogGeenDoelenIngesteld => 'No doelen ingesteld.';
  @override
  String get nogGeenDossier => 'No dossier';
  @override
  String get nogGeenFacturen => 'No facturen';
  @override
  String get nogGeenGesprekken => 'No gesprekken';
  @override
  String get nogGeenGroepslessen => 'No groepslessen';
  @override
  String get nogGeenHuiswerkGeregistreerd => 'No huiswerk geregistreerd.';
  @override
  String get nogGeenInterneNotities => 'No interne notities.';
  @override
  String get nogGeenKomendeSessies => 'No komende sessies';
  @override
  String get nogGeenNieuwsbrieven => 'No nieuwsbrieven';
  @override
  String get nogGeenPakketten => 'No pakketten';
  @override
  String get nogGeenPromotiecodes => 'No promotiecodes';
  @override
  String get nogGeenSessies => 'No sessies';
  @override
  String get nogGeenTariefIngesteld => 'No tarief ingesteld';
  @override
  String get nogGeenVisibilityPolicy => 'No visibility policy.';
  @override
  String get nogGeenVoltooideSessies => 'No voltooide sessies';
  @override
  String get nogNietGeconfigureerd => 'Nog niet geconfigureerd';
  @override
  String get nogNietGeverifieerd => 'Nog niet geverifieerd';
  @override
  String get ofInJeSportschool => 'of in je sportschool.';
  @override
  String get omzetDezeMaand => 'Omzet deze maand';
  @override
  String get onbeperkteBoekingen => 'Onbeperkte boekingen';
  @override
  String get onderwerpMagNietLangerZijnDan => 'Onderwerp mag niet langer zijn dan 200 tekens';
  @override
  String get ontvangEenExportVanAlleData => 'Ontvang een export van alle data';
  @override
  String get opDeHoogteVanNieuweLessen => 'op de hoogte van nieuwe lessen, aanbiedingen en tips.';
  @override
  String get openMijnSessies => 'Open mijn sessies';
  @override
  String get opgelostInHetVoordeelVanDe => 'Opgelost in het voordeel van de klant';
  @override
  String get opgelostInHetVoordeelVanDe2 => 'Opgelost in het voordeel van de trainer';
  @override
  String get opgelostMetEenCompromisSplit => 'Opgelost met een compromis (split)';
  @override
  String get opnieuwUploaden => 'Opnieuw uploaden';
  @override
  String get opnieuwVersturen => 'Opnieuw versturen';
  @override
  String get opslaan2 => 'Opslaan...';
  @override
  String get opslaan3 => 'Opslaan…';
  @override
  String get opslaanGeluktMaarControleerVerplichteVelden => 'Opslaan gelukt, maar controleer verplichte velden opnieuw.';
  @override
  String get overboekingenCash => 'Overboekingen & cash';
  @override
  String get pakketVerwijderd => 'Pakket verwijderd';
  @override
  String get pakketidOntbreektVernieuwDeLijstEn => 'Pakket-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.';
  @override
  String get pasAanWelkeFeaturesBijStarter => 'Pas aan welke features bij Starter, Pro, Pro+ of Studio horen. ';
  @override
  String get pasDeResolutieAan => 'pas de resolutie aan.';
  @override
  String get pasJeBookingWidgetAanEn => 'Pas je booking widget aan en deel je profiel met een QR-code.';
  @override
  String get pasJeZoektermOfFilterAan => 'Pas je zoekterm of filter aan.';
  @override
  String get paspoortIdkaartOfRijbewijsGeldigWe => 'Paspoort, ID-kaart of rijbewijs (geldig). We verwerken dit volgens de AVG.';
  @override
  String get paspoortRijbewijsOfIdkaart => 'Paspoort, rijbewijs of ID-kaart';
  @override
  String get pbdatumbDatumEnTijdbr => '<p><b>Datum:</b> [datum en tijd]<br>';
  @override
  String get pbenJeKlaarLatenWeAan => '<p>Ben je klaar? Laten we aan de slag gaan!</p>';
  @override
  String get pbhoePasJeDitToebbrpraktischeStappenp => '<p><b>Hoe pas je dit toe?</b><br>[Praktische stappen]</p>';
  @override
  String get pbwaaromIsDitBelangrijkbbruitlegVanHet => '<p><b>Waarom is dit belangrijk?</b><br>[Uitleg van het voordeel]</p>';
  @override
  String get pbwatTeVerwachtenbp => '<p><b>Wat te verwachten:</b></p>';
  @override
  String get pdezeVeranderingenHelpenOnsOmJe => '<p>This veranderingen helpen ons om je beter van dienst te zijn. ';
  @override
  String get pdezeWeekDelenWeEenWaardevolle => '<p>This week delen we een waardevolle fitnesstip met je:</p>';
  @override
  String get perTrainerEenCustomFee => 'Per trainer een custom fee';
  @override
  String get percentageMagNietHogerZijnDan => 'Percentage mag niet hoger zijn dan 100%';
  @override
  String get personalTrainerAmsterdam => 'Personal trainer Amsterdam';
  @override
  String get pgroetenbrjeTrainerp => '<p>Groeten,<br>Je trainer</p>';
  @override
  String get pittigMaarGoedVoelHetNog => 'Pittig maar goed! Voel het nog 😅';
  @override
  String get pjeNieuweTrainingsschemaIsNuBeschikbaar => '<p>Je nieuwe trainingsschema is nu beschikbaar in de app. ';
  @override
  String get plakDezeCodeOpJeWebsite => 'Plak deze code op je website om klanten ';
  @override
  String get planEenSessieOpHetMoment => 'Plan een sessie op het moment dat jou uitkomt';
  @override
  String get planEnBeheerGroepssessies => 'Plan en beheer groepssessies';
  @override
  String get plekGereserveerdJeOntvangtBerichtAls => 'Plek gereserveerd! Je ontvangt bericht als de les doorgaat.';
  @override
  String get pnietGemistDitAanbodIsExclusief => '<p>Niet gemist! This aanbod is exclusief voor onze vaste klanten.</p>';
  @override
  String get postcodeIsVerplicht => 'Postcode is required';
  @override
  String get prijsHoogNaarLaag => 'Prijs: hoog naar laag';
  @override
  String get prijsLaagNaarHoog => 'Prijs: laag naar hoog';
  @override
  String get prijsPerSessie => 'Prijs per sessie';
  @override
  String get primaDatIsGoed => 'Prima, dat is goed!';
  @override
  String get prioriteitInZoekresultaten => 'Prioriteit in zoekresultaten';
  @override
  String get probeerEenAndereCategorie => 'Probeer een andere categorie.';
  @override
  String get probeerGymiesMijnTip => 'Probeer GYMIES — mijn tip!';
  @override
  String get profielBewerken => 'Profile bewerken';
  @override
  String get profielBranding => 'Profile branding';
  @override
  String get profielQrcode => 'Profile QR-code';
  @override
  String get profielUrl => 'Profile URL';
  @override
  String get promocodeVerwijderd => 'Promocode verwijderd';
  @override
  String get promocodeidOntbreektVernieuwDeLijstEn => 'Promocode-ID ontbreekt. Vernieuw de lijst en probeer opnieuw.';
  @override
  String get promocodesAanmaken => 'Promo-codes aanmaken';
  @override
  String get promotieEnKlantwerving => 'Promotie en klantwerving';
  @override
  String get psnelAanmeldenBeperktAantalPlaatsenBeschikbaarp => '<p>Snel aanmelden! Beperkt aantal plaatsen beschikbaar.</p>';
  @override
  String get pvragenLaatHetWetenJeTrainer => '<p>Vragen? Laat het weten! Je trainer is altijd beschikbaar.</p>';
  @override
  String get pweHebbenEenSpecialeAanbiedingVoor => '<p>We hebben een speciale aanbieding voor jou! ';
  @override
  String get pweKijkenErnaarUitJeBinnenkort => '<p>We kijken ernaar uit je binnenkort weer te zien!</p>';
  @override
  String get pweOrganiserenEenSpeciaalEventEn => '<p>We organiseren een speciaal event en je bent van harte uitgenodigd!</p>';
  @override
  String get pweWillenJeGraagInformerenDat => '<p>We willen je graag informeren dat onze studio gesloten is ';
  @override
  String get pweWillenJeGraagOpDe => '<p>We willen je graag op de hoogte stellen van de volgende updates:</p>';
  @override
  String get pwijZijnDanNietBeschikbaarVoor => '<p>Wij zijn dan not available voor sessies, maar je kunt ';
  @override
  String get qrcodeVoorJeProfiel => 'QR-code voor je profiel';
  @override
  String get reageertNaHetVerwachteEindeVan => 'reageert na het verwachte einde van de sessie.';
  @override
  String get reminder24UurVooraf => 'Reminder 24 uur vooraf';
  @override
  String get reminder2UurVooraf => 'Reminder 2 uur vooraf';
  @override
  String get reminderSessie => 'Reminder sessie';
  @override
  String get reviewFactuur => 'Review factuur';
  @override
  String get sNietBeschikbaar => 's not available';
  @override
  String get sOpJeProfiel => 's op je profiel';
  @override
  String get sToeVoorJeStoryEn => 's toe voor je Story en de Media Gallery. Video\\'s max. 30 sec. Clienten zien dit op je openbare profiel.';
  @override
  String get schakelInVoorAutomatischeHerinneringen => 'Schakel in voor automatische herinneringen';
  @override
  String get schrijfEnVerstuurJeEersteNieuwsbrief => 'Schrijf en verstuur je eerste nieuwsbrief via het tabblad "Nieuw"';
  @override
  String get schrijfJeBerichtHier => 'Schrijf je bericht hier. ';
  @override
  String get schrijfJeNieuwsbrief => 'Schrijf je nieuwsbrief...';
  @override
  String get segmenteerJeKlantenEnStuurBulk => 'Segmenteer je klanten en stuur bulk berichten.';
  @override
  String get segoeUi => 'Segoe UI';
  @override
  String get selecteerEenDatumEnTijd => 'Selecteer een datum en tijd';
  @override
  String get seoinstellingen => 'SEO-instellingen';
  @override
  String get sessie2 => ' /sessie';
  @override
  String get sessie3 => 'sessie';
  @override
  String get sessieEindeBereikt => 'Session einde bereikt';
  @override
  String get sessieInDeAfgelopen60Dagen => '(sessie in de afgelopen 60 dagen). Maximaal 2 per week.';
  @override
  String get sessieTegoed => 'Session tegoed';
  @override
  String get sessieToegevoegdAanJeAgenda => 'Session toegevoegd aan je agenda';
  @override
  String get sessieVerplaatst => 'Session verplaatst';
  @override
  String get sessieVoltooid => 'Session voltooid';
  @override
  String get sessiebeheer => 'Sessionbeheer';
  @override
  String get sessieentry => 'Session-entry';
  @override
  String get sessieinkomsten => 'Session-inkomsten';
  @override
  String get sessies => 'sessies';
  @override
  String get snellereReactieVanOnsTeam => 'Snellere reactie van ons team';
  @override
  String get spamOfMisleiding => 'Spam of misleiding';
  @override
  String get stadIsVerplicht => 'Stad is required';
  @override
  String get standbyActiefJeKrijgtEenMelding => 'Standby actief – je krijgt een melding bij vrije plek';
  @override
  String get standbyPlekBeschikbaar => 'Standby plek beschikbaar';
  @override
  String get standbySessieGeboekt => 'Standby sessie geboekt';
  @override
  String get standbyaanmeldingMisluktProbeerOpnieuw => 'Standby-aanmelding mislukt. Probeer opnieuw.';
  @override
  String get startBetaling => 'Start betaling';
  @override
  String get startJeBusiness => 'Start je business';
  @override
  String get statusGewijzigd => 'Status gewijzigd';
  @override
  String get stelJezelfVoorAanKlanten => 'Stel jezelf voor aan klanten';
  @override
  String get stuurEenBerichtOmHetGesprek => 'Stuur een bericht om het gesprek te starten.';
  @override
  String get stuurEenNieuwsbriefNaarAlJe => 'Stuur een nieuwsbrief naar al je actieve klanten ';
  @override
  String get stuurJeEersteNieuwsbriefNaarAl => 'Stuur je eerste nieuwsbrief naar al je klanten. Deel tips, aanbiedingen of updates.';
  @override
  String get stuurJePersoonlijkeLinkNaarVrienden => 'Stuur je persoonlijke link naar vrienden via WhatsApp, e-mail of deel de QR-code.';
  @override
  String get stuurNieuwsbrievenNaarAlJeKlanten => 'Stuur nieuwsbrieven naar al je klanten tegelijk. Houd ze ';
  @override
  String get stuurNieuwsbrievenNaarJeKlantenMet => 'Stuur nieuwsbrieven naar je klanten met templates en analytics.';
  @override
  String get supportverzoek => 'Supportverzoek';
  @override
  String get tarievenBetaling => 'Tarieven & betaling';
  @override
  String get tegelijkBoekenVerhoogJeOmzetPer => 'tegelijk boeken. Verhoog je omzet per uur met groepstraining.';
  @override
  String get ticketIsAfgerond => 'Ticket is afgerond';
  @override
  String get tijdslotVerwijderd => 'Tijdslot verwijderd';
  @override
  String get titelEnBeschrijvingVoorZoekmachines => 'Titel en beschrijving voor zoekmachines';
  @override
  String get toonEenYoutubeOfVimeoVideo => 'Toon een YouTube of Vimeo video op je profiel';
  @override
  String get toonJeSocialsOpJeProfiel => 'Toon je socials op je profiel';
  @override
  String get totDeVolgendeSessie => 'Tot de volgende sessie!';
  @override
  String get trainMetMijMee => 'Train met mij mee!';
  @override
  String get trainMinstens3xPerWeekVoor => 'Train minstens 3x per week voor optimaal resultaat. Plan je eerste sessie van de week!';
  @override
  String get trainer2 => 'trainer';
  @override
  String get trainerBetaalt => 'Trainer betaalt';
  @override
  String get trainerNietGevonden => 'Trainer not found';
  @override
  String get trainerOnboarding => 'Trainer Onboarding';
  @override
  String get trainerOverride => 'Trainer override';
  @override
  String get trainerOverrides => 'Trainer overrides';
  @override
  String get trainerTrainerslugOfTraineridVereist => 'trainer, trainerSlug of trainerId vereist';
  @override
  String get traineraddressline1 => 'trainer_address_line1';
  @override
  String get trainerapprovedat => 'trainer_approved_at';
  @override
  String get traineravatar => 'trainer_avatar';
  @override
  String get traineravatar2 => 'trainerAvatar';
  @override
  String get trainerchat => 'TrainerChat';
  @override
  String get trainerchatWebsocketVerbindingGesloten => '[TrainerChat] WebSocket verbinding gesloten';
  @override
  String get trainerchatWebsocketVerbonden => '[TrainerChat] WebSocket verbonden';
  @override
  String get trainercheckin => 'trainer_check_in';
  @override
  String get trainercity => 'trainer_city';
  @override
  String get trainercountry => 'trainer_country';
  @override
  String get trainerdashboard => 'TrainerDashboard';
  @override
  String get trainerdashboardGeenSetauthtokenAuthtokenIsLeeg => '[TrainerDashboard] GEEN setAuthToken – auth.token is leeg of null';
  @override
  String get trainerdashboardGetTrainersummary => '[TrainerDashboard] GET trainer/summary...';
  @override
  String get trainerdashboardGettrainersummaryOk => '[TrainerDashboard] getTrainerSummary OK';
  @override
  String get trainerid => 'trainer_id';
  @override
  String get traineridOntbreekt2 => 'Trainer-ID ontbreekt.';
  @override
  String get trainerincomeFallbackLeegOverzicht => '[TrainerIncome] Fallback: leeg overzicht';
  @override
  String get trainerinvoicenumber => 'trainer_invoice_number';
  @override
  String get trainername => 'trainer_name';
  @override
  String get trainername2 => 'trainerName';
  @override
  String get trainernoshow => 'trainer_no_show';
  @override
  String get trainerpostcode => 'trainer_postcode';
  @override
  String get trainerprofileFallbackProfielGebruiktNaFout => '[TrainerProfile] Fallback profiel gebruikt na fout';
  @override
  String get trainerprofileFallbackProfielGebruiktVanuitAuthservice => '[TrainerProfile] Fallback profiel gebruikt vanuit AuthService';
  @override
  String get trainerprofileProfielLaden => '[TrainerProfile] Profile laden...';
  @override
  String get trainers2 => 'trainers';
  @override
  String get trainerscan => 'trainer_scan';
  @override
  String get trainertextcontains => ') || trainerText.contains(';
  @override
  String get traineruserid => 'trainer_user_id';
  @override
  String get traineruserid2 => 'trainerUserId';
  @override
  String get trainerverifiedat => 'trainer_verified_at';
  @override
  String get trainingVoor2PersonenTegelijk => 'Training voor 2 personen tegelijk';
  @override
  String get trainingsabonnementenAanbieden => 'Trainingsabonnementen aanbieden';
  @override
  String get transactiesVerschijnenNaBevestigdeEnAfgeronde => 'Transacties verschijnen na bevestigde en afgeronde sessies.';
  @override
  String get transactiesVerschijnenNaBevestigdeSessies => 'Transacties verschijnen na bevestigde sessies.';
  @override
  String get ulliaangepastAanJouwDoelenli => '<ul><li>Aangepast aan jouw doelen</li>';
  @override
  String get ullibbeschrijvingVanAanbiedingbli => '<ul><li><b>[Beschrijving van aanbieding]</b></li>';
  @override
  String get uploadJeFitnesscertificeringOfDiploma => 'Upload je fitness-certificering of diploma';
  @override
  String get uploadJeFitnesscertificeringOfDiploma2 => 'Upload je fitness-certificering of diploma.';
  @override
  String get uploadJeKamerVanKoophandelUittreksel => 'Upload je Kamer van Koophandel uittreksel (PDF of afbeelding).';
  @override
  String get uploadJeRecenteKvkuittrekselMax6 => 'Upload je recente KvK-uittreksel (max 6 maanden oud)';
  @override
  String get uploadMislukt => 'Upload mislukt';
  @override
  String get vanBdatumbTotBdatumbVanwegeVakantiep => 'van <b>[datum]</b> tot <b>[datum]</b> vanwege vakantie.</p>';
  @override
  String get veiligheidssessieActief => 'Veiligheidssessie actief';
  @override
  String get verbeterJeVindbaarheid => 'Verbeter je vindbaarheid';
  @override
  String get vergeetJeSessieNietVandaagTot => 'Vergeet je sessie niet vandaag! Tot zo.';
  @override
  String get verifiedTrainerBadge => 'Verified trainer badge';
  @override
  String get verklaringOmtrentHetGedrag => 'Verklaring Omtrent het Gedrag';
  @override
  String get verklaringOmtrentHetGedragNietVerplicht => 'Verklaring Omtrent het Gedrag — niet verplicht, wel aanbevolen.';
  @override
  String get verplaatsSessie => 'Verplaats sessie';
  @override
  String get verplaatsingsverzoek => 'Verplaatsingsverzoek';
  @override
  String get versturen2 => 'Versturen...';
  @override
  String get versturenMisluktTikOmOpnieuwTe => 'Versturen mislukt. Tik om opnieuw te proberen.';
  @override
  String get verstuurMaandelijksEenNieuwsbriefOmKlanten => 'Verstuur maandelijks een nieuwsbrief om klanten betrokken te houden';
  @override
  String get verstuurNaarKlant => 'Verstuur naar klant';
  @override
  String get verstuurUpdatesNaarJeKlanten => 'Verstuur updates naar je klanten';
  @override
  String get vertelWieJeBentWatJe => 'Vertel wie je bent, wat je drijft en hoe je klanten helpt...';
  @override
  String get verversBerichten => 'Ververs berichten';
  @override
  String get verwijderPermanentAvgArt17 => 'Verwijder permanent (AVG Art. 17)';
  @override
  String get verzoekAfgewezen => 'Verzoek afgewezen';
  @override
  String get videosOpProfiel => 'Videos op profiel';
  @override
  String get vindDePerfecteTrainerBijJou => 'Vind de perfecte trainer bij jou in de buurt';
  @override
  String get voegEenBlokkeringToeVoorDagen => 'Voeg een blokkering toe voor dagen dat je not available bent, zoals vakantie of ziekte.';
  @override
  String get voegJeSocialMediaLinksToe => 'Voeg je social media links toe zodat klanten je kunnen volgen';
  @override
  String get voegPakkettenToeVoorKlantenOm => 'Voeg pakketten toe voor klanten om te boeken.';
  @override
  String get voegTrainersToeAanJeFavorieten => 'Voeg trainers toe aan je favorieten via hun profiel.';
  @override
  String get volledigGepersonaliseerdProfiel => 'Volledig gepersonaliseerd profiel';
  @override
  String get voorDeSerieuzeTrainer => 'Voor de serieuze trainer';
  @override
  String get voorHetLeverenVanOnzeDiensten => 'voor het leveren van onze diensten. You have te allen tijde ';
  @override
  String get voorkeurenOpgeslagen => 'Voorkeuren opgeslagen';
  @override
  String get vraagDeKlantEenNieuweCode => 'Vraag de klant een nieuwe code op te vragen.';
  @override
  String get vraagDeKlantOmEenNieuwe => 'Vraag de klant om een nieuwe QR-code te genereren in de app.';
  @override
  String get vraagVerificatieAanOmEenBlauw => 'Vraag verificatie aan om een blauw vinkje op je profiel te krijgen. Gymies beoordeelt je aanvraag.';
  @override
  String get vraagVerificatieAanVoorEenBlauw => 'Vraag verificatie aan voor een blauw vinkje.';
  @override
  String get vraagjeHierover => 'Vraagje hierover';
  @override
  String get vriendMeldtZichAan => 'Vriend meldt zich aan';
  @override
  String get vulEenAandachtspuntIn => 'Vul een aandachtspunt in';
  @override
  String get vulEenBerichtIn => 'Vul een bericht in';
  @override
  String get vulEenDienstnaamIn => 'Vul een dienstnaam in';
  @override
  String get vulEenGeldigBedragIn => 'Vul een geldig bedrag in';
  @override
  String get vulEenGeldigBedragInBijv => 'Vul een geldig bedrag in (bijv. 5.00)';
  @override
  String get vulEenGeldigEmailadresIn => 'Vul een geldig e-mailadres in';
  @override
  String get vulEenGeldigPercentageIn1100 => 'Vul een geldig percentage in (1-100)';
  @override
  String get vulEenNaamIn => 'Vul een naam in';
  @override
  String get vulEenPromocodeIn => 'Vul een promocode in';
  @override
  String get vulEenTitelInEnEen => 'Vul een titel in en een capaciteit van minimaal 1.';
  @override
  String get vulEenWachtwoordIn => 'Vul een wachtwoord in';
  @override
  String get vulJeEmailIn => 'Vul je e-mail in';
  @override
  String get vulJeEmailadresIn => 'Vul je e-mailadres in.';
  @override
  String get vulJeWachtwoordIn => 'Vul je wachtwoord in';
  @override
  String get vulMinimaal1PositiefPuntIn => 'Vul minimaal 1 positief punt in';
  @override
  String get wachtOpBetaling => 'Wacht op betaling';
  @override
  String get wachtwoordTeZwakGebruikLettersN => 'Password te zwak. Gebruik letters én cijfers.';
  @override
  String get wachtwoordenKomenNietOvereen => 'Passworden komen niet overeen.';
  @override
  String get wanneerEenKlantEenSessieAanvraagt => 'Wanneer een klant een sessie aanvraagt, zie je het hier direct.';
  @override
  String get wanneerIsDeVolgendeSessie => 'Wanneer is de volgende sessie?';
  @override
  String get watKostEenSessieEnHoe => 'Wat kost een sessie en hoe wordt betaald?';
  @override
  String get watMoet => 'wat moet';
  @override
  String get weKrijgenAllebeiEenBeloningNn => 'we krijgen allebei een beloning 💪\n\n';
  @override
  String get weMissenJePlanJeVolgende => 'We missen je! Plan je volgende sessie via Mijn afspraken in de app.';
  @override
  String get weergavenaamIsVerplicht => 'Weergavenaam is required';
  @override
  String get weetJeZekerDatJeDeze => 'Are you sure dat je deze promocode wilt verwijderen? This kan niet ongedaan worden.';
  @override
  String get weetJeZekerDatJeDeze2 => 'Are you sure dat je deze video wilt verwijderen?';
  @override
  String get weetJeZekerDatJeDit => 'Are you sure dat je dit wilt verwijderen?';
  @override
  String get weetJeZekerDatJeEen => 'Are you sure dat je een noodalert wilt versturen?\n\n';
  @override
  String get weetJeZekerDatJeEen2 => 'Are you sure dat je een noodalert wilt versturen? ';
  @override
  String get weetJeZekerDatJeEen3 => 'Are you sure dat je een noodalert wilt versturen?\n\nJe noodcontact en het platform worden direct op de hoogte gesteld.';
  @override
  String get weetJeZekerDatJeJe => 'Are you sure dat je je inschrijving wilt annuleren?';
  @override
  String get weetJeZekerDatJeJe2 => 'Are you sure dat je je abonnement wilt opzeggen? Je verliest toegang tot de bijbehorende features.';
  @override
  String get weetJeZekerDatJeJe3 => 'Are you sure dat je je standby-inschrijving wilt verwijderen? Je verliest je plek op de wachtlijst.';
  @override
  String get weetJeZekerDatJeVan => 'Are you sure dat je van abonnement wilt veranderen?';
  @override
  String get weetJeZekerDatJeWilt => 'Are you sure dat je wilt downgraden?';
  @override
  String get weetJeZekerDatJeZonder => 'Are you sure dat je zonder opslaan wilt sluiten?';
  @override
  String get welkeTijdenHebJeBeschikbaar => 'Welke tijden heb je beschikbaar?';
  @override
  String get wijzigingenNietOpgeslagen => 'Wijzigingen niet opgeslagen';
  @override
  String get wordenHogerGetoondInZoekresultatenEn => 'worden hoger getoond in zoekresultaten en winnen meer vertrouwen bij klanten. ';
  @override
  String get zalIkHetEvenTelefonischUitleggen => 'Zal ik het even telefonisch uitleggen? Dat gaat sneller.';
  @override
  String get zieJeZo => 'zie je zo';
  @override
  String get zieWelkeKlantenDreigenAfTe => 'Zie welke klanten dreigen af te haken en krijg AI-suggesties voor upsells en herboekingen.';
  @override
  String get zipKlaarVoorDownload => 'ZIP klaar voor download';
  @override
  String get zoZienMensenJouInZoekresultaten => 'Zo zien mensen jou in zoekresultaten';
  @override
  String get zodraEenSessieIsGeweestZie => 'Zodra een sessie is geweest zie je hier het overzicht.';
  @override
  String get zodraJeEenTrainerBerichtVerschijnt => 'Zodra je een trainer bericht, verschijnt het gesprek hier.';
  @override
  String get zoekEnBoekTrainers => 'Zoek en boek trainers';
  @override
  String get zoekTrainer => 'Zoek trainer';
  @override
  String get zorgErvoorDatJeKlantenGoed => 'Zorg ervoor dat je klanten goed begrijpen wat je wilt communiceren.';

  // ═══ PHASE 4 — REMAINING STRINGS ═══
  @override
  String get actiefLower => 'active';
  @override
  String beschikbaarMet(String tier) => 'Available with \$tier';
  @override
  String beschikbaarVanaf(String requiredTier) => 'Available from \$requiredTier';
  @override
  String betalingGeluktTier(String tier) => 'Payment successful! Your \$tier subscription is now active.';
  @override
  String betalingStartenVoor(String label) => 'Starting payment for \$label';
  @override
  String get bevestigIdentiteitBetaling => 'Confirm your identity to complete the payment';
  @override
  String get bevestigIdentiteitProfiel => 'Confirm your identity to edit your profile';
  @override
  String get bevestigen => 'Confirm';
  @override
  String get blokkeringVerwijderen => 'Remove block';
  @override
  String get boekingBevestigd => 'Booking confirmed';
  @override
  String boekingNummer(String id) => 'Booking #\$id';
  @override
  String get dezeFunctieIsNietBeschikbaar => 'This feature is currently unavailable. Please try again later.';
  @override
  String get dezeMaand => 'This month';
  @override
  String doelBoekingen(String target) => '\$target bookings!';
  @override
  String get eersteBetaling => 'First payment!';
  @override
  String get eersteSessie => 'First session!';
  @override
  String get facturen => 'Invoices';
  @override
  String factuurVoorSessie(String bookingId, String trainerName) => 'I would like an invoice for session \$bookingId with \$trainerName.';
  @override
  String geenGesprekkenGevondenVoor(String query) => 'No conversations found for "\$query".';
  @override
  String geenOpenTicketsVan(String roleLabel) => 'No open tickets from \$roleLabel';
  @override
  String geenResultatenVoor(String query) => 'No results for "\$query"';
  @override
  String get geenTokenOntvangenVanServer => 'No token received from the server.';
  @override
  String get geenVerbindingControleerInternet => 'No connection. Check your internet and try again later.';
  @override
  String get geenVerbindingProbeerOpnieuw => 'No connection. Check your internet and try again.';
  @override
  String geenVerplaatsbareSessiesBij(String name) => 'No reschedulable sessions with \$name';
  @override
  String geenVerplaatsbareSessiesMet(String name) => 'No reschedulable sessions with \$name';
  @override
  String get geschilOpgelost => 'Dispute resolved';
  @override
  String get gisteren => 'Yesterday';
  @override
  String get gisterenLower => 'yesterday';
  @override
  String get goedemorgen => 'Good morning';
  @override
  String get gymiesLiveMeldingen => 'GYMIES live notifications';
  @override
  String get inactiefLower => 'inactive';
  @override
  String get jaAnnuleren => 'Yes, cancel';
  @override
  String get jaVerwijderen => 'Yes, delete';
  @override
  String kiesEenBeschikbaarMomentVan(String trainerName) => 'Choose an available time slot from \$trainerName';
  @override
  String laatsteSessieWasDagenGeleden(String daysSince) => 'Your last session was \$daysSince days ago. Time to get back to it!';
  @override
  String get mediaVerwijderen => 'Delete media';
  @override
  String mediaVerwijderenCount(String count) => 'Are you sure you want to delete \$count item(s)?';
  @override
  String get mijnProfiel => 'MY PROFILE';
  @override
  String get morgenLower => 'tomorrow';
  @override
  String get neeTochAnnuleren => 'No, cancel anyway';
  @override
  String nogSessionsTotMilestone(String remaining, String nextMilestone) => '\$remaining session(s) until your next milestone (\$nextMilestone)!';
  @override
  String onbekendActieType(String type) => 'Unknown action type: \$type';
  @override
  String get onbekendDomein => 'Unknown domain';
  @override
  String get onbekendeDatum => 'Unknown date';
  @override
  String get ongeldigeOfVerlopenSessieLogOpnieuwIn => 'Invalid or expired session. Please log in again.';
  @override
  String get onveiligeVerbindingGeenHttps => 'Unsafe connection (no HTTPS). Payment cancelled.';
  @override
  String perSessie(String price) => '\$price / session';
  @override
  String get planSessie => 'Plan session';
  @override
  String profielMeldingTrainer(String trainerName) => 'Profile report: \$trainerName';
  @override
  String get promotieActief => 'Promotion active';
  @override
  String get realtimeUpdatesEnBroadcast => 'Realtime updates and broadcast notifications';
  @override
  String sessieBij(String trainerName) => 'Session with \$trainerName';
  @override
  String get sessieGeannuleerd => 'Session cancelled';
  @override
  String sessieMet(String name) => 'Gymies session – \$name';
  @override
  String get sessieboeking => 'Session booking';
  @override
  String sessiesVoltooid(String count) => '\$count sessions completed!';
  @override
  String get standbyVerwijderen => 'Remove from standby';
  @override
  String get statusAfgerond => 'Completed';
  @override
  String get statusInBehandeling => 'In progress';
  @override
  String get statusOnbekend => 'Unknown';
  @override
  String get tarievenEnBetaling => 'Rates & Payment';
  @override
  String get teBevestigen => 'To confirm';
  @override
  String get terugbetaald => 'Refunded';
  @override
  String get tijdslotVerwijderen => 'Delete time slot';
  @override
  String trainerBoekingContext(String trainerName, String bookingId) => 'Trainer: \$trainerName · Booking \$bookingId';
  @override
  String get typeBetaling => 'Payment';
  @override
  String get typeGeschil => 'Dispute';
  @override
  String get typeIncident => 'Incident';
  @override
  String get typeOverig => 'Other';
  @override
  String get uitzonderingToevoegen => 'Add exception';
  @override
  String get vandaag => 'Today';
  @override
  String get vandaagLower => 'today';

  // ═══ FAQ CONTENT STRINGS ═══
  @override
  String get faqCatBoekingen => 'Bookings';
  @override
  String get faqCatBoekDesc => 'Modify, cancel, reschedule';
  @override
  String get faqCatBetalingen => 'Payments';
  @override
  String get faqCatBetalDesc => 'Invoices, refunds, subscription';
  @override
  String get faqCatAccount => 'My Account';
  @override
  String get faqCatAccountDesc => 'Profile, password, settings';
  @override
  String get faqCatTrainer => 'My Trainer';
  @override
  String get faqCatTrainerDesc => 'Contact, reviews, complaints';
  @override
  String get faqCatVeiligheid => 'Safety';
  @override
  String get faqCatVeiligheidDesc => 'Report, block, privacy';
  @override
  String get faqCatTechnisch => 'Technical';
  @override
  String get faqCatTechnischDesc => 'Bugs, crashes, app issues';
  @override
  String get faqQWijzigBoeking => 'How do I change my booking?';
  @override
  String get faqAWijzigBoeking => 'Go to the "Sessions" tab at the bottom of the app. Tap the session you want to change and choose the desired action from the menu. You can make changes free of charge up to 24 hours in advance.';
  @override
  String get faqActionNaarSessies => 'Go to My Sessions';
  @override
  String get faqQAnnuleerSessie => 'Can I cancel a session?';
  @override
  String get faqAAnnuleerSessie => 'Yes, you can cancel up to 12 hours before the session. Go to the "Sessions" tab, tap the booking and choose "Cancel" from the action menu. Late cancellation may incur charges.';
  @override
  String get faqQTrainerAfgezegd => 'My trainer cancelled, what now?';
  @override
  String get faqATrainerAfgezegd => 'You will automatically receive a full refund. You can immediately book a new session with the same trainer or find another trainer via the "Discover" tab.';
  @override
  String get faqQGroepssessie => 'How do I book a group session?';
  @override
  String get faqAGroepssessie => 'Go to your Profile → Group classes to view available group sessions. You can also see which group classes are offered via the trainer profile.';
  @override
  String get faqActionNaarGroepslessen => 'Go to Group Classes';
  @override
  String get faqQBoekingsgeschiedenis => 'Where can I find my booking history?';
  @override
  String get faqABoekingsgeschiedenis => 'Go to the "Sessions" tab. Under "Past" you can see all your past sessions. For invoices, go to Profile → Invoices.';
  @override
  String get faqQFacturen => 'Where can I find my invoices?';
  @override
  String get faqAFacturen => 'Go to your Profile (bottom right tab) → tap "Invoices" under "My activity". Here you can view all your invoices, filter by status and request details.';
  @override
  String get faqActionNaarFacturen => 'Go to Invoices';
  @override
  String get faqQTerugbetaling => 'How do I request a refund?';
  @override
  String get faqATerugbetaling => 'When cancelling within the deadline, refunds are automatically processed via Mollie. For other cases, you can create a support request with type "Payment".';
  @override
  String get faqActionSupport => 'Create support request';
  @override
  String get faqQBetaalmethoden => 'Which payment methods are accepted?';
  @override
  String get faqABetaalmethoden => 'We accept iDEAL, credit card (Visa/Mastercard), Bancontact and Apple Pay. You choose the payment method for each booking via our payment partner Mollie.';
  @override
  String get faqQBetalingMislukt => 'My payment failed, what now?';
  @override
  String get faqABetalingMislukt => 'Check your bank account and try again via the "Sessions" tab. If the problem persists, contact your bank or try a different payment method for your next booking.';
  @override
  String get faqQWijzigProfiel => 'How do I edit my profile?';
  @override
  String get faqAWijzigProfiel => 'Go to Profile (bottom right tab) → Settings → "My profile". Here you can edit your name, phone number, city and bio.';
  @override
  String get faqActionNaarProfiel => 'Go to My Profile';
  @override
  String get faqQWachtwoord => 'How do I change my password?';
  @override
  String get faqAWachtwoord => 'Go to Profile → Settings → "My profile". Tap "Change password" at the bottom. You need your current password plus a new password of at least 8 characters.';
  @override
  String get faqQNietInloggen => 'I can\'t log in';
  @override
  String get faqANietInloggen => 'Use "Forgot password" on the login screen. You will receive an email with a reset link. Also check your spam folder and whether you are using the correct email address.';
  @override
  String get faqQMeldingen => 'Where can I see my notifications?';
  @override
  String get faqAMeldingen => 'Go to Profile → "Notifications" under "My activity". Here you can find all your notifications about bookings, messages and updates.';
  @override
  String get faqActionNaarMeldingen => 'Go to Notifications';
  @override
  String get faqQDossier => 'How do I view my training record?';
  @override
  String get faqADossier => 'Go to Profile → "My record" under "My activity". Here you can find your personal training record with notes from your trainer.';
  @override
  String get faqActionNaarDossier => 'Go to My Record';
  @override
  String get faqQUitloggen => 'How do I log out?';
  @override
  String get faqAUitloggen => 'Go to Profile (bottom right tab) and scroll down. Tap the "Log out" button at the bottom of the page.';
  @override
  String get faqQTrainerReageertNiet => 'My trainer doesn\'t respond to messages';
  @override
  String get faqATrainerReageertNiet => 'Trainers usually respond within 24 hours. Check the Messages tab to see if your message was sent. If you haven\'t heard back after 48 hours, create a support request so we can contact the trainer.';
  @override
  String get faqQReview => 'How do I leave a review?';
  @override
  String get faqAReview => 'After each completed session, you will receive a notification to leave a review. You can also go to the "Sessions" tab, open a past session and write your review there.';
  @override
  String get faqQKlacht => 'I want to file a complaint about my trainer';
  @override
  String get faqAKlacht => 'We\'re sorry you had a bad experience. Create a support request with type Dispute. Describe the situation as clearly as possible and we will handle this with priority.';
  @override
  String get faqActionKlacht => 'File complaint';
  @override
  String get faqQOngepasteGedrag => 'How do I report inappropriate behavior?';
  @override
  String get faqAOngepasteGedrag => 'Create a support request with type Incident and describe what happened. Include the trainer\'s name and possibly the session date. Reports are handled within 24 hours.';
  @override
  String get faqActionIncident => 'Report incident';
  @override
  String get faqQGegevensVeilig => 'Is my data stored securely?';
  @override
  String get faqAGegevensVeilig => 'Yes, we fully comply with GDPR. Your data is stored on secure EU servers. Payments are securely processed via Mollie, a certified payment provider.';
  @override
  String get faqQGegevensOpvragen => 'How can I request my data?';
  @override
  String get faqAGegevensOpvragen => 'You can submit a request via support with type Other. We will send you an overview of all your stored data within 30 days, in accordance with GDPR.';
  @override
  String get faqActionGegevens => 'Submit data request';
  @override
  String get faqQCrash => 'The app keeps crashing';
  @override
  String get faqACrash => 'Try updating the app to the latest version in the App Store or Google Play Store. If the problem persists: delete the app, restart your phone and reinstall the app. Your data is preserved via your account.';
  @override
  String get faqQWitScherm => 'I see a white or blank screen';
  @override
  String get faqAWitScherm => 'This is usually caused by an outdated app version or poor internet. Update the app and check your wifi or mobile data connection. Try fully closing and reopening the app.';
  @override
  String get faqQPushNotificaties => 'Push notifications don\'t work';
  @override
  String get faqAPushNotificaties => 'Check your phone settings → Apps → GYMIES → Notifications and make sure everything is enabled. Also check in the app at Profile → Notifications whether you are receiving notifications.';
  @override
  String get faqQQrScanner => 'QR code scanner doesn\'t work';
  @override
  String get faqAQrScanner => 'Make sure you have given camera permission to the GYMIES app. Go to your phone settings → Apps → GYMIES → Permissions → Camera → Allow. Then restart the app.';

  // ═══ RESTORED KEYS ═══
  @override
  String get automatischVerstuurdZodraJeWeerOnline => 'Automatically sent once you are back online';
  @override
  String get deFactuurIsVerstuurdNaarJe => 'The invoice has been sent to your';
  @override
  String get factuurNietVerstuurd => 'Invoice not sent';
  @override
  String get factuurNogNietVerstuurd => 'Invoice not yet sent';
  @override
  String get factuurOpgesteldEnVerstuurdNaarKlant => 'Invoice created and sent to client';
  @override
  String get factuurVerstuurd => 'Invoice sent';
  @override
  String get factuurverzoekVerstuurdNaarTrainer => 'Invoice request sent to trainer';
  @override
  String get nieuwsbriefVerstuurd => 'Newsletter sent';
  @override
  String get tegenvoorstelVerstuurd => 'Counter-proposal sent';

  // ═══ RESTORED KEYS (BATCH 2) ═══
  @override
  String get feedbackVerstuurd => 'Feedback sent';
  @override
  String get hetBerichtIsVerstuurd => 'The message has been sent';
  @override
  String get incidentMeldingVerstuurd => 'Incident report sent';
  @override
  String get linkVerstuurd => 'Link sent';
  @override
  String get meldingenGemarkeerdAlsGelezen => 'Notifications marked as read';
  @override
  String get messageVerstuurd => 'Message Sent';
  @override
  String get resetLinkVerstuurd => 'Reset Link Sent';
  @override
  String get reviewVerstuurd => 'Review Sent';
  @override
  String get uitnodigingVerstuurd => 'Uitnodiging Sent';
  @override
  String get verificatieCodeVerstuurd => 'Verification Code Sent';
  @override
  String get verzoekVerstuurd => 'Request Sent';
  @override
  String get waarschuwingVerstuurd => 'Waarschuwing Sent';

  // ═══ PHASE 4D — INTERPOLATED STRINGS ═══
  @override
  String get goedGetraindVandaag => 'Great workout today. Until next time!';
  @override
  String get mediaVerwijderenTitle => 'Delete media';
  @override
  String get onbekendBedrag => 'Unknown amount';
  @override
  String get toekomst => 'Future';
  @override
  String get toevoegenMax20Tags => 'Add max 20 tags';
  @override
  String get totMorgen => 'See you tomorrow!';
  @override
  String get videoToevoegen => 'Add video';
  @override
  String get volgendeStapLogin => 'Next step';
  @override
  String get vorigeWeek => 'Last week';
  @override
  String vandaagTijd(String time) => 'Today $time';
  @override
  String morgenTijd(String time) => 'Tomorrow $time';
  @override
  String vandaagTijdFormatted(String hour, String min) => 'Today $hour:$min';
  @override
  String gisterenTijdFormatted(String hour, String min) => 'Yesterday $hour:$min';
  @override
  String voorSessie(String date) => 'For session: $date';
  @override
  String foutBijOpslaan(String error) => 'Error saving: $error';
  @override
  String foutBijOpslaanStatus(String statusCode) => 'Error saving ($statusCode)';
  @override
  String opslaanMislukt(String error) => 'Save failed: $error';
  @override
  String foutBijLadenStats(String error) => 'Error loading stats: $error';
  @override
  String foutBijLadenOpenstaande(String error) => 'Error loading pending: $error';
  @override
  String foutBijLadenGeschiedenis(String error) => 'Error loading history: $error';
  @override
  String betalingGemarkeerd(String info) => 'Payment marked as paid';
  @override
  String snellerInloggenMet(String label) => 'Log in faster with $label. You can always change this later in Settings.';
  @override
  String sessiesEnRevenue(String sessions, String revenue) => '$sessions sessions · €$revenue';
  @override
  String prijsPerSessie(String price) => '€$price/session';

  // ═══ PHASE 4 FIX — MISSING KEYS ═══
  @override
  String get accountVerwijderen => 'Delete account';
  @override
  String get pakketToevoegen => 'Add package';
  @override
  String get pakketVerwijderen => 'Delete package';
  @override
  String get promocodeToevoegen => 'Add promo code';
  @override
  String get promocodeVerwijderenVraag => 'Delete promo code?';
  @override
  String get verstuurd => 'sent';
  @override
  String get videoVerwijderen => 'Delete video';

  // ── PHASE 5: FINAL CLEANUP ──
  @override
  String get fout => 'Error';
  // PHASE 5B: ONBOARDING FEATURES
  // PHASE 5C: ONBOARDING REMAINING
  @override
  String get kvkUittreksel => 'Chamber of Commerce extract';
  @override
  String get idVerificatie => 'ID verification';
  @override
  String get certificering => 'Certification';
  @override
  String get vogOptional => 'VOG (optional)';
  @override
  String get volgende => 'Next';
  @override
  String get geverifieerdCheck => 'Verified ✓';
  @override
  String get afgekeurdX => 'Rejected ✗';
  @override
  String get geupload => 'Uploaded';
  @override
  String get documentUploaden => 'Upload document';
  @override
  String get vogUploaden => 'Upload VOG';
  @override
  String get optioneel => 'optional';
  @override
  String get alleBasisfeatures => 'All basic features';
  @override
  String get planSelecterenOfBetalenMislukt => 'Failed to select plan or start payment';
  @override
  String redenMsg(String reason) => 'Reason: \$reason';
  @override
  String mollieConnectMisluktCode(String code) => 'Mollie Connect failed (\$code).';
  @override
  String get basisAgendaBeheer => 'Basic calendar management';
  @override
  String get emailSupport => 'E-mail support';
  @override
  String get strippenkaartenEnPakketten => 'Punch cards & packages';
  @override
  String get crmEnMarketingTools => 'CRM & marketing tools';
  @override
  String get prioriteitSupport => 'Priority support';
  @override
  String get eigenUrl => 'Custom URL';
  @override
  String get verder => 'Continue';
  @override
  String get retryKlaar => 'Retry done';
  @override
  String get actiesVerstuurd => 'action(s) sent';
  @override
  String get retryWachtrij => 'Retry queue';
  @override
  String get perAbonnementsPlan => 'Per subscription plan';
  @override
  String get vergoedingen => 'Fees';
  @override
  String get mijnInschrijvingen => 'My enrollments';
  @override
  String get voltooid => 'Completed';
  @override
  String get referraltegoed => 'Referral credit';
  @override
  String get wasGoed => 'Was good';
  @override
  String get goedemorgen => 'Good morning!';
  @override
  String get goedeLes => 'Great session!';
  @override
  String get bevestigd => 'Confirmed';
  @override
  String get actie => 'Action';
  @override
  String get nieuweUpdatesVerschijnenHier => 'New updates will appear here.';
  @override
  String get puntenEnTegoed => 'Points & credit';
  @override
  String get bekijkOverzicht => 'View overview';
  @override
  String get mijnDossier => 'My dossier';
  @override
  String get mijnGegevensOpvragen => 'Request my data';
  @override
  String get annuleringsoverzicht => 'Cancellation overview';
  @override
  String get betalingStarten => 'Start payment';
  @override
  String get actiepunten => 'Action items';
  @override
  String get wachtwoordVergeten => 'Forgot password';
  @override
  String get mijnBranding => 'My Branding';
  @override
  String get graagGedaan => 'You\'re welcome!';
  @override
  String get goedBezig => 'Great job!';
  @override
  String get ikStaKlaar => 'I\'m ready';
  @override
  String get totZoChat => 'See you soon!';
  @override
  String get totMorgen => 'See you tomorrow!';
  @override
  String get exportMislukt => 'Export failed';
  @override
  String get bulkBericht => 'Bulk message';
  @override
  String get verstuur => 'Send';
  @override
  String get actief => 'Active';
  @override
  String get inactief => 'Inactive';
  @override
  String get storyUploadMislukt => 'Story upload failed';
  @override
  String get nieuweOpzetKlaar => 'New setup ready';
  @override
  String get ontvangen2 => 'Received';
  @override
  String get transacties => 'Transactions';
  @override
  String get nieuwBericht => 'New message';
  @override
  String get bulkVersturen => 'Bulk send';
  @override
  String get nieuweNieuwsbrief => 'New newsletter';
  @override
  String get actievePromo => 'Active promo';
  @override
  String get mijnEtalage => 'My Storefront';
  @override
  String get gymDashboard => 'Gym Dashboard';
  @override
  String get actieVereist => 'Action required';
  @override
  String get mollieGekoppeld => 'Mollie connected';
  @override
  String get onboarding => 'Onboarding';
  @override
  String get actieveCodes => 'Active codes';
  @override
  String get nieuweGroepsles => 'New group class';
  @override
  String get branding => 'Branding';
  @override
  String get studioEnOnboarding => 'Studio & Onboarding';
  @override
  String get mediaVerwijderen => 'Delete media';
  @override
  String get zoek2 => 'Search';
  @override
  String retryKlaarActies(String sent) => 'Retry done: \$sent action(s) sent';
  @override
  String actiesInRetryQueue(String count) => '\$count action(s) in retry queue';
  @override
  String geenVerplaatsbareSessiesMet(String name) => 'No reschedulable sessions with \$name';
  @override
  String geenVerplaatsbareSessiesBij(String name) => 'No reschedulable sessions with \$name';
  @override
  String goedBezigNaam(String name) => 'Great job \$name! Keep it up 💪';
  @override
  String betalingStartenMislukt(String error) => 'Failed to start payment: \$error';
  @override
  String konAbonnementNietWijzigen(String error) => 'Could not change subscription: \$error';
  @override
  String storyUploadMisluktMsg(String error) => 'Story upload failed: \$error';
  @override
  String exportMisluktMsg(String error) => 'Export failed: \$error';
  @override
  String uploadMisluktMsg(String error) => 'Upload failed: \$error';
  @override
  String mollieConnectMislukt(String error) => 'Mollie Connect failed: \$error';
  @override
  String foutMsg(String error) => 'Error: \$error';
  @override
  String opslaanMisluktMsg(String error) => 'Save failed: \$error';
  @override
  String foutBijOpslaanMsg(String error) => 'Error saving: \$error';
  @override
  String konFotoNietUploaden(String error) => 'Could not upload photo: \$error';
  @override
  String klantenCount(String count) => 'Clients: \$count';
  @override
  String beschikbaarVanaf(String tier) => 'Available from \$tier';
  @override
  String mediaItemsVerwijderd(String count) => '\$count item(s) deleted';
  @override
  String weetJeZekerVerwijderen(String count) => 'Are you sure you want to delete \$count item(s)?';
  @override
  String logSnellerInMet(String label) => 'Log in faster with \$label. You can always change this later in Settings.';
  @override
  String tegoedSuggested(String amount) => 'Credit: \$amount';
  @override
  String waaromWilJeMelden(String name) => 'Why do you want to report \$name?';

}
