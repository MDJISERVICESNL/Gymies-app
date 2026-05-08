import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';

/// Full-screen rich text newsletter compose screen.
///
/// Uses a WebView with `contenteditable` to provide WYSIWYG editing with
/// bold, italic, underline, lists, and headings — outputs HTML for email.
class TrainerNewsletterComposeScreen extends StatefulWidget {
  const TrainerNewsletterComposeScreen({super.key});

  @override
  State<TrainerNewsletterComposeScreen> createState() =>
      _TrainerNewsletterComposeScreenState();
}

class _TrainerNewsletterComposeScreenState
    extends State<TrainerNewsletterComposeScreen> {
  final _subjectCtrl = TextEditingController();
  final _subjectFocus = FocusNode();
  late final WebViewController _webCtrl;

  bool _sending = false;
  bool _editorReady = false;

  // Formatting state (updated from JS)
  bool _isBold = false;
  bool _isItalic = false;
  bool _isUnderline = false;
  bool _isList = false;
  bool _isOrderedList = false;

  // ── Templates ──────────────────────────────────────────────
  static const _templates = <_NewsletterTemplate>[
    _NewsletterTemplate(
      icon: Icons.fitness_center_rounded,
      label: 'Nieuw schema',
      subject: S.of(context).nieuwTrainingsschemaBeschikbaar2,
      html: '<p>Hallo!</p>'
          S.of(context).pjeNieuweTrainingsschemaIsNuBeschikbaar
          S.of(context).bekijkDeUpdatesEnZorgDat
          '<p><b>Bijzonderheden:</b></p>'
          S.of(context).ulliaangepastAanJouwDoelenli
          '<li>Progressieve oefeningen</li>'
          S.of(context).liflexibelInTeDelenliul
          S.of(context).pbenJeKlaarLatenWeAan
          S.of(context).pgroetenbrjeTrainerp,
    ),
    _NewsletterTemplate(
      icon: Icons.beach_access_rounded,
      label: 'Vakantie',
      subject: 'Vakantieperiode – Studio gesloten',
      html: '<p>Hallo!</p>'
          S.of(context).pweWillenJeGraagInformerenDat
          S.of(context).vanBdatumbTotBdatumbVanwegeVakantiep
          S.of(context).pwijZijnDanNietBeschikbaarVoor
          S.of(context).jeTrainingsplanVolgenViaDeAppp
          S.of(context).pweKijkenErnaarUitJeBinnenkort
          S.of(context).pgroetenbrjeTrainerp,
    ),
    _NewsletterTemplate(
      icon: Icons.local_offer_rounded,
      label: S.of(context).actie,
      subject: S.of(context).exclusieveActieVoorOnzeKlanten2,
      html: '<p>Hallo!</p>'
          S.of(context).pweHebbenEenSpecialeAanbiedingVoor
          S.of(context).alsDankVoorJeVertrouwenEn
          S.of(context).ullibbeschrijvingVanAanbiedingbli
          S.of(context).livoordeelVoorJouli
          '<li>Geldig tot <b>[datum]</b></li></ul>'
          S.of(context).pnietGemistDitAanbodIsExclusief
          S.of(context).pgroetenbrjeTrainerp,
    ),
    _NewsletterTemplate(
      icon: Icons.lightbulb_outline_rounded,
      label: 'Tips',
      subject: S.of(context).fitnesstipVanDeWeek2,
      html: '<p>Hallo!</p>'
          S.of(context).pdezeWeekDelenWeEenWaardevolle
          '<h2>[Tip/advies]</h2>'
          S.of(context).pbwaaromIsDitBelangrijkbbruitlegVanHet
          S.of(context).pbhoePasJeDitToebbrpraktischeStappenp
          S.of(context).pvragenLaatHetWetenJeTrainer
          S.of(context).pgroetenbrjeTrainerp,
    ),
    _NewsletterTemplate(
      icon: Icons.event_rounded,
      label: 'Evenement',
      subject: S.of(context).komNaarOnsEvent2,
      html: '<p>Hallo!</p>'
          S.of(context).pweOrganiserenEenSpeciaalEventEn
          S.of(context).pbdatumbDatumEnTijdbr
          '<b>Locatie:</b> [adres]</p>'
          S.of(context).pbwatTeVerwachtenbp
          '<ul><li>[Activiteit 1]</li>'
          '<li>[Activiteit 2]</li>'
          '<li>[Activiteit 3]</li></ul>'
          S.of(context).psnelAanmeldenBeperktAantalPlaatsenBeschikbaarp
          S.of(context).pgroetenbrjeTrainerp,
    ),
    _NewsletterTemplate(
      icon: Icons.campaign_rounded,
      label: 'Update',
      subject: S.of(context).belangrijkUpdateVanJeTrainer2,
      html: '<p>Hallo!</p>'
          S.of(context).pweWillenJeGraagOpDe
          '<ul><li>[Update 1]</li>'
          '<li>[Update 2]</li>'
          '<li>[Update 3]</li></ul>'
          S.of(context).pdezeVeranderingenHelpenOnsOmJe
          S.of(context).hebJeVragenNeemGerustContact
          S.of(context).pgroetenbrjeTrainerp,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initEditor();
  }

  void _initEditor() {
    _webCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0D1B2A))
      ..addJavaScriptChannel('Flutter', onMessageReceived: _onJsMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _editorReady = true);
        },
      ))
      ..loadHtmlString(_editorHtml, baseUrl: 'about:blank');
  }

  void _onJsMessage(JavaScriptMessage msg) {
    try {
      final data = jsonDecode(msg.message);
      if (data['type'] == 'formatState' && mounted) {
        setState(() {
          _isBold = data['bold'] == true;
          _isItalic = data['italic'] == true;
          _isUnderline = data['underline'] == true;
          _isList = data['insertUnorderedList'] == true;
          _isOrderedList = data['insertOrderedList'] == true;
        });
      }
    } catch (e) {
      // Fail-open: Format state parsing failed, UI state remains unchanged
      if (kDebugMode) debugPrint('[NewsletterCompose] Parse format state failed: $e');
    }
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _subjectFocus.dispose();
    super.dispose();
  }

  // ── Editor HTML ────────────────────────────────────────────
  static const _editorHtml = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body {
    height: 100%;
    background: #0D1B2A;
    color: #E8E8E8;
    font-family: -apple-system, BlinkMacSystemFont, S.of(context).segoeUi, Roboto, sans-serif;
    font-size: 15px;
    line-height: 1.6;
    -webkit-text-size-adjust: none;
  }
  #editor {
    min-height: 100%;
    padding: 16px;
    outline: none;
    caret-color: #FEBE23;
    word-wrap: break-word;
    overflow-wrap: break-word;
  }
  #editor:empty::before {
    content: S.of(context).schrijfJeNieuwsbrief;
    color: rgba(255,255,255,0.3);
    pointer-events: none;
  }
  #editor h2 {
    font-size: 20px;
    font-weight: 700;
    color: #FFFFFF;
    margin: 12px 0 6px;
  }
  #editor h3 {
    font-size: 17px;
    font-weight: 600;
    color: #FFFFFF;
    margin: 10px 0 4px;
  }
  #editor b, #editor strong { font-weight: 700; color: #FFFFFF; }
  #editor i, #editor em { font-style: italic; }
  #editor u { text-decoration: underline; text-decoration-color: #FEBE23; }
  #editor ul, #editor ol {
    padding-left: 24px;
    margin: 8px 0;
  }
  #editor li { margin: 4px 0; }
  #editor a { color: #FEBE23; text-decoration: underline; }
  #editor blockquote {
    border-left: 3px solid #FEBE23;
    padding-left: 12px;
    margin: 8px 0;
    color: rgba(255,255,255,0.7);
  }
  ::selection {
    background: rgba(254, 190, 35, 0.35);
  }
