import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../services/citizen_auth_service.dart';
import '../../services/identity_services.dart';

Future<bool> showCitizenLogin(BuildContext context, AuthService auth) async {
  FocusManager.instance.primaryFocus?.unfocus();
  return await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : const AnimationStyle(
                duration: Duration(milliseconds: 240),
                reverseDuration: Duration(milliseconds: 180),
              ),
        builder: (_) => CitizenLoginSheet(auth: auth),
      ) ??
      false;
}

/// Phone/code input is transient and disposed when the sheet closes.
class CitizenLoginSheet extends StatefulWidget {
  const CitizenLoginSheet({super.key, required this.auth});
  final AuthService auth;
  @override
  State<CitizenLoginSheet> createState() => _CitizenLoginSheetState();
}

class _CitizenLoginSheetState extends State<CitizenLoginSheet> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _alias = TextEditingController();
  final _aliasFocus = FocusNode();
  bool _sent = false;
  bool _busy = false;
  bool _aliasPublic = false;
  int _seconds = 0;
  Timer? _timer;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    _alias.dispose();
    _aliasFocus.dispose();
    super.dispose();
  }

  void _cooldown() {
    _timer?.cancel();
    _seconds = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _seconds--);
      if (_seconds == 0) timer.cancel();
    });
  }

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final phone = normalizeCitizenPhone(_phone.text);
      await widget.auth.requestCode(phone);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _code.clear();
        _cooldown();
      });
    } on CitizenAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo solicitar el código. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.verifyCode(
        phone: normalizeCitizenPhone(_phone.text),
        code: _code.text.trim(),
        alias: _alias.text,
        aliasPublic: _aliasPublic,
      );
      if (!widget.auth.isSignedIn) {
        throw const CitizenAuthException(
          'No se pudo verificar el número. Inténtalo de nuevo.',
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on CitizenAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo verificar el número. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        // The modal route already offsets the sheet for the keyboard inset.
        // Keep only content padding here so the scrollable can use the space
        // left above the keyboard without reserving that inset a second time.
        padding: const EdgeInsets.all(AldiaSpace.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Verifica tu número',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: AldiaSpace.xs),
                Text(
                  'Recibe avisos y consulta tus reportes desde tu cuenta.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AldiaSpace.l),
                Container(
                  padding: const EdgeInsets.all(AldiaSpace.m),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Tu número no será público. El acceso dura 90 días en este dispositivo. Los avisos se consultan en Aldia; las notificaciones push aún no están disponibles.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: AldiaSpace.xl),
                TextField(
                  key: const Key('citizen-phone'),
                  controller: _phone,
                  enabled: !_busy && !_sent,
                  style: theme.textTheme.bodyLarge,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (!_busy && !_sent) _request();
                  },
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Número de teléfono',
                    prefixText: '+502 ',
                    helperText: 'Guatemala · 8 dígitos',
                  ),
                ),
                if (_sent) ...[
                  const SizedBox(height: AldiaSpace.l),
                  Text(
                    'Si la solicitud fue aceptada, podrás usar el código de 6 dígitos. Vence en 10 minutos.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AldiaSpace.m),
                  TextField(
                    key: const Key('citizen-code'),
                    controller: _code,
                    enabled: !_busy,
                    style: theme.textTheme.bodyLarge,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _aliasFocus.requestFocus(),
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Código de verificación',
                    ),
                  ),
                  const SizedBox(height: AldiaSpace.l),
                  TextField(
                    focusNode: _aliasFocus,
                    controller: _alias,
                    enabled: !_busy,
                    style: theme.textTheme.bodyLarge,
                    maxLength: 60,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_busy) _verify();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Nombre para mostrar (opcional)',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mostrar mi nombre en reportes nuevos'),
                    subtitle: const Text(
                      'Solo se publicará si activas esta opción.',
                    ),
                    value: _aliasPublic,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _aliasPublic = value),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AldiaSpace.m),
                    child: Semantics(
                      liveRegion: true,
                      child: Container(
                        padding: const EdgeInsets.all(AldiaSpace.m),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: AldiaSpace.s),
                            Expanded(
                              child: Text(
                                _error!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: AldiaSpace.m),
                ] else
                  const SizedBox(height: AldiaSpace.m),
                FilledButton(
                  onPressed: _busy ? null : (_sent ? _verify : _request),
                  child: Text(_sent ? 'Verificar número' : 'Solicitar código'),
                ),
                if (_sent) ...[
                  const SizedBox(height: AldiaSpace.s),
                  TextButton(
                    onPressed: _busy || _seconds > 0 ? null : _request,
                    child: Text(
                      _seconds > 0
                          ? 'Reenviar en $_seconds s'
                          : 'Reenviar código',
                      style: _seconds > 0
                          ? theme.textTheme.labelLarge?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: AldiaSpace.s),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            _timer?.cancel();
                            setState(() {
                              _sent = false;
                              _error = null;
                              _code.clear();
                            });
                          },
                    child: const Text('Cambiar número'),
                  ),
                ],
                const SizedBox(height: AldiaSpace.s),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context, false),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
