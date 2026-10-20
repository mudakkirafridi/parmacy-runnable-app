import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'firestore_repository.dart';
import 'local_workspace.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../core/ledger.dart';
import '../core/ownership.dart';
import '../core/orders.dart';

final appProvider = ChangeNotifierProvider<AppStore>(
  (ref) => throw UnimplementedError(),
);

class AppStore extends ChangeNotifier with WidgetsBindingObserver {
  final Duration syncTimeout;
  AppStore({this.syncTimeout = const Duration(seconds: 15)});
  int _workspaceVersion = 0, _localRevision = 0;
  Future<void>? _refreshTask;
  bool syncing = false, hasWorkspace = false;
  late SharedPreferences prefs;
  late LocalWorkspace local;
  List<Json> pendingUploads = [];
  Future<void>? _uploadTask;
  Timer? _uploadRetry, _autoSync;
  bool _observing = false;
  List<Json> get uploadIssues =>
      pendingUploads.where((m) => m['failed'] == true).toList();
  bool _disposed = false;
  int get pendingCount => pendingUploads.length;

  late Ledger ledger;
  Json state = {},
      settings = {
        'name': 'Family Pharmacy',
        'accounts': ['cash', 'bank'],
      },
      member = {'role': 'owner', 'active': true};
  List<Json> entries = [], profiles = [], drafts = [], orders = [];
  List<String> allowed = [];
  bool ur = false, dark = false, busy = false, live = false, cached = false;
  String? error;
  String storeId = '';
  String get uid =>
      live ? FirebaseAuth.instance.currentUser?.uid ?? 'signed-out' : 'demo';
  String get cacheKey => 'workspace-v2-$uid-$storeId';
  String get draftKey => 'drafts-v2-$uid-$storeId';
  bool get owner => member['role'] == 'owner';
  bool can(String module) =>
      !live ||
      allowed.contains(
        module == 'orders'
            ? 'suppliers'
            : module == 'profiles'
            ? 'people'
            : module,
      );
  bool canPost(String module) => module == 'orders'
      ? canPost('suppliers')
      : !live ||
            owner ||
            (member['role'] == 'manager' &&
                ![
                  'salary',
                  'zakat',
                  'zakat_companies',
                  'loans',
                  'owner',
                ].contains(module)) ||
            (member['permissions'] as List? ?? []).contains('$module:post');
  Future<void> init() async {
    if (Firebase.apps.isNotEmpty) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
      _autoSync = Timer.periodic(const Duration(seconds: 20), (_) {
        if (live && pendingUploads.isNotEmpty) unawaited(syncUploads());
      });
    }
    prefs = await SharedPreferences.getInstance();
    local = LocalWorkspace(prefs);
    await local.open();
    ledger = Ledger(
      jsonDecode(await rootBundle.loadString('assets/transaction_types.json')),
    );
    ur = prefs.getBool('urdu') ?? false;
    dark = prefs.getBool('dark') ?? false;
    await loadDemo();
    if (Firebase.apps.isNotEmpty) {
      final user = await FirebaseAuth.instance.authStateChanges().first;
      if (user != null) {
        await connect(
          prefs.getString('last-store-${user.uid}') ??
              const String.fromEnvironment(
                'STORE_ID',
                defaultValue: 'family-pharmacy',
              ),
          refreshNow: false,
        );
      }
    }
  }

  Future<void> loadDemo() async {
    _workspaceVersion++;
    _refreshTask = null;
    _uploadTask = null;
    _uploadRetry?.cancel();
    syncing = false;
    live = false;
    storeId = '';
    allowed = [];
    member = {'role': 'owner', 'active': true};
    state = ledger.empty();
    settings = {
      'name': 'Family Pharmacy',
      'accounts': ['cash', 'bank'],
      'zakatTarget': 10000000,
      'owners': defaultOwners(),
    };
    entries = [];
    profiles = [];
    orders = [];
    error = null;
    cached = false;
    pendingUploads = [];
    final raw = await local.read(cacheKey);
    if (raw == null) {
      seed();
      await persist();
    } else {
      final saved = Json.from(jsonDecode(raw));
      pendingUploads = (saved['pendingUploads'] as List? ?? [])
          .map((e) => Json.from(e))
          .toList();
      restore(saved);
    }
    loadDrafts();
    notifyListeners();
  }

  void restore(Json x, {bool migrateNames = false}) {
    state = Json.from(x['state']);
    entries = (x['entries'] as List).map((e) => Json.from(e)).toList();
    orders = (x['orders'] as List? ?? []).map((e) => Json.from(e)).toList();
    profiles = {
      for (final e in (x['profiles'] as List? ?? []))
        '${e['id']}': Json.from(e),
    }.values.toList();
    settings = Json.from(x['config'] ?? x['settings']);
    if (x['member'] != null) member = Json.from(x['member']);
    allowed = List<String>.from(x['allowed'] ?? []);
    settings.putIfAbsent('owners', defaultOwners);
    for (final profile in profiles) {
      if (profile['module'] == 'customers') {
        profile['legacyModule'] = 'customers';
        profile['module'] = 'people';
      }
    }
    normalizeProfileNames(persistRenames: migrateNames);
    drafts.removeWhere((d) => ledger.types[d['type']]?['retired'] == true);
    hasWorkspace = true;
  }

  Json snapshot() => {
    'state': state,
    'entries': entries,
    'profiles': profiles,
    'orders': orders,
    'config': settings,
    'member': member,
    'allowed': allowed,
    'pendingUploads': pendingUploads,
  };
  Future<void> persist() => local.write(cacheKey, snapshot());
  void loadDrafts() {
    drafts = (jsonDecode(prefs.getString(draftKey) ?? '[]') as List)
        .map((e) => Json.from(e))
        .where((e) => ledger.types[e['type']]?['retired'] != true)
        .toList();
  }

  Future<void> saveDraft(
    Json x, {
    String status = 'Draft saved locally',
    String? rejection,
  }) async {
    x = {...x, 'syncStatus': status, 'rejection': rejection};
    final i = drafts.indexWhere((d) => d['id'] == x['id']);
    if (i < 0) {
      drafts.add(x);
    } else {
      drafts[i] = x;
    }
    await prefs.setString(draftKey, jsonEncode(drafts));
    notifyListeners();
  }

  Future<void> discardDraft(String id) async {
    drafts.removeWhere((e) => e['id'] == id);
    await prefs.setString(draftKey, jsonEncode(drafts));
    notifyListeners();
  }

  Future<dynamic> call(String name, Json data) =>
      FirestoreRepository(ledger).execute(storeId, name, data);
  Future<void> connect(String store, {bool refreshNow = true}) async {
    _workspaceVersion++;
    _refreshTask = null;
    _uploadTask = null;
    _uploadRetry?.cancel();
    syncing = false;
    live = true;
    storeId = store;
    cached = false;
    hasWorkspace = false;
    error = null;
    state = ledger.empty();
    entries = [];
    profiles = [];
    orders = [];
    settings = {
      'name': 'Family Pharmacy',
      'accounts': ['cash', 'bank'],
    };
    member = {};
    allowed = [];
    pendingUploads = [];
    final raw = await local.read(cacheKey);
    if (raw != null) {
      final saved = Json.from(jsonDecode(raw));
      pendingUploads = (saved['pendingUploads'] as List? ?? [])
          .map((e) => Json.from(e))
          .toList();
      restore(saved);
      cached = true;
    }
    loadDrafts();
    await prefs.setString('last-store-$uid', store);
    notifyListeners();
    if (refreshNow) await refresh();
  }

  Future<void> refresh({bool afterWrite = false}) {
    if (!live || _disposed) return Future.value();
    unawaited(syncUploads());
    if (_refreshTask != null) {
      // A read begun before a successful write cannot confirm that write.
      if (afterWrite) return _refreshTask!.then((_) => refresh());
      return _refreshTask!;
    }
    final task = _refreshWorkspace(_workspaceVersion);
    _refreshTask = task;
    return task.whenComplete(() {
      if (identical(_refreshTask, task)) _refreshTask = null;
    });
  }

  Future<void> _refreshWorkspace(int version) async {
    syncing = true;
    final revision = _localRevision;
    error = null;
    notifyListeners();
    try {
      final value = await call('workspace', {}).timeout(syncTimeout);
      if (version != _workspaceVersion || !live || revision != _localRevision) {
        return;
      }
      restore(jsonDecode(jsonEncode(value)), migrateNames: true);
      replayPending();
      unawaited(syncUploads());
      cached = false;
      await persist();
    } catch (e) {
      if (version != _workspaceVersion || !live) return;
      cached = hasWorkspace;
      error = e is TimeoutException
          ? 'Sync took too long. Check your internet and tap Retry.'
          : 'Data could not sync. Check your connection or pharmacy access and tap Retry.';
      debugPrint('Workspace sync failed: $e');
    } finally {
      if (version == _workspaceVersion && live) {
        syncing = false;
        notifyListeners();
      }
    }
  }

  Future<void> submit(Json x) async {
    if (entries.any((e) => e['id'] == x['id'])) {
      unawaited(syncUploads());
      await discardDraft(x['id']);
      return;
    }
    if (!canPost(ledger.types[x['type']]?['module'] ?? '')) {
      throw StateError('Entry permission required');
    }
    if ((x['party'] ?? '').isNotEmpty) {
      x = {...x, 'partyName': name(x['party'])};
    }
    if (['capital', 'withdrawal'].contains(x['type'])) {
      final person = owners.where((o) => o['id'] == x['party']).firstOrNull;
      if (person == null) throw StateError('Select an active owner');
      x = {...x, 'ownerShareBps': person['shareBps']};
    }
    final parts = splitPayment(x);
    await _saveFinancial([
      for (final part in parts)
        {
          'id': part['id'],
          'operation': 'postEntry',
          'key': 'entry',
          'value': part,
        },
    ]);
    await discardDraft(x['id']);
  }

  List<Json> splitPayment(Json input) {
    final rows = List<Json>.from(
      (input['allocations'] as List? ?? []).map((v) => Json.from(v)),
    );
    if (rows.length <= 3) return [clone(input)];
    final parts = <Json>[];
    var remaining = input['amount'] as int;
    for (var offset = 0; offset < rows.length; offset += 3) {
      final chunk = rows.skip(offset).take(3).toList();
      final amount = offset + 3 >= rows.length
          ? remaining
          : chunk.fold<int>(0, (n, a) => n + (a['amount'] as int));
      parts.add({
        ...input,
        'id': offset == 0
            ? input['id']
            : '${input['id']}-part-${parts.length + 1}',
        'paymentGroup': input['id'],
        'paymentTotal': input['amount'],
        'amount': amount,
        'allocations': chunk,
      });
      remaining -= amount;
    }
    return parts;
  }

  Future<void> reverseEntry(Json e, String reason, String date) async {
    if (!owner) throw StateError('Owner access required');
    await _saveFinancial([
      {
        'id': 'reverse-${e['id']}',
        'operation': 'reverseEntry',
        'key': 'command',
        'value': {
          'id': 'reverse-${e['id']}',
          'original': e['id'],
          'date': date,
          'reason': reason.trim().isEmpty ? 'Entry removed' : reason,
        },
      },
    ]);
  }

  Json pendingEntry(Json entry) => {
    ...entry,
    if (live) 'syncStatus': 'Pending upload',
    if (live) 'createdBy': uid,
  };

  void _applyFinancial(Json mutation) {
    final op = mutation['operation'], value = Json.from(mutation['value']);
    if (op == 'postEntry') {
      if (entries.any((e) => e['id'] == value['id'])) return;
      if (value['orderId'] != null) {
        validateOrderBill(
          orders.where((o) => o['id'] == value['orderId']).firstOrNull,
          value,
        );
      }
      final result = ledger.post(state, value);
      state = result['state'];
      entries.insert(0, pendingEntry(Json.from(result['entry'])));
      if (value['orderId'] != null) {
        orders.where((o) => o['id'] == value['orderId']).firstOrNull?.addAll({
          'status': 'received',
          'billId': value['id'],
          'billAmount': value['amount'],
        });
      }
      return;
    }
    final id = op == 'correctExpense' ? value['entry']['id'] : value['id'];
    if (entries.any((e) => e['id'] == id)) return;
    final original = entries
        .where((e) => e['id'] == value['original'])
        .firstOrNull;
    if (original == null) throw StateError('Original entry is missing');
    final reversal = ledger.reverse(state, original, {
      'id': op == 'correctExpense' ? value['reverseId'] : id,
      'date': op == 'correctExpense' ? value['entry']['date'] : value['date'],
      'reason': value['reason'],
    });
    if (op == 'correctExpense') {
      final posted = ledger.post(reversal['state'], {
        ...Json.from(value['entry']),
        'replaces': original['id'],
      });
      state = posted['state'];
      original['reversedBy'] = value['reverseId'];
      entries.insertAll(0, [
        pendingEntry(Json.from(posted['entry'])),
        pendingEntry(Json.from(reversal['entry'])),
      ]);
    } else {
      state = reversal['state'];
      original['reversedBy'] = id;
      entries.insert(0, pendingEntry(Json.from(reversal['entry'])));
      if (original['orderId'] != null) {
        orders.where((o) => o['id'] == original['orderId']).firstOrNull?.addAll(
          {'status': 'open', 'billId': '', 'billAmount': 0},
        );
      }
    }
  }

  Future<void> _saveFinancial(List<Json> operations) async {
    if (busy) throw StateError('Submission in progress');
    final previous = clone(snapshot());
    final scope = cacheKey;
    busy = true;
    notifyListeners();
    try {
      for (final operation in operations) {
        _applyFinancial(operation);
        if (live) pendingUploads.add(clone(operation));
      }
      _localRevision++;
      await persist();
    } catch (_) {
      if (scope == cacheKey) {
        pendingUploads = (previous['pendingUploads'] as List)
            .map((e) => Json.from(e))
            .toList();
        restore(previous);
      }
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
    if (live) unawaited(syncUploads());
  }

  bool financialMutation(Json m) =>
      ['postEntry', 'reverseEntry', 'correctExpense'].contains(m['operation']);
  void replayPending() {
    for (final mutation in pendingUploads) {
      if (financialMutation(mutation) && mutation['failed'] == true) continue;
      try {
        _overlayMutation(mutation);
      } catch (e) {
        mutation['failed'] = true;
        mutation['failure'] = e.toString().replaceFirst('Bad state: ', '');
      }
    }
    if (uploadIssues.isNotEmpty) error = 'Some entries need review';
  }

  Future<void> retryUploads() async {
    for (final m in pendingUploads) {
      m.remove('failed');
      m.remove('failure');
    }
    error = null;
    await persist();
    await syncUploads();
  }

  Future<void> discardFailedUpload(String id) async {
    final mutation = pendingUploads
        .where((m) => m['id'] == id && m['failed'] == true)
        .firstOrNull;
    if (mutation == null) return;
    final version = _workspaceVersion;
    // Only rejected writes can be discarded; timeout/unknown commits remain
    // queued with their original idempotency IDs until the server confirms.
    final server = await call('workspace', {}).timeout(syncTimeout);
    if (version != _workspaceVersion) throw StateError('Session changed');
    pendingUploads.removeWhere((m) => m['id'] == id);
    restore(Json.from(server), migrateNames: true);
    replayPending();
    _localRevision++;
    await persist();
    notifyListeners();
    unawaited(syncUploads());
  }

  Future<void> saveOrder(Json order) async {
    if (!canPost('orders')) throw StateError('Supplier permission required');
    validateOrder(
      order,
      previous: orders.where((o) => o['id'] == order['id']).firstOrNull,
    );
    await _saveLocalMutation('saveOrder', 'order', order);
  }

  Future<void> saveStaffProfile(
    Json profile, {
    String? salaryPeriod,
    int? salaryAmount,
  }) async {
    if (salaryPeriod != null &&
        (salaryAmount == null ||
            salaryAmount <= 0 ||
            salaryAmount > 900000000000)) {
      throw StateError('Enter salary for the selected month');
    }
    if (salaryPeriod != null &&
        (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(salaryPeriod) ||
            salaryPeriod.compareTo(today().substring(0, 7)) > 0)) {
      throw StateError('Choose a valid current or past salary month');
    }
    await saveProfile(profile);
    if (salaryPeriod != null) {
      final baseId = 'salary-${profile['id']}-$salaryPeriod';
      final id =
          entries.any((e) => e['id'] == baseId && e['reversedBy'] != null)
          ? '$baseId-${const Uuid().v4()}'
          : baseId;
      final existing = entries
          .where((e) => e['id'] == id && e['reversedBy'] == null)
          .firstOrNull;
      if (existing != null) {
        throw StateError(
          'This month is already recorded. Reverse the old salary entry before changing it.',
        );
      }
      await submit({
        'id': id,
        'type': 'salary_accrual',
        'party': profile['id'],
        'date': today(),
        'reference': salaryPeriod,
        'amount': salaryAmount,
        'notes': 'Salary set from staff profile',
        'allocations': [],
      });
    }
  }

  String normalizeName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ');
  String uniqueProfileName(String requested, {String? exceptId}) {
    final clean = normalizeName(requested);
    final used = profiles
        .where((p) => p['id'] != exceptId)
        .map((p) => normalizeName('${p['name']}').toLowerCase())
        .toSet();
    if (!used.contains(clean.toLowerCase())) return clean;
    final match = RegExp(r'^(.*?)(\d{2,})$').firstMatch(clean);
    final stem = match == null ? clean : match.group(1)!;
    var suffix = match == null ? 2 : (int.tryParse(match.group(2)!) ?? 1) + 1;
    while (used.contains(
      '$stem${suffix.toString().padLeft(2, '0')}'.toLowerCase(),
    )) {
      suffix++;
    }
    return '$stem${suffix.toString().padLeft(2, '0')}';
  }

  void normalizeProfileNames({bool persistRenames = false}) {
    final used = <String>{};
    final usage = <String, int>{};
    for (final e in entries) {
      final id = '${e['party'] ?? ''}';
      usage[id] = (usage[id] ?? 0) + 1;
    }
    final sorted = [...profiles]
      ..sort((a, b) {
        final active = (profileVisible(b) ? 1 : 0).compareTo(
          profileVisible(a) ? 1 : 0,
        );
        if (active != 0) {
          return active;
        }
        final used = (usage['${b['id']}'] ?? 0).compareTo(
          usage['${a['id']}'] ?? 0,
        );
        return used != 0 ? used : '${a['id']}'.compareTo('${b['id']}');
      });
    // Reserve every existing spelling before assigning suffixes.
    final reserved = profiles
        .map((p) => normalizeName('${p['name']}').toLowerCase())
        .toSet();
    for (final profile in sorted) {
      final clean = normalizeName('${profile['name']}');
      var name = clean;
      if (used.contains(clean.toLowerCase())) {
        final match = RegExp(r'^(.*?)(\d{2,})$').firstMatch(clean);
        final stem = match == null ? clean : match.group(1)!;
        var suffix = match == null
            ? 2
            : (int.tryParse(match.group(2)!) ?? 1) + 1;
        do {
          name = '$stem${suffix.toString().padLeft(2, '0')}';
          suffix++;
        } while (reserved.contains(name.toLowerCase()) ||
            used.contains(name.toLowerCase()));
      }
      used.add(name.toLowerCase());
      reserved.add(name.toLowerCase());
      if (name != profile['name']) {
        profile['name'] = name;
        if (persistRenames && live && canPost(profile['module'])) {
          final queued = pendingUploads
              .where(
                (m) =>
                    m['key'] == 'profile' && m['value']['id'] == profile['id'],
              )
              .firstOrNull;
          if (queued != null) {
            queued['value'] = {...Json.from(queued['value']), 'name': name};
          } else {
            pendingUploads.add({
              'id': const Uuid().v4(),
              'operation': 'saveProfile',
              'key': 'profile',
              'value': clone(profile),
            });
          }
        }
      }
    }
  }

  String entryName(Json e) {
    final profile = profiles.where((p) => p['id'] == e['party']).firstOrNull;
    if (profile != null) return profile['name'];
    return e['partyName'] ?? name(e['party']);
  }

  Future<void> saveProfile(Json p) async {
    if (!canPost(p['module'])) throw StateError('Profile permission required');
    if ((p['name'] ?? '').toString().trim().isEmpty) {
      throw StateError('Enter name');
    }
    await _saveLocalMutation('saveProfile', 'profile', {
      ...p,
      'name': uniqueProfileName('${p['name']}', exceptId: p['id']),
      'visible': p['visible'] ?? (p['deleted'] == true ? 0 : 1),
    });
  }

  void _overlayMutation(Json mutation) {
    if (financialMutation(mutation)) {
      _applyFinancial(mutation);
      return;
    }
    final key = mutation['key'] as String;
    final value = Json.from(mutation['value']);
    final list = key == 'profile' ? profiles : orders;
    list.removeWhere((p) => p['id'] == value['id']);
    list.insert(0, value);
  }

  Future<void> _saveLocalMutation(
    String operation,
    String key,
    Json value,
  ) async {
    final previousProfiles = profiles.map(clone).toList();
    final previousOrders = orders.map(clone).toList();
    final previousQueue = pendingUploads.map(clone).toList();
    final mutation = <String, dynamic>{
      'id': const Uuid().v4(),
      'operation': operation,
      'key': key,
      'value': clone(value),
    };
    if (live) {
      pendingUploads.removeWhere(
        (m) => m['key'] == key && m['value']['id'] == value['id'],
      );
      pendingUploads.add(mutation);
    }
    _localRevision++;
    _overlayMutation(mutation);
    try {
      await persist();
    } catch (_) {
      profiles = previousProfiles;
      orders = previousOrders;
      pendingUploads = previousQueue;
      rethrow;
    }
    notifyListeners();
    if (live) unawaited(syncUploads());
  }

  Future<void> syncUploads() {
    if (!live || pendingUploads.isEmpty || _disposed) return Future.value();
    if (_uploadTask != null) return _uploadTask!;
    final version = _workspaceVersion;
    final scope = cacheKey;
    final task = _flushUploads(version, scope);
    _uploadTask = task;
    return task.whenComplete(() {
      if (identical(_uploadTask, task)) _uploadTask = null;
    });
  }

  Future<void> _flushUploads(int version, String scope) async {
    Json? current;
    try {
      while (pendingUploads.isNotEmpty &&
          version == _workspaceVersion &&
          live &&
          !_disposed) {
        current = clone(pendingUploads.first);
        if (current['failed'] == true) {
          error = 'Some entries need review';
          notifyListeners();
          return;
        }
        final args = current['key'] == 'command'
            ? Json.from(current['value'])
            : <String, dynamic>{current['key']: current['value']};
        await call(current['operation'], args).timeout(syncTimeout);
        if (version != _workspaceVersion || scope != cacheKey || _disposed) {
          return;
        }
        _localRevision++;
        pendingUploads.removeWhere((m) => m['id'] == current!['id']);
        if (financialMutation(current)) {
          for (final entry in entries) {
            if (entry['id'] == current['id'] ||
                (current['operation'] == 'correctExpense' &&
                    entry['id'] == current['value']['reverseId'])) {
              entry.remove('syncStatus');
            }
          }
        }
        await persist();
        notifyListeners();
      }
      if (version == _workspaceVersion &&
          live &&
          !_disposed &&
          current != null) {
        error = null;
        unawaited(refresh(afterWrite: true));
      }
    } catch (e) {
      if (version != _workspaceVersion || scope != cacheKey || _disposed) {
        return;
      }
      final rejected =
          e is StateError ||
          (e is FirebaseException &&
              [
                'permission-denied',
                'invalid-argument',
                'failed-precondition',
                'not-found',
                'already-exists',
              ].contains(e.code));
      if (rejected && current != null) {
        final record = pendingUploads
            .where((m) => m['id'] == current!['id'])
            .firstOrNull;
        record?.addAll({
          'failed': true,
          'failure': e is StateError
              ? e.message
              : 'Server rejected this change',
        });
        error = 'Some entries need review';
        await persist();
        notifyListeners();
        // Rebase balances on server data; never count a rejected journal as
        // confirmed. The rejected input remains available for review.
        unawaited(refresh(afterWrite: true));
      } else if (Firebase.apps.isNotEmpty) {
        _uploadRetry?.cancel();
        _uploadRetry = Timer(
          const Duration(seconds: 20),
          () => unawaited(syncUploads()),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && live) {
      unawaited(syncUploads());
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _workspaceVersion++;
    _uploadRetry?.cancel();
    _autoSync?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> saveSettings(Json x) async {
    validateOwners(
      (x['owners'] as List? ?? defaultOwners())
          .map((e) => Json.from(e))
          .toList(),
    );
    if (live) {
      await call('saveSettings', {'settings': x});
      settings = clone(x);
      state['accounts'] = List.from(x['accounts']);
      await persist();
      notifyListeners();
      await refresh(afterWrite: true);
    } else {
      settings = x;
      state['accounts'] = x['accounts'];
      await persist();
      notifyListeners();
    }
  }

  Future<void> closeDay(String date, int counted, String reason) async {
    if (live) {
      await call('closeDay', {
        'date': date,
        'counted': counted,
        'reason': reason,
      });
      await refresh(afterWrite: true);
    } else {
      if (state['closed'][date] != null) throw StateError('Day already closed');
      final expected = entries
          .where((e) => (e['date'] as String).compareTo(date) <= 0)
          .fold<int>(
            0,
            (sum, e) =>
                sum + ((e['effects'] as Json)['money:cash'] as int? ?? 0),
          );
      if (counted != expected && reason.trim().isEmpty) {
        throw StateError('Explain the difference');
      }
      state['closed'][date] = {
        'expected': expected,
        'counted': counted,
        'difference': counted - expected,
        'reason': reason,
        'by': 'demo-owner',
        'at': DateTime.now().toUtc().toIso8601String(),
      };
      await persist();
      notifyListeners();
    }
  }

  void toggleLanguage() {
    ur = !ur;
    prefs.setBool('urdu', ur);
    notifyListeners();
  }

  void toggleDark() {
    dark = !dark;
    prefs.setBool('dark', dark);
    notifyListeners();
  }

  int balance(String key) => state['balances']?[key] as int? ?? 0;
  int total(String prefix) => ((state['balances'] ?? {}) as Json).entries
      .where((e) => e.key.startsWith(prefix))
      .fold(0, (a, e) => a + (e.value as int));
  String name(String? id) =>
      profiles.where((p) => p['id'] == id).firstOrNull?['name'] ??
      owners.where((o) => o['id'] == id).firstOrNull?['name'] ??
      id ??
      '';
  List<Json> people(String module) => module == 'owner'
      ? owners
      : profiles
            .where((p) => p['module'] == module && profileVisible(p))
            .toList();
  List<Json> bills(String module, String party) =>
      ((state['obligations'] ?? {}) as Json).values
          .map((v) => Json.from(v))
          .where((v) => v['module'] == module && v['party'] == party)
          .toList();
  String tr(String en) {
    final label = en
        .replaceAll('Supplier companies', 'Companies')
        .replaceAll('Supplier reports', 'Company reports')
        .replaceAll('Suppliers', 'Companies')
        .replaceAll('Supplier', 'Company')
        .replaceAll('supplier', 'company');
    return ur ? (translations[label] ?? translations[en] ?? label) : label;
  }

  String typeLabel(String type) =>
      ledger.types[type]?[ur ? 'ur' : 'label'] ?? tr('Reversal');
  int get netSalesTotal => entries.fold<int>(
    0,
    (sum, e) =>
        sum -
        ((e['effects'] as Json)['netSales'] as int? ?? 0) -
        ((e['effects'] as Json)['sales'] as int? ?? 0) -
        ((e['effects'] as Json)['returns'] as int? ?? 0),
  );
  int amountForPerson(String module, String party) => entries
      .where((e) => e['module'] == module && e['party'] == party)
      .fold<int>(
        0,
        (sum, e) =>
            sum +
            ((e['effects'] as Json)[module == 'rent'
                        ? 'expense:rent'
                        : module == 'zakat_companies'
                        ? 'zakat:company'
                        : 'zakat']
                    as int? ??
                0),
      );
  static bool profileVisible(Json p) =>
      p['visible'] != 0 &&
      p['active'] != false &&
      p['deleted'] != true &&
      p['purged'] != true;
  Map<String, int> profileBalances(String id) => {
    'Qarz': balance('loanAsset:$id') + balance('loanDebt:$id'),
    'Salary remaining': -balance('salary:$id'),
    'Salary advance': balance('salaryAdvance:$id'),
    'Company balance': -balance('supplier:$id'),
  }..removeWhere((_, value) => value == 0);
  Future<void> removeProfile(Json profile, {bool force = false}) async {
    if (!force && profileBalances(profile['id']).isNotEmpty) {
      throw StateError('Clear remaining balance or choose Force move to bin');
    }
    await saveProfile({
      ...profile,
      'active': false,
      'deleted': true,
      'visible': 0,
      'purged': false,
    });
  }

  Future<void> restoreProfile(Json profile) => saveProfile({
    ...profile,
    'active': true,
    'deleted': false,
    'visible': 1,
    'purged': false,
  });
  Future<void> purgeProfile(Json profile) async {
    if (!owner) throw StateError('Owner access required');
    // A hidden tombstone retains the historical name and journal references.
    await saveProfile({
      'id': profile['id'],
      'module': profile['module'],
      'name': profile['name'],
      'active': false,
      'deleted': true,
      'visible': 0,
      'purged': true,
    });
  }

  String nextBillNumber(String party) {
    var last = 0;
    for (final e in entries.where(
      (e) =>
          e['type'] == 'supplier_bill' &&
          (party.isEmpty || e['party'] == party),
    )) {
      final n = int.tryParse('${e['reference']}') ?? 0;
      if (n > last) last = n;
    }
    return '${last + 1}';
  }

  List<Json> allocateOldest(
    String module,
    String party,
    int amount, {
    bool allowExcess = false,
  }) {
    final chronology = {
      for (var i = 0; i < entries.length; i++) entries[i]['id']: i,
    };
    final sources = {for (final e in entries) e['id']: e};
    final unpaid =
        bills(module, party).where((b) => b['remaining'] > 0).toList()..sort((
          a,
          b,
        ) {
          final d = '${a['date']}'.compareTo('${b['date']}');
          if (d != 0) return d;
          final time = '${sources[a['id']]?['createdAt'] ?? ''}'.compareTo(
            '${sources[b['id']]?['createdAt'] ?? ''}',
          );
          if (time != 0) return time;
          final ai = int.tryParse('${a['reference']}'),
              bi = int.tryParse('${b['reference']}');
          if (ai != null && bi != null && ai != bi) return ai.compareTo(bi);
          return (chronology[b['id']] ?? 0).compareTo(chronology[a['id']] ?? 0);
        });
    var left = amount;
    final result = <Json>[];
    for (final b in unpaid) {
      if (left <= 0) break;
      final take = left < b['remaining'] ? left : b['remaining'] as int;
      result.add({'id': b['id'], 'amount': take});
      left -= take;
    }
    if (left > 0 && !allowExcess) {
      throw StateError('Amount exceeds remaining balance');
    }
    return result;
  }

  List<Json> salaryAllocations(String party, int amount) {
    final unpaid =
        bills('salary', party).where((b) => b['remaining'] > 0).toList()..sort(
          (a, b) =>
              '${a['date']} ${a['id']}'.compareTo('${b['date']} ${b['id']}'),
        );
    var left = amount;
    final rows = <Json>[];
    for (final b in unpaid) {
      if (left == 0 || rows.length == 3) break;
      final take = left < b['remaining'] ? left : b['remaining'] as int;
      rows.add({'id': b['id'], 'amount': take});
      left -= take;
    }
    if (left > 0) {
      throw StateError(
        'Amount exceeds salary due for three periods. Use a smaller payment or Pay advance.',
      );
    }
    return rows;
  }

  List<Json> get owners => (settings['owners'] as List? ?? defaultOwners())
      .map((e) => Json.from(e))
      .toList();
  Future<void> correctExpense(
    Json original,
    Json replacement,
    String reason,
  ) async {
    if (!owner) throw StateError('Owner access required');
    await _saveFinancial([
      {
        'id': replacement['id'],
        'operation': 'correctExpense',
        'key': 'command',
        'value': {
          'original': original['id'],
          'entry': replacement,
          'reverseId': 'reverse-${original['id']}',
          'reason': reason.trim().isEmpty ? 'Entry edited' : reason,
        },
      },
    ]);
  }

  Future<void> signOut() async {
    if (Firebase.apps.isNotEmpty) await FirebaseAuth.instance.signOut();
    await loadDemo();
  }

  void seed() {
    profiles = [
      {
        'id': 'khan',
        'module': 'suppliers',
        'name': 'Khan Distributors',
        'phone': '091 555 0104',
        'active': true,
      },
      {
        'id': 'staff',
        'module': 'salary',
        'name': 'Bilal Ahmad',
        'active': true,
      },
      {'id': 'shop', 'module': 'rent', 'name': 'Main pharmacy', 'active': true},
      {
        'id': 'loan',
        'module': 'loans',
        'name': 'Business loan',
        'active': true,
      },
      {
        'id': 'recipient',
        'module': 'zakat',
        'name': 'Anonymous recipient',
        'active': true,
      },
      {
        'id': 'company',
        'module': 'zakat_companies',
        'name': 'Family welfare company',
        'active': true,
      },
    ];
    void add(
      String id,
      String type,
      int amount, {
      String party = '',
      String date = '2026-10-14',
      String reference = '',
      String? bill,
      Json extra = const {},
    }) {
      final x = {
        'id': id,
        'type': type,
        'amount': amount * 100,
        'party': party,
        'date': date,
        'account': 'cash',
        'target': 'bank',
        'reference': reference,
        'notes': 'Synthetic demo data',
        if (bill != null)
          'allocations': [
            {'id': bill, 'amount': amount * 100},
          ],
        ...extra,
      };
      final result = ledger.post(state, x);
      state = result['state'];
      entries.insert(0, result['entry']);
    }

    add('opening', 'opening_cash', 200000, date: '2026-09-01');
    add(
      'bill-kd',
      'supplier_bill',
      300000,
      party: 'khan',
      date: '2026-09-20',
      reference: 'KD-104',
      extra: {'due': '2026-10-15'},
    );
    add(
      'return-kd',
      'supplier_return',
      15000,
      party: 'khan',
      date: '2026-09-28',
      bill: 'bill-kd',
    );
    add(
      'payment-1',
      'supplier_payment',
      25000,
      party: 'khan',
      date: '2026-10-05',
      bill: 'bill-kd',
    );
    add('payment-2', 'supplier_payment', 10000, party: 'khan', bill: 'bill-kd');
    add(
      'salary-advance',
      'salary_advance',
      5000,
      party: 'staff',
      date: '2026-10-01',
    );
    add(
      'salary-month',
      'salary_accrual',
      30000,
      party: 'staff',
      reference: '2026-10',
    );
    add(
      'salary-apply',
      'salary_apply',
      5000,
      party: 'staff',
      bill: 'salary-month',
    );
    add(
      'salary-paid',
      'salary_payment',
      20000,
      party: 'staff',
      bill: 'salary-month',
    );
    add(
      'rent-paid',
      'rent_payment',
      15000,
      party: 'shop',
      reference: '2026-10',
    );
    add('zakat-paid', 'zakat', 2000, party: 'recipient');
    add('loan-given', 'loan_lend', 20000, party: 'loan');
    add('loan-received', 'loan_collect', 5000, party: 'loan');
    add('daily-demo', 'daily_sales', 53000);
  }
}

const translations = <String, String>{
  'Profiles': 'پروفائلز',
  'Net daily sale': 'روزانہ خالص فروخت',
  'Daily net sale': 'روزانہ خالص فروخت',
  'Zakat companies': 'زکوٰۃ کمپنیاں',
  'Owners & shares': 'مالکان اور حصص',
  'Owner share': 'مالک کا حصہ',
  'Add owner': 'مالک شامل کریں',
  'Edit owners': 'مالکان کی تفصیل بدلیں',
  'Total shares': 'کل حصص',
  'Remove profile': 'پروفائل ہٹائیں',
  'Edit expense': 'خرچ درست کریں',
  'Remove expense': 'خرچ منسوخ کریں',
  'Reverse expense': 'خرچ واپس کریں',
  'Dinner': 'رات کا کھانا',
  'Lunch': 'دوپہر کا کھانا',
  'Tea': 'چائے',
  'Other': 'دیگر',
  'Rent paid': 'ادا شدہ کرایہ',
  'Loan people': 'قرض کے افراد',
  'Staff profiles': 'عملے کی پروفائلز',
  'Zakat recipients': 'زکوٰۃ وصول کنندگان',
  'Supplier companies': 'سپلائر کمپنیاں',
  'General profiles': 'عام پروفائلز',
  'Change category': 'قسم بدلیں',
  'Security': 'سیکیورٹی',
  'Lock app': 'ایپ لاک کریں',
  'PIN & fingerprint': 'پن اور فنگر پرنٹ',
  'Archived': 'محفوظ شدہ',
  'Daily sale already includes returns from Abuzar.':
      'روزانہ فروخت میں ابوزر کی واپسی پہلے سے شامل ہے۔',

  'Pharmacy Hisab': 'فارمیسی حساب',
  'Family Pharmacy': 'فیملی فارمیسی',
  'Home': 'ہوم',
  'Registers': 'رجسٹر',
  'Reports': 'رپورٹس',
  'More': 'مزید',
  'Suppliers': 'سپلائرز',
  'Pay supplier': 'سپلائر کو ادائیگی',
  'Customers': 'گاہک',
  'Salary': 'تنخواہ',
  'Rent': 'کرایہ',
  'Loans': 'قرض',
  'Zakat': 'زکوٰۃ',
  'Expenses': 'اخراجات',
  'Owner': 'مالک',
  'Cashbook': 'کیش بک',
  'Daily sales': 'روزانہ فروخت',
  'Net sales today': 'آج کی خالص فروخت',
  'Gross sales': 'کل فروخت',
  'Returns': 'واپسی',
  'Customer dues': 'گاہکوں کے بقایا',
  'Supplier payable': 'سپلائر کو واجب الادا',
  'Add daily sales': 'روزانہ فروخت درج کریں',
  'Receive payment': 'رقم وصول کریں',
  'Expense': 'خرچ',
  'Due soon': 'جلد واجب الادا',
  'See all': 'سب دیکھیں',
  'Tomorrow': 'کل',
  'Total payable': 'کل واجب الادا',
  'Search name or reference': 'نام یا حوالہ تلاش کریں',
  'Bill': 'بل',
  'Paid': 'ادا شدہ',
  'Confirmed return credit': 'تصدیق شدہ واپسی کریڈٹ',
  'Outstanding': 'بقایا',
  'Payment history': 'ادائیگی کی تفصیل',
  'Payment': 'ادائیگی',
  'Return credit': 'واپسی کریڈٹ',
  'Confirmed': 'تصدیق شدہ',
  'Amount': 'رقم',
  'Date': 'تاریخ',
  'Payment account': 'ادائیگی کا اکاؤنٹ',
  'Cash drawer': 'نقد دراز',
  'Bank / digital': 'بینک / ڈیجیٹل',
  'Allocate to bill': 'بل میں تقسیم کریں',
  'Remaining after payment': 'ادائیگی کے بعد بقایا',
  'Reference / notes (optional)': 'حوالہ / نوٹ (اختیاری)',
  'Review payment': 'ادائیگی کا جائزہ',
  'Review entry': 'اندراج کا جائزہ',
  'Confirm and post': 'تصدیق اور درج کریں',
  'Save local draft': 'مقامی مسودہ محفوظ کریں',
  'Cancel': 'منسوخ',
  'Saved successfully': 'کامیابی سے محفوظ ہوگیا',
  'Demo mode': 'ڈیمو موڈ',
  'Local synthetic data': 'مقامی فرضی ڈیٹا',
  'No entries yet': 'ابھی کوئی اندراج نہیں',
  'Add entry': 'اندراج کریں',
  'Add person': 'نیا نام شامل کریں',
  'Name': 'نام',
  'Phone': 'فون',
  'Address': 'پتہ',
  'Notes': 'نوٹس',
  'Save': 'محفوظ کریں',
  'Reference': 'حوالہ',
  'Due date': 'آخری تاریخ',
  'Select person': 'نام منتخب کریں',
  'Unallocated advance': 'غیر مختص ایڈوانس',
  'Allow intentional advance / excess': 'جان بوجھ کر ایڈوانس کی اجازت',
  'Account statement': 'اکاؤنٹ کی تفصیل',
  'All': 'سب',
  'From': 'سے',
  'To': 'تک',
  'Export CSV': 'CSV برآمد کریں',
  'Export PDF': 'PDF برآمد کریں',
  'Settings': 'ترتیبات',
  'Pharmacy name': 'فارمیسی کا نام',
  'Dark mode': 'ڈارک موڈ',
  'Language': 'زبان',
  'Offline drafts': 'آف لائن مسودے',
  'Production sign in': 'اصل اکاؤنٹ میں داخل ہوں',
  'Email': 'ای میل',
  'Password': 'پاس ورڈ',
  'Store ID': 'سٹور آئی ڈی',
  'Sign in': 'داخل ہوں',
  'Sign out': 'باہر نکلیں',
  'Retry': 'دوبارہ کوشش',
  'Daily close': 'روزانہ حساب بند کریں',
  'Expected cash': 'متوقع نقد',
  'Counted cash': 'گنی ہوئی نقدی',
  'Difference explanation': 'فرق کی وضاحت',
  'Close day': 'دن بند کریں',
  'Reversal': 'منسوخی اندراج',
  'Reverse entry': 'اندراج واپس کریں',
  'Correction reason': 'درستگی کی وجہ',
  'Amount paid': 'ادا شدہ رقم',
  'Annual zakat target': 'سالانہ زکوٰۃ ہدف',
  'Remaining target': 'باقی ہدف',
  'Loan receivables': 'قابل وصول قرض',
  'Loan payables': 'واجب الادا قرض',
  'Salary outstanding': 'تنخواہ بقایا',
  'Rent outstanding': 'کرایہ بقایا',
  'Cash balance': 'نقد بیلنس',
  'Collections of old dues': 'پرانے بقایا کی وصولی',
  'Cash outflows': 'نقد ادائیگیاں',
  'Zakat this month': 'اس ماہ کی زکوٰۃ',
  'Sales receipts': 'فروخت کی وصولیاں',
  'Cash sales': 'نقد فروخت',
  'Bank sales': 'بینک فروخت',
  'Named customer credit': 'گاہک کی ادھار فروخت',
  'Customer returns': 'گاہک کی واپسی',
  'Cash refund now': 'فوری نقد واپسی',
  'Bank refund now': 'فوری بینک واپسی',
  'Customer debt reduction': 'گاہک کے قرض میں کمی',
  'Retained customer credit': 'گاہک کا محفوظ کریڈٹ',
  'Shift / period reference': 'شفٹ / مدت کا حوالہ',
  'Category': 'قسم',
  'Target account': 'وصول کنندہ اکاؤنٹ',
  'Bill / period': 'بل / مدت',
  'Current': 'موجودہ',
  'Overdue': 'تاخیر شدہ',
  'Advance / credit': 'ایڈوانس / کریڈٹ',
  'Profile': 'تفصیل',
  'Active': 'فعال',
  'Salary basis': 'تنخواہ کی بنیاد',
  'Rate': 'شرح',
  'Payable days': 'قابل ادائیگی دن',
  'Allowances / bonus': 'الاؤنس / بونس',
  'Deductions': 'کٹوتیاں',
  'Deduction reason': 'کٹوتی کی وجہ',
  'Effective date': 'مؤثر تاریخ',
  'Joining date': 'شمولیت کی تاریخ',
  'Monthly proration': 'ماہانہ تناسب',
  'Calendar days': 'کیلنڈر کے دن',
  'Fixed 30 days': 'مقررہ ۳۰ دن',
  'Pay schedule': 'ادائیگی کا شیڈول',
  'Credit limit': 'ادھار کی حد',
  'Security deposit': 'سیکیورٹی ڈپازٹ',
  'Review': 'جائزہ',
  'No matching records': 'کوئی مماثل ریکارڈ نہیں',
  'Audit history': 'آڈٹ کی تفصیل',
  'User access': 'صارف کی رسائی',
  'User UID': 'صارف کی شناخت',
  'Role': 'کردار',
  'Permissions': 'اجازتیں',
  'Owner approval': 'مالک کی منظوری',
  'Create store': 'سٹور بنائیں',
  'Financial overview': 'مالی جائزہ',
  'Aging': 'بقایا کی مدت',
  'Total': 'کل',
  'Draft saved locally': 'مسودہ مقامی طور پر محفوظ',
  'Pending submission': 'جمع کرانا باقی',
  'Rejected / retry required': 'مسترد / دوبارہ کوشش کریں',
  'Posted successfully': 'کامیابی سے درج ہوا',
  'Read cached data': 'محفوظ شدہ ڈیٹا',
  'Refresh': 'تازہ کریں',
  'Receipt': 'رسید',
  'Delete draft': 'مسودہ حذف کریں',
  'Preview': 'پیش نظارہ',
  'View details': 'تفصیل دیکھیں',
  'All accounts': 'تمام اکاؤنٹس',
  'All types': 'تمام اقسام',
  'All statuses': 'تمام حالتیں',
  'Posted': 'درج شدہ',
  'Reversed': 'واپس شدہ',
  'Original': 'اصل',
  'Balance': 'بیلنس',
  'Monthly': 'ماہانہ',
  'Weekly': 'ہفتہ وار',
  'Daily': 'روزانہ',
  'Yearly': 'سالانہ',
  'Custom': 'منتخب مدت',
  'Reports and statements': 'رپورٹس اور حساب',
  'Only confirmed credits reduce payable.':
      'صرف تصدیق شدہ کریڈٹ بقایا کم کرتا ہے۔',
  'No cash movement': 'نقد رقم کی کوئی حرکت نہیں',
  'Saved drafts require review before posting.':
      'مسودہ درج کرنے سے پہلے جائزہ ضروری ہے۔',
  'Payment reminders': 'ادائیگی کی یاددہانیاں',
  'Installment amount': 'قسط کی رقم',
  'Payment frequency': 'ادائیگی کی مدت',
  'Irregular': 'غیر مقرر',
  'Draft / requested return': 'مسودہ / درخواست کردہ واپسی',
  'Rejected return': 'مسترد شدہ واپسی',
  'Confirm return': 'واپسی کی تصدیق',
  'Report period': 'رپورٹ کی مدت',
  'Generated': 'تیار شدہ',
  'Filters': 'فلٹرز',
  'Opening': 'ابتدائی',
  'Receipts': 'وصولیاں',
  'Payments': 'ادائیگیاں',
  'Closing': 'اختتامی',
  'No inventory or cost of goods is tracked.':
      'اسٹاک یا فروخت شدہ مال کی لاگت درج نہیں ہوتی۔',
};