</style>
</head>
<body>
<div id="editor" contenteditable="true"></div>
<script>
  const editor = document.getElementById('editor');

  function sendState() {
    const state = {
      type: 'formatState',
      bold: document.queryCommandState('bold'),
      italic: document.queryCommandState('italic'),
      underline: document.queryCommandState('underline'),
      insertUnorderedList: document.queryCommandState('insertUnorderedList'),
      insertOrderedList: document.queryCommandState('insertOrderedList'),
    };
    Flutter.postMessage(JSON.stringify(state));
  }

  editor.addEventListener('input', sendState);
  editor.addEventListener('keyup', sendState);
  editor.addEventListener('mouseup', sendState);
  document.addEventListener('selectionchange', sendState);

  function execCmd(cmd, value) {
    document.execCommand(cmd, false, value || null);
    editor.focus();
    sendState();
  }

  function setHTML(html) {
    editor.innerHTML = html;
    editor.focus();
    sendState();
  }

  function getHTML() {
    return editor.innerHTML;
  }

  function getTextLength() {
    return (editor.innerText || '').trim().length;
  }

  editor.focus();
</script>
</body>
</html>
''';

  // ── Formatting commands ────────────────────────────────────
  void _execCommand(String cmd, [String? value]) {
    Haptics.selection();
    _webCtrl.runJavaScript("execCmd('$cmd'${value != null ? ",'$value'" : ''})");
  }

  // ── Apply template ─────────────────────────────────────────
  void _applyTemplate(_NewsletterTemplate tpl) {
    Haptics.selection();
    _subjectCtrl.text = tpl.subject;
    // Escape single quotes and backslashes for JS string
    final escaped = tpl.html
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'");
    _webCtrl.runJavaScript("setHTML('$escaped')");
  }

  void _showTemplatePicker() {
    Haptics.selection();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GymiesColors.darkBlue,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  S.of(context).kiesEenTemplate,
                  style: GoogleFonts.sora(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  S.of(context).startMetEenVoorgeschrevenMail,
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
                const SizedBox(height: 16),
                // Template grid (2 columns)
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.4,
                  children: _templates.map((tpl) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _applyTemplate(tpl);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Row(
                          children: [
                            Icon(tpl.icon, size: 18, color: GymiesColors.primary.withOpacity(0.7)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tpl.label,
                                style: GoogleFonts.sora(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withOpacity(0.8),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Send ───────────────────────────────────────────────────
  Future<void> _send() async {
    final subject = _subjectCtrl.text.trim();
    if (subject.isEmpty) {
      _subjectFocus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(S.of(context).vulEenOnderwerpIn),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Get text length for minimum validation
    final lengthRaw =
        await _webCtrl.runJavaScriptReturningResult('getTextLength()');
    final textLen = int.tryParse(lengthRaw.toString()) ?? 0;
    if (textLen < 10) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(S.of(context).schrijfMinimaal10Tekens),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Get HTML body
    final htmlRaw =
        await _webCtrl.runJavaScriptReturningResult('getHTML()');
    // runJavaScriptReturningResult wraps strings in quotes on some platforms
    String htmlBody = htmlRaw.toString();
    if (htmlBody.startsWith('"') && htmlBody.endsWith('"')) {
      htmlBody = htmlBody.substring(1, htmlBody.length - 1);
      // Unescape JS string escapes
      htmlBody = htmlBody
          .replaceAll(r'\"', '"')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\/', '/')
          .replaceAll(r'\\', r'\');
    }

    setState(() => _sending = true);

    try {
      // ignore: use_build_context_synchronously
      await context.read<GymiesApi>().sendNewsletter(
            subject: subject,
            body: htmlBody,
          );
      if (!mounted) return;
      Haptics.light();
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(S.of(context).nieuwsbriefVerstuurd),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
      // ignore: use_build_context_synchronously
      Navigator.of(context).pop(true); // Return true = sent
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(S.of(context).versturenMisluktProbeerOpnieuw),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: GymiesColors.darkBlue,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
        ),
        title: Text(
          S.of(context).nieuwsbrief,
          style: GoogleFonts.sora(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: GymiesColors.primary,
                    ),
                  )
                : GestureDetector(
                    onTap: _send,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: GymiesColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        S.of(context).versturen,
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Subject field ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: GymiesColors.darkBlue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.of(context).onderwerp,
                  style: GoogleFonts.sora(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: Colors.white.withOpacity(0.35),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      inputDecorationTheme: const InputDecorationTheme(
                        filled: false,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    child: TextField(
                      controller: _subjectCtrl,
                      focusNode: _subjectFocus,
                      style: GoogleFonts.sora(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                      cursorColor: GymiesColors.primary,
                      decoration: InputDecoration(
                        hintText: S.of(context).typJeOnderwerpHier,
                        hintStyle: GoogleFonts.sora(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withOpacity(0.25),
                        ),
                        filled: false,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Templates bar ──
          GestureDetector(
            onTap: _showTemplatePicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: GymiesColors.primary.withOpacity(0.08),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 16, color: GymiesColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    S.of(context).kiesEenTemplate,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: GymiesColors.primary,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward_ios_rounded, size: 12, color: GymiesColors.primary.withOpacity(0.5)),
                ],
              ),
            ),
          ),

          // ── Editor (WebView) ──
          Expanded(
            child: _editorReady
                ? WebViewWidget(controller: _webCtrl)
                : const Center(
                    child: CircularProgressIndicator(
                      color: GymiesColors.primary,
                      strokeWidth: 2,
                    ),
                  ),
          ),

          // ── Formatting toolbar ──
          Container(
            padding: EdgeInsets.only(bottom: bottomPad > 0 ? 0 : 8),
            decoration: BoxDecoration(
              color: GymiesColors.darkBlue,
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    _ToolbarBtn(
                      icon: Icons.format_bold_rounded,
                      active: _isBold,
                      onTap: () => _execCommand('bold'),
                    ),
                    _ToolbarBtn(
                      icon: Icons.format_italic_rounded,
                      active: _isItalic,
                      onTap: () => _execCommand('italic'),
                    ),
                    _ToolbarBtn(
                      icon: Icons.format_underlined_rounded,
                      active: _isUnderline,
                      onTap: () => _execCommand('underline'),
                    ),
                    _divider(),
                    _ToolbarBtn(
                      icon: Icons.format_list_bulleted_rounded,
                      active: _isList,
                      onTap: () => _execCommand('insertUnorderedList'),
                    ),
                    _ToolbarBtn(
                      icon: Icons.format_list_numbered_rounded,
                      active: _isOrderedList,
                      onTap: () => _execCommand('insertOrderedList'),
                    ),
                    _divider(),
                    _ToolbarBtn(
                      icon: Icons.title_rounded,
                      active: false,
                      tooltip: 'Heading',
                      onTap: () => _execCommand('formatBlock', '<h2>'),
                    ),
                    _ToolbarBtn(
                      icon: Icons.format_quote_rounded,
                      active: false,
                      tooltip: 'Citaat',
                      onTap: () => _execCommand('formatBlock', '<blockquote>'),
                    ),
                    const Spacer(),
                    _ToolbarBtn(
                      icon: Icons.format_clear_rounded,
                      active: false,
                      tooltip: 'Opmaak wissen',
                      onTap: () => _execCommand('removeFormat'),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        color: Colors.white.withOpacity(0.1),
      );
}

// ── Template data class ──────────────────────────────────────
class _NewsletterTemplate {
  const _NewsletterTemplate({
    required this.icon,
    required this.label,
    required this.subject,
    required this.html,
  });

  final IconData icon;
  final String label;
  final String subject;
  final String html;
}

// ── Toolbar button ───────────────────────────────────────────
class _ToolbarBtn extends StatelessWidget {
  const _ToolbarBtn({
    required this.icon,
    required this.active,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active
              ? GymiesColors.primary.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 20,
          color: active
              ? GymiesColors.primary
              : Colors.white.withOpacity(0.55),
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}
