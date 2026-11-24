import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Kit visuel de l'espace CLIENT MONTOTEM.
///
/// Principes (inspirÃƒÂ©s des meilleures apps de mobilitÃƒÂ© et de livraison, sans
/// les copier) :
///  - fonds calmes, cartes ÃƒÂ  plat avec un simple filet (pas d'ombres lourdes) ;
///  - un seul accent (la couleur primaire du thÃƒÂ¨me client) ;
///  - gros titres francs, texte courant en 15 px, zones tactiles Ã¢â€°Â¥ 48 dp ;
///  - la carte et les actions principales d'abord, le reste disparaÃƒÂ®t.

// ---------------------------------------------------------------------------
// Carte ÃƒÂ  plat
// ---------------------------------------------------------------------------

class ClientCard extends StatelessWidget {
  const ClientCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.radius = 20,
    this.borderColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? scheme.outlineVariant),
    );
    return Material(
      color: color ?? scheme.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              customBorder: shape,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Titres
// ---------------------------------------------------------------------------

class ClientSectionTitle extends StatelessWidget {
  const ClientSectionTitle(
    this.text, {
    super.key,
    this.action,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(2, 26, 2, 12),
  });

  final String text;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
          if (action != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 40),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: scheme.primary,
              ),
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

/// Grand titre d'un onglet (Ã‚Â« ActivitÃƒÂ© Ã‚Â», Ã‚Â« Compte Ã‚Â»Ã¢â‚¬Â¦).
class ClientPageTitle extends StatelessWidget {
  const ClientPageTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1.1,
                ),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Barre de recherche Ã‚Â« OÃƒÂ¹ allez-vous ? Ã‚Â»
// ---------------------------------------------------------------------------

class ClientSearchPill extends StatelessWidget {
  const ClientSearchPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.search_rounded,
  });

  final String label;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.07),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 58,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(icon, size: 26, color: scheme.onSurface),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: scheme.onSurface,
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Maintenant',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tuile de service (grille d'accueil)
// ---------------------------------------------------------------------------

class ClientServiceTile extends StatelessWidget {
  const ClientServiceTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = context.readable(color);
    final radius = BorderRadius.circular(22);
    return Semantics(
      button: true,
      label: '$label. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: color.withValues(alpha: 0.10),
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 28, color: fg),
                ),
                const SizedBox(height: 14),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pastille de filtre (rail de catÃƒÂ©gories)
// ---------------------------------------------------------------------------

class ClientChip extends StatelessWidget {
  const ClientChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    this.elevated = false,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  /// Ombre lÃƒÂ©gÃƒÂ¨re : pour les chips posÃƒÂ©es au-dessus de la carte.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected ? scheme.onSurface : scheme.surface;
    final fg = selected ? scheme.surface : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          boxShadow: elevated
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: bg,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? scheme.onSurface : scheme.outlineVariant,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: fg),
                      const SizedBox(width: 7),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bouton rond posÃƒÂ© sur la carte
// ---------------------------------------------------------------------------

class ClientRoundButton extends StatelessWidget {
  const ClientRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 48,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: scheme.surface,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: 24, color: scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar
// ---------------------------------------------------------------------------

class ClientAvatar extends StatelessWidget {
  const ClientAvatar({
    super.key,
    this.name,
    this.photoUrl,
    this.radius = 22,
    this.onTap,
  });

  final String? name;
  final String? photoUrl;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = (name ?? '').trim();
    final aPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primary.withValues(alpha: 0.14),
      backgroundImage: aPhoto ? NetworkImage(photoUrl!) : null,
      child: aPhoto
          ? null
          : (n.isEmpty
                ? Icon(
                    Icons.person_rounded,
                    size: radius * 1.05,
                    color: scheme.primary,
                  )
                : Text(
                    n.characters.first.toUpperCase(),
                    style: TextStyle(
                      fontSize: radius * 0.85,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  )),
    );
    if (onTap == null) return avatar;
    return Semantics(
      button: true,
      label: 'Mon compte',
      child: InkResponse(onTap: onTap, radius: radius + 8, child: avatar),
    );
  }
}

// ---------------------------------------------------------------------------
// Ligne de liste (profil, rÃƒÂ©glages)
// ---------------------------------------------------------------------------

class ClientListRow extends StatelessWidget {
  const ClientListRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = destructive ? scheme.error : scheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 26, color: tint),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: tint,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: context.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.textTertiary,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Groupe de lignes dans une mÃƒÂªme carte, sÃƒÂ©parÃƒÂ©es par un filet.
class ClientGroup extends StatelessWidget {
  const ClientGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClientCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 58, color: scheme.outlineVariant),
            children[i],
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation : barre basse (tÃƒÂ©lÃƒÂ©phone) / rail (tablette, ordinateur)
// ---------------------------------------------------------------------------

class ClientNavItem {
  const ClientNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.showBadge = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool showBadge;
}

class ClientShell extends StatelessWidget {
  const ClientShell({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
    required this.body,
  });

  final List<ClientNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final Widget body;

  static Widget _icon(IconData data, bool badge) =>
      badge ? Badge(smallSize: 9, child: Icon(data)) : Icon(data);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final largeur = MediaQuery.sizeOf(context).width;

    if (largeur >= 720) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                extended: largeur >= 1100,
                selectedIndex: index,
                onDestinationSelected: onSelect,
                backgroundColor: scheme.surface,
                indicatorColor: scheme.primary.withValues(alpha: 0.14),
                selectedIconTheme: IconThemeData(color: scheme.primary),
                unselectedIconTheme: IconThemeData(
                  color: scheme.onSurfaceVariant,
                ),
                selectedLabelTextStyle: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
                unselectedLabelTextStyle: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                labelType: largeur >= 1100
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                destinations: [
                  for (final d in items)
                    NavigationRailDestination(
                      icon: _icon(d.icon, d.showBadge),
                      selectedIcon: _icon(d.selectedIcon, d.showBadge),
                      label: Text(d.label),
                    ),
                ],
              ),
              VerticalDivider(width: 1, color: scheme.outlineVariant),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: _BottomBar(
        items: items,
        index: index,
        onSelect: onSelect,
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.items,
    required this.index,
    required this.onSelect,
  });

  final List<ClientNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _BottomItem(
                    item: items[i],
                    selected: i == index,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ClientNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final icon = ClientShell._icon(
      selected ? item.selectedIcon : item.icon,
      item.showBadge,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        highlightShape: BoxShape.rectangle,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconTheme(
              data: IconThemeData(color: color, size: 26),
              child: icon,
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
