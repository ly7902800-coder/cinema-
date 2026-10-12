import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const omdbApiKey = String.fromEnvironment('OMDB_API_KEY');
void main() => runApp(const CineVerseApp());

class CineVerseApp extends StatelessWidget {
  const CineVerseApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'CineVerse', debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF0B0D14),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B5CF6), brightness: Brightness.dark)),
    home: const HomePage());
}

class CatalogItem {
  final String id, title, overview, poster, year, rating, type, genres, runtime, actors, director;
  const CatalogItem({required this.id, required this.title, required this.overview, required this.poster,
    required this.year, required this.rating, required this.type, this.genres = '', this.runtime = '', this.actors = '', this.director = ''});
  factory CatalogItem.omdb(Map<String, dynamic> j) => CatalogItem(
    id: (j['imdbID'] ?? '').toString(), title: (j['Title'] ?? 'بدون عنوان').toString(),
    overview: (j['Plot'] ?? '').toString(), poster: (j['Poster'] ?? '').toString(),
    year: (j['Year'] ?? '').toString(), rating: (j['imdbRating'] ?? 'N/A').toString(),
    type: (j['Type'] ?? 'movie').toString(), genres: (j['Genre'] ?? '').toString(),
    runtime: (j['Runtime'] ?? '').toString(), actors: (j['Actors'] ?? '').toString(), director: (j['Director'] ?? '').toString());
  factory CatalogItem.tvmaze(Map<String, dynamic> j) {
    final img = j['image'] as Map<String, dynamic>?;
    final rate = j['rating'] as Map<String, dynamic>?;
    final premiered = (j['premiered'] ?? '').toString();
    final genresList = j['genres'] as List<dynamic>? ?? [];
    return CatalogItem(id: (j['id'] ?? '').toString(), title: (j['name'] ?? 'بدون عنوان').toString(),
      overview: (j['summary'] ?? '').toString().replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&amp;', '&'),
      poster: (img?['original'] ?? img?['medium'] ?? '').toString(),
      year: premiered.length >= 4 ? premiered.substring(0, 4) : premiered,
      rating: (rate?['average'] ?? 'N/A').toString(), type: 'series', genres: genresList.join(' • '),
      runtime: (j['runtime'] ?? j['averageRuntime'] ?? '').toString());
  }
}

