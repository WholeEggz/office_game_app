import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_auth_service.dart';

void main() {
  group('LocalAuthService location profile', () {
    test('signInWithDisplayName records country/city/company for later suggestions', () async {
      final auth = LocalAuthService();
      await auth.signInWithDisplayName(
        'Alice',
        country: 'Poland',
        city: 'Warsaw',
        companyOrOffice: 'Acme Corp',
      );

      expect(await auth.suggestCountries('pol'), ['Poland']);
      expect(await auth.suggestCities('war'), ['Warsaw']);
      expect(await auth.suggestCompanies('acme'), ['Acme Corp']);
    });

    test('suggestions match case/whitespace-insensitively and ignore unrelated prefixes',
        () async {
      final auth = LocalAuthService();
      await auth.signInWithDisplayName(
        'Alice',
        country: 'Poland',
        city: 'Warsaw',
        companyOrOffice: 'Acme Corp',
      );

      expect(await auth.suggestCountries('POL'), ['Poland']);
      expect(await auth.suggestCountries('  pol'), ['Poland']);
      expect(await auth.suggestCountries('xyz'), isEmpty);
      expect(await auth.suggestCountries(''), isEmpty);
    });

    test('a second registration with a near-duplicate value keeps only the first-seen casing',
        () async {
      final auth = LocalAuthService();
      await auth.signInWithDisplayName(
        'Alice',
        country: 'Poland',
        city: 'Warsaw',
        companyOrOffice: 'Acme Corp',
      );
      await auth.signInWithDisplayName(
        'Bob',
        country: 'poland',
        city: 'WARSAW',
        companyOrOffice: 'ACME CORP',
      );

      // Still just one suggestion per dimension — the differently-cased
      // re-entry converged on the same normalized value instead of
      // fragmenting into a second entry.
      expect(await auth.suggestCountries('pol'), ['Poland']);
      expect(await auth.suggestCities('war'), ['Warsaw']);
      expect(await auth.suggestCompanies('acme'), ['Acme Corp']);
    });

    test('different values across registrations all show up as separate suggestions', () async {
      final auth = LocalAuthService();
      await auth.signInWithDisplayName(
        'Alice',
        country: 'Poland',
        city: 'Warsaw',
        companyOrOffice: 'Acme Corp',
      );
      await auth.signInWithDisplayName(
        'Bob',
        country: 'Portugal',
        city: 'Porto',
        companyOrOffice: 'Beta Inc',
      );

      expect(await auth.suggestCountries('po'), containsAll(['Poland', 'Portugal']));
      expect(await auth.suggestCities('war'), ['Warsaw']);
      expect(await auth.suggestCompanies('beta'), ['Beta Inc']);
    });

    test('currentLocationProfile returns null before any registration', () async {
      final auth = LocalAuthService();
      expect(await auth.currentLocationProfile(), isNull);
    });

    test('currentLocationProfile returns the current identity\'s own saved location', () async {
      final auth = LocalAuthService();
      await auth.signInWithDisplayName(
        'Alice',
        country: 'Poland',
        city: 'Warsaw',
        companyOrOffice: 'Acme Corp',
      );

      final profile = await auth.currentLocationProfile();
      expect(profile?.country, 'Poland');
      expect(profile?.city, 'Warsaw');
      expect(profile?.companyOrOffice, 'Acme Corp');
    });

    test('currentLocationProfile follows switchToUser, not just the most recent registration',
        () async {
      final auth = LocalAuthService();
      final alice = await auth.signInWithDisplayName(
        'Alice',
        country: 'Poland',
        city: 'Warsaw',
        companyOrOffice: 'Acme Corp',
      );
      await auth.signInWithDisplayName(
        'Bob',
        country: 'Portugal',
        city: 'Porto',
        companyOrOffice: 'Beta Inc',
      );

      await auth.switchToUser(alice.id);
      final profile = await auth.currentLocationProfile();
      expect(profile?.companyOrOffice, 'Acme Corp');
    });

    test('suggestions are always Title Cased, regardless of how they were typed', () async {
      final auth = LocalAuthService();
      await auth.signInWithDisplayName(
        'Alice',
        country: 'united states',
        city: 'NEW YORK',
        companyOrOffice: 'acme CORP',
      );

      expect(await auth.suggestCountries('uni'), ['United States']);
      expect(await auth.suggestCities('new'), ['New York']);
      expect(await auth.suggestCompanies('acme'), ['Acme Corp']);

      // Each user's own saved profile still keeps their own as-typed
      // casing — only the shared suggestion directory is normalized.
      final profile = await auth.currentLocationProfile();
      expect(profile?.country, 'united states');
      expect(profile?.city, 'NEW YORK');
      expect(profile?.companyOrOffice, 'acme CORP');
    });

    test('updateLocationProfile changes currentLocationProfile without changing currentUser',
        () async {
      final auth = LocalAuthService();
      final alice = await auth.signInWithDisplayName(
        'Alice',
        country: 'Poland',
        city: 'Warsaw',
        companyOrOffice: 'Acme Corp',
      );

      await auth.updateLocationProfile(
        country: 'Portugal',
        city: 'Porto',
        companyOrOffice: 'Beta Inc',
      );

      expect(auth.currentUser?.id, alice.id);
      final profile = await auth.currentLocationProfile();
      expect(profile?.country, 'Portugal');
      expect(profile?.city, 'Porto');
      expect(profile?.companyOrOffice, 'Beta Inc');
      // The new values also feed the shared suggestion directories, same
      // as a fresh registration would.
      expect(await auth.suggestCountries('port'), ['Portugal']);
    });
  });
}
