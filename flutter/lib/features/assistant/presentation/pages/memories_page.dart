import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/app_widgets.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/assistant_settings.dart';
import '../bloc/memories_cubit.dart';

/// Assistant memory list (GET /memories, DELETE /memories/{key} one at a time)
class MemoriesPage extends StatelessWidget {
  const MemoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<MemoriesCubit>()..load(),
      child: const _MemoriesView(),
    );
  }
}

class _MemoriesView extends StatelessWidget {
  const _MemoriesView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.asstMemories)),
      body: BlocBuilder<MemoriesCubit, MemoriesState>(
        builder: (context, s) {
          final list = s.memories;
          if (list == null) {
            return s.failure != null
                ? FailureView(failure: s.failure!, onRetry: () => context.read<MemoriesCubit>().load())
                : const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: () => context.read<MemoriesCubit>().load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                NoticeBox(child: Text(l.asstMemoriesNotice)),
                const SizedBox(height: 14),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Text(l.asstMemoriesEmpty,
                        textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                  )
                else ...[
                  SectionTitle(l.asstMemories,
                      trailing: Text('${list.length}/${AssistantLimits.memories}',
                          style: Theme.of(context).textTheme.bodySmall)),
                  ListGroup(children: [
                    for (final m in list)
                      ListRow(
                        title: m.value,
                        subtitle: m.key,
                        trailing: s.deleting.contains(m.key)
                            ? const SizedBox(
                                width: 44,
                                height: 44,
                                child: Center(
                                    child: SizedBox(
                                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                              )
                            : IconButton(
                                tooltip: l.asstForget,
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _forget(context, m.key, m.value),
                              ),
                      ),
                  ]),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _forget(BuildContext context, String key, String value) async {
    final l = AppLocalizations.of(context);
    final cubit = context.read<MemoriesCubit>();
    final ok = await confirm(context, title: l.asstForgetTitle, body: value, action: l.asstForget, destructive: true);
    if (!ok) return;
    final f = await cubit.forget(key);
    if (!context.mounted) return;
    if (f != null) {
      showFailure(context, f);
    } else {
      showMessage(context, l.asstForgotten);
    }
  }
}
