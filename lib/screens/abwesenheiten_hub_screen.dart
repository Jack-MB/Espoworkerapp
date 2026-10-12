import 'package:flutter/material.dart';
import 'urlaub_screen.dart';
import 'krankentage_screen.dart';
import 'abwesenheit_screen.dart';

class AbwesenheitenHubScreen extends StatefulWidget {
  final int initialIndex;
  const AbwesenheitenHubScreen({Key? key, this.initialIndex = 0}) : super(key: key);

  @override
  _AbwesenheitenHubScreenState createState() => _AbwesenheitenHubScreenState();
}

class _AbwesenheitenHubScreenState extends State<AbwesenheitenHubScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<State> _urlaubKey = GlobalKey();
  final GlobalKey<State> _krankKey = GlobalKey();
  final GlobalKey<State> _abwesenheitKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, 2),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onFabPressed() {
    if (_tabController.index == 0) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => const _CreateUrlaubFormWrapper(),
      ).then((val) {
        if (val == true && mounted) {
          setState(() {});
        }
      });
    } else if (_tabController.index == 1) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => const _CreateKrankmeldungWrapper(),
      ).then((val) {
        if (val == true && mounted) {
          setState(() {});
        }
      });
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => const _CreateAbwesenheitWrapper(),
      ).then((val) {
        if (val == true && mounted) {
          setState(() {});
        }
      });
    }
  }

  Widget _buildFab() {
    if (_tabController.index == 0) {
      return FloatingActionButton.extended(
        onPressed: _onFabPressed,
        backgroundColor: Theme.of(context).primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Neuer Urlaubsantrag', style: TextStyle(color: Colors.white)),
      );
    } else if (_tabController.index == 1) {
      return FloatingActionButton.extended(
        onPressed: _onFabPressed,
        backgroundColor: Colors.red.shade600,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Krankmelden', style: TextStyle(color: Colors.white)),
      );
    } else {
      return FloatingActionButton.extended(
        onPressed: _onFabPressed,
        backgroundColor: Theme.of(context).primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Neuer Termin', style: TextStyle(color: Colors.white)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Urlaub & Abwesenheiten'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(
              icon: Icon(Icons.beach_access, size: 20),
              text: 'Urlaub',
            ),
            Tab(
              icon: Icon(Icons.healing, size: 20),
              text: 'Krankmeldungen',
            ),
            Tab(
              icon: Icon(Icons.event_note, size: 20),
              text: 'Termine',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          UrlaubScreen(key: _urlaubKey, embedded: true),
          KrankentageScreen(key: _krankKey, embedded: true),
          AbwesenheitScreen(key: _abwesenheitKey, embedded: true),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }
}

// Lightweight wrappers around bottom sheets to expose cleanly to Hub FAB
class _CreateUrlaubFormWrapper extends StatelessWidget {
  const _CreateUrlaubFormWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const UrlaubScreen(embedded: false);
  }
}

class _CreateKrankmeldungWrapper extends StatelessWidget {
  const _CreateKrankmeldungWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const KrankentageScreen(embedded: false);
  }
}

class _CreateAbwesenheitWrapper extends StatelessWidget {
  const _CreateAbwesenheitWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const AbwesenheitScreen(embedded: false);
  }
}
