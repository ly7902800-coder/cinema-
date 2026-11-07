# CineVerse — Refactor Proposal

Status: **proposal only — no application code has been changed.**
Baseline: branch `appjet`, HEAD `48ee715`.
Scope: `lib/main.dart` (156 lines / 14 KB), `pubspec.yaml`, `.github/workflows/build-apk.yml`.

This document records the inspection findings, the proposed target structure, a
phased plan with acceptance criteria, and the tradeoffs that need a decision
before any code is touched.

---

## 1. Baseline

| File | Content |
| --- | --- |
| `lib/main.dart` | 156 lines / 14 KB — app shell, model, both HTTP factories, service, 3 screens, search delegate |
| `pubspec.yaml` | `cineverse`, sdk `>=3.4.0 <4.0.0`, deps `http ^1.2.2`, dev `flutter_test` + `flutter_lints ^4.0.0` |
| `.github/workflows/build-apk.yml` | analyze → APK → web, artifact upload |
| `README.md` | 9 bytes (empty heading) |
| — | **missing:** `analysis_options.yaml`, `test/`, `pubspec.lock`, `.gitignore` |

This is a single-file prototype with no test safety net and no effective lint gate.
That constraint drives the phase ordering in section 4.

---

## 2. Findings, ranked by cost

### A. The provider's `'N/A'` sentinel has leaked into the UI

`CatalogItem` stores `rating`, `year`, `runtime`, `poster`, `genres`, `director`,
`actors` all as `String`, so OMDb's `"N/A"` becomes a *domain value*. Presentation
then guards it in six places: `item.rating == 'N/A'`, `item.poster != 'N/A'`,
`runtime != 'N/A'`, `genres != 'N/A'`, `director != 'N/A'`, `actors != 'N/A'`,
plus `overview == 'N/A'`.

Every new field adds another guard. TVmaze never produces `'N/A'`, so half the
guards are dead for one provider and load-bearing for the other. This is the root
cause the rest of the design follows from.

### B. `CatalogService` is untestable by construction

All methods are `static` and call the top-level `http.get`. There is no seam for a
fake, which is why there are zero tests. `package:http/testing.dart` already ships
`MockClient`, so the fix needs **no new dependency**.

### C. Three inconsistent error paths; one is a real bug

- `movies()` — checks status, then checks `Response == 'False'`.
- `series()` / `seriesDetails()` — check status only.
- `movieDetails()` — checks **neither** status **nor** `omdbApiKey.isEmpty`.

With no key configured, `movieDetails` sends a keyless request and then
`jsonDecode`s whatever comes back: a `FormatException` from a non-JSON body rather
than a readable message.

### D. Errors reach the user as Dart internals

The UI does `s.error.toString().replaceFirst('Exception: ', '')`. That only strips
the prefix for `Exception`. A `TimeoutException` renders as
`TimeoutException after 0:00:20.000000: Future not completed`; a `FormatException`
renders as `FormatException: Unexpected character`. The details screen prints
`snapshot.error.toString()` verbatim.

### E. Retry silently discards the search query

The error-state button calls `choose(category)`, which refetches with the *default*
query — `'batman'` for movies, page 0 for series. After a failed search,
"إعادة المحاولة" reloads something unrelated.

### F. Incomplete HTML decoding

`overview` is cleaned with
`replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&amp;', '&')`.
TVmaze summaries contain `&#39;`, `&quot;`, `&nbsp;`, `&lt;`, which reach the
screen literally.

Not a security issue: the string goes into a `Text` widget, which does not parse
markup. This is purely a display bug.

### G. RTL is applied per-screen instead of app-wide

`HomePage` and `ItemDetails` each wrap in
`Directionality(textDirection: TextDirection.rtl)`, but `MaterialApp` sets no
`locale`, `supportedLocales` or `localizationsDelegates`. Anything pushed on the
root navigator — including `SearchDelegate` and text-selection toolbars — falls
back to English/LTR Material strings.

### H. The series list is unbounded and eagerly built

`series()` with no query hits `/shows?page=0`, which returns a full TVmaze page
(~250 shows). Results go into a `GridView.builder` with `shrinkWrap: true` +
`NeverScrollableScrollPhysics` nested in a `ListView`, so **every card is
constructed at once**, with no cap and no pagination. Combined with
`childAspectRatio: .57` and a 2-line title, long titles overflow at larger text
scales.

### I. Lint and CI gates do not run

`flutter_lints` is declared but there is no `analysis_options.yaml` including it,
so `flutter analyze` applies only default rules and the declared dependency is
inert. The workflow runs no `flutter test`, and its trigger is
`push: branches: [main]` while work happens on `appjet` — **CI has never run on
this branch**. That explains a commit titled "Fix ItemCard widget parenthesis for
Flutter analysis": the fix was made blind.

