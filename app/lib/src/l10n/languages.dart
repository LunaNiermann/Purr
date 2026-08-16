/// The languages Purr ships, with their native display names. This order is the
/// order shown in the language picker (device-match first, then English, then
/// the rest). Keep in sync with the ARB files in `lib/l10n/` and with
/// `AppLocalizations.supportedLocales`.
class AppLanguage {
  const AppLanguage(this.tag, this.nativeName);

  /// BCP-47 tag, matching the ARB suffix (e.g. 'es' → app_es.arb).
  final String tag;

  /// The language's own name, always written in that language.
  final String nativeName;
}

const kAppLanguages = <AppLanguage>[
  AppLanguage('en', 'English'),
  AppLanguage('es', 'Español'),
  AppLanguage('de', 'Deutsch'),
  AppLanguage('fr', 'Français'),
  AppLanguage('it', 'Italiano'),
  AppLanguage('pt', 'Português'),
  AppLanguage('id', 'Bahasa Indonesia'),
  AppLanguage('hi', 'हिन्दी'),
  AppLanguage('ar', 'العربية'),
  AppLanguage('ja', '日本語'),
  AppLanguage('ko', '한국어'),
];
