import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../services/app_sounds.dart';
import '../theme.dart';

Future<void> _setSound(AppSounds sounds, bool value) async {
  await sounds.setEnabled(value);
  if (value) sounds.play(AppSound.stamp);
}

class SoundToggleButton extends StatelessWidget {
  final AppSounds? sounds;
  const SoundToggleButton({super.key, this.sounds});

  @override
  Widget build(BuildContext context) {
    final controller = sounds ?? AppSounds.shared;
    return ValueListenableBuilder<bool>(valueListenable: controller.enabled, builder: (context, on, _) => Semantics(
      toggled: on,
      child: IconButton(
        tooltip: on ? '關閉音效' : '開啟音效',
        onPressed: () => _setSound(controller, !on),
        icon: Icon(on ? CupertinoIcons.speaker_2 : CupertinoIcons.speaker_slash, size: 21, color: on ? actionCoral : muted),
      ),
    ));
  }
}

class SoundSettingsTile extends StatelessWidget {
  final AppSounds? sounds;
  const SoundSettingsTile({super.key, this.sounds});

  @override
  Widget build(BuildContext context) {
    final controller = sounds ?? AppSounds.shared;
    return ValueListenableBuilder<bool>(valueListenable: controller.enabled, builder: (context, on, _) => SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: const Text('操作音效', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink)),
      subtitle: const Text('快門、送紙和貼紙的聲音', style: TextStyle(fontSize: 12, color: muted)),
      value: on,
      onChanged: (value) => _setSound(controller, value),
    ));
  }
}
