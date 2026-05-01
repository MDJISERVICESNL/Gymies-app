import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/gymies_theme.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import '../utils/haptics.dart';
import 'mollie_connect_webview_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_dialog.dart';

/// Trainer onboarding: documenten, Mollie, abonnement.
/// Trainers kunnen overslaan; dan is account niet actief en dashboard toont "Activeer je account".
class TrainerOnboardingScreen extends StatefulWidget {
  const TrainerOnboardingScreen({
    super.key,
    this.mollieConnectSuccess = false,
    this.initialStep,
  });

  /// Bij deep link gymies://mollie-connect/success – toon direct success-dialog.
  final bool mollieConnectSuccess;

  /// Start direct op deze stap (0–5). Bijv. 4 = Mollie koppelen.
  final int? initialStep;

  @override
  State<TrainerOnboardingScreen> createState() => _TrainerOnboardingScreenState();
}

class _TrainerOnboardingScreenState extends State<TrainerOnboardingScreen> {
  int _currentStep = 0;
  bool _loading = true;
  Map<String, dynamic> _status = {};
  List<Map<String, dynamic>> _plans = [];
  String? _selectedPlanId;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.mollieConnectSuccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showMollieSuccessDialog();
      });
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final api = context.read<GymiesApi>();
      final status = await api.getOnboardingStatus();
      final plans = await api.getPlans();
      if (!mounted) return;
      final step = status['current_step'] as String? ?? 'documents';
      final stepIndex = switch (step) {
        'mollie_connect' => 4,
        'select_plan' => 5,
        'completed' => 6,
        _ => _determineDocStep(status),
      };
      setState(() {
        _status = status;
        _plans = plans;
        _currentStep = widget.initialStep != null &&
                widget.initialStep! >= 0 &&
                widget.initialStep! <= 5
            ? widget.initialStep!
            : stepIndex;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  int _determineDocStep(Map<String, dynamic> status) {
    final docs = status['documents'] as Map<String, dynamic>? ?? {};
    if (_docUploaded(docs, 'kvk_extract')) {
      if (_docUploaded(docs, 'id_document')) {
        if (_docUploaded(docs, 'certification')) return 3;
        return 2;
      }
      return 1;
    }
    return 0;
  }

  bool _docUploaded(Map<String, dynamic> docs, String category) {
    final doc = docs[category] as Map<String, dynamic>?;
    return doc?['uploaded'] == true;
  }

  Future<void> _uploadDocument(String category) async {
    Haptics.light();
    final api = context.read<GymiesApi>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final file = result.files.single;
      List<int> bytes = file.bytes ?? [];
      if (bytes.isEmpty) {
        try {
          bytes = await file.xFile.readAsBytes();
        } catch (_) {}
      }
      if (bytes.isEmpty) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Bestand kon niet worden gelezen.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final fileName = file.name.isNotEmpty ? file.name : 'document.pdf';
      setState(() => _loading = true);
      await api.uploadOnboardingDocument(
            category: category,
            fileBytes: bytes,
            fileName: fileName,
          );
      await _load();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Document geüpload.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(e.message.isNotEmpty ? e.message : 'Upload mislukt'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Upload mislukt: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startMollieConnect() async {
    Haptics.selection();
    setState(() => _loading = true);
    try {
      final api = context.read<GymiesApi>();
      final result = await api.startOnboardingMollieConnect();
      final redirectUrl = result['redirect_url'] as String?;
      if (redirectUrl == null || redirectUrl.isEmpty) {
        final msg = result['message'] as String? ??
            'Geen Mollie-link ontvangen. Configureer MOLLIE_CLIENT_ID op de server.';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red),
          );
        }
        return;
      }
      if (!mounted) return;
      final success = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => MollieConnectWebViewScreen(initialUrl: redirectUrl),
        ),
      );
      if (!mounted) return;
      if (success == true) {
        await _load();
        if (!mounted) return;
        _showMollieSuccessDialog();
      }
    } on ApiException catch (e) {
      if (mounted) {
        final msg = e.message.isNotEmpty
            ? e.message
            : (e.statusCode == 422
                ? 'Mollie Connect kan nu niet gestart worden.'
                : 'Mollie Connect mislukt (${e.statusCode}).');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mollie Connect mislukt: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMollieSuccessDialog() {
    GymiesDialog.success(
      context,
      title: 'Mollie gekoppeld',
      message: 'Het is gelukt om te verbinden met Mollie. Je kunt nu betalingen ontvangen van klanten.',
      icon: Icons.check_circle_rounded,
      buttonLabel: 'Verder',
    ).then((_) {
      if (mounted) setState(() => _currentStep = 5);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _status.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: const GymiesAppBar(title: 'Onboarding'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_currentStep >= 6) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: const GymiesAppBar(title: 'Onboarding'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 80),
                const SizedBox(height: 16),
                Text(
                  'Onboarding voltooid!',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Je account is klaar. Je kunt nu sessies aanbieden.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: GymiesColors.primary,
                    foregroundColor: GymiesColors.darkBlue,
                  ),
                  child: const Text('Naar Dashboard'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: const GymiesAppBar(title: 'Trainer Onboarding'),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () async {
          if (_currentStep == 5) {
            final planId = _selectedPlanId ??
                _plans.firstOrNull?['id']?.toString() ??
                _plans.firstOrNull?['plan_id']?.toString() ??
                'starter';
            String slug = 'starter';
            for (final p in _plans) {
              final s = (p['slug'] ?? p['plan_slug'] ?? '').toString().toLowerCase();
              final id = p['id']?.toString() ?? p['plan_id']?.toString();
              if (id == planId || s == planId.toString().toLowerCase()) {
                slug = s.isNotEmpty ? s : 'starter';
                break;
              }
            }
            if (slug.isEmpty) {
              slug = planId.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
            }
            if (slug.isEmpty) slug = 'starter';
            final api = context.read<GymiesApi>();
            final messenger = ScaffoldMessenger.of(context);
            setState(() => _loading = true);
            try {
              await api.selectOnboardingPlan(planId);
              final paymentData = await api.startSubscriptionPayment(slug);
              final paymentUrl = (paymentData['payment_url'] ?? paymentData['url'] ?? '').toString();
              if (paymentUrl.isEmpty) {
                if (mounted) setState(() => _currentStep = 6);
                return;
              }
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(
                  content: Text(
                    'Je wordt doorgestuurd naar de betaalpagina. Na betaling keer je terug naar de app.',
                  ),
                  backgroundColor: Colors.green,
                ),
              );
              final uri = Uri.parse(paymentUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              if (mounted) setState(() => _currentStep = 6);
            } catch (e) {
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      e is ApiException ? e.message : 'Plan selecteren of betalen mislukt: $e',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            } finally {
              if (mounted) setState(() => _loading = false);
            }
          } else if (_currentStep < 5) {
            setState(() => _currentStep++);
          }
        },
        onStepCancel: _currentStep > 0 ? () => setState(() => _currentStep--) : null,
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                FilledButton(
                  onPressed: _loading
                      ? null
                      : () {
                          Haptics.light();
                          details.onStepContinue?.call();
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: GymiesColors.primary,
                    foregroundColor: GymiesColors.darkBlue,
                  ),
                  child: Text(_currentStep == 5 ? 'Betaal en afronden' : 'Volgende'),
                ),
                if (details.onStepCancel != null) ...[
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () {
                      Haptics.selection();
                      details.onStepCancel?.call();
                    },
                    child: const Text('Terug'),
                  ),
                ],
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Haptics.selection();
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Overslaan voor nu',
                    style: GoogleFonts.sora(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ),
              ],
            ),
          );
        },
        steps: [
          _buildDocStep(
            0,
            'KvK-uittreksel',
            'kvk_extract',
            'Upload je Kamer van Koophandel uittreksel (PDF of afbeelding).',
          ),
          _buildDocStep(
            1,
            'ID-verificatie',
            'id_document',
            'Paspoort, ID-kaart of rijbewijs (geldig). We verwerken dit volgens de AVG.',
          ),
          _buildDocStep(
            2,
            'Certificering',
            'certification',
            'Upload je fitness-certificering of diploma.',
          ),
          _buildDocStepOptional(
            3,
            'VOG (optioneel)',
            'vog',
            'Verklaring Omtrent het Gedrag — niet verplicht, wel aanbevolen.',
          ),
          Step(
            title: const Text('Mollie koppelen'),
            subtitle: const Text('Ontvang betalingen direct op je rekening'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Koppel je Mollie-account zodat klanten direct aan jou kunnen betalen.',
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _startMollieConnect,
                  icon: const Icon(Icons.link),
                  label: const Text('Mollie Connect starten'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GymiesColors.darkBlue,
                    side: const BorderSide(color: GymiesColors.primary),
                  ),
                ),
              ],
            ),
            isActive: _currentStep >= 4,
            state: _currentStep > 4 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('Abonnement kiezen'),
            subtitle: const Text('Kies je Gymies-plan'),
            content: _PlanSelector(
              plans: _plans,
              selectedPlanId: _selectedPlanId,
              onChanged: (planId) => setState(() => _selectedPlanId = planId),
            ),
            isActive: _currentStep >= 5,
            state: _currentStep > 5 ? StepState.complete : StepState.indexed,
          ),
        ],
      ),
    );
  }

  Step _buildDocStep(int index, String title, String category, String description) {
    final docs = _status['documents'] as Map<String, dynamic>? ?? {};
    final doc = docs[category] as Map<String, dynamic>?;
    final uploaded = doc?['uploaded'] == true;
    final verified = doc?['verified'] == true;
    final rejected = doc?['rejected'] == true;

    return Step(
      title: Text(title),
      subtitle: uploaded
          ? Text(verified ? 'Geverifieerd ✓' : (rejected ? 'Afgekeurd ✗' : 'Geüpload'))
          : const Text('Nog niet geüpload'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description),
          if (rejected && doc?['rejection_reason'] != null) ...[
            const SizedBox(height: 8),
            Text(
              'Reden: ${doc!['rejection_reason']}',
              style: GoogleFonts.sora(color: Colors.red),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              Haptics.light();
              _uploadDocument(category);
            },
            icon: const Icon(Icons.upload_file),
            label: Text(uploaded ? 'Opnieuw uploaden' : 'Document uploaden'),
            style: OutlinedButton.styleFrom(
              foregroundColor: GymiesColors.darkBlue,
              side: const BorderSide(color: GymiesColors.primary),
            ),
          ),
        ],
      ),
      isActive: _currentStep >= index,
      state: uploaded
          ? (verified ? StepState.complete : StepState.editing)
          : StepState.indexed,
    );
  }

  Step _buildDocStepOptional(int index, String title, String category, String description) {
    final docs = _status['documents'] as Map<String, dynamic>? ?? {};
    final doc = docs[category] as Map<String, dynamic>?;
    final uploaded = doc?['uploaded'] == true;
    final verified = doc?['verified'] == true;

    return Step(
      title: Text('$title (optioneel)'),
      subtitle: uploaded
          ? Text(verified ? 'Geverifieerd ✓' : 'Geüpload')
          : const Text('Overslaan mag'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              Haptics.light();
              _uploadDocument(category);
            },
            icon: const Icon(Icons.upload_file),
            label: Text(uploaded ? 'Opnieuw uploaden' : 'VOG uploaden'),
            style: OutlinedButton.styleFrom(
              foregroundColor: GymiesColors.darkBlue,
              side: const BorderSide(color: GymiesColors.primary),
            ),
          ),
        ],
      ),
      isActive: _currentStep >= index,
      state: uploaded
          ? (verified ? StepState.complete : StepState.editing)
          : StepState.complete,
    );
  }
}

