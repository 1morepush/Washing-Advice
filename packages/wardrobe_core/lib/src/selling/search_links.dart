/// Links that open the same searches a price check runs, in a browser or in
/// the Depop app, for a person to look at themselves.
///
/// The server can search for comparables, and it will not always: it needs a
/// key, the key has a monthly allowance, and a search service can be down. A
/// price a person cannot check is a price they should not trust either way, so
/// these three links are always offered beside whatever the search found —
/// "here is what I found, and here is how to look for yourself".
///
/// Built here rather than in a screen so that the encoding is tested once. A
/// query with an ampersand in it ("H&M", "Levi's & Co") that is not encoded
/// quietly becomes two parameters, and the search that opens is for something
/// else.
library;

/// Depop's own search: what is for sale now, at what asking price.
///
/// A web link, which an iPhone with the Depop app installed opens in the app.
Uri depopSearchLink(String query) =>
    Uri.https('www.depop.com', '/search/', {'q': _tidy(query)});

/// eBay's sold and completed listings for [query].
///
/// The best free evidence of what something sold for rather than what someone
/// hopes it will: `LH_Sold` and `LH_Complete` together restrict the results to
/// listings that ended in a sale.
Uri ebaySoldLink(String query) => Uri.https('www.ebay.com', '/sch/i.html', {
      '_nkw': _tidy(query),
      'LH_Sold': '1',
      'LH_Complete': '1',
    });

/// Google Shopping for [query]: what the same thing costs new, across shops.
Uri googleShoppingLink(String query) =>
    Uri.https('www.google.com', '/search', {'tbm': 'shop', 'q': _tidy(query)});

/// The query without the stray spacing that a pasted or edited phrase picks up.
///
/// Spaces in a query are information only once; a trailing space or a double
/// one makes the same search look different and encodes as a run of `+`.
String _tidy(String query) => query.trim().replaceAll(RegExp(r'\s+'), ' ');
