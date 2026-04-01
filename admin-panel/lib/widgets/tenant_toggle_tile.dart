import 'package:flutter/material.dart';

class TenantToggleTile extends StatelessWidget {
  const TenantToggleTile({super.key, required this.title, required this.value, required this.onChanged});

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}

