import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/categories.dart';
import '../../core/citizen_states.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
import '../drafts/draft_store.dart';
import '../outbox/outbox_service.dart';
import '../../services/citizen_auth_service.dart';
import 'login_sheet.dart';

class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key, required this.onOpen});
  final void Function(Report) onOpen;
  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  bool _loading = false;
  bool _failed = false;
  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      await context.read<ReportRepository>().mine();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ReportRepository>();
    final theme = Theme.of(context);
    final gutter = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 24.0;
    return AnimatedBuilder(
      animation: repository.local,
      builder: (context, _) {
        final notices = repository.local.notices;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 24),
                children: [
                  Text(
                    'Aquí aparecen los cambios de estado que Aldia detecta al actualizar tus reportes en este dispositivo. Los avisos push todavía no están disponibles.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AldiaSpace.l),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar avisos'),
                  ),
                  if (_loading) ...[
                    const SizedBox(height: AldiaSpace.l),
                    const LinearProgressIndicator(),
                  ],
                  if (_failed)
                    Padding(
                      padding: const EdgeInsets.only(top: AldiaSpace.l),
                      child: Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.all(AldiaSpace.m),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'No se pudo actualizar. Los avisos guardados siguen disponibles.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (notices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AldiaSpace.xxl,
                      ),
                      child: Column(
                        children: [
                          ExcludeSemantics(
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.notifications_none,
                                size: 32,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          SizedBox(height: AldiaSpace.l),
                          Text(
                            'Todavía no tienes avisos.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge,
                          ),
                          SizedBox(height: AldiaSpace.s),
                          Text(
                            'Los cambios de estado de tus reportes aparecerán aquí.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (var i = 0; i < notices.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        top: i == 0 ? AldiaSpace.l : AldiaSpace.m,
                      ),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          minTileHeight: 64,
                          leading: Icon(citizenStateFor(notices[i].state).icon),
                          title: Text(
                            categoryById(notices[i].category).label,
                            style: theme.textTheme.titleMedium,
                          ),
                          subtitle: Text(
                            '${citizenStateFor(notices[i].state).label}\n${notices[i].at.day}/${notices[i].at.month}/${notices[i].at.year} · ${S.reference(notices[i].reportId)}',
                            style: theme.textTheme.bodySmall,
                          ),
                          isThreeLine: false,
                          onTap: () async {
                            try {
                              final report = await repository.get(
                                notices[i].reportId,
                              );
                              if (mounted) widget.onOpen(report);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text(S.loadError)),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.onCleared});
  final VoidCallback onCleared;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _deleting = false;
  bool _signingOut = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    String? message;
    try {
      await context.read<ReportRepository>().auth.signOut();
    } on CitizenAuthException catch (e) {
      message = e.message;
    } catch (_) {
      message = 'No se pudo cerrar la sesión. Inténtalo de nuevo.';
    }
    if (!mounted) return;
    setState(() => _signingOut = false);
    widget.onCleared();
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _clear() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Duration(milliseconds: 180),
              reverseDuration: Duration(milliseconds: 120),
            ),
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar mis datos de este dispositivo?'),
        content: const Text(
          'Se borrarán borradores y sus fotos, reportes por enviar, seguimientos, avisos y la lista de tus reportes. Los reportes ya enviados seguirán siendo públicos en el servidor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ).copyWith(
                  side: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.disabled)) return null;
                    if (!states.contains(WidgetState.focused)) {
                      return const BorderSide(color: Colors.transparent);
                    }
                    return BorderSide(
                      color: Theme.of(context).colorScheme.onError,
                      width: 2,
                    );
                  }),
                ),
            child: const Text('Borrar datos locales'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repository = context.read<ReportRepository>();
    final drafts = context.read<DraftStore?>();
    final outbox = context.read<OutboxService?>();
    setState(() => _deleting = true);
    try {
      // Outbox operations serialize with an in-flight send before forgetting ids.
      for (final entry in outbox?.entries ?? const <OutboxEntry>[]) {
        await outbox!.remove(entry.draft.id);
      }
      for (final draft in await drafts?.loadAll() ?? []) {
        await drafts!.delete(draft.id);
      }
      await repository.clearLocalData();
      try {
        await repository.auth.signOut();
      } catch (_) {}
      if (!mounted) return;
      widget.onCleared();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Datos locales borrados.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudieron borrar todos los datos. Inténtalo de nuevo.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ReportRepository>();
    final local = repository.local;
    final auth = repository.auth;
    final theme = Theme.of(context);
    final gutter = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 24.0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: AnimatedBuilder(
          animation: Listenable.merge([local, auth]),
          builder: (context, _) => ListView(
            padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 24),
            children: [
              Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.person_outline,
                      size: 32,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AldiaSpace.xl),
              Semantics(
                header: true,
                child: Text(
                  'Tu perfil en Aldia',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: AldiaSpace.xl),
              Text('Tu cuenta', style: theme.textTheme.titleMedium),
              const SizedBox(height: AldiaSpace.s),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone_outlined),
                title: const Text('Número de teléfono'),
                subtitle: Text(
                  auth.maskedPhone ?? 'Sin verificar. Verifica tu número para consultar tus reportes desde tu cuenta.',
                ),
              ),
              if (auth.isSignedIn)
                OutlinedButton.icon(
                  onPressed: _signingOut ? null : _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesión'),
                )
              else
                FilledButton(
                  onPressed: () async {
                    final verified = await showCitizenLogin(context, auth);
                    if (mounted && verified) {
                      setState(() {});
                      widget.onCleared();
                    }
                  },
                  child: const Text('Verificar mi número'),
                ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.visibility_outlined),
                title: Text('Nombre público'),
                subtitle: Text(
                  'Al verificar tu número puedes elegir un nombre y autorizar su publicación en reportes nuevos. Tu número siempre es privado.',
                ),
              ),
              const SizedBox(height: AldiaSpace.xl),
              Text('Acerca de Aldia', style: theme.textTheme.titleMedium),
              const SizedBox(height: AldiaSpace.s),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.language),
                title: Text('Idioma'),
                subtitle: Text('Español (Guatemala)'),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline),
                title: Text('Versión de Aldia'),
                subtitle: Text('0.1.0+1'),
              ),
              const SizedBox(height: AldiaSpace.xl),
              const Divider(),
              const SizedBox(height: AldiaSpace.xl),
              OutlinedButton.icon(
                onPressed: _deleting ? null : _clear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Borrar mis datos'),
                style:
                    OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ).copyWith(
                      side: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.disabled)) return null;
                        return BorderSide(
                          color: theme.colorScheme.error,
                          width: states.contains(WidgetState.focused) ? 2 : 1,
                        );
                      }),
                    ),
              ),
              if (_deleting) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
