import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_and_storage.dart';
import 'create_flow.dart';

void main() => runApp(const My3DApp());

class My3DApp extends StatelessWidget {
  const My3DApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My3D AI Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kLime, onPrimary: Colors.black, surface: kCard),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainNav()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: kLime, width: 2),
                boxShadow: [BoxShadow(color: kLime.withOpacity(0.2), blurRadius: 24)],
              ),
              child: const Icon(Icons.view_in_ar_rounded, size: 68, color: kLime),
            ),
            const SizedBox(height: 22),
            const Text('My3D AI Studio', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            const Text('Photos into 3D models', style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 36),
            SizedBox(
              width: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const LinearProgressIndicator(color: kLime, backgroundColor: kCard, minHeight: 5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MainNav extends StatefulWidget {
  const MainNav({super.key});
  @override
  State<MainNav> createState() => _MainNavState();
}

class _MainNavState extends State<MainNav> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _idx == 0 ? const HomeScreen() : const HistoryScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        backgroundColor: kCard,
        indicatorColor: kLime,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded, color: Colors.black), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded, color: Colors.black), label: 'History'),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SavedModel> _recent = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final list = await loadSavedModels();
    if (mounted) setState(() => _recent = list.take(4).toList());
  }

  Future<void> _openSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final ctrl = TextEditingController(text: prefs.getString('saved_api_url') ?? '');
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Backend API URL', style: TextStyle(color: kLime, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'https://....trycloudflare.com', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kLime, foregroundColor: Colors.black),
            onPressed: () async {
              await prefs.setString('saved_api_url', ctrl.text.trim());
              if (mounted) {
                Navigator.pop(context);
                showToast(context, 'API URL ಸೇವ್ ಆಗಿದೆ! ✅');
              }
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _goUpload() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const UploadScreen()));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: kLime.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.view_in_ar_rounded, color: kLime, size: 22),
          ),
          const SizedBox(width: 10),
          const Text('My3D AI Studio', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        ]),
        actions: [IconButton(icon: const Icon(Icons.settings_rounded), onPressed: _openSettings)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Row(children: [
            Expanded(child: _studioCard(Icons.image_rounded, 'Image to 3D', 'Photo to GLB', true, _goUpload)),
            const SizedBox(width: 14),
            Expanded(child: _studioCard(Icons.text_fields_rounded, 'Text to 3D', 'Coming soon', false, () => showToast(context, 'Text to 3D ಶೀಘ್ರದಲ್ಲೇ ಬರಲಿದೆ! ✨'))),
          ]),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _goUpload,
            icon: const Icon(Icons.add_rounded, color: Colors.black, size: 24),
            label: const Text('Create new model', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black)),
            style: ElevatedButton.styleFrom(
              backgroundColor: kLime,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
          ),
          const SizedBox(height: 28),
          const Text('Recent projects', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (_recent.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kBorder)),
              child: const Column(children: [
                Icon(Icons.view_in_ar_outlined, size: 40, color: Colors.grey),
                SizedBox(height: 8),
                Text('No 3D models yet', style: TextStyle(color: Colors.grey)),
              ]),
            )
          else
            ..._recent.map((m) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBorder)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 52,
                    height: 52,
                    color: kBg,
                    child: m.thumbFile != null
                        ? Image.file(m.thumbFile!, fit: BoxFit.cover)
                        : const Icon(Icons.view_in_ar_rounded, color: kLime),
                  ),
                ),
                title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${m.sizeMb} MB • GLB', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewScreen(glbPath: m.glbFile.path))),
              ),
            )),
        ],
      ),
    );
  }

  Widget _studioCard(IconData ic, String title, String sub, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? kLime.withOpacity(0.6) : kBorder, width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: active ? kLime.withOpacity(0.15) : kCardLight, borderRadius: BorderRadius.circular(12)),
            child: Icon(ic, color: active ? kLime : Colors.grey, size: 26),
          ),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 4),
          Text(sub, style: TextStyle(color: active ? kLime : Colors.grey, fontSize: 12, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<SavedModel> _models = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await loadSavedModels();
    if (mounted) setState(() => _models = list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Models', style: TextStyle(fontWeight: FontWeight.w900)), backgroundColor: Colors.transparent),
      body: _models.isEmpty
          ? const Center(child: Text('No saved models yet', style: TextStyle(color: Colors.grey)))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 0.82),
              itemCount: _models.length,
              itemBuilder: (_, i) {
                final m = _models[i];
                return Container(
                  decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kBorder)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewScreen(glbPath: m.glbFile.path))),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              width: double.infinity,
                              color: kBg,
                              child: m.thumbFile != null
                                  ? Image.file(m.thumbFile!, fit: BoxFit.cover)
                                  : const Center(child: Icon(Icons.view_in_ar_rounded, size: 44, color: kLime)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text('${m.sizeMb} MB', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () async {
                              await deleteSavedModel(m);
                              _load();
                              if (mounted) showToast(context, 'Model deleted');
                            },
                          ),
                        ]),
                      ]),
                    ),
                  ),
                );
              },
            ),
    );
  }
}