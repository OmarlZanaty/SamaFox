import 'package:flutter/widgets.dart';

/// App-wide bilingual text (2026-10-23, "اللغة لما بتتغير مش كل الكلام بيتغير").
///
/// Most screens hard-coded Arabic, so switching to English changed only the
/// handful that used [AppStrings]. Every user-visible literal now goes through
/// [tr] with both languages side by side:
///
///   Text(tr('قبول', 'Accept'))
///   tr('تمت دعوتك إلى $name', 'You were invited to $name')
///
/// Arabic is the default: anything not explicitly English gets it, matching
/// [AppConfig.defaultLanguage]. [AppLang.code] is set by `LocaleNotifier`,
/// which then rebuilds the whole tree, so [tr] needs no BuildContext and works
/// in snackbars, dialogs and services too. Call it in `build` (or when the
/// message is shown), never once in `initState` / a `static final`, or the
/// text stays in the language of the moment it was created.
class AppLang {
  AppLang._();

  static String code = 'ar';

  static bool get isEn => code == 'en';
  static bool get isAr => !isEn;
}

String tr(String ar, String en) => AppLang.isEn ? en : ar;

/// Marks every mounted element dirty so each [tr] call re-runs after a
/// language switch (what a hot reload does, minus the code swap).
void rebuildAllWidgets() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}
