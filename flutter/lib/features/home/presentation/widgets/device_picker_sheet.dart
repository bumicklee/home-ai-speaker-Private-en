import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/routes.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../devices/presentation/bloc/devices_cubit.dart';

/// Choose a speaker (when more than one is registered)
Future<void> showDevicePicker(BuildContext context) {
  final cubit = context.read<DevicesCubit>();
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheet) {
      final l = AppLocalizations.of(sheet);
      final state = cubit.state;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(l.homeSelectSpeaker),
              ListGroup(children: [
                for (final d in state.devices)
                  ListRow(
                    title: d.name,
                    subtitle: d.host ?? d.shortId,
                    selected: d.id == state.selectedId,
                    leading: const Icon(Icons.speaker_rounded),
                    onTap: () {
                      cubit.select(d.id);
                      Navigator.pop(sheet);
                    },
                  ),
              ]),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheet);
                  Navigator.pushNamed(context, AppRoutes.provisioning);
                },
                icon: const Icon(Icons.add),
                label: Text(l.homeAddSpeaker),
              ),
            ],
          ),
        ),
      );
    },
  );
}