### J. No `pubspec.lock`

For an application (not a package) this means CI resolves fresh versions on every
build — builds are not reproducible.

### K. The OMDb key is compile-time and public in the web build

`String.fromEnvironment('OMDB_API_KEY')` + `--dart-define` embeds the key into the
compiled JS. Anyone can extract it. A client-side refactor cannot fix this; it
needs a proxy. Recorded as a decision (section 5), not a task.

---

## 3. Proposed target structure

```
lib/
  main.dart                     # main() + CineVerseApp only (~40 lines)
  app/theme.dart                # ThemeData
  core/
    failure.dart                # sealed CatalogFailure
    html_text.dart              # decodeHtmlText()
  data/
    catalog_item.dart           # typed domain model
    media_kind.dart             # enum { movie, series }
    catalog_source.dart         # abstract interface
    http_json.dart              # getJson(): status guard + decode + timeout
    omdb_source.dart            # OmdbSource(http.Client, apiKey)
    tvmaze_source.dart          # TvMazeSource(http.Client)
  features/catalog/
    catalog_category.dart       # enum { movies, series } + Arabic label
    catalog_controller.dart     # ChangeNotifier
    catalog_page.dart
    item_card.dart
    item_details_page.dart
    catalog_search_delegate.dart
test/
  html_text_test.dart
  omdb_source_test.dart
  tvmaze_source_test.dart
  catalog_controller_test.dart
analysis_options.yaml
```

### Contract changes that do the real work

```dart
enum MediaKind { movie, series }

/// Replaces the Arabic string used today as both a display label and a switch key.
enum CatalogCategory { movies, series }

class CatalogItem {
  final String id;
  final String title;
  final String? overview;
  final String? posterUrl;
  final String? director;
  final String? actors;
  final String? runtimeLabel;
  final int? year;            // was String, including 'N/A'
  final double? rating;       // was String, including 'N/A'
  final List<String> genres;  // was a ' • '-joined String
  final MediaKind kind;
}

sealed class CatalogFailure implements Exception {
  /// Arabic, ready to render. The UI never inspects the exception type.
  String get userMessage;
}

class MissingApiKeyFailure extends CatalogFailure {}
class NetworkFailure extends CatalogFailure {
  final int? statusCode;
}
class NotFoundFailure extends CatalogFailure {}
class MalformedResponseFailure extends CatalogFailure {}

abstract class CatalogSource {
  Future<List<CatalogItem>> searchMovies(String query);
  Future<CatalogItem> movieDetails(String id);
  Future<List<CatalogItem>> browseSeries({String? query});
  Future<CatalogItem> seriesDetails(String id);
}
```

`CatalogController extends ChangeNotifier` holds `category`, `query` and a state
of `loading | data | failure | empty`, so retry re-runs **the current** query and
the UI never touches `Exception.toString()`.

---

## 4. Phased plan and acceptance criteria

Ordering is deliberate: each phase is independently verifiable, and the risky
change (model typing) lands last, on top of a green test suite.

### Phase 0 — make the repo checkable

Work: add `analysis_options.yaml` including `package:flutter_lints/flutter.yaml`;
commit `pubspec.lock`; workflow triggers on `appjet` and runs `flutter test`
before the builds; replace the 9-byte `README.md` with setup + `OMDB_API_KEY`
instructions.

- [ ] `flutter analyze` exits 0 with the lint set enabled.
- [ ] CI runs and is green on branch `appjet`.
- [ ] `pubspec.lock` is tracked.

### Phase 1 — introduce seams, change no behavior

Work: inject `http.Client` into `OmdbSource` / `TvMazeSource`; add the
`CatalogSource` interface; `main.dart` keeps calling them the same way.

- [ ] `test/omdb_source_test.dart` and `test/tvmaze_source_test.dart` pass using
      `MockClient` with zero real network calls.
- [ ] Rendered UI unchanged: same widgets, same strings.

### Phase 2 — failure typing

Work: add the `CatalogFailure` hierarchy; delete
`replaceFirst('Exception: ', '')`; add the missing status and key guards to
`movieDetails`.

- [ ] No `replaceFirst('Exception: '` anywhere in `lib/`.
- [ ] No bare `Exception(` in `lib/data/`.
- [ ] Unit tests assert: missing key → `MissingApiKeyFailure` **with zero HTTP
      requests issued**; `Response: "False"` → `NotFoundFailure`; HTTP 500 →
      `NetworkFailure`; non-JSON body → `MalformedResponseFailure`.

### Phase 3 — model typing

