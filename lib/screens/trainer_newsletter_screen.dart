import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
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
  // ignore: unused_field
  String? _error;

  late TabController _tabController;
  late Future<List<Map<String, dynamic>>> _historyFuture;

  // Templates
  final Map<String, Map<String, String>> _templates = {
    'Nieuw schema': {
      'subject': S.of(context).nieuwTrainingsschemaBeschikbaar,
      'body':
          S.of(context).hallonnjeNieuweTrainingsschemaIsNuBeschikbaar
    },
    'Vakantie': {
      'subject': 'Vakantieperiode – Studio gesloten 🏖️',
      'body':
          S.of(context).hallonnweWillenJeGraagInformerenDat
    },
    'Actie': {
      'subject': S.of(context).exclusieveActieVoorOnzeKlanten,
      'body':
          S.of(context).hallonnweHebbenEenSpecialeAanbiedingVoor
    },
    'Tips': {
      'subject': S.of(context).fitnesstipVanDeWeek,
      'body':
          S.of(context).hallonndezeWeekDelenWeEenWaardevolle
    },
    'Evenement': {
      'subject': S.of(context).komNaarOnsEvent,
      'body':
          S.of(context).hallonnweOrganiserenEenSpeciaalEventEn
    },
    'Update': {
      'subject': S.of(context).belangrijkUpdateVanJeTrainer,
      'body':
          S.of(context).hallonnweWillenJeGraagOpDe
    },
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _subjectController.addListener(() => setState(() {}));
    _bodyController.addListener(() => setState(() {}));
    _historyFuture = context.read<GymiesApi>().getTrainerNewsletterHistory();
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

    if (!mounted) return;
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
          throw Exception(S.of(context).selecteerEenDatumEnTijd);
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
            title: S.of(context).nieuwsbriefVerstuurd,
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
            S.of(context).jeHebtHetLimietBereiktMaximaal;
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
            content: const Text(S.of(context).foutBijVerstureninplannenNieuwsbrief),
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
        appBar: const GymiesAppBar(title: S.of(context).newsletterLabel),
        body: const GymiesUpgradePrompt(
          icon: Icons.newspaper_rounded,
          feature: S.of(context).newsletterLabel,
          tier: 'Pro+',
          description: S.of(context).stuurNieuwsbrievenNaarJeKlantenMet,
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: S.of(context).newsletterLabel,
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
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: GymiesColors.darkBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.info_outline_rounded, size: 16, color: GymiesColors.darkBlue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    S.of(context).stuurEenNieuwsbriefNaarAlJe
                    S.of(context).sessieInDeAfgelopen60Dagen,
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
                        S.of(context).bijvoorbeeldNieuwTrainingsschemaBeschikbaar,
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
                      return S.of(context).vulEenOnderwerpIn;
                    }
                    if (value.trim().length > 200) {
                      return S.of(context).onderwerpMagNietLangerZijnDan;
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
                GymiesSectionHeader(S.of(context).bericht),
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
                        S.of(context).schrijfJeBerichtHier
                        S.of(context).zorgErvoorDatJeKlantenGoed,
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
                      return S.of(context).vulEenBerichtIn;
                    }
                    if (value.trim().length < 10) {
                      return S.of(context).berichtMoetMinstens10TekensLang;
                    }
                    if (value.trim().length > 2000) {
                      return S.of(context).berichtMagNietLangerZijnDan;
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
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
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
                                S.of(context).voorbeeldBekijken,
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
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                S.of(context).voorbeeldEmail,
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
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
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
                                    S.of(context).nuVersturen,
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
                                    S.of(context).inplannen,
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
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
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
                                      S.of(context).verzendtijd,
                                      style: GoogleFonts.sora(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _scheduledDateTime == null
                                          ? S.of(context).klikOmDatumtijdTeSelecteren
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
                            _isScheduled ? S.of(context).inplannen : S.of(context).submitLabel,
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
      future: _historyFuture,
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
                  S.of(context).foutBijLadenGeschiedenis,
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
                    S.of(context).geenNieuwsbrievenVerzonden,
                    style: GoogleFonts.sora(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.of(context).schrijfEnVerstuurJeEersteNieuwsbrief,
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
            final subject = newsletter['subject'] as String? ?? S.of(context).geenOnderwerp;
            final sentDate = newsletter['sent_at'] as String? ?? S.of(context).onbekendeDatum;
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
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
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
              color: GymiesColors.primary.withOpacity(0.12),
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