class CatalogService {
  static Future<List<CatalogItem>> movies({String query = 'batman'}) async {
    if (omdbApiKey.isEmpty) throw Exception('أضف مفتاح OMDB_API_KEY في GitHub Secrets لتفعيل بيانات الأفلام. لا تضع المفتاح داخل الكود.');
    final uri = Uri.https('www.omdbapi.com', '/', {'apikey': omdbApiKey, 's': query, 'type': 'movie', 'page': '1'});
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('تعذر الاتصال بـ OMDb: ' + response.statusCode.toString());
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['Response'] == 'False') throw Exception((json['Error'] ?? 'لا توجد نتائج').toString());
    return (json['Search'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().map(CatalogItem.omdb).toList();
  }
  static Future<List<CatalogItem>> series({String? query}) async {
    final uri = query == null || query.trim().isEmpty
      ? Uri.https('api.tvmaze.com', '/shows', {'page': '0'})
      : Uri.https('api.tvmaze.com', '/search/shows', {'q': query.trim()});
    final response = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('تعذر الاتصال بـ TVmaze: ' + response.statusCode.toString());
    final decoded = jsonDecode(response.body);
    final List<dynamic> rows = query == null || query.trim().isEmpty
      ? decoded as List<dynamic>
      : (decoded as List<dynamic>).map((e) => e is Map<String, dynamic> ? e['show'] : null).whereType<Map<String, dynamic>>().toList();
    return rows.whereType<Map<String, dynamic>>().map(CatalogItem.tvmaze).toList();
  }
  static Future<CatalogItem> movieDetails(String id) async {
    final response = await http.get(Uri.https('www.omdbapi.com', '/', {'apikey': omdbApiKey, 'i': id, 'plot': 'full'})).timeout(const Duration(seconds: 20));
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['Response'] == 'False') throw Exception((json['Error'] ?? 'تعذر تحميل التفاصيل').toString());
    return CatalogItem.omdb(json);
  }
  static Future<CatalogItem> seriesDetails(String id) async {
    final response = await http.get(Uri.https('api.tvmaze.com', '/shows/' + id)).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('تعذر تحميل تفاصيل المسلسل');
    return CatalogItem.tvmaze(jsonDecode(response.body) as Map<String, dynamic>);
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  String category = 'الأفلام';
  late Future<List<CatalogItem>> future = CatalogService.movies();
  void choose(String c) => setState(() { category = c; future = c == 'الأفلام' ? CatalogService.movies() : CatalogService.series(); });
  void search(String q) { if (q.trim().isEmpty) return; setState(() { future = category == 'الأفلام' ? CatalogService.movies(query: q.trim()) : CatalogService.series(query: q.trim()); }); }
  @override Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(
    appBar: AppBar(title: const Row(children: [Icon(Icons.movie_filter_rounded, color: Color(0xFFA78BFA), size: 30), SizedBox(width: 9), Text('CineVerse', style: TextStyle(fontWeight: FontWeight.w900))]),
      actions: [IconButton(onPressed: () async { final q = await showSearch<String>(context: context, delegate: CatalogSearch(category)); if (q != null) search(q); }, icon: const Icon(Icons.search_rounded))]),
    body: RefreshIndicator(onRefresh: () async { final f = category == 'الأفلام' ? CatalogService.movies() : CatalogService.series(); setState(() => future = f); await f; },
      child: ListView(padding: const EdgeInsets.all(18), children: [
        Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: const LinearGradient(colors: [Color(0xFF37206C), Color(0xFF17172B), Color(0xFF11131D)], begin: Alignment.topRight, end: Alignment.bottomLeft)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('عالم السينما بين إيديك', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)), SizedBox(height: 9), Text('بيانات أفلام عبر OMDb ومسلسلات عبر TVmaze.', style: TextStyle(color: Colors.white70, height: 1.6)), SizedBox(height: 14), Text('✦ بحث • تفاصيل • تقييمات', style: TextStyle(color: Color(0xFFE9D5FF), fontWeight: FontWeight.w700))])),
        const SizedBox(height: 24),
        Row(children: [const Expanded(child: Text('اكتشف الآن', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))), ChoiceChip(label: const Text('الأفلام'), selected: category == 'الأفلام', onSelected: (_) => choose('الأفلام')), const SizedBox(width: 8), ChoiceChip(label: const Text('المسلسلات'), selected: category == 'المسلسلات', onSelected: (_) => choose('المسلسلات'))]),
        const SizedBox(height: 16),
        FutureBuilder<List<CatalogItem>>(future: future, builder: (context, s) {
          if (s.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
          if (s.hasError) return Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: const Color(0xFF171A27), borderRadius: BorderRadius.circular(20)), child: Column(children: [const Icon(Icons.cloud_off_rounded, size: 40, color: Color(0xFFA78BFA)), const SizedBox(height: 12), const Text('تعذر تحميل البيانات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(s.error.toString().replaceFirst('Exception: ', ''), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.6)), const SizedBox(height: 12), FilledButton(onPressed: () => choose(category), child: const Text('إعادة المحاولة'))]));
          final items = s.data ?? [];
          if (items.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('لا توجد نتائج حالياً')));
          return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: items.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: .57, crossAxisSpacing: 13, mainAxisSpacing: 17), itemBuilder: (context, i) => ItemCard(item: items[i], onOpen: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetails(item: items[i])))));
        }),
        const SizedBox(height: 22), const Center(child: Text('CineVerse • اكتشف قصتك القادمة', style: TextStyle(color: Colors.white38, fontSize: 12)))
      ]))));
}

class ItemCard extends StatelessWidget {
  final CatalogItem item; final VoidCallback onOpen;
  const ItemCard({super.key, required this.item, required this.onOpen});
  @override Widget build(BuildContext context) {
    final validImage = item.poster.isNotEmpty && item.poster != 'N/A';
    return InkWell(borderRadius: BorderRadius.circular(18), onTap: onOpen, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(18), child: Container(width: double.infinity, color: const Color(0xFF202333), child: !validImage ? const Center(child: Icon(Icons.movie_outlined, size: 44)) : Image.network(item.poster, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.movie_outlined, size: 44)))))),
      const SizedBox(height: 8), Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)), const SizedBox(height: 5),
      Row(children: [const Icon(Icons.star_rounded, size: 17, color: Color(0xFFFBBF24)), const SizedBox(width: 4), Text(item.rating == 'N/A' ? '—' : item.rating, style: const TextStyle(color: Colors.white70, fontSize: 12)), const Spacer(), Text(item.year, style: const TextStyle(color: Colors.white54, fontSize: 12))])
    ]));
  }
}

class ItemDetails extends StatefulWidget {
  final CatalogItem item; const ItemDetails({super.key, required this.item});
  @override State<ItemDetails> createState() => _ItemDetailsState();
}
class _ItemDetailsState extends State<ItemDetails> {
  late Future<CatalogItem> detail = _load();
  Future<CatalogItem> _load() {
    if (widget.item.type == 'series') return CatalogService.seriesDetails(widget.item.id);
    if (omdbApiKey.isEmpty || widget.item.id.isEmpty) return Future.value(widget.item);
    return CatalogService.movieDetails(widget.item.id);
  }
  @override Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: FutureBuilder<CatalogItem>(future: detail, builder: (context, snapshot) {
    final item = snapshot.data ?? widget.item;
    return CustomScrollView(slivers: [
      SliverAppBar(expandedHeight: 290, pinned: true, flexibleSpace: FlexibleSpaceBar(title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis), background: item.poster.isEmpty || item.poster == 'N/A' ? const ColoredBox(color: Color(0xFF25213D)) : Image.network(item.poster, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF25213D))))),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (snapshot.connectionState == ConnectionState.waiting) const LinearProgressIndicator(),
        if (snapshot.hasError) Text('لم تكتمل التفاصيل: ' + snapshot.error.toString(), style: const TextStyle(color: Colors.orangeAccent)),
        Wrap(spacing: 14, runSpacing: 8, children: [Text('⭐ ' + item.rating), Text(item.year), if (item.runtime.isNotEmpty && item.runtime != 'N/A') Text(item.runtime), if (item.genres.isNotEmpty && item.genres != 'N/A') Text(item.genres)]),
        const SizedBox(height: 22), const Text('القصة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(height: 10),
        Text(item.overview.isEmpty || item.overview == 'N/A' ? 'لا تتوفر قصة لهذا العمل حالياً.' : item.overview, style: const TextStyle(height: 1.8, color: Colors.white70, fontSize: 15)),
        if (item.director.isNotEmpty && item.director != 'N/A') ...[const SizedBox(height: 18), Text('المخرج: ' + item.director)],
        if (item.actors.isNotEmpty && item.actors != 'N/A') ...[const SizedBox(height: 12), Text('التمثيل: ' + item.actors, style: const TextStyle(color: Colors.white70, height: 1.6))],
        const SizedBox(height: 24), const Text('روابط المشاهدة القانونية حسب بلدك ستُضاف بعد ربط مصدر موثوق لها.', style: TextStyle(color: Colors.white54, height: 1.6))
      ])))
    ];
  }))));
}

class CatalogSearch extends SearchDelegate<String> {
  final String category; CatalogSearch(this.category);
  @override String get searchFieldLabel => category == 'الأفلام' ? 'ابحث عن فيلم' : 'ابحث عن مسلسل';
  @override List<Widget>? buildActions(BuildContext context) => [IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))];
  @override Widget? buildLeading(BuildContext context) => IconButton(onPressed: () => close(context, ''), icon: const Icon(Icons.arrow_back));
  @override Widget buildResults(BuildContext context) => Center(child: FilledButton(onPressed: () => close(context, query.trim()), child: const Text('عرض النتائج')));
  @override Widget buildSuggestions(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(query.isEmpty ? 'اكتب اسم العمل ثم اضغط عرض النتائج.' : 'بحث مباشر في مصدر البيانات', textAlign: TextAlign.center)));
}
