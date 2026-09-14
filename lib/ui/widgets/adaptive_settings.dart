import 'dart:io' show Platform;

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'floating_chrome.dart' show isIOS26OrAbove;

/// Settings-page building blocks that render as the platform expects.
///
/// Android keeps Material — [ListTile], [SwitchListTile], section headers
/// over a flat list. iOS gets the inset-grouped list iOS Settings uses, with
/// [CupertinoListTile] rows, no leading icons (Cupertino sub-pages seldom
/// have them), chevrons on rows that navigate, and switches that are the
/// system's own: [CNSwitch] on iOS 26+, [CupertinoSwitch] below it.
///
/// One rule keeps the page code readable: the page describes rows, these
/// widgets decide how they look. Nothing in settings_page.dart branches on
/// platform.

/// Whole page: app bar + scrolling body.
class SettingsScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SettingsScaffold({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(children: children),
      );
    }
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return CupertinoPageScaffold(
      backgroundColor: bg,
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        backgroundColor: bg.withValues(alpha: 0.85),
        border: null,
      ),
      // ListView's default padding already includes the bar heights above
      // and the shell's bottom chrome below (extendBody puts it in
      // MediaQuery.padding), so nothing scrolls under either.
      child: ListView(children: children),
    );
  }
}

/// A titled group of rows.
class SettingsSection extends StatelessWidget {
  final String header;
  final List<Widget> children;

  const SettingsSection({super.key, required this.header, required this.children});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              header.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          ...children,
          const Divider(height: 0),
        ],
      );
    }
    return CupertinoListSection.insetGrouped(
      // insetGrouped defaults to a large bold header; iOS Settings itself uses
      // small grey capitals for sections within a page, which is what this is.
      header: Text(
        header.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.08,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
      children: children,
    );
  }
}

/// A plain row: title, optional subtitle, optional trailing, optional tap.
///
/// [external] marks a row that leaves the app (a web page, the store, mail)
/// so the trailing glyph says so instead of promising an in-app screen.
/// [choice] marks one option of a pick-one group: it shows a checkmark when
/// [checked] and nothing otherwise — never a chevron, since tapping it
/// selects rather than navigates.
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool external;
  final bool choice;
  final bool checked;
  final Widget? trailing;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.external = false,
    this.choice = false,
    this.checked = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!Platform.isIOS) {
      return ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: trailing ??
            (checked
                ? Icon(Icons.check, color: scheme.primary)
                : external
                    ? const Icon(Icons.open_in_new, size: 18)
                    : null),
        onTap: onTap,
      );
    }

    final Widget? tail = trailing ??
        (checked
            ? Icon(CupertinoIcons.check_mark, color: scheme.primary, size: 18)
            : choice
                ? null
                : external
                    ? const Icon(CupertinoIcons.arrow_up_right_square, size: 18)
                    : onTap != null
                        ? const CupertinoListTileChevron()
                        : null);
    return CupertinoListTile.notched(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: tail,
      onTap: onTap,
    );
  }
}

/// An on/off row with the platform's own switch.
class SettingsSwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) {
      return SwitchListTile(
        secondary: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        value: value,
        onChanged: onChanged,
      );
    }
    final Widget toggle = isIOS26OrAbove
        // The system control itself, so it picks up whatever the OS does
        // with switches this year — the Liquid Glass thumb included.
        ? SizedBox(
            width: 52,
            height: 32,
            child: CNSwitch(value: value, onChanged: onChanged, height: 32),
          )
        : CupertinoSwitch(value: value, onChanged: onChanged);
    return CupertinoListTile.notched(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: toggle,
      // Tapping the row toggles too — the switch is small and the row is
      // the target the eye lands on.
      onTap: () => onChanged(!value),
    );
  }
}

/// Brief confirmation after an action ("cache cleared").
void showSettingsToast(BuildContext context, String message) {
  if (Platform.isIOS) {
    // A Flutter overlay, not a platform view, so it runs on every iOS
    // version; the glass effect simply has less to do below 26.
    CNToast.success(context: context, message: message);
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
