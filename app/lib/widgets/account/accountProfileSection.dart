import 'package:cashew_selfhosted/colors.dart';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/account/accountSheets.dart';
import 'package:cashew_selfhosted/widgets/settingsContainers.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Who you are signed in as, and what you can change about it.
///
/// Everything shown here comes from [cachedServerProfile], never from a live
/// request, so the page renders correctly with no network -- required by
/// specs/01-local-first-invariant.md.
class AccountProfileSection extends StatelessWidget {
  const AccountProfileSection({super.key, required this.onSignOut});

  final Future<void> Function() onSignOut;

  String get _displayName =>
      cachedServerProfile?.displayName ??
      (appStateSettings["currentUserEmail"] ?? "").toString();

  String get _email =>
      cachedServerProfile?.email ??
      (appStateSettings["currentUserEmail"] ?? "").toString();

  @override
  Widget build(BuildContext context) {
    final initial = _displayName.trim().isNotEmpty
        ? _displayName.trim()[0].toUpperCase()
        : "";
    return Column(
      children: [
        const SizedBox(height: 20),
        ClipOval(
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dynamicPastel(
                  context, Theme.of(context).colorScheme.primary,
                  amount: 0.2),
            ),
            child: Center(
              child: TextFont(
                text: initial,
                fontSize: 52,
                textAlign: TextAlign.center,
                fontWeight: FontWeight.bold,
                textColor: dynamicPastel(
                    context, Theme.of(context).colorScheme.primary,
                    amount: 0.85, inverse: false),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextFont(
          text: _displayName,
          textAlign: TextAlign.center,
          fontSize: 23,
          fontWeight: FontWeight.bold,
          maxLines: 2,
        ),
        const SizedBox(height: 2),
        TextFont(
          text: _email,
          textAlign: TextAlign.center,
          fontSize: 15,
          textColor: getColor(context, "textLight"),
          maxLines: 2,
        ),
        if (cachedServerProfile?.isAdmin == true) ...[
          const SizedBox(height: 10),
          const _AdminBadge(),
        ],
        const SizedBox(height: 20),
        SettingsContainer(
          title: "edit-profile".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.person_outlined
              : Icons.person_rounded,
          onTap: () => openEditProfileSheet(context),
        ),
        SettingsContainer(
          title: "change-password".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.lock_outlined
              : Icons.lock_rounded,
          onTap: () => openChangePasswordSheet(context),
        ),
        SettingsContainer(
          title: "logout".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.logout_outlined
              : Icons.logout_rounded,
          onTap: onSignOut,
        ),
      ],
    );
  }
}

class _AdminBadge extends StatelessWidget {
  const _AdminBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            appStateSettings["outlinedIcons"]
                ? Icons.shield_outlined
                : Icons.shield_rounded,
            size: 16,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 6),
          TextFont(
            text: "administrator".tr(),
            fontSize: 13,
            fontWeight: FontWeight.bold,
            textColor: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ],
      ),
    );
  }
}
