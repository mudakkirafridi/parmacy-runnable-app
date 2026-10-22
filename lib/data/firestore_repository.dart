import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/ledger.dart';
import '../core/ownership.dart';

/// Spark-plan repository. Firestore rules validate every atomic financial write.
/// No Cloud Functions, service-account key or client-side password is required.
class FirestoreRepository {
  final Ledger ledger;
  final FirebaseFirestore db;
  FirestoreRepository(this.ledger, {FirebaseFirestore? db})
    : db = db ?? FirebaseFirestore.instance;
  String get uid => FirebaseAuth.instance.currentUser!.uid;
  dynamic plain(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    if (value is Map) {
      return value.map((key, v) => MapEntry(key.toString(), plain(v)));
    }
    if (value is List) return value.map(plain).toList();
    return value;
  }

  bool permitted(Json member, String module, String action) {
    if (member['active'] != true) return false;
    if (member['role'] == 'owner') return true;
    if (module == 'owner') return false;
    if (member['role'] == 'manager' &&
        ![
          'salary',
          'zakat',
          'zakat_companies',
          'loans',
          'committee',
        ].contains(module)) {
      return true;
    }
    return (member['permissions'] as List? ?? []).contains('$module:$action');
  }

  Future<dynamic> execute(String store, String operation, Json args) async {
    final root = db.collection('stores').doc(store);
    switch (operation) {
      case 'workspace':
        return workspace(root);
      case 'postEntry':
        return post(root, Json.from(args['entry']));
      case 'reverseEntry':
        return reverse(root, args);
      case 'correctExpense':
        return correctExpense(root, args);
      case 'closeDay':
        return closeDay(root, args);
      case 'saveOrder':
        final order = Json.from(args['order']);
        await root.collection('orders').doc(order['id']).set({
          ...order,
          'updatedBy': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return {'ok': true};
      case 'saveProfile':
        final profile = Json.from(args['profile']);
        // Old customer documents retain their server module/identity. The
        // client displays these as general profiles without changing journals.
        if (profile['legacyModule'] == 'customers') {
          profile['module'] = 'customers';
        }
        await root.collection('profiles').doc(profile['id']).set(profile);
        return {'ok': true};
      case 'saveSettings':
        final settings = Json.from(args['settings']);
        validateOwners(
          (settings['owners'] as List).map((v) => Json.from(v)).toList(),
        );
        await root.update({
          'name': settings['name'],
          'accounts': settings['accounts'],
          'owners': settings['owners'],
          'zakatTarget': settings['zakatTarget'] ?? 0,
        });
        return {'ok': true};
      case 'setMember':
        await root.collection('members').doc(args['uid']).set({
          'role': args['role'],
          'active': args['active'],
          'permissions': args['permissions'],
          'approvedBy': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return {'ok': true};
      case 'reconcile':
        return reconcile(root);
      default:
        throw StateError('Unsupported Firestore operation');
    }
  }

  Future<Json> workspace(DocumentReference<Json> root) async {
    const server = GetOptions(source: Source.server);
    final header = await Future.wait([
      root.collection('members').doc(uid).get(server),
      root.get(server),
      root.collection('control').doc('periods').get(server),
    ], eagerError: true);
    final m = header[0];
    final member = m.data() ?? {};
    if (member['active'] != true) {
      throw StateError('Access revoked or no store membership');
    }
    final config = header[1].data();
    if (config == null) throw StateError('Pharmacy store is not set up');
    final control = header[2].data() ?? {};
    final modules = <String>{
      ...ledger.types.values.map((v) => v['module'] as String),
      'people',
    };
    final allowed = modules
        .where((module) => permitted(member, module, 'read'))
        .toList();
    final entries = <Json>[], profiles = <Json>[];
    final combined = ledger.empty();
    combined['accounts'] = config['accounts'];
    // Launch independent reads together. Serial module reads previously made
    // login wait for dozens of network round trips, even for an empty store.
    final List<List<dynamic>> moduleReads;
    if (member['role'] == 'owner') {
      final bulk = await Future.wait<dynamic>([
        root.collection('entries').get(server),
        root.collection('profiles').get(server),
        root.collection('modules').get(server),
      ], eagerError: true);
      entries.addAll(
        (bulk[0] as QuerySnapshot<Json>).docs.map(
          (d) => Json.from(plain(d.data())),
        ),
      );
      profiles.addAll(
        (bulk[1] as QuerySnapshot<Json>).docs.map(
          (d) => {'id': d.id, ...Json.from(plain(d.data()))},
        ),
      );
      moduleReads = [
        for (final d in (bulk[2] as QuerySnapshot<Json>).docs) [null, null, d],
      ];
    } else {
      moduleReads = await Future.wait(
        allowed.map(
          (module) => Future.wait<dynamic>([
            root
                .collection('entries')
                .where('module', isEqualTo: module)
                .get(server),
            root
                .collection('profiles')
                .where('module', isEqualTo: module)
                .get(server),
            root.collection('modules').doc(module).get(server),
          ], eagerError: true),
        ),
        eagerError: true,
      );
    }
    for (final values in moduleReads) {
      if (values[0] != null) {
        final source = values[0] as QuerySnapshot<Json>;
        entries.addAll(source.docs.map((d) => Json.from(plain(d.data()))));
        final people = values[1] as QuerySnapshot<Json>;
        profiles.addAll(
          people.docs.map((d) => {'id': d.id, ...Json.from(plain(d.data()))}),
        );
      }
      final state = (values[2] as DocumentSnapshot<Json>).data();
      if (state != null) {
        for (final item in (state['balances'] as Map? ?? {}).entries) {
          combined['balances'][item.key] =
              (combined['balances'][item.key] ?? 0) + item.value;
        }
        (combined['obligations'] as Json).addAll(
          Json.from(state['obligations'] ?? {}),
        );
        (combined['unique'] as Json).addAll(Json.from(state['unique'] ?? {}));
        (combined['unallocated'] as Json).addAll(
          Json.from(state['unallocated'] ?? {}),
        );
      }
    }
    if (allowed.contains('cashbook')) {
      final accounts = List<String>.from(config['accounts']);
      final money = await Future.wait(
        accounts.map(
          (account) => root.collection('accounts').doc(account).get(server),
        ),
        eagerError: true,
      );
      for (var i = 0; i < accounts.length; i++) {
        final account = accounts[i], doc = money[i];
        combined['balances']['money:$account'] = doc.data()?['balance'] ?? 0;
      }
      final closures = await root.collection('closures').get(server);
      for (final closure in closures.docs) {
        combined['closed'][closure.id] = plain(closure.data());
      }
    }
    if ((control['lockedThrough'] ?? '').isNotEmpty) {
      combined['closed'][control['lockedThrough']] ??= {};
    }
    return {
      'config': plain(config),
      'member': plain(member),
      'state': combined,
      'entries': entries,
      'profiles': profiles,
      'orders': permitted(member, 'suppliers', 'read')
          ? (await root.collection('orders').get(server)).docs
                .map((d) => Json.from(plain(d.data())))
                .toList()
          : [],
      'allowed': allowed,
    };
  }

  Json stateFor(Json? stored, Json config, Json control) {
    final state = ledger.empty();
    if (stored != null) {
      for (final key in ['balances', 'obligations', 'unique', 'unallocated']) {
        state[key] = Json.from(stored[key] ?? {});
      }
    }
    state['accounts'] = config['accounts'];
    if ((control['lockedThrough'] ?? '').isNotEmpty) {
      state['closed'][control['lockedThrough']] = {};
    }
    return state;
  }

  String resolve(String template, Json entry) => template.replaceAllMapped(
    RegExp(r'\{(\w+)\}'),
    (m) => '${entry[m[1]] ?? ''}',
  );
  Json metadata(Json entry) {
    final type = ledger.types[entry['type']];
    return {
      ...entry,
      'definition': {
        for (final flag in [
          'obligation',
          'allocate',
          'creditReturn',
          'applyCredit',
          'owner',
          'partyRequired',
          'allowZero',
          'onePerDay',
          'period',
          'limit',
          'requireCredit',
        ])
          flag: type[flag] ?? false,
        for (final key in ['module', 'debit', 'credit']) key: type[key],
      },
      'debitAccount': resolve(type['debit'], entry),
      'creditAccount': resolve(type['credit'], entry),
      'allocations': entry['allocations'] ?? [],
      'allocatedAmount': (entry['allocations'] as List? ?? []).fold<int>(
        0,
        (total, a) => total + (a['amount'] as int),
      ),
      'reference': entry['reference'] ?? '',
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Json persisted(
    Json state,
    Json operation, {
    String kind = 'post',
    String original = '',
    String reversal = '',
  }) => {
    'balances': Map.fromEntries(
      (state['balances'] as Json).entries.where(
        (e) => !e.key.startsWith('money:'),
      ),
    ),
    'obligations': state['obligations'],
    'unique': state['unique'],
    'unallocated': state['unallocated'] ?? {},
    'operation': Map.from(operation)..remove('createdAt'),
    'lastOperation': operation['id'],
    'lastKind': kind,
    'lastOriginal': original,
    'lastReversal': reversal,
  };
  Json correctionState(Json state) => {
    'balances': Map.fromEntries(
      (state['balances'] as Json).entries.where(
        (e) => !e.key.startsWith('money:'),
      ),
    ),
    'obligations': state['obligations'],
    'unique': state['unique'],
    'unallocated': state['unallocated'] ?? {},
  };
  void moneyWrites(
    Transaction t,
    DocumentReference<Json> root,
    Json entry,
    Json effects,
  ) {
    for (final item in effects.entries.where(
      (e) => e.key.startsWith('money:') && e.value != 0,
    )) {
      t.set(
        root.collection('accounts').doc(item.key.substring(6)),
        {
          'balance': FieldValue.increment(item.value as int),
          'lastOperation': entry['id'],
          'lastModule': entry['module'],
        },
        SetOptions(merge: true),
      );
    }
  }

  Future<Json> post(DocumentReference<Json> root, Json input) async {
    final type = ledger.types[input['type']];
    if (type == null || type['retired'] == true) {
      throw StateError('This entry type has been removed');
    }
    final module = type['module'] as String,
        er = root.collection('entries').doc(input['id']);
    final sr = root.collection('modules').doc(module);
    return db.runTransaction((t) async {
      final existing = await t.get(er);
      if (existing.exists) return {'id': input['id'], 'repeated': true};
      final ms = await t.get(root.collection('members').doc(uid));
      final cs = await t.get(root);
      final ss = await t.get(sr);
      final control = await t.get(root.collection('control').doc('periods'));
      if (!permitted(ms.data() ?? {}, module, 'post')) {
        throw StateError('Module permission required');
      }
      final state = stateFor(ss.data(), cs.data()!, control.data() ?? {}),
          result = ledger.post(state, {
            ...input,
            'allocations': input['allocations'] ?? [],
          });
      Json? order;
      if ((input['orderId'] ?? '') != '') {
        order = (await t.get(
          root.collection('orders').doc(input['orderId']),
        )).data();
        if (order == null ||
            order['status'] != 'open' ||
            order['party'] != input['party'] ||
            input['type'] != 'supplier_bill') {
          throw StateError(
            'Order is already received, cancelled or belongs to another company',
          );
        }
      }
      final entry = metadata(Json.from(result['entry']));
      if (order != null) {
        t.update(root.collection('orders').doc(input['orderId']), {
          'status': 'received',
          'billId': entry['id'],
          'billAmount': entry['amount'],
          'updatedBy': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      t.set(sr, persisted(result['state'], entry));
      t.set(er, entry);
      moneyWrites(t, root, entry, entry['effects']);
      return {'id': entry['id']};
    });
  }

  Json reversalMetadata(Json reversal, Json original) => {
    ...reversal,
    'debitAccount': original['creditAccount'],
    'creditAccount': original['debitAccount'],
    'allocations': original['allocations'] ?? [],
    'allocatedAmount': original['allocatedAmount'] ?? 0,
    'advanceDelta': -(original['advanceDelta'] as int? ?? 0),
    'createdBy': uid,
    'createdAt': FieldValue.serverTimestamp(),
  };
  Future<Json> reverse(DocumentReference<Json> root, Json input) async =>
      db.runTransaction((t) async {
        final originalRef = root.collection('entries').doc(input['original']),
            er = root.collection('entries').doc(input['id']);
        final exists = await t.get(er);
        if (exists.exists) return {'id': input['id'], 'repeated': true};
        final os = await t.get(originalRef);
        if (!os.exists) throw StateError('Original missing');
        final original = Json.from(plain(os.data()));
        final sr = root.collection('modules').doc(original['module']);
        final ss = await t.get(sr),
            cs = await t.get(root),
            control = await t.get(root.collection('control').doc('periods'));
        final result = ledger.reverse(
              stateFor(ss.data(), cs.data()!, control.data() ?? {}),
              original,
              input,
            ),
            entry = reversalMetadata(result['entry'], original);
        t.set(
          sr,
          persisted(
            result['state'],
            entry,
            kind: 'reverse',
            original: original['id'],
            reversal: entry['id'],
          ),
        );
        if (original['orderId'] != null) {
          t.update(root.collection('orders').doc(original['orderId']), {
            'status': 'open',
            'billId': '',
            'billAmount': 0,
            'updatedBy': uid,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        t.set(er, entry);
        t.update(originalRef, {'reversedBy': entry['id']});
        moneyWrites(t, root, entry, entry['effects']);
        return {'id': entry['id']};
      });
  Future<Json> correctExpense(DocumentReference<Json> root, Json input) async {
    final source =
        (await root.collection('entries').doc(input['original']).get()).data();
    if (source == null) throw StateError('Original missing');
    final replacement = Json.from(input['entry']);
    if (source['type'] != replacement['type']) {
      throw StateError('Keep the same entry type');
    }
    if ((source['allocations'] as List? ?? []).length > 1 ||
        (replacement['allocations'] as List? ?? []).length > 1) {
      // Each stage has its own rule budget and stable retry identity.
      await reverse(root, {
        'id': input['reverseId'],
        'original': input['original'],
        'date': replacement['date'],
        'reason': input['reason'],
        'editTarget': replacement['id'],
      });
      final rev =
          (await root.collection('entries').doc(input['reverseId']).get())
              .data();
      if (rev?['editTarget'] != replacement['id']) {
        throw StateError(
          'This entry was changed by another action. Refresh records.',
        );
      }
      return post(
        root,
        {
          ...replacement,
          'editedFrom': input['original'],
          'editReversal': input['reverseId'],
        }..remove('replaces'),
      );
    }
    return atomicCorrection(root, input);
  }

  Future<Json> atomicCorrection(
    DocumentReference<Json> root,
    Json input,
  ) async => db.runTransaction((t) async {
    final replacement = Json.from(input['entry']);
    final er = root.collection('entries').doc(replacement['id']);
    final existing = await t.get(er);
    if (existing.exists) return {'id': replacement['id'], 'repeated': true};
    final originalRef = root.collection('entries').doc(input['original']),
        os = await t.get(originalRef);
    if (!os.exists) throw StateError('Original missing');
    final original = Json.from(plain(os.data()));
    if (replacement['type'] != original['type'] ||
        ledger.types[replacement['type']]['module'] != original['module']) {
      throw StateError('Keep the same entry type');
    }
    final sr = root.collection('modules').doc(original['module']),
        ss = await t.get(sr),
        cs = await t.get(root),
        control = await t.get(root.collection('control').doc('periods'));
    final reversed = ledger.reverse(
      stateFor(ss.data(), cs.data()!, control.data() ?? {}),
      original,
      {
        'id': input['reverseId'],
        'date': replacement['date'],
        'reason': input['reason'],
      },
    );
    final posted = ledger.post(reversed['state'], {
      ...replacement,
      'replaces': original['id'],
    });
    if ((original['orderId'] ?? '') != '') {
      if (replacement['orderId'] != original['orderId'] ||
          replacement['party'] != original['party']) {
        throw StateError('Keep the linked order company');
      }
      final order = (await t.get(
        root.collection('orders').doc(original['orderId']),
      )).data();
      if (order?['status'] != 'received' ||
          order?['billId'] != original['id']) {
        throw StateError('Order bill has changed. Refresh and retry.');
      }
    }
    final entry = metadata(posted['entry']),
        reverseEntry = {
          ...reversalMetadata(reversed['entry'], original),
          'correctionReversal': true,
        };
    final effects = Json.from(entry['effects']);
    for (final item in (reverseEntry['effects'] as Json).entries) {
      effects[item.key] = (effects[item.key] ?? 0) + item.value;
    }
    t.set(
      sr,
      persisted(
        posted['state'],
        entry,
        kind: 'correct',
        original: original['id'],
        reversal: reverseEntry['id'],
      )..['correctionState'] = correctionState(reversed['state']),
    );
    if ((original['orderId'] ?? '') != '') {
      t.update(root.collection('orders').doc(original['orderId']), {
        'status': 'received',
        'billId': entry['id'],
        'billAmount': entry['amount'],
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    t.set(er, entry);
    t.set(root.collection('entries').doc(reverseEntry['id']), reverseEntry);
    t.update(originalRef, {'reversedBy': reverseEntry['id']});
    moneyWrites(t, root, entry, effects);
    return {'id': entry['id']};
  });
  Future<Json> closeDay(DocumentReference<Json> root, Json input) async =>
      db.runTransaction((t) async {
        final ref = root.collection('closures').doc(input['date']);
        final previous = await t.get(ref);
        if (previous.exists) throw StateError('Day already closed');
        final cash = await t.get(root.collection('accounts').doc('cash'));
        final control = root.collection('control').doc('periods');
        await t.get(control);
        final expected = cash.data()?['balance'] ?? 0;
        final close = {
          'date': input['date'],
          'expected': expected,
          'counted': input['counted'],
          'difference': input['counted'] - expected,
          'reason': input['reason'] ?? '',
          'by': uid,
          'at': FieldValue.serverTimestamp(),
        };
        t.set(ref, close);
        t.set(control, {'lockedThrough': input['date']});
        return {'ok': true};
      });
  Future<Json> reconcile(DocumentReference<Json> root) async {
    final workspaceData = await workspace(root);
    if (workspaceData['member']['role'] != 'owner') {
      throw StateError('Owner access required');
    }
    final calculated = <String, int>{};
    for (final entry in workspaceData['entries']) {
      for (final item in (entry['effects'] as Json).entries) {
        calculated[item.key] =
            (calculated[item.key] ?? 0) + (item.value as int);
      }
    }
    final balances = Json.from(workspaceData['state']['balances']),
        differences = <String, dynamic>{};
    for (final key in <String>{...calculated.keys, ...balances.keys}) {
      if ((calculated[key] ?? 0) != (balances[key] ?? 0)) {
        differences[key] = {
          'ledger': calculated[key] ?? 0,
          'cached': balances[key] ?? 0,
        };
      }
    }
    return {
      'balanced': differences.isEmpty,
      'differences': differences,
      'entries': workspaceData['entries'].length,
    };
  }
}
