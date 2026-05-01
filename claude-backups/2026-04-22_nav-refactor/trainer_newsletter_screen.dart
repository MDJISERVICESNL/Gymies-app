import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_section_header.dart';

class TrainerNewsletterScreen extends StatefulWidget {
  const TrainerNewsletterScreen({super.key});

  @override
  State<TrainerNewsletterScreen> createState() =>
      _TrainerNewsletterScreenState();
}

class _TrainerNewsletterScreenState extends State<TrainerNewsletterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();

  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subjectController.addListener(() => setState(() {}));
    _bodyController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _sendNewsletter() async {
    // Validate form
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
      final result = await api.sendNewsletter(
        subject: _subjectController.text.trim(),
        body: _bodyController.text.trim(),
      );

      if (!mounted) return;

      final sentTo = result['sent_to'] ?? 0;

      // Clear form
      _subjectController.clear();
      _bodyController.clear();

      // Show success dialog
      if (mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return AlertDialog(
              title: Text(
                'Nieuwsbrief verstuurd!',
                style: GoogleFonts.fjallaOne(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  const Icon(
                    Icons.celebration,
                    size: 64,
                    color: GymiesColors.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nieuwsbrief verstuurd naar $sentTo klanten!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Sluiten'),
                ),
              ],
            );
          },
        );
      }

      setState(() {
        _sending = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;

      // Check for rate limit error
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

      final errorMessage = 'Fout bij versturen nieuwsbrief: ${e.toString()}';
      setState(() {
        _error = errorMessage;
        _sending = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Fout bij versturen nieuwsbrief'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: const GymiesAppBar(title: 'Nieuwsbrief'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: GymiesColors.darkBlue, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Stuur een nieuwsbrief naar al je actieve klanten '
                        '(sessie in de afgelopen 60 dagen). Maximaal 2 per week.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Form
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Subject field
                  const GymiesSectionHeader('Onderwerp'),
                  TextFormField(
                    controller: _subjectController,
                    maxLength: 200,
                    enabled: !_sending,
                    decoration: const InputDecoration(
                      hintText: 'Bijvoorbeeld: "Nieuw trainingsschema beschikbaar"',
                      counterText: '',
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Body field
                  const GymiesSectionHeader('Bericht'),
                  TextFormField(
                    controller: _bodyController,
                    maxLength: 1000,
                    minLines: 8,
                    maxLines: null,
                    enabled: !_sending,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      hintText:
                          'Schrijf je bericht hier. '
                          'Zorg ervoor dat je klanten goed begrijpen wat je wilt communiceren.',
                      counterText: '',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Vul een bericht in';
                      }
                      if (value.trim().length < 10) {
                        return 'Bericht moet minstens 10 tekens lang zijn';
                      }
                      if (value.trim().length > 1000) {
                        return 'Bericht mag niet langer zijn dan 1000 tekens';
                      }
                      return null;
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${_bodyController.text.length}/1000',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Send button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _sending ? null : _sendNewsletter,
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
                          : const Text('Versturen',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