Work: `int? year`, `double? rating`, `List<String> genres`, `MediaKind`,
nullable `String?` for the rest; `decodeHtmlText` covering
`&amp; &lt; &gt; &quot; &#39; &nbsp;` and nested tags.

- [ ] The literal `'N/A'` appears **only** inside `lib/data/`.
- [ ] `html_text_test.dart` covers all five entities plus `&#39;`.
- [ ] Details screen renders rating and year with no `'N/A'` fallback logic in the
      widget layer.

### Phase 4 — file split and controller

Work: mechanical extraction of the 156-line file; `CatalogController`; retry
preserves the query.

- [ ] `lib/main.dart` ≤ 40 lines and imports neither `dart:convert` nor `http`.
- [ ] No file in `lib/` exceeds ~200 lines.
- [ ] Regression test: a failed search followed by retry re-issues **the same**
      query.

### Phase 5 — layout and locale

Work: `MaterialApp` gets `locale: Locale('ar')`, `supportedLocales` and
`localizationsDelegates` via `flutter_localizations`; remove both `Directionality`
wrappers; move the grid out of `shrinkWrap` into a `CustomScrollView` +
`SliverGrid`; cap the TVmaze page.

- [ ] No `Directionality(` in `lib/`.
- [ ] `flutter_localizations` present and referenced.
- [ ] Widget test renders the catalog page and finds the expected cards.
- [ ] Series browse renders at most the configured cap.

---

## 5. Tradeoffs — decisions, not preferences

### Big-bang rewrite vs. phased

The file is small enough that a single rewrite is tempting and would finish in one
pass. Recommended against: there is no test, no lint config, and CI has never run
on this branch, so a rewrite would be validated by nothing. Phases 0–2 are
behavior-preserving and give a green baseline before the model types change.
**Cost:** more turns, and intermediate states look half-migrated.

### Typed model (`double?` / `int?`) vs. keeping strings

The only change that can alter visible output. OMDb returns `"8.5"` as a string;
TVmaze returns `8.5` as a number. Unifying to `double?` requires deciding how to
render it (`8.5` vs `8,5` in Arabic) and mapping `"N/A"` → `null`. It buys the
elimination of all six `'N/A'` guards. **Recommended**, but expect a small visual
diff on rating and year — the one place to review carefully.

### `ChangeNotifier` vs. Riverpod/Bloc

Riverpod is the idiomatic modern choice and pays off if auth, watchlists or
caching are added. It also adds a dependency and a package-specific learning
surface to an app that is currently 156 lines. **Recommended:** built-in
`ChangeNotifier` + `ListenableBuilder` — zero dependencies, testable without a
widget tree. If this is intended to grow into a real product, choose Riverpod now;
retrofitting it later is more work than starting with it.

### Full ARB localization vs. app-level locale only

Phase 5 as written fixes the *engine* (Material's own strings and RTL resolution)
with a small diff. Extracting every Arabic string into ARB files is the "correct"
answer but touches every widget, adds `intl` + codegen, and buys nothing until a
second language actually ships. **Recommended:** defer, unless Arabic-only is not
the plan.

### OMDb key handling

As long as the key ships in the client, the web build leaks it. Options:

- **(a)** Accept it, document the risk, use a low-quota key.
- **(b)** Add a thin proxy — new hosting, latency, abuse control; a real project,
  and this repo has no backend.

Phases 0–5 do not change this either way. **Recommended:** (a) plus an explicit
README note, with (b) as separate future work.

### Pagination vs. cap

Capping the series list (e.g. 40) is one line and fixes the eager-build problem.
Real pagination is a UX change (infinite scroll or a "load more" button) plus
controller state. **Recommended:** cap now, paginate when requested.

---

## 6. Verification limits

There is no `flutter` or `dart` binary in the AppJet sandbox (confirmed —
`command -v` finds neither), and Flutter native/web compilation is outside what can
be built and run here. So the acceptance criteria above are written to be executed
by GitHub Actions, which already has Flutter.

That is precisely why **Phase 0** puts `flutter test` and the `appjet` branch
filter into the workflow first. Until CI runs on this branch, any refactor here is
unverified, and it will be reported as unverified rather than claimed as green.

---

## 7. Decisions required before implementation

1. **Scope** — all of Phases 0–5, or a subset? (Highest value per unit of risk:
   Phases 0–4, defer 5.)
2. **State management** — built-in `ChangeNotifier` (recommended) or Riverpod?
3. **Model typing** — adopt `double?` / `int?` / `List<String>`, accepting a small
   rating/year display change?
4. **Localization** — app-level locale only, or full ARB extraction?
5. **OMDb key** — accept client-side exposure for now, or plan a proxy?
