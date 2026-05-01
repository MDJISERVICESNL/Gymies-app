import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../services/subscription_entitlements_service.dart';
import '../theme/gymies_theme.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_dialog.dart';
import 'widgets/gymies_section_header.dart';
import 'widgets/gymies_segment_tab_bar.dart';
import 'widgets/gymies_upgrade_prompt.dart';
import '../utils/haptics.dart';

class TrainerNewsletterScreen extends StatefulWidget {
  const TrainerNewsletterScreen({super.key});

  @override
  State<TrainerNewsletterScreen> createState() =>
      _TrainerNewsletterScreenState();
}

class _TrainerNewsletterScreenState extends State<TrainerNewsletterScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();

  bool _sending = false;
  bool _showPreview = false;
  bool _isScheduled = false;
  DateTime? _scheduledDateTime;
  String? _error;

  late TabController _tabController;

  // Templates
  final Map<String, Map<String, String>> _templates = {
    'Nieuw schema': {
      'subject': 'Nieuw trainingsschema beschikbaar! 📅',
      'body':
          'Hallo!\n\nJe nieuwe trainingsschema is nu beschikbaar in de app. Bekijk de updates en zorg dat je goed bent voorbereid voor je volgende sessies.\n\nBijzonderheden:\n• Aangepast aan jouw doelen\n• Progressieve oefeningen\n• Flexibel in te delen\n\nBen je klaar? Laten we aan de slag gaan!\n\nGroeten,\nJe trainer'
    },
    'Vakantie': {
      'subject': 'Vakantieperiode – Studio gesloten 🏖️',
      'body':
          'Hallo!\n\nWe willen je graag informeren dat onze studio gesloten is van [datum] tot [datum] vanwege vakantie.\n\nWij zijn dan niet beschikbaar voor sessies, maar je kunt je trainingsplan volgen via de app.\n\nWe kijken ernaar uit je binnenkort weer te zien!\n\nGroeten,\nJe trainer'
    },
    'Actie': {
      'subject': 'Exclusieve actie voor onze klanten! 🎉',
      'body':
          'Hallo!\n\nWe hebben een speciale aanbieding voor jou! Als dank voor je vertrouwen en inzet bieden we dit week:\n\n🎁 [Beschrijving van aanbieding]\n💰 [Voordeel voor jou]\n⏰ Geldig tot [datum]\n\nNot gemist! Dit aanbod is exclusief voor onze vaste klanten.\n\nGroeten,\nJe trainer'
    },
    'Tips': {
      'subject': 'FitnessTip van de week 💪',
      'body':
          'Hallo!\n\nDeze week delen we een waardevolle fitnessTip met je:\n\n📌 [Tip/advies]\n\nWaarom is dit belangrijk?\n[Uitleg van het voordeel]\n\nHoe pas je dit toe?\n[Praktische stappen]\n\nVragen? Laat het weten! Je trainer is altijd beschikbaar.\n\nGroeten,\nJe trainer'
    },
    'Evenement': {
      'subject': 'Kom naar ons event! 🎪',
      'body':
          'Hallo!\n\nWe organiseren een speciaal event en je bent van harte uitgenodigd!\n\n📅 Datum: [datum en tijd]\n📍 Locatie: [adres]\n👥 Wat te verwachten:\n   • [Activiteit 1]\n   • [Activiteit 2]\n   • [Activiteit 3]\n\nSnel aanmelden! Beperkt aantal plaatsen beschikbaar.\n\nGroeten,\nJe trainer'
    },
    'Update': {
      'subject': 'Belangrijk update van je trainer 📢',
      'body':
          'Hallo!\n\nWe willen je graag op de hoogte stellen van de volgende updates:\n\n✅ [Update 1]\n✅ [Update 2]\n✅ [Update 3]\n\nDeze veranderingen helpen ons om je beter van dienst te zijn. Heb je vragen? Neem gerust contact op!\n\nGroeten,\nJe trainer'
    },
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _subjectController.addListener(() => setState(() {}));
    _bodyController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _applyTemplate(String templateName) {
    Haptics.light();
    final template = _templates[templateName];
    if (template != null) {
      _subjectController.text = template['subject'] ?? '';
      _bodyController.text = template['body'] ?? '';
    }
  }

  Future<void> _selectDateTime() async {
    Haptics.light();
    final now = DateTime.now();
    final initialDate = _scheduledDateTime ?? now.add(Duration(days: 1));

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(Duration(days: 365)),
    );

    if (selectedDate == null) return;

    final selectedTime = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay.fromDateTime(_scheduledDateTime ?? DateTime.now()),
    );

    if (selectedTime == null) return;

    setState(() {
      _scheduledDateTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  String _formatScheduledTime() {
    if (_scheduledDateTime == null) return '';
    final day = _scheduledDateTime!.day;
    final month = _scheduledDateTime!.month;
    final year = _scheduledDateTime!.year;
    final hour = _scheduledDateTime!.hour.toString().padLeft(2, '0');
    final minute = _scheduledDateTime!.minute.toString().padLeft(2, '0');
    return '$day-$month-$year om $hour:$minute';
  }

  Future<void> _sendOrScheduleNewsletter() async {
    Haptics.light();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_sending) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final api = context.read<GymiesApi>();

      if (_isScheduled) {
        if (_scheduledDateTime == null) {
          throw Exception('Selecteer een datum en tijd');
        }

        await api.scheduleNewsletter(
          subject: _subjectController.text.trim(),
          body: _bodyController.text.trim(),
          scheduledAt: _scheduledDateTime!,
        );

        if (!mounted) return;

        _subjectController.clear();
        _bodyController.clear();
        setState(() {
          _isScheduled = false;
          _scheduledDateTime = null;
          _sending = false;
        });

        if (mounted) {
          await GymiesDialog.custom<void>(
            context,
            title: 'Ingepland! ✓',
            icon: Icons.schedule,
            iconColor: GymiesColors.primary,
            content: Text(
              'Je nieuwsbrief wordt verstuurd op ${_formatScheduledTime()}',
              textAlign: TextAlign.center,
            ),
            actions: [
              GymiesDialogAction(
                label: 'Sluiten',
                isPrimary: true,
              ),
            ],
            barrierDismissible: false,
          );
        }
      } else {
        final result = await api.sendNewsletter(
          subject: _subjectController.text.trim(),
          body: _bodyController.text.trim(),
        );

        if (!mounted) return;

        final sentTo = result['sent_to'] ?? 0;

        _subjectController.clear();
        _bodyController.clear();

        if (mounted) {
          await GymiesDialog.custom<void>(
            context,
            title: 'Nieuwsbrief verstuurd!',
            icon: Icons.celebration,
            iconColor: GymiesColors.primary,
            content: Text(
              'Nieuwsbrief verstuurd naar $sentTo klanten!',
              textAlign: TextAlign.center,
            ),
            actions: [
              GymiesDialogAction(
                label: 'Sluiten',
                isPrimary: true,
              ),
            ],
            barrierDismissible: false,
          );
        }

        setState(() {
          _sending = false;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;

      String errorMessage = e.message;
      if (e.statusCode == 429 || e.message.contains('429')) {
        errorMessage =
            'Je hebt het limiet bereikt. Maximaal 2 nieuwsbrieven per week.';
      }

      setState(() {
        _error = errorMessage;
        _sending = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      final errorMessage = 'Fout bij versturen/inplannen: ${e.toString()}';
      setState(() {
        _error = errorMessage;
        _sending = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Fout bij versturen/inplannen nieuwsbrief'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ent = context.watch<SubscriptionEntitlementsService>();
    final tierLower = ent.tier?.toLowerCase() ?? 'starter';
    final isProPlus = tierLower.contains('pro_plus') ||
        tierLower.contains('proplus') ||
        tierLower == 'studio';

    if (!isProPlus) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: const GymiesAppBar(title: 'Nieuwsbrief'),
        body: const GymiesUpgradePrompt(
          icon: Icons.newspaper_rounded,
          feature: 'Nieuwsbrief',
          tier: 'Pro+',
          description: 'Stuur nieuwsbrieven naar je klanten met templates en analytics.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Nieuwsbrief',
        bottom: GymiesSegmentTabBar(
          controller: _tabController,
          tabs: const ['Nieuw', 'Verzonden'],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildComposeTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildComposeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: GymiesColors.darkBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.info_outline_rounded, size: 16, color: GymiesColors.darkBlue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Stuur een nieuwsbrief naar al je actieve klanten '
                    '(sessie in de afgelopen 60 dagen). Maximaal 2 per week.',
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Template chips
          GymiesSectionHeader('Sjablonen'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _templates.keys.map((templateName) {
              return FilterChip(
                label: Text(templateName),
                onSelected: (_) => _applyTemplate(templateName),
                backgroundColor: Colors.white,
                side: BorderSide(color: Colors.grey.shade300),
                labelStyle: GoogleFonts.sora(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: GymiesColors.darkBlue,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),

          // Form
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subject field
                GymiesSectionHeader('Onderwerp'),
                TextFormField(
                  controller: _subjectController,
                  maxLength: 200,
                  enabled: !_sending,
                  style: GoogleFonts.sora(),
                  decoration: InputDecoration(
                    hintText:
                        'Bijvoorbeeld: "Nieuw trainingsschema beschikbaar"',
                    counterText: '',
                    contentPadding: const EdgeInsets.all(16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vul een onderwerp in';
                    }
                    if (value.trim().length > 200) {
                      return 'Onderwerp mag niet langer zijn dan 200 tekens';
                    }
                    return null;
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${_subjectController.text.length}/200',
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Body field
                GymiesSectionHeader('Bericht'),
                TextFormField(
                  controller: _bodyController,
                  maxLength: 2000,
                  minLines: 10,
                  maxLines: null,
                  enabled: !_sending,
                  textAlignVertical: TextAlignVertical.top,
                  style: GoogleFonts.sora(),
                  decoration: InputDecoration(
                    hintText:
                        'Schrijf je bericht hier. '
                        'Zorg ervoor dat je klanten goed begrijpen wat je wilt communiceren.',
                    counterText: '',
                    alignLabelWithHint: true,
                    contentPadding: const EdgeInsets.all(16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vul een bericht in';
                    }
                    if (value.trim().length < 10) {
                      return 'Bericht moet minstens 10 tekens lang zijn';
                    }
                    if (value.trim().length > 2000) {
                      return 'Bericht mag niet langer zijn dan 2000 tekens';
                    }
                    return null;
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${_bodyController.text.length}/2000',
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Preview toggle
                GestureDetector(
                  onTap: () {
                    Haptics.light();
                    setState(() {
                      _showPreview = !_showPreview;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _showPreview
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: GymiesColors.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Voorbeeld bekijken',
                                style: GoogleFonts.sora(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                            ],
                          ),
                          Icon(
                            _showPreview
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: Colors.grey.shade600,
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // Preview card (if shown)
                if (_showPreview && _subjectController.text.isNotEmpty)
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Voorbeeld e-mail',
                                style: GoogleFonts.sora(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _subjectController.text,
                                style: GoogleFonts.sora(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                height: 1,
                                color: Colors.grey.shade200,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _bodyController.text,
                                style: GoogleFonts.sora(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),

                // Schedule option
                GymiesSectionHeader('Verzenden'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                            onTap: () {
                              Haptics.light();
                              setState(() {
                                _isScheduled = false;
                                _scheduledDateTime = null;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.send_rounded,
                                    color: !_isScheduled
                                        ? GymiesColors.primary
                                        : Colors.grey.shade400,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Nu versturen',
                                    style: GoogleFonts.sora(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: !_isScheduled
                                          ? GymiesColors.primary
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 50,
                          color: Colors.grey.shade200,
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              Haptics.light();
                              setState(() {
                                _isScheduled = true;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    color: _isScheduled
                                        ? GymiesColors.primary
                                        : Colors.grey.shade400,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Inplannen',
                                    style: GoogleFonts.sora(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: _isScheduled
                                          ? GymiesColors.primary
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // Schedule date/time picker
                if (_isScheduled)
                  Column(
                    children: [
                      GestureDetector(
                        onTap: _selectDateTime,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                          ),
                          child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Verzendtijd',
                                      style: GoogleFonts.sora(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _scheduledDateTime == null
                                          ? 'Klik om datum/tijd te selecteren'
                                          : _formatScheduledTime(),
                                      style: GoogleFonts.sora(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: _scheduledDateTime == null
                                            ? Colors.grey.shade500
                                            : GymiesColors.darkBlue,
                                      ),
                                    ),
                                  ],
                                ),
                                Icon(
                                  Icons.edit_calendar_rounded,
                                  color: GymiesColors.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),

                // Send/Schedule button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _sending ? null : _sendOrScheduleNewsletter,
                    style: FilledButton.styleFrom(
                      backgroundColor: GymiesColors.primary,
                      foregroundColor: GymiesColors.darkBlue,
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isScheduled ? 'Inplannen' : 'Versturen',
                            style: GoogleFonts.sora(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: context.read<GymiesApi>().getTrainerNewsletterHistory(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: GymiesColors.primary,
                strokeWidth: 2,
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: Colors.red.shade400,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Fout bij laden geschiedenis',
                  style: GoogleFonts.sora(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: GymiesColors.darkBlue,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  snapshot.error.toString(),
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final newsletters = snapshot.data ?? [];

        if (newsletters.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.mail_outline_rounded,
                    color: Colors.grey.shade400,
                    size: 56,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Geen nieuwsbrieven verzonden',
                    style: GoogleFonts.sora(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Schrijf en verstuur je eerste nieuwsbrief via het tabblad "Nieuw"',
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: newsletters.length,
          itemBuilder: (context, index) {
            final newsletter = newsletters[index];
            final subject = newsletter['subject'] as String? ?? 'Geen onderwerp';
            final sentDate = newsletter['sent_at'] as String? ?? 'Onbekende datum';
            final recipientCount =
                newsletter['recipient_count'] as int? ?? 0;
            final openRate = (newsletter['open_rate'] as num?)?.toDouble() ?? 0.0;
            final clickRate =
                (newsletter['click_rate'] as num?)?.toDouble() ?? 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject,
                      style: GoogleFonts.sora(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: GymiesColors.darkBlue,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sentDate,
                      style: GoogleFonts.sora(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStatColumn('Ontvangers', '$recipientCount',
                            Icons.person_outline_rounded),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey.shade200,
                        ),
                        _buildStatColumn(
                            'Open rate', '${openRate.toStringAsFixed(1)}%',
                            Icons.mail_outline_rounded),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey.shade200,
                        ),
                        _buildStatColumn(
                            'Click rate', '${clickRate.toStringAsFixed(1)}%',
                            Icons.touch_app_outlined),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatColumn(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: GymiesColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              icon,
              color: GymiesColors.darkBlue,
              size: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.sora(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: GymiesColors.darkBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.sora(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
