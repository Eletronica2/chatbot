import 'package:flutter/material.dart';

/// Durações e curves da Fundação V2. Respeita `MediaQuery.disableAnimations`.
class AppMotion {
  static const Duration page = Duration(milliseconds: 220);
  static const Duration dialog = Duration(milliseconds: 180);
  static const Duration sidebar = Duration(milliseconds: 240);
  static const Duration contextPanel = Duration(milliseconds: 220);
  static const Duration hover = Duration(milliseconds: 140);
  static const Duration hoverFast = Duration(milliseconds: 120);
  static const Duration hoverSlow = Duration(milliseconds: 160);

  static const Curve pageCurve = Curves.easeOutCubic;
  static const Curve dialogCurve = Curves.easeOutCubic;
  static const Curve sidebarCurve = Curves.easeInOutCubic;
  static const Curve hoverCurve = Curves.easeOut;

  static bool reduce(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  static Duration of(BuildContext context, Duration duration) =>
      reduce(context) ? Duration.zero : duration;

  static Duration pageOf(BuildContext context) => of(context, page);
  static Duration dialogOf(BuildContext context) => of(context, dialog);
  static Duration sidebarOf(BuildContext context) => of(context, sidebar);
  static Duration hoverOf(BuildContext context) => of(context, hover);
}

/// Transição de página: fade + leve deslocamento vertical.
class AppFadeUpPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppFadeUpPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.reduce(context)) return child;
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.pageCurve);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.012),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

class AppPageSwitcher extends StatelessWidget {
  const AppPageSwitcher({
    super.key,
    required this.pageKey,
    required this.child,
  });

  final Object pageKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.pageOf(context),
      switchInCurve: AppMotion.pageCurve,
      switchOutCurve: AppMotion.pageCurve,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: KeyedSubtree(key: ValueKey<Object>(pageKey), child: child),
    );
  }
}

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.54),
    transitionDuration: AppMotion.dialogOf(context),
    pageBuilder: (context, animation, secondaryAnimation) {
      return builder(context);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      if (AppMotion.reduce(context)) return child;
      final curved =
          CurvedAnimation(parent: animation, curve: AppMotion.dialogCurve);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
