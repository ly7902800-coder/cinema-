import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const tmdbApiKey = String.fromEnvironment('TMDB_API_KEY');
const imageBase = 'https://image.tmdb.org/t/p/w500';

void main() => runApp(const CineVerseApp());

class CineVerseApp extends StatelessWidget {
  const CineVerseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CineVerse', debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF0B0D14),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B5CF6), brightness: Brightness.dark)),
    home: const HomePage(),
  );
}

class Movie {
  final int id; final String title; final String overview; final String poster; final String backdrop; final double rating; final String date;
  const Movie({required this.id, required this.title, required this.overview, required this.poster, required this.backdrop, required this.rating, required this.date});
  factory Movie.fromJson(Map<String, dynamic> j) => Movie(
    id: j['id'] as int? ?? 0, title: (j['title'] ?? j['name'] ?? 'بدون عنوان').toString(),
    overview: (j['overview'] ?? '').toString(), poster: (j['poster_path'] ?? '').toString(),
    backdrop: (j['backdrop_path'] ?? '').toString(), rating: (j['vote_average'] as num?)?.toDouble() ?? 0,
    date: (j['release_date'] ?? j['first_air_date'] ?? '').toString());
}

class Tmdb {
  static Future<List<Movie>> load(String category) async {
    if (tmdbApiKey.isEmpty) throw Exception('أضف مفتاح TMDB_API_KEY إلى GitHub Secrets لتفعيل بيانات الأفلام الحقيقية.');
    final path = category == 'المسلسلات' ? 'tv/popular' : 'movie/now_playing';
    final uri = Uri.https('api.themoviedb.org', '/3/' + path, {'api_key': tmdbApiKey, 'language': 'ar', 'page': '1'});
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('تعذر جلب البيانات (' + res.statusCode.toString() + '). تحقق من مفتاح TMDB.');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return (json['results'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().map(Movie.fromJson).toList();
  }
}

class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState() => _HomePageState(); }
class _HomePageState extends State<HomePage> {
  String category = 'الأفلام';
  late Future<List<Movie>> future = Tmdb.load(category);
  void choose(String c) => setState(() { category = c; future = Tmdb.load(c); });
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(
    appBar: AppBar(title: const Row(children: [Icon(Icons.movie_filter_rounded, color: Color(0xFFA78BFA), size: 30), SizedBox(width: 9), Text('CineVerse', style: TextStyle(fontWeight: FontWeight.w900))]),
      actions: [IconButton(onPressed: () => showSearch(context: context, delegate: MovieSearch()), icon: const Icon(Icons.search_rounded))]),
    body: RefreshIndicator(onRefresh: () async { setState(() => future = Tmdb.load(category)); await future; }, child: ListView(padding: const EdgeInsets.all(18), children: [
      Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: const LinearGradient(colors: [Color(0xFF37206C), Color(0xFF17172B), Color(0xFF11131D)], begin: Alignment.topRight, end: Alignment.bottomLeft)),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('عالم السينما بين إيديك', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)), SizedBox(height: 9), Text('اكتشف أحدث الأفلام والمسلسلات وقصصها وتقييماتها.', style: TextStyle(color: Colors.white70, height: 1.6)), SizedBox(height: 14), Text('✦ اكتشاف • تفاصيل • تقييمات', style: TextStyle(color: Color(0xFFE9D5FF), fontWeight: FontWeight.w700))]),
      ), const SizedBox(height: 24),
      Row(children: [const Expanded(child: Text('اكتشف الآن', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
        ChoiceChip(label: const Text('الأفلام'), selected: category == 'الأفلام', onSelected: (_) => choose('الأفلام')), const SizedBox(width: 8),
        ChoiceChip(label: const Text('المسلسلات'), selected: category == 'المسلسلات', onSelected: (_) => choose('المسلسلات'))]),
      const SizedBox(height: 16),
      FutureBuilder<List<Movie>>(future: future, builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
        if (s.hasError) return Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: const Color(0xFF171A27), borderRadius: BorderRadius.circular(20)), child: Column(children: [const Icon(Icons.cloud_off_rounded, size: 40, color: Color(0xFFA78BFA)), const SizedBox(height: 12), const Text('تفعيل بيانات الأفلام', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(s.error.toString().replaceFirst('Exception: ', ''), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.6)), const SizedBox(height: 12), FilledButton(onPressed: () => setState(() => future = Tmdb.load(category)), child: const Text('إعادة المحاولة'))]));
        final movies = s.data ?? [];
        if (movies.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('لا توجد نتائج حالياً')));
        return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: movies.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: .57, crossAxisSpacing: 13, mainAxisSpacing: 17), itemBuilder: (context, i) => MovieCard(movie: movies[i]));
      }), const SizedBox(height: 22), const Center(child: Text('CineVerse • اكتشف قصتك القادمة', style: TextStyle(color: Colors.white38, fontSize: 12)))
    ])))));
}

