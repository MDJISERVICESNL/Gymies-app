import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/promotion.dart';
import '../../services/promotion_service.dart';
import '../../theme/gymies_theme.dart';

/// Invoerveld voor promo-codes op het subscription/onboarding scherm.
/// Valideert de code bij de backend en toont het resultaat.
class PromoCodeField extends StatefulWidget {
  const PromoCodeField({
    super.key,
    required this.promotionService,
    required this.tier,
    this.onPromoValidated,
  });

  final PromotionService promotionService;
  final String tier; // 'starter', 'pro', 'pro_plus'
  final ValueChanged<AvailablePromotion?>? onPromoValidated;

  @override
  State<PromoCodeField> createState() => _PromoCodeFieldState();
}

class _PromoCodeFieldState extends State<PromoCodeField> {
  final _controller = TextEditingController();
  bool _loading = false;
  AvailablePromotion? _validPromo;
  String? _error;

  Future<void> _validate() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _validPromo = null;
    });

    final result = await widget.promotionService.validateCode(code, widget.tier);

    if (!mounted) return;

    setState(() {
      _loading = false;
      _validPromo = result.promotion;
      _error = result.error;
    });

    widget.onPromoValidated?.call(result.promotion);
  }

  void _clear() {
    _controller.clear();
    setState(() {
      _validPromo = null;
      _error = null;
    });
    widget.onPromoValidated?.call(null);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !_loading && _validPromo == null,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: S.of(context).haveACode,
                  hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                  filled: true,
                  fillColor: _validPromo != null
                      ? Colors.green.shade50
                      : Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: _validPromo != null
                        ? BorderSide(color: Colors.green.shade400, width: 1.5)
                        : BorderSide.none,
                  ),
                  suffixIcon: _validPromo != null
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _clear,
                        )
                      : null,
                ),
                onSubmitted: (_) => _validate(),
              ),
            ),
            if (_validPromo == null) ...[
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _loading ? null : _validate,
                  style: FilledButton.styleFrom(
                    backgroundColor: GymiesColors.darkBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(S.of(context).applyAction, style: const TextStyle(fontSize: 14)),
                ),
              ),
            ],
          ],
        ),

        // Succes-melding
        if (_validPromo != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _validPromo!.displayLabel ?? 'Code toegepast!',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.green.shade800,
                        ),
                      ),
                      if (_validPromo!.originalPrice != null &&
                          _validPromo!.price != null)
                        Text(
                          '${_validPromo!.originalPrice} → ${_validPromo!.price}/mnd',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade700,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // Foutmelding
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(
              fontSize: 13,
              color: Colors.red.shade700,
            ),
          ),
        ],
      ],
    );
  }
}
