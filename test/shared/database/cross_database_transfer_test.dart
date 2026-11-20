import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/database/cross_database_transfer.dart';
import 'package:keepass_mobile/shared/database/item_edits.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  test('copia gruppi e voci con allegati, cronologia e icone', () async {
    final source = newTestDatabase();
    final target = newTestDatabase();
    final group = source.createGroup(parent: source.root, name: 'Gruppo');
    final icon = KdbxUuid.random();
    source.meta.customIcons[icon] = KdbxCustomIcon(data: [1, 2]);
    group.customIcon = icon;
    final entry = addTestEntry(source, group, {EntryFields.title: 'Voce'});
    entry.customIcon = icon;
    entry.binaries['file'] = source.binaries.add(
      PlainBinary(data: [3, 4], compressed: false),
    );
    entry.pushHistory();
    final snapshot = snapshotItems(source, [itemIdOf(group)]);
    copySnapshotEdit(snapshot, itemIdOf(target.root))(target);
    final (file, reopened) = await saveToTempFile(target);
    addTearDown(() => file.parent.deleteSync(recursive: true));
    expect(reopened.root.groups, hasLength(2));
    final copied = reopened.root.groups.singleWhere((g) => g.name == 'Gruppo');
    final result = copied.entries.single;
    expect(copied.name, 'Gruppo');
    expect(reopened.meta.customIcons[copied.customIcon]!.data, [1, 2]);
    expect(reopened.meta.customIcons[result.customIcon]!.data, [1, 2]);
    expect(reopened.binaries.getByRef(result.binaries['file']!)!.data, [3, 4]);
    expect(result.history, hasLength(1));
    expect(
      reopened.binaries.getByRef(result.history.single.binaries['file']!)!.data,
      [3, 4],
    );
    expect(snapshot.header.credentials.hasRawKey, isTrue);
  });

  test('rifiuta selezioni sovrapposte', () {
    final source = newTestDatabase();
    final group = source.createGroup(parent: source.root, name: 'Gruppo');
    final entry = addTestEntry(source, group, {EntryFields.title: 'Voce'});
    expect(
      () => snapshotItems(source, [itemIdOf(group), itemIdOf(entry)]),
      throwsA(isA<InvalidItemEditException>()),
    );
  });
}