class MovieCard extends StatelessWidget { final Movie movie; const MovieCard({super.key, required this.movie});
  @override Widget build(BuildContext context) => InkWell(borderRadius: BorderRadius.circular(18), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Details(movie: movie))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(18), child: Container(width: double.infinity, color: const Color(0xFF202333), child: movie.poster.isEmpty ? const Center(child: Icon(Icons.movie_outlined, size: 44)) : Image.network(imageBase + movie.poster, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.movie_outlined, size: 44))))),
    const SizedBox(height: 8), Text(movie.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)), const SizedBox(height: 5),
    Row(children: [const Icon(Icons.star_rounded, size: 17, color: Color(0xFFFBBF24)), const SizedBox(width: 4), Text(movie.rating.toStringAsFixed(1), style: const TextStyle(color: Colors.white70, fontSize: 12)), const Spacer(), Text(movie.date.length >= 4 ? movie.date.substring(0, 4) : movie.date, style: const TextStyle(color: Colors.white54, fontSize: 12))])
  ]));
}

class Details extends StatelessWidget { final Movie movie; const Details({super.key, required this.movie});
  @override Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: CustomScrollView(slivers: [
    SliverAppBar(expandedHeight: 290, pinned: true, flexibleSpace: FlexibleSpaceBar(title: Text(movie.title, maxLines: 1, overflow: TextOverflow.ellipsis), background: movie.backdrop.isEmpty ? const ColoredBox(color: Color(0xFF25213D)) : Image.network(imageBase + movie.backdrop, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF25213D)))),
    SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Icon(Icons.star_rounded, color: Color(0xFFFBBF24)), const SizedBox(width: 6), Text(movie.rating.toStringAsFixed(1)), const SizedBox(width: 16), Text(movie.date)]), const SizedBox(height: 22), const Text('القصة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(height: 10), Text(movie.overview.isEmpty ? 'لا تتوفر قصة باللغة المختارة لهذا العمل حالياً.' : movie.overview, style: const TextStyle(height: 1.8, color: Colors.white70, fontSize: 15)), const SizedBox(height: 24), const Text('روابط المشاهدة القانونية حسب بلدك ستُضاف في مرحلة لاحقة.', style: TextStyle(color: Colors.white54, height: 1.6))]))),
  ])));
}

class MovieSearch extends SearchDelegate<String> {
  @override String get searchFieldLabel => 'ابحث عن فيلم أو مسلسل';
  @override List<Widget>? buildActions(BuildContext context) => [IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))];
  @override Widget? buildLeading(BuildContext context) => IconButton(onPressed: () => close(context, ''), icon: const Icon(Icons.arrow_back));
  Widget result() => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(query.isEmpty ? 'اكتب اسم الفيلم أو المسلسل.' : 'البحث العام قيد الإضافة؛ القائمة الرئيسية تعرض الأعمال الشائعة.', textAlign: TextAlign.center)));
  @override Widget buildResults(BuildContext context) => result();
  @override Widget buildSuggestions(BuildContext context) => result();
}