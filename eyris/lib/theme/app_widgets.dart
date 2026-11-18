import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Reusable widgets for consistent look across all screens.
/// Import: import '../theme/app_widgets.dart';

/// A standard card container with consistent padding, radius and border.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool elevated;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return Container(
        width: double.infinity,
        padding: padding,
        decoration:
            elevated ? AppDecorations.cardElevated : AppDecorations.card,
        child: child,
      );
    }

    // When tappable, use Ink + InkWell so the ripple and hit-testing
    // sit correctly on top of the colored background.
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Ink(
        decoration:
            elevated ? AppDecorations.cardElevated : AppDecorations.card,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Primary gradient button — the main call-to-action style.
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final double height;

  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: onPressed == null || loading
              ? null
              : AppColors.primaryGradient,
          color: onPressed == null || loading
              ? AppColors.surfaceLight
              : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          onPressed: loading ? null : onPressed,
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Text(label, style: AppText.button),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Secondary (outline) button.
class AppSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final double height;

  const AppSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: c,
          side: BorderSide(color: c, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: c),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: c,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small colored status pill (e.g. "Active", "Connected").
class AppStatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const AppStatusPill({
    super.key,
    required this.text,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: AppDecorations.pill(color),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty-state placeholder with icon + title + subtitle.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 44, color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(title, style: AppText.subheading),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppText.bodySecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section header with optional trailing action.
class AppSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const AppSectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppText.subheading),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The EYRIS logo. [emblemOnly] shows just the glasses emblem (no lettering);
/// otherwise the full logo with the name and tagline is shown.
class EyrisLogo extends StatelessWidget {
  final double size;
  final bool emblemOnly;

  const EyrisLogo({super.key, this.size = 160, this.emblemOnly = false});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'EYRIS logo',
      image: true,
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          // Same near-black as the artwork's own background.
          color: const Color(0xFF01060A),
          borderRadius: BorderRadius.circular(size * 0.16),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Image.asset(
          emblemOnly
              ? 'assets/images/eyris_emblem.png'
              : 'assets/images/eyris_logo.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