class _PlanSelector extends StatefulWidget {
  const _PlanSelector({
    required this.plans,
    required this.selectedPlanId,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> plans;
  final String? selectedPlanId;
  final void Function(String planId) onChanged;

  @override
  State<_PlanSelector> createState() => _PlanSelectorState();
}

class _PlanSelectorState extends State<_PlanSelector> {
  String? _localSlug;

  @override
  Widget build(BuildContext context) {
    final plans = widget.plans;
    if (plans.isEmpty) {
      final slug = _localSlug ?? 'starter';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Geen plannen beschikbaar. Laad opnieuw.'),
          const SizedBox(height: 16),
          _PlanCard(
            planId: 'starter',
            slug: 'starter',
            name: 'Gymies Starter',
            price: '€27,99/mnd',
            features: const ['Eigen profiel op Gymies', 'Onbeperkte boekingen', 'Basis agenda beheer', 'E-mail support'],
            selected: slug == 'starter',
            onTap: () {
              Haptics.selection();
              setState(() => _localSlug = 'starter');
              widget.onChanged('starter');
            },
          ),
          const SizedBox(height: 8),
          _PlanCard(
            planId: 'pro',
            slug: 'pro',
            name: 'Gymies Pro',
            price: '€64,99/mnd',
            features: const ['Alles van Starter', 'Groepslessen beheer', 'Strippenkaarten & pakketten', 'CRM & marketing tools', 'Prioriteit support'],
            selected: slug == 'pro',
            onTap: () {
              Haptics.selection();
              setState(() => _localSlug = 'pro');
              widget.onChanged('pro');
            },
          ),
          const SizedBox(height: 8),
          _PlanCard(
            planId: 'pro_plus',
            slug: 'pro_plus',
            name: 'Gymies Pro+',
            price: '€79,99/mnd',
            features: const ['Alles van Pro', 'Eigen branded profiel', 'Eigen URL', 'Verified trainer badge', 'Klant analytics'],
            selected: slug == 'pro_plus',
            onTap: () {
              Haptics.selection();
              setState(() => _localSlug = 'pro_plus');
              widget.onChanged('pro_plus');
            },
          ),
        ],
      );
    }

    return RadioGroup<String>(
      groupValue: _localSlug ?? widget.selectedPlanId ?? 'starter',
      onChanged: (v) {
        if (v != null) {
          Haptics.selection();
          setState(() => _localSlug = v);
          widget.onChanged(v);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: plans.map((p) {
            final id = p['id']?.toString() ?? p['plan_id']?.toString();
            final slug = (p['slug'] ?? p['plan_slug'] ?? 'starter').toString().toLowerCase();
            final name = p['name'] ?? p['plan_name'] ?? 'Plan';
            final price = p['price'] ?? p['amount'] ?? p['price_label'] ?? '';
            final features = (p['features'] as List?)?.map((e) => e.toString()).toList() ?? [];
            final isSelected = widget.selectedPlanId == id ||
                widget.selectedPlanId == slug ||
                (_localSlug == null && slug == 'starter');
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PlanCard(
                planId: id ?? slug,
                slug: slug,
                name: name,
                price: price is String ? price : '€${price ?? ''}/mnd',
                features: features.isNotEmpty ? features : ['Alle basisfeatures'],
                selected: isSelected,
                onTap: () {
                  Haptics.selection();
                  setState(() => _localSlug = slug);
                  widget.onChanged(id ?? slug);
                },
              ),
            );
        }).toList(),
      ),
    );
  }

}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.planId,
    required this.slug,
    required this.name,
    required this.price,
    required this.features,
    required this.selected,
    required this.onTap,
  });

  final String planId;
  final String slug;
  final String name;
  final String price;
  final List<String> features;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: selected
              ? Border.all(color: GymiesColors.primary, width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.08 : 0.04),
              blurRadius: selected ? 12 : 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Radio<String>(
                value: slug,
                activeColor: GymiesColors.darkBlue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      price,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: GymiesColors.primary,
                          ),
                    ),
                    const SizedBox(height: 4),
                    ...features.map((f) => Row(
                          children: [
                            const Icon(Icons.check, size: 16, color: Colors.green),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                f,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
