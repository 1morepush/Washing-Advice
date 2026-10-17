import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  group('depopSearchLink', () {
    test('searches Depop for the query', () {
      expect(
        depopSearchLink('Nike crewneck sweatshirt grey').toString(),
        'https://www.depop.com/search/?q=Nike+crewneck+sweatshirt+grey',
      );
    });

    test('is a plain https link, so an iPhone can open it in the app', () {
      final link = depopSearchLink('nike');

      expect(link.scheme, 'https');
      expect(link.host, 'www.depop.com');
      expect(link.path, '/search/');
    });
  });

  group('ebaySoldLink', () {
    test('asks for sold and completed listings only', () {
      expect(
        ebaySoldLink('Nike crewneck sweatshirt grey').toString(),
        'https://www.ebay.com/sch/i.html'
        '?_nkw=Nike+crewneck+sweatshirt+grey&LH_Sold=1&LH_Complete=1',
      );
    });

    test('carries both filters, since either alone shows unsold listings', () {
      final params = ebaySoldLink('x').queryParameters;

      expect(params['LH_Sold'], '1');
      expect(params['LH_Complete'], '1');
    });
  });

  group('googleShoppingLink', () {
    test('searches the Shopping tab', () {
      expect(
        googleShoppingLink('Nike Club Fleece crew grey').toString(),
        'https://www.google.com/search?tbm=shop&q=Nike+Club+Fleece+crew+grey',
      );
    });
  });

  group('encoding', () {
    final links = <String, Uri Function(String)>{
      'Depop': depopSearchLink,
      'eBay': ebaySoldLink,
      'Google Shopping': googleShoppingLink,
    };

    String searched(String name, String query) {
      final params = links[name]!(query).queryParameters;
      return params[name == 'eBay' ? '_nkw' : 'q']!;
    }

    test('an ampersand stays part of the query instead of splitting it', () {
      for (final name in links.keys) {
        expect(searched(name, 'H&M denim jacket'), 'H&M denim jacket',
            reason: name);
      }
      expect(depopSearchLink('H&M denim').toString(), contains('H%26M'));
    });

    test('quotes survive, so an exact phrase can be searched for', () {
      for (final name in links.keys) {
        expect(
          searched(name, 'Nike "Club Fleece" crew'),
          'Nike "Club Fleece" crew',
          reason: name,
        );
      }
      expect(
        depopSearchLink('"Club Fleece"').toString(),
        contains('%22Club+Fleece%22'),
      );
    });

    test('unicode is percent-encoded as UTF-8 and read back whole', () {
      for (final name in links.keys) {
        expect(
          searched(name, 'Comme des Garçons play'),
          'Comme des Garçons play',
          reason: name,
        );
      }
      expect(depopSearchLink('Garçons').toString(), contains('Gar%C3%A7ons'));
    });

    test('an apostrophe, a plus sign and a hash do not change the query', () {
      for (final name in links.keys) {
        expect(
          searched(name, "Levi's 501 + belt #vintage"),
          "Levi's 501 + belt #vintage",
          reason: name,
        );
      }
    });

    test('a query is trimmed and its spacing tidied', () {
      expect(
        depopSearchLink('  Nike    crewneck \n grey  ').toString(),
        'https://www.depop.com/search/?q=Nike+crewneck+grey',
      );
    });

    test('an empty query still makes a valid link', () {
      for (final empty in ['', '   ']) {
        final link = depopSearchLink(empty);

        expect(link.host, 'www.depop.com');
        expect(link.queryParameters, {'q': ''});
      }
    });
  });
}
