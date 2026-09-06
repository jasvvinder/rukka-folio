// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $EnvelopesLocalTable extends EnvelopesLocal
    with TableInfo<$EnvelopesLocalTable, EnvelopesLocalData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EnvelopesLocalTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _envelopeIdMeta = const VerificationMeta(
    'envelopeId',
  );
  @override
  late final GeneratedColumn<String> envelopeId = GeneratedColumn<String>(
    'envelope_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _objectIdMeta = const VerificationMeta(
    'objectId',
  );
  @override
  late final GeneratedColumn<String> objectId = GeneratedColumn<String>(
    'object_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _objectTypeMeta = const VerificationMeta(
    'objectType',
  );
  @override
  late final GeneratedColumn<String> objectType = GeneratedColumn<String>(
    'object_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyVersionMeta = const VerificationMeta(
    'keyVersion',
  );
  @override
  late final GeneratedColumn<int> keyVersion = GeneratedColumn<int>(
    'key_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<int> hlc = GeneratedColumn<int>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _authorDeviceMeta = const VerificationMeta(
    'authorDevice',
  );
  @override
  late final GeneratedColumn<String> authorDevice = GeneratedColumn<String>(
    'author_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorSeqMeta = const VerificationMeta(
    'authorSeq',
  );
  @override
  late final GeneratedColumn<int> authorSeq = GeneratedColumn<int>(
    'author_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _envelopeBlobMeta = const VerificationMeta(
    'envelopeBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> envelopeBlob =
      GeneratedColumn<Uint8List>(
        'blob',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _blobHashMeta = const VerificationMeta(
    'blobHash',
  );
  @override
  late final GeneratedColumn<Uint8List> blobHash = GeneratedColumn<Uint8List>(
    'blob_hash',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _verifiedMeta = const VerificationMeta(
    'verified',
  );
  @override
  late final GeneratedColumn<int> verified = GeneratedColumn<int>(
    'verified',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _quarantinedMeta = const VerificationMeta(
    'quarantined',
  );
  @override
  late final GeneratedColumn<int> quarantined = GeneratedColumn<int>(
    'quarantined',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _quarantineReasonMeta = const VerificationMeta(
    'quarantineReason',
  );
  @override
  late final GeneratedColumn<String> quarantineReason = GeneratedColumn<String>(
    'quarantine_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heldMeta = const VerificationMeta('held');
  @override
  late final GeneratedColumn<int> held = GeneratedColumn<int>(
    'held',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _heldForMeta = const VerificationMeta(
    'heldFor',
  );
  @override
  late final GeneratedColumn<String> heldFor = GeneratedColumn<String>(
    'held_for',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    envelopeId,
    bookId,
    objectId,
    objectType,
    keyVersion,
    hlc,
    seq,
    authorDevice,
    authorSeq,
    envelopeBlob,
    blobHash,
    verified,
    quarantined,
    quarantineReason,
    held,
    heldFor,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'envelopes_local';
  @override
  VerificationContext validateIntegrity(
    Insertable<EnvelopesLocalData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('envelope_id')) {
      context.handle(
        _envelopeIdMeta,
        envelopeId.isAcceptableOrUnknown(data['envelope_id']!, _envelopeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_envelopeIdMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('object_id')) {
      context.handle(
        _objectIdMeta,
        objectId.isAcceptableOrUnknown(data['object_id']!, _objectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_objectIdMeta);
    }
    if (data.containsKey('object_type')) {
      context.handle(
        _objectTypeMeta,
        objectType.isAcceptableOrUnknown(data['object_type']!, _objectTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_objectTypeMeta);
    }
    if (data.containsKey('key_version')) {
      context.handle(
        _keyVersionMeta,
        keyVersion.isAcceptableOrUnknown(data['key_version']!, _keyVersionMeta),
      );
    } else if (isInserting) {
      context.missing(_keyVersionMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    }
    if (data.containsKey('author_device')) {
      context.handle(
        _authorDeviceMeta,
        authorDevice.isAcceptableOrUnknown(
          data['author_device']!,
          _authorDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authorDeviceMeta);
    }
    if (data.containsKey('author_seq')) {
      context.handle(
        _authorSeqMeta,
        authorSeq.isAcceptableOrUnknown(data['author_seq']!, _authorSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_authorSeqMeta);
    }
    if (data.containsKey('blob')) {
      context.handle(
        _envelopeBlobMeta,
        envelopeBlob.isAcceptableOrUnknown(data['blob']!, _envelopeBlobMeta),
      );
    } else if (isInserting) {
      context.missing(_envelopeBlobMeta);
    }
    if (data.containsKey('blob_hash')) {
      context.handle(
        _blobHashMeta,
        blobHash.isAcceptableOrUnknown(data['blob_hash']!, _blobHashMeta),
      );
    } else if (isInserting) {
      context.missing(_blobHashMeta);
    }
    if (data.containsKey('verified')) {
      context.handle(
        _verifiedMeta,
        verified.isAcceptableOrUnknown(data['verified']!, _verifiedMeta),
      );
    }
    if (data.containsKey('quarantined')) {
      context.handle(
        _quarantinedMeta,
        quarantined.isAcceptableOrUnknown(
          data['quarantined']!,
          _quarantinedMeta,
        ),
      );
    }
    if (data.containsKey('quarantine_reason')) {
      context.handle(
        _quarantineReasonMeta,
        quarantineReason.isAcceptableOrUnknown(
          data['quarantine_reason']!,
          _quarantineReasonMeta,
        ),
      );
    }
    if (data.containsKey('held')) {
      context.handle(
        _heldMeta,
        held.isAcceptableOrUnknown(data['held']!, _heldMeta),
      );
    }
    if (data.containsKey('held_for')) {
      context.handle(
        _heldForMeta,
        heldFor.isAcceptableOrUnknown(data['held_for']!, _heldForMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {envelopeId};
  @override
  EnvelopesLocalData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EnvelopesLocalData(
      envelopeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}envelope_id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      objectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}object_id'],
      )!,
      objectType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}object_type'],
      )!,
      keyVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}key_version'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hlc'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      ),
      authorDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_device'],
      )!,
      authorSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}author_seq'],
      )!,
      envelopeBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}blob'],
      )!,
      blobHash: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}blob_hash'],
      )!,
      verified: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}verified'],
      )!,
      quarantined: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quarantined'],
      )!,
      quarantineReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quarantine_reason'],
      ),
      held: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}held'],
      )!,
      heldFor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}held_for'],
      ),
    );
  }

  @override
  $EnvelopesLocalTable createAlias(String alias) {
    return $EnvelopesLocalTable(attachedDatabase, alias);
  }
}

class EnvelopesLocalData extends DataClass
    implements Insertable<EnvelopesLocalData> {
  /// Envelope id (client-minted UUIDv7, 03 §1).
  final String envelopeId;

  /// Book.
  final String bookId;

  /// Object the envelope carries a version of.
  final String objectId;

  /// `object_type` registry value (03 §2.3).
  final String objectType;

  /// Book-key version the blob is sealed under.
  final int keyVersion;

  /// Ordering authority (03 §1).
  final int hlc;

  /// Server sequence; null until acknowledged. Revocation cut-off (ADR 05b §5).
  final int? seq;

  /// Authoring device.
  final String authorDevice;

  /// Per-author sequence, copied from inside the ciphertext (ADR 05b §3).
  final int authorSeq;

  /// Opaque ciphertext (SQL column `blob`).
  final Uint8List envelopeBlob;

  /// Hash of [blob], verified on read (ADR 05c §2, §6).
  final Uint8List blobHash;

  /// 1 after the signature-chain check.
  final int verified;

  /// 1 when a reader refused it (security event).
  final int quarantined;

  /// Why it was quarantined.
  final String? quarantineReason;

  /// 1 while a dangling reference waits for its target (ADR 05b §4).
  final int held;

  /// The missing target's id.
  final String? heldFor;
  const EnvelopesLocalData({
    required this.envelopeId,
    required this.bookId,
    required this.objectId,
    required this.objectType,
    required this.keyVersion,
    required this.hlc,
    this.seq,
    required this.authorDevice,
    required this.authorSeq,
    required this.envelopeBlob,
    required this.blobHash,
    required this.verified,
    required this.quarantined,
    this.quarantineReason,
    required this.held,
    this.heldFor,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['envelope_id'] = Variable<String>(envelopeId);
    map['book_id'] = Variable<String>(bookId);
    map['object_id'] = Variable<String>(objectId);
    map['object_type'] = Variable<String>(objectType);
    map['key_version'] = Variable<int>(keyVersion);
    map['hlc'] = Variable<int>(hlc);
    if (!nullToAbsent || seq != null) {
      map['seq'] = Variable<int>(seq);
    }
    map['author_device'] = Variable<String>(authorDevice);
    map['author_seq'] = Variable<int>(authorSeq);
    map['blob'] = Variable<Uint8List>(envelopeBlob);
    map['blob_hash'] = Variable<Uint8List>(blobHash);
    map['verified'] = Variable<int>(verified);
    map['quarantined'] = Variable<int>(quarantined);
    if (!nullToAbsent || quarantineReason != null) {
      map['quarantine_reason'] = Variable<String>(quarantineReason);
    }
    map['held'] = Variable<int>(held);
    if (!nullToAbsent || heldFor != null) {
      map['held_for'] = Variable<String>(heldFor);
    }
    return map;
  }

  EnvelopesLocalCompanion toCompanion(bool nullToAbsent) {
    return EnvelopesLocalCompanion(
      envelopeId: Value(envelopeId),
      bookId: Value(bookId),
      objectId: Value(objectId),
      objectType: Value(objectType),
      keyVersion: Value(keyVersion),
      hlc: Value(hlc),
      seq: seq == null && nullToAbsent ? const Value.absent() : Value(seq),
      authorDevice: Value(authorDevice),
      authorSeq: Value(authorSeq),
      envelopeBlob: Value(envelopeBlob),
      blobHash: Value(blobHash),
      verified: Value(verified),
      quarantined: Value(quarantined),
      quarantineReason: quarantineReason == null && nullToAbsent
          ? const Value.absent()
          : Value(quarantineReason),
      held: Value(held),
      heldFor: heldFor == null && nullToAbsent
          ? const Value.absent()
          : Value(heldFor),
    );
  }

  factory EnvelopesLocalData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EnvelopesLocalData(
      envelopeId: serializer.fromJson<String>(json['envelopeId']),
      bookId: serializer.fromJson<String>(json['bookId']),
      objectId: serializer.fromJson<String>(json['objectId']),
      objectType: serializer.fromJson<String>(json['objectType']),
      keyVersion: serializer.fromJson<int>(json['keyVersion']),
      hlc: serializer.fromJson<int>(json['hlc']),
      seq: serializer.fromJson<int?>(json['seq']),
      authorDevice: serializer.fromJson<String>(json['authorDevice']),
      authorSeq: serializer.fromJson<int>(json['authorSeq']),
      envelopeBlob: serializer.fromJson<Uint8List>(json['envelopeBlob']),
      blobHash: serializer.fromJson<Uint8List>(json['blobHash']),
      verified: serializer.fromJson<int>(json['verified']),
      quarantined: serializer.fromJson<int>(json['quarantined']),
      quarantineReason: serializer.fromJson<String?>(json['quarantineReason']),
      held: serializer.fromJson<int>(json['held']),
      heldFor: serializer.fromJson<String?>(json['heldFor']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'envelopeId': serializer.toJson<String>(envelopeId),
      'bookId': serializer.toJson<String>(bookId),
      'objectId': serializer.toJson<String>(objectId),
      'objectType': serializer.toJson<String>(objectType),
      'keyVersion': serializer.toJson<int>(keyVersion),
      'hlc': serializer.toJson<int>(hlc),
      'seq': serializer.toJson<int?>(seq),
      'authorDevice': serializer.toJson<String>(authorDevice),
      'authorSeq': serializer.toJson<int>(authorSeq),
      'envelopeBlob': serializer.toJson<Uint8List>(envelopeBlob),
      'blobHash': serializer.toJson<Uint8List>(blobHash),
      'verified': serializer.toJson<int>(verified),
      'quarantined': serializer.toJson<int>(quarantined),
      'quarantineReason': serializer.toJson<String?>(quarantineReason),
      'held': serializer.toJson<int>(held),
      'heldFor': serializer.toJson<String?>(heldFor),
    };
  }

  EnvelopesLocalData copyWith({
    String? envelopeId,
    String? bookId,
    String? objectId,
    String? objectType,
    int? keyVersion,
    int? hlc,
    Value<int?> seq = const Value.absent(),
    String? authorDevice,
    int? authorSeq,
    Uint8List? envelopeBlob,
    Uint8List? blobHash,
    int? verified,
    int? quarantined,
    Value<String?> quarantineReason = const Value.absent(),
    int? held,
    Value<String?> heldFor = const Value.absent(),
  }) => EnvelopesLocalData(
    envelopeId: envelopeId ?? this.envelopeId,
    bookId: bookId ?? this.bookId,
    objectId: objectId ?? this.objectId,
    objectType: objectType ?? this.objectType,
    keyVersion: keyVersion ?? this.keyVersion,
    hlc: hlc ?? this.hlc,
    seq: seq.present ? seq.value : this.seq,
    authorDevice: authorDevice ?? this.authorDevice,
    authorSeq: authorSeq ?? this.authorSeq,
    envelopeBlob: envelopeBlob ?? this.envelopeBlob,
    blobHash: blobHash ?? this.blobHash,
    verified: verified ?? this.verified,
    quarantined: quarantined ?? this.quarantined,
    quarantineReason: quarantineReason.present
        ? quarantineReason.value
        : this.quarantineReason,
    held: held ?? this.held,
    heldFor: heldFor.present ? heldFor.value : this.heldFor,
  );
  EnvelopesLocalData copyWithCompanion(EnvelopesLocalCompanion data) {
    return EnvelopesLocalData(
      envelopeId: data.envelopeId.present
          ? data.envelopeId.value
          : this.envelopeId,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      objectId: data.objectId.present ? data.objectId.value : this.objectId,
      objectType: data.objectType.present
          ? data.objectType.value
          : this.objectType,
      keyVersion: data.keyVersion.present
          ? data.keyVersion.value
          : this.keyVersion,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      seq: data.seq.present ? data.seq.value : this.seq,
      authorDevice: data.authorDevice.present
          ? data.authorDevice.value
          : this.authorDevice,
      authorSeq: data.authorSeq.present ? data.authorSeq.value : this.authorSeq,
      envelopeBlob: data.envelopeBlob.present
          ? data.envelopeBlob.value
          : this.envelopeBlob,
      blobHash: data.blobHash.present ? data.blobHash.value : this.blobHash,
      verified: data.verified.present ? data.verified.value : this.verified,
      quarantined: data.quarantined.present
          ? data.quarantined.value
          : this.quarantined,
      quarantineReason: data.quarantineReason.present
          ? data.quarantineReason.value
          : this.quarantineReason,
      held: data.held.present ? data.held.value : this.held,
      heldFor: data.heldFor.present ? data.heldFor.value : this.heldFor,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EnvelopesLocalData(')
          ..write('envelopeId: $envelopeId, ')
          ..write('bookId: $bookId, ')
          ..write('objectId: $objectId, ')
          ..write('objectType: $objectType, ')
          ..write('keyVersion: $keyVersion, ')
          ..write('hlc: $hlc, ')
          ..write('seq: $seq, ')
          ..write('authorDevice: $authorDevice, ')
          ..write('authorSeq: $authorSeq, ')
          ..write('envelopeBlob: $envelopeBlob, ')
          ..write('blobHash: $blobHash, ')
          ..write('verified: $verified, ')
          ..write('quarantined: $quarantined, ')
          ..write('quarantineReason: $quarantineReason, ')
          ..write('held: $held, ')
          ..write('heldFor: $heldFor')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    envelopeId,
    bookId,
    objectId,
    objectType,
    keyVersion,
    hlc,
    seq,
    authorDevice,
    authorSeq,
    $driftBlobEquality.hash(envelopeBlob),
    $driftBlobEquality.hash(blobHash),
    verified,
    quarantined,
    quarantineReason,
    held,
    heldFor,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EnvelopesLocalData &&
          other.envelopeId == this.envelopeId &&
          other.bookId == this.bookId &&
          other.objectId == this.objectId &&
          other.objectType == this.objectType &&
          other.keyVersion == this.keyVersion &&
          other.hlc == this.hlc &&
          other.seq == this.seq &&
          other.authorDevice == this.authorDevice &&
          other.authorSeq == this.authorSeq &&
          $driftBlobEquality.equals(other.envelopeBlob, this.envelopeBlob) &&
          $driftBlobEquality.equals(other.blobHash, this.blobHash) &&
          other.verified == this.verified &&
          other.quarantined == this.quarantined &&
          other.quarantineReason == this.quarantineReason &&
          other.held == this.held &&
          other.heldFor == this.heldFor);
}

class EnvelopesLocalCompanion extends UpdateCompanion<EnvelopesLocalData> {
  final Value<String> envelopeId;
  final Value<String> bookId;
  final Value<String> objectId;
  final Value<String> objectType;
  final Value<int> keyVersion;
  final Value<int> hlc;
  final Value<int?> seq;
  final Value<String> authorDevice;
  final Value<int> authorSeq;
  final Value<Uint8List> envelopeBlob;
  final Value<Uint8List> blobHash;
  final Value<int> verified;
  final Value<int> quarantined;
  final Value<String?> quarantineReason;
  final Value<int> held;
  final Value<String?> heldFor;
  final Value<int> rowid;
  const EnvelopesLocalCompanion({
    this.envelopeId = const Value.absent(),
    this.bookId = const Value.absent(),
    this.objectId = const Value.absent(),
    this.objectType = const Value.absent(),
    this.keyVersion = const Value.absent(),
    this.hlc = const Value.absent(),
    this.seq = const Value.absent(),
    this.authorDevice = const Value.absent(),
    this.authorSeq = const Value.absent(),
    this.envelopeBlob = const Value.absent(),
    this.blobHash = const Value.absent(),
    this.verified = const Value.absent(),
    this.quarantined = const Value.absent(),
    this.quarantineReason = const Value.absent(),
    this.held = const Value.absent(),
    this.heldFor = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EnvelopesLocalCompanion.insert({
    required String envelopeId,
    required String bookId,
    required String objectId,
    required String objectType,
    required int keyVersion,
    required int hlc,
    this.seq = const Value.absent(),
    required String authorDevice,
    required int authorSeq,
    required Uint8List envelopeBlob,
    required Uint8List blobHash,
    this.verified = const Value.absent(),
    this.quarantined = const Value.absent(),
    this.quarantineReason = const Value.absent(),
    this.held = const Value.absent(),
    this.heldFor = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : envelopeId = Value(envelopeId),
       bookId = Value(bookId),
       objectId = Value(objectId),
       objectType = Value(objectType),
       keyVersion = Value(keyVersion),
       hlc = Value(hlc),
       authorDevice = Value(authorDevice),
       authorSeq = Value(authorSeq),
       envelopeBlob = Value(envelopeBlob),
       blobHash = Value(blobHash);
  static Insertable<EnvelopesLocalData> custom({
    Expression<String>? envelopeId,
    Expression<String>? bookId,
    Expression<String>? objectId,
    Expression<String>? objectType,
    Expression<int>? keyVersion,
    Expression<int>? hlc,
    Expression<int>? seq,
    Expression<String>? authorDevice,
    Expression<int>? authorSeq,
    Expression<Uint8List>? envelopeBlob,
    Expression<Uint8List>? blobHash,
    Expression<int>? verified,
    Expression<int>? quarantined,
    Expression<String>? quarantineReason,
    Expression<int>? held,
    Expression<String>? heldFor,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (envelopeId != null) 'envelope_id': envelopeId,
      if (bookId != null) 'book_id': bookId,
      if (objectId != null) 'object_id': objectId,
      if (objectType != null) 'object_type': objectType,
      if (keyVersion != null) 'key_version': keyVersion,
      if (hlc != null) 'hlc': hlc,
      if (seq != null) 'seq': seq,
      if (authorDevice != null) 'author_device': authorDevice,
      if (authorSeq != null) 'author_seq': authorSeq,
      if (envelopeBlob != null) 'blob': envelopeBlob,
      if (blobHash != null) 'blob_hash': blobHash,
      if (verified != null) 'verified': verified,
      if (quarantined != null) 'quarantined': quarantined,
      if (quarantineReason != null) 'quarantine_reason': quarantineReason,
      if (held != null) 'held': held,
      if (heldFor != null) 'held_for': heldFor,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EnvelopesLocalCompanion copyWith({
    Value<String>? envelopeId,
    Value<String>? bookId,
    Value<String>? objectId,
    Value<String>? objectType,
    Value<int>? keyVersion,
    Value<int>? hlc,
    Value<int?>? seq,
    Value<String>? authorDevice,
    Value<int>? authorSeq,
    Value<Uint8List>? envelopeBlob,
    Value<Uint8List>? blobHash,
    Value<int>? verified,
    Value<int>? quarantined,
    Value<String?>? quarantineReason,
    Value<int>? held,
    Value<String?>? heldFor,
    Value<int>? rowid,
  }) {
    return EnvelopesLocalCompanion(
      envelopeId: envelopeId ?? this.envelopeId,
      bookId: bookId ?? this.bookId,
      objectId: objectId ?? this.objectId,
      objectType: objectType ?? this.objectType,
      keyVersion: keyVersion ?? this.keyVersion,
      hlc: hlc ?? this.hlc,
      seq: seq ?? this.seq,
      authorDevice: authorDevice ?? this.authorDevice,
      authorSeq: authorSeq ?? this.authorSeq,
      envelopeBlob: envelopeBlob ?? this.envelopeBlob,
      blobHash: blobHash ?? this.blobHash,
      verified: verified ?? this.verified,
      quarantined: quarantined ?? this.quarantined,
      quarantineReason: quarantineReason ?? this.quarantineReason,
      held: held ?? this.held,
      heldFor: heldFor ?? this.heldFor,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (envelopeId.present) {
      map['envelope_id'] = Variable<String>(envelopeId.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (objectId.present) {
      map['object_id'] = Variable<String>(objectId.value);
    }
    if (objectType.present) {
      map['object_type'] = Variable<String>(objectType.value);
    }
    if (keyVersion.present) {
      map['key_version'] = Variable<int>(keyVersion.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<int>(hlc.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (authorDevice.present) {
      map['author_device'] = Variable<String>(authorDevice.value);
    }
    if (authorSeq.present) {
      map['author_seq'] = Variable<int>(authorSeq.value);
    }
    if (envelopeBlob.present) {
      map['blob'] = Variable<Uint8List>(envelopeBlob.value);
    }
    if (blobHash.present) {
      map['blob_hash'] = Variable<Uint8List>(blobHash.value);
    }
    if (verified.present) {
      map['verified'] = Variable<int>(verified.value);
    }
    if (quarantined.present) {
      map['quarantined'] = Variable<int>(quarantined.value);
    }
    if (quarantineReason.present) {
      map['quarantine_reason'] = Variable<String>(quarantineReason.value);
    }
    if (held.present) {
      map['held'] = Variable<int>(held.value);
    }
    if (heldFor.present) {
      map['held_for'] = Variable<String>(heldFor.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EnvelopesLocalCompanion(')
          ..write('envelopeId: $envelopeId, ')
          ..write('bookId: $bookId, ')
          ..write('objectId: $objectId, ')
          ..write('objectType: $objectType, ')
          ..write('keyVersion: $keyVersion, ')
          ..write('hlc: $hlc, ')
          ..write('seq: $seq, ')
          ..write('authorDevice: $authorDevice, ')
          ..write('authorSeq: $authorSeq, ')
          ..write('envelopeBlob: $envelopeBlob, ')
          ..write('blobHash: $blobHash, ')
          ..write('verified: $verified, ')
          ..write('quarantined: $quarantined, ')
          ..write('quarantineReason: $quarantineReason, ')
          ..write('held: $held, ')
          ..write('heldFor: $heldFor, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _envelopeIdMeta = const VerificationMeta(
    'envelopeId',
  );
  @override
  late final GeneratedColumn<String> envelopeId = GeneratedColumn<String>(
    'envelope_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _envelopeBlobMeta = const VerificationMeta(
    'envelopeBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> envelopeBlob =
      GeneratedColumn<Uint8List>(
        'blob',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pushStateMeta = const VerificationMeta(
    'pushState',
  );
  @override
  late final GeneratedColumn<String> pushState = GeneratedColumn<String>(
    'push_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (push_state IN (\'queued\',\'inflight\',\'acked\',\'observed\',\'rejected\'))',
  );
  static const VerificationMeta _ackedSeqMeta = const VerificationMeta(
    'ackedSeq',
  );
  @override
  late final GeneratedColumn<int> ackedSeq = GeneratedColumn<int>(
    'acked_seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rejectReasonMeta = const VerificationMeta(
    'rejectReason',
  );
  @override
  late final GeneratedColumn<String> rejectReason = GeneratedColumn<String>(
    'reject_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    envelopeId,
    bookId,
    envelopeBlob,
    createdAt,
    pushState,
    ackedSeq,
    rejectReason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('envelope_id')) {
      context.handle(
        _envelopeIdMeta,
        envelopeId.isAcceptableOrUnknown(data['envelope_id']!, _envelopeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_envelopeIdMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('blob')) {
      context.handle(
        _envelopeBlobMeta,
        envelopeBlob.isAcceptableOrUnknown(data['blob']!, _envelopeBlobMeta),
      );
    } else if (isInserting) {
      context.missing(_envelopeBlobMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('push_state')) {
      context.handle(
        _pushStateMeta,
        pushState.isAcceptableOrUnknown(data['push_state']!, _pushStateMeta),
      );
    } else if (isInserting) {
      context.missing(_pushStateMeta);
    }
    if (data.containsKey('acked_seq')) {
      context.handle(
        _ackedSeqMeta,
        ackedSeq.isAcceptableOrUnknown(data['acked_seq']!, _ackedSeqMeta),
      );
    }
    if (data.containsKey('reject_reason')) {
      context.handle(
        _rejectReasonMeta,
        rejectReason.isAcceptableOrUnknown(
          data['reject_reason']!,
          _rejectReasonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {envelopeId};
  @override
  OutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxData(
      envelopeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}envelope_id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      envelopeBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}blob'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      pushState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}push_state'],
      )!,
      ackedSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}acked_seq'],
      ),
      rejectReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reject_reason'],
      ),
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class OutboxData extends DataClass implements Insertable<OutboxData> {
  /// Envelope id.
  final String envelopeId;

  /// Book.
  final String bookId;

  /// The sealed envelope as pushed (SQL column `blob`).
  final Uint8List envelopeBlob;

  /// Injected creation time (ms); never read from a clock inside this package.
  final int createdAt;

  /// queued → inflight → acked → observed; any state → rejected.
  final String pushState;

  /// Server seq returned on ack.
  final int? ackedSeq;

  /// Server's reason on rejection.
  final String? rejectReason;
  const OutboxData({
    required this.envelopeId,
    required this.bookId,
    required this.envelopeBlob,
    required this.createdAt,
    required this.pushState,
    this.ackedSeq,
    this.rejectReason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['envelope_id'] = Variable<String>(envelopeId);
    map['book_id'] = Variable<String>(bookId);
    map['blob'] = Variable<Uint8List>(envelopeBlob);
    map['created_at'] = Variable<int>(createdAt);
    map['push_state'] = Variable<String>(pushState);
    if (!nullToAbsent || ackedSeq != null) {
      map['acked_seq'] = Variable<int>(ackedSeq);
    }
    if (!nullToAbsent || rejectReason != null) {
      map['reject_reason'] = Variable<String>(rejectReason);
    }
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      envelopeId: Value(envelopeId),
      bookId: Value(bookId),
      envelopeBlob: Value(envelopeBlob),
      createdAt: Value(createdAt),
      pushState: Value(pushState),
      ackedSeq: ackedSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(ackedSeq),
      rejectReason: rejectReason == null && nullToAbsent
          ? const Value.absent()
          : Value(rejectReason),
    );
  }

  factory OutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxData(
      envelopeId: serializer.fromJson<String>(json['envelopeId']),
      bookId: serializer.fromJson<String>(json['bookId']),
      envelopeBlob: serializer.fromJson<Uint8List>(json['envelopeBlob']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      pushState: serializer.fromJson<String>(json['pushState']),
      ackedSeq: serializer.fromJson<int?>(json['ackedSeq']),
      rejectReason: serializer.fromJson<String?>(json['rejectReason']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'envelopeId': serializer.toJson<String>(envelopeId),
      'bookId': serializer.toJson<String>(bookId),
      'envelopeBlob': serializer.toJson<Uint8List>(envelopeBlob),
      'createdAt': serializer.toJson<int>(createdAt),
      'pushState': serializer.toJson<String>(pushState),
      'ackedSeq': serializer.toJson<int?>(ackedSeq),
      'rejectReason': serializer.toJson<String?>(rejectReason),
    };
  }

  OutboxData copyWith({
    String? envelopeId,
    String? bookId,
    Uint8List? envelopeBlob,
    int? createdAt,
    String? pushState,
    Value<int?> ackedSeq = const Value.absent(),
    Value<String?> rejectReason = const Value.absent(),
  }) => OutboxData(
    envelopeId: envelopeId ?? this.envelopeId,
    bookId: bookId ?? this.bookId,
    envelopeBlob: envelopeBlob ?? this.envelopeBlob,
    createdAt: createdAt ?? this.createdAt,
    pushState: pushState ?? this.pushState,
    ackedSeq: ackedSeq.present ? ackedSeq.value : this.ackedSeq,
    rejectReason: rejectReason.present ? rejectReason.value : this.rejectReason,
  );
  OutboxData copyWithCompanion(OutboxCompanion data) {
    return OutboxData(
      envelopeId: data.envelopeId.present
          ? data.envelopeId.value
          : this.envelopeId,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      envelopeBlob: data.envelopeBlob.present
          ? data.envelopeBlob.value
          : this.envelopeBlob,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      pushState: data.pushState.present ? data.pushState.value : this.pushState,
      ackedSeq: data.ackedSeq.present ? data.ackedSeq.value : this.ackedSeq,
      rejectReason: data.rejectReason.present
          ? data.rejectReason.value
          : this.rejectReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxData(')
          ..write('envelopeId: $envelopeId, ')
          ..write('bookId: $bookId, ')
          ..write('envelopeBlob: $envelopeBlob, ')
          ..write('createdAt: $createdAt, ')
          ..write('pushState: $pushState, ')
          ..write('ackedSeq: $ackedSeq, ')
          ..write('rejectReason: $rejectReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    envelopeId,
    bookId,
    $driftBlobEquality.hash(envelopeBlob),
    createdAt,
    pushState,
    ackedSeq,
    rejectReason,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxData &&
          other.envelopeId == this.envelopeId &&
          other.bookId == this.bookId &&
          $driftBlobEquality.equals(other.envelopeBlob, this.envelopeBlob) &&
          other.createdAt == this.createdAt &&
          other.pushState == this.pushState &&
          other.ackedSeq == this.ackedSeq &&
          other.rejectReason == this.rejectReason);
}

class OutboxCompanion extends UpdateCompanion<OutboxData> {
  final Value<String> envelopeId;
  final Value<String> bookId;
  final Value<Uint8List> envelopeBlob;
  final Value<int> createdAt;
  final Value<String> pushState;
  final Value<int?> ackedSeq;
  final Value<String?> rejectReason;
  final Value<int> rowid;
  const OutboxCompanion({
    this.envelopeId = const Value.absent(),
    this.bookId = const Value.absent(),
    this.envelopeBlob = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.pushState = const Value.absent(),
    this.ackedSeq = const Value.absent(),
    this.rejectReason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxCompanion.insert({
    required String envelopeId,
    required String bookId,
    required Uint8List envelopeBlob,
    required int createdAt,
    required String pushState,
    this.ackedSeq = const Value.absent(),
    this.rejectReason = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : envelopeId = Value(envelopeId),
       bookId = Value(bookId),
       envelopeBlob = Value(envelopeBlob),
       createdAt = Value(createdAt),
       pushState = Value(pushState);
  static Insertable<OutboxData> custom({
    Expression<String>? envelopeId,
    Expression<String>? bookId,
    Expression<Uint8List>? envelopeBlob,
    Expression<int>? createdAt,
    Expression<String>? pushState,
    Expression<int>? ackedSeq,
    Expression<String>? rejectReason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (envelopeId != null) 'envelope_id': envelopeId,
      if (bookId != null) 'book_id': bookId,
      if (envelopeBlob != null) 'blob': envelopeBlob,
      if (createdAt != null) 'created_at': createdAt,
      if (pushState != null) 'push_state': pushState,
      if (ackedSeq != null) 'acked_seq': ackedSeq,
      if (rejectReason != null) 'reject_reason': rejectReason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxCompanion copyWith({
    Value<String>? envelopeId,
    Value<String>? bookId,
    Value<Uint8List>? envelopeBlob,
    Value<int>? createdAt,
    Value<String>? pushState,
    Value<int?>? ackedSeq,
    Value<String?>? rejectReason,
    Value<int>? rowid,
  }) {
    return OutboxCompanion(
      envelopeId: envelopeId ?? this.envelopeId,
      bookId: bookId ?? this.bookId,
      envelopeBlob: envelopeBlob ?? this.envelopeBlob,
      createdAt: createdAt ?? this.createdAt,
      pushState: pushState ?? this.pushState,
      ackedSeq: ackedSeq ?? this.ackedSeq,
      rejectReason: rejectReason ?? this.rejectReason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (envelopeId.present) {
      map['envelope_id'] = Variable<String>(envelopeId.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (envelopeBlob.present) {
      map['blob'] = Variable<Uint8List>(envelopeBlob.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (pushState.present) {
      map['push_state'] = Variable<String>(pushState.value);
    }
    if (ackedSeq.present) {
      map['acked_seq'] = Variable<int>(ackedSeq.value);
    }
    if (rejectReason.present) {
      map['reject_reason'] = Variable<String>(rejectReason.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('envelopeId: $envelopeId, ')
          ..write('bookId: $bookId, ')
          ..write('envelopeBlob: $envelopeBlob, ')
          ..write('createdAt: $createdAt, ')
          ..write('pushState: $pushState, ')
          ..write('ackedSeq: $ackedSeq, ')
          ..write('rejectReason: $rejectReason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AuthorSeqLocalTable extends AuthorSeqLocal
    with TableInfo<$AuthorSeqLocalTable, AuthorSeqLocalData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuthorSeqLocalTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nextSeqMeta = const VerificationMeta(
    'nextSeq',
  );
  @override
  late final GeneratedColumn<int> nextSeq = GeneratedColumn<int>(
    'next_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [bookId, deviceId, nextSeq];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'author_seq_local';
  @override
  VerificationContext validateIntegrity(
    Insertable<AuthorSeqLocalData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('next_seq')) {
      context.handle(
        _nextSeqMeta,
        nextSeq.isAcceptableOrUnknown(data['next_seq']!, _nextSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_nextSeqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId, deviceId};
  @override
  AuthorSeqLocalData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuthorSeqLocalData(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      nextSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_seq'],
      )!,
    );
  }

  @override
  $AuthorSeqLocalTable createAlias(String alias) {
    return $AuthorSeqLocalTable(attachedDatabase, alias);
  }
}

class AuthorSeqLocalData extends DataClass
    implements Insertable<AuthorSeqLocalData> {
  /// Book.
  final String bookId;

  /// This device.
  final String deviceId;

  /// The next sequence number to hand out.
  final int nextSeq;
  const AuthorSeqLocalData({
    required this.bookId,
    required this.deviceId,
    required this.nextSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['device_id'] = Variable<String>(deviceId);
    map['next_seq'] = Variable<int>(nextSeq);
    return map;
  }

  AuthorSeqLocalCompanion toCompanion(bool nullToAbsent) {
    return AuthorSeqLocalCompanion(
      bookId: Value(bookId),
      deviceId: Value(deviceId),
      nextSeq: Value(nextSeq),
    );
  }

  factory AuthorSeqLocalData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuthorSeqLocalData(
      bookId: serializer.fromJson<String>(json['bookId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      nextSeq: serializer.fromJson<int>(json['nextSeq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'deviceId': serializer.toJson<String>(deviceId),
      'nextSeq': serializer.toJson<int>(nextSeq),
    };
  }

  AuthorSeqLocalData copyWith({
    String? bookId,
    String? deviceId,
    int? nextSeq,
  }) => AuthorSeqLocalData(
    bookId: bookId ?? this.bookId,
    deviceId: deviceId ?? this.deviceId,
    nextSeq: nextSeq ?? this.nextSeq,
  );
  AuthorSeqLocalData copyWithCompanion(AuthorSeqLocalCompanion data) {
    return AuthorSeqLocalData(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      nextSeq: data.nextSeq.present ? data.nextSeq.value : this.nextSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuthorSeqLocalData(')
          ..write('bookId: $bookId, ')
          ..write('deviceId: $deviceId, ')
          ..write('nextSeq: $nextSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bookId, deviceId, nextSeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthorSeqLocalData &&
          other.bookId == this.bookId &&
          other.deviceId == this.deviceId &&
          other.nextSeq == this.nextSeq);
}

class AuthorSeqLocalCompanion extends UpdateCompanion<AuthorSeqLocalData> {
  final Value<String> bookId;
  final Value<String> deviceId;
  final Value<int> nextSeq;
  final Value<int> rowid;
  const AuthorSeqLocalCompanion({
    this.bookId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.nextSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AuthorSeqLocalCompanion.insert({
    required String bookId,
    required String deviceId,
    required int nextSeq,
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       deviceId = Value(deviceId),
       nextSeq = Value(nextSeq);
  static Insertable<AuthorSeqLocalData> custom({
    Expression<String>? bookId,
    Expression<String>? deviceId,
    Expression<int>? nextSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (deviceId != null) 'device_id': deviceId,
      if (nextSeq != null) 'next_seq': nextSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AuthorSeqLocalCompanion copyWith({
    Value<String>? bookId,
    Value<String>? deviceId,
    Value<int>? nextSeq,
    Value<int>? rowid,
  }) {
    return AuthorSeqLocalCompanion(
      bookId: bookId ?? this.bookId,
      deviceId: deviceId ?? this.deviceId,
      nextSeq: nextSeq ?? this.nextSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (nextSeq.present) {
      map['next_seq'] = Variable<int>(nextSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuthorSeqLocalCompanion(')
          ..write('bookId: $bookId, ')
          ..write('deviceId: $deviceId, ')
          ..write('nextSeq: $nextSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AuthorGapsTable extends AuthorGaps
    with TableInfo<$AuthorGapsTable, AuthorGap> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuthorGapsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorDeviceMeta = const VerificationMeta(
    'authorDevice',
  );
  @override
  late final GeneratedColumn<String> authorDevice = GeneratedColumn<String>(
    'author_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expectedSeqMeta = const VerificationMeta(
    'expectedSeq',
  );
  @override
  late final GeneratedColumn<int> expectedSeq = GeneratedColumn<int>(
    'expected_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sinceHlcMeta = const VerificationMeta(
    'sinceHlc',
  );
  @override
  late final GeneratedColumn<int> sinceHlc = GeneratedColumn<int>(
    'since_hlc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookId,
    authorDevice,
    expectedSeq,
    sinceHlc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'author_gaps';
  @override
  VerificationContext validateIntegrity(
    Insertable<AuthorGap> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('author_device')) {
      context.handle(
        _authorDeviceMeta,
        authorDevice.isAcceptableOrUnknown(
          data['author_device']!,
          _authorDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authorDeviceMeta);
    }
    if (data.containsKey('expected_seq')) {
      context.handle(
        _expectedSeqMeta,
        expectedSeq.isAcceptableOrUnknown(
          data['expected_seq']!,
          _expectedSeqMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expectedSeqMeta);
    }
    if (data.containsKey('since_hlc')) {
      context.handle(
        _sinceHlcMeta,
        sinceHlc.isAcceptableOrUnknown(data['since_hlc']!, _sinceHlcMeta),
      );
    } else if (isInserting) {
      context.missing(_sinceHlcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId, authorDevice, expectedSeq};
  @override
  AuthorGap map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuthorGap(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      authorDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_device'],
      )!,
      expectedSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_seq'],
      )!,
      sinceHlc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}since_hlc'],
      )!,
    );
  }

  @override
  $AuthorGapsTable createAlias(String alias) {
    return $AuthorGapsTable(attachedDatabase, alias);
  }
}

class AuthorGap extends DataClass implements Insertable<AuthorGap> {
  /// Book.
  final String bookId;

  /// Author whose sequence has a hole.
  final String authorDevice;

  /// The sequence number that has not arrived.
  final int expectedSeq;

  /// HLC of the earliest later envelope from that author — since when we know.
  final int sinceHlc;
  const AuthorGap({
    required this.bookId,
    required this.authorDevice,
    required this.expectedSeq,
    required this.sinceHlc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['author_device'] = Variable<String>(authorDevice);
    map['expected_seq'] = Variable<int>(expectedSeq);
    map['since_hlc'] = Variable<int>(sinceHlc);
    return map;
  }

  AuthorGapsCompanion toCompanion(bool nullToAbsent) {
    return AuthorGapsCompanion(
      bookId: Value(bookId),
      authorDevice: Value(authorDevice),
      expectedSeq: Value(expectedSeq),
      sinceHlc: Value(sinceHlc),
    );
  }

  factory AuthorGap.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuthorGap(
      bookId: serializer.fromJson<String>(json['bookId']),
      authorDevice: serializer.fromJson<String>(json['authorDevice']),
      expectedSeq: serializer.fromJson<int>(json['expectedSeq']),
      sinceHlc: serializer.fromJson<int>(json['sinceHlc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'authorDevice': serializer.toJson<String>(authorDevice),
      'expectedSeq': serializer.toJson<int>(expectedSeq),
      'sinceHlc': serializer.toJson<int>(sinceHlc),
    };
  }

  AuthorGap copyWith({
    String? bookId,
    String? authorDevice,
    int? expectedSeq,
    int? sinceHlc,
  }) => AuthorGap(
    bookId: bookId ?? this.bookId,
    authorDevice: authorDevice ?? this.authorDevice,
    expectedSeq: expectedSeq ?? this.expectedSeq,
    sinceHlc: sinceHlc ?? this.sinceHlc,
  );
  AuthorGap copyWithCompanion(AuthorGapsCompanion data) {
    return AuthorGap(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      authorDevice: data.authorDevice.present
          ? data.authorDevice.value
          : this.authorDevice,
      expectedSeq: data.expectedSeq.present
          ? data.expectedSeq.value
          : this.expectedSeq,
      sinceHlc: data.sinceHlc.present ? data.sinceHlc.value : this.sinceHlc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuthorGap(')
          ..write('bookId: $bookId, ')
          ..write('authorDevice: $authorDevice, ')
          ..write('expectedSeq: $expectedSeq, ')
          ..write('sinceHlc: $sinceHlc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bookId, authorDevice, expectedSeq, sinceHlc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthorGap &&
          other.bookId == this.bookId &&
          other.authorDevice == this.authorDevice &&
          other.expectedSeq == this.expectedSeq &&
          other.sinceHlc == this.sinceHlc);
}

class AuthorGapsCompanion extends UpdateCompanion<AuthorGap> {
  final Value<String> bookId;
  final Value<String> authorDevice;
  final Value<int> expectedSeq;
  final Value<int> sinceHlc;
  final Value<int> rowid;
  const AuthorGapsCompanion({
    this.bookId = const Value.absent(),
    this.authorDevice = const Value.absent(),
    this.expectedSeq = const Value.absent(),
    this.sinceHlc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AuthorGapsCompanion.insert({
    required String bookId,
    required String authorDevice,
    required int expectedSeq,
    required int sinceHlc,
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       authorDevice = Value(authorDevice),
       expectedSeq = Value(expectedSeq),
       sinceHlc = Value(sinceHlc);
  static Insertable<AuthorGap> custom({
    Expression<String>? bookId,
    Expression<String>? authorDevice,
    Expression<int>? expectedSeq,
    Expression<int>? sinceHlc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (authorDevice != null) 'author_device': authorDevice,
      if (expectedSeq != null) 'expected_seq': expectedSeq,
      if (sinceHlc != null) 'since_hlc': sinceHlc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AuthorGapsCompanion copyWith({
    Value<String>? bookId,
    Value<String>? authorDevice,
    Value<int>? expectedSeq,
    Value<int>? sinceHlc,
    Value<int>? rowid,
  }) {
    return AuthorGapsCompanion(
      bookId: bookId ?? this.bookId,
      authorDevice: authorDevice ?? this.authorDevice,
      expectedSeq: expectedSeq ?? this.expectedSeq,
      sinceHlc: sinceHlc ?? this.sinceHlc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (authorDevice.present) {
      map['author_device'] = Variable<String>(authorDevice.value);
    }
    if (expectedSeq.present) {
      map['expected_seq'] = Variable<int>(expectedSeq.value);
    }
    if (sinceHlc.present) {
      map['since_hlc'] = Variable<int>(sinceHlc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuthorGapsCompanion(')
          ..write('bookId: $bookId, ')
          ..write('authorDevice: $authorDevice, ')
          ..write('expectedSeq: $expectedSeq, ')
          ..write('sinceHlc: $sinceHlc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AuthorDuplicatesTable extends AuthorDuplicates
    with TableInfo<$AuthorDuplicatesTable, AuthorDuplicate> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuthorDuplicatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorDeviceMeta = const VerificationMeta(
    'authorDevice',
  );
  @override
  late final GeneratedColumn<String> authorDevice = GeneratedColumn<String>(
    'author_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorSeqMeta = const VerificationMeta(
    'authorSeq',
  );
  @override
  late final GeneratedColumn<int> authorSeq = GeneratedColumn<int>(
    'author_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keptEnvelopeIdMeta = const VerificationMeta(
    'keptEnvelopeId',
  );
  @override
  late final GeneratedColumn<String> keptEnvelopeId = GeneratedColumn<String>(
    'kept_envelope_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _duplicateEnvelopeIdMeta =
      const VerificationMeta('duplicateEnvelopeId');
  @override
  late final GeneratedColumn<String> duplicateEnvelopeId =
      GeneratedColumn<String>(
        'duplicate_envelope_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    bookId,
    authorDevice,
    authorSeq,
    keptEnvelopeId,
    duplicateEnvelopeId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'author_duplicates';
  @override
  VerificationContext validateIntegrity(
    Insertable<AuthorDuplicate> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('author_device')) {
      context.handle(
        _authorDeviceMeta,
        authorDevice.isAcceptableOrUnknown(
          data['author_device']!,
          _authorDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authorDeviceMeta);
    }
    if (data.containsKey('author_seq')) {
      context.handle(
        _authorSeqMeta,
        authorSeq.isAcceptableOrUnknown(data['author_seq']!, _authorSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_authorSeqMeta);
    }
    if (data.containsKey('kept_envelope_id')) {
      context.handle(
        _keptEnvelopeIdMeta,
        keptEnvelopeId.isAcceptableOrUnknown(
          data['kept_envelope_id']!,
          _keptEnvelopeIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_keptEnvelopeIdMeta);
    }
    if (data.containsKey('duplicate_envelope_id')) {
      context.handle(
        _duplicateEnvelopeIdMeta,
        duplicateEnvelopeId.isAcceptableOrUnknown(
          data['duplicate_envelope_id']!,
          _duplicateEnvelopeIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_duplicateEnvelopeIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId, duplicateEnvelopeId};
  @override
  AuthorDuplicate map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuthorDuplicate(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      authorDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_device'],
      )!,
      authorSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}author_seq'],
      )!,
      keptEnvelopeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kept_envelope_id'],
      )!,
      duplicateEnvelopeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}duplicate_envelope_id'],
      )!,
    );
  }

  @override
  $AuthorDuplicatesTable createAlias(String alias) {
    return $AuthorDuplicatesTable(attachedDatabase, alias);
  }
}

class AuthorDuplicate extends DataClass implements Insertable<AuthorDuplicate> {
  /// Book.
  final String bookId;

  /// Author whose sequence repeats.
  final String authorDevice;

  /// The repeated sequence number.
  final int authorSeq;

  /// The envelope that keeps the seq (earliest by `(hlc, envelope_id)`).
  final String keptEnvelopeId;

  /// The later envelope, quarantined.
  final String duplicateEnvelopeId;
  const AuthorDuplicate({
    required this.bookId,
    required this.authorDevice,
    required this.authorSeq,
    required this.keptEnvelopeId,
    required this.duplicateEnvelopeId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['author_device'] = Variable<String>(authorDevice);
    map['author_seq'] = Variable<int>(authorSeq);
    map['kept_envelope_id'] = Variable<String>(keptEnvelopeId);
    map['duplicate_envelope_id'] = Variable<String>(duplicateEnvelopeId);
    return map;
  }

  AuthorDuplicatesCompanion toCompanion(bool nullToAbsent) {
    return AuthorDuplicatesCompanion(
      bookId: Value(bookId),
      authorDevice: Value(authorDevice),
      authorSeq: Value(authorSeq),
      keptEnvelopeId: Value(keptEnvelopeId),
      duplicateEnvelopeId: Value(duplicateEnvelopeId),
    );
  }

  factory AuthorDuplicate.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuthorDuplicate(
      bookId: serializer.fromJson<String>(json['bookId']),
      authorDevice: serializer.fromJson<String>(json['authorDevice']),
      authorSeq: serializer.fromJson<int>(json['authorSeq']),
      keptEnvelopeId: serializer.fromJson<String>(json['keptEnvelopeId']),
      duplicateEnvelopeId: serializer.fromJson<String>(
        json['duplicateEnvelopeId'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'authorDevice': serializer.toJson<String>(authorDevice),
      'authorSeq': serializer.toJson<int>(authorSeq),
      'keptEnvelopeId': serializer.toJson<String>(keptEnvelopeId),
      'duplicateEnvelopeId': serializer.toJson<String>(duplicateEnvelopeId),
    };
  }

  AuthorDuplicate copyWith({
    String? bookId,
    String? authorDevice,
    int? authorSeq,
    String? keptEnvelopeId,
    String? duplicateEnvelopeId,
  }) => AuthorDuplicate(
    bookId: bookId ?? this.bookId,
    authorDevice: authorDevice ?? this.authorDevice,
    authorSeq: authorSeq ?? this.authorSeq,
    keptEnvelopeId: keptEnvelopeId ?? this.keptEnvelopeId,
    duplicateEnvelopeId: duplicateEnvelopeId ?? this.duplicateEnvelopeId,
  );
  AuthorDuplicate copyWithCompanion(AuthorDuplicatesCompanion data) {
    return AuthorDuplicate(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      authorDevice: data.authorDevice.present
          ? data.authorDevice.value
          : this.authorDevice,
      authorSeq: data.authorSeq.present ? data.authorSeq.value : this.authorSeq,
      keptEnvelopeId: data.keptEnvelopeId.present
          ? data.keptEnvelopeId.value
          : this.keptEnvelopeId,
      duplicateEnvelopeId: data.duplicateEnvelopeId.present
          ? data.duplicateEnvelopeId.value
          : this.duplicateEnvelopeId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuthorDuplicate(')
          ..write('bookId: $bookId, ')
          ..write('authorDevice: $authorDevice, ')
          ..write('authorSeq: $authorSeq, ')
          ..write('keptEnvelopeId: $keptEnvelopeId, ')
          ..write('duplicateEnvelopeId: $duplicateEnvelopeId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    bookId,
    authorDevice,
    authorSeq,
    keptEnvelopeId,
    duplicateEnvelopeId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthorDuplicate &&
          other.bookId == this.bookId &&
          other.authorDevice == this.authorDevice &&
          other.authorSeq == this.authorSeq &&
          other.keptEnvelopeId == this.keptEnvelopeId &&
          other.duplicateEnvelopeId == this.duplicateEnvelopeId);
}

class AuthorDuplicatesCompanion extends UpdateCompanion<AuthorDuplicate> {
  final Value<String> bookId;
  final Value<String> authorDevice;
  final Value<int> authorSeq;
  final Value<String> keptEnvelopeId;
  final Value<String> duplicateEnvelopeId;
  final Value<int> rowid;
  const AuthorDuplicatesCompanion({
    this.bookId = const Value.absent(),
    this.authorDevice = const Value.absent(),
    this.authorSeq = const Value.absent(),
    this.keptEnvelopeId = const Value.absent(),
    this.duplicateEnvelopeId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AuthorDuplicatesCompanion.insert({
    required String bookId,
    required String authorDevice,
    required int authorSeq,
    required String keptEnvelopeId,
    required String duplicateEnvelopeId,
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       authorDevice = Value(authorDevice),
       authorSeq = Value(authorSeq),
       keptEnvelopeId = Value(keptEnvelopeId),
       duplicateEnvelopeId = Value(duplicateEnvelopeId);
  static Insertable<AuthorDuplicate> custom({
    Expression<String>? bookId,
    Expression<String>? authorDevice,
    Expression<int>? authorSeq,
    Expression<String>? keptEnvelopeId,
    Expression<String>? duplicateEnvelopeId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (authorDevice != null) 'author_device': authorDevice,
      if (authorSeq != null) 'author_seq': authorSeq,
      if (keptEnvelopeId != null) 'kept_envelope_id': keptEnvelopeId,
      if (duplicateEnvelopeId != null)
        'duplicate_envelope_id': duplicateEnvelopeId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AuthorDuplicatesCompanion copyWith({
    Value<String>? bookId,
    Value<String>? authorDevice,
    Value<int>? authorSeq,
    Value<String>? keptEnvelopeId,
    Value<String>? duplicateEnvelopeId,
    Value<int>? rowid,
  }) {
    return AuthorDuplicatesCompanion(
      bookId: bookId ?? this.bookId,
      authorDevice: authorDevice ?? this.authorDevice,
      authorSeq: authorSeq ?? this.authorSeq,
      keptEnvelopeId: keptEnvelopeId ?? this.keptEnvelopeId,
      duplicateEnvelopeId: duplicateEnvelopeId ?? this.duplicateEnvelopeId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (authorDevice.present) {
      map['author_device'] = Variable<String>(authorDevice.value);
    }
    if (authorSeq.present) {
      map['author_seq'] = Variable<int>(authorSeq.value);
    }
    if (keptEnvelopeId.present) {
      map['kept_envelope_id'] = Variable<String>(keptEnvelopeId.value);
    }
    if (duplicateEnvelopeId.present) {
      map['duplicate_envelope_id'] = Variable<String>(
        duplicateEnvelopeId.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuthorDuplicatesCompanion(')
          ..write('bookId: $bookId, ')
          ..write('authorDevice: $authorDevice, ')
          ..write('authorSeq: $authorSeq, ')
          ..write('keptEnvelopeId: $keptEnvelopeId, ')
          ..write('duplicateEnvelopeId: $duplicateEnvelopeId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SignedRecordsLocalTable extends SignedRecordsLocal
    with TableInfo<$SignedRecordsLocalTable, SignedRecordsLocalData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SignedRecordsLocalTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tenantIdMeta = const VerificationMeta(
    'tenantId',
  );
  @override
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
    'tenant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<Uint8List> payload = GeneratedColumn<Uint8List>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorDeviceMeta = const VerificationMeta(
    'authorDevice',
  );
  @override
  late final GeneratedColumn<String> authorDevice = GeneratedColumn<String>(
    'author_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sigMeta = const VerificationMeta('sig');
  @override
  late final GeneratedColumn<Uint8List> sig = GeneratedColumn<Uint8List>(
    'sig',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<int> hlc = GeneratedColumn<int>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _verifiedMeta = const VerificationMeta(
    'verified',
  );
  @override
  late final GeneratedColumn<int> verified = GeneratedColumn<int>(
    'verified',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    tenantId,
    kind,
    payload,
    authorDevice,
    sig,
    hlc,
    seq,
    verified,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'signed_records_local';
  @override
  VerificationContext validateIntegrity(
    Insertable<SignedRecordsLocalData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('tenant_id')) {
      context.handle(
        _tenantIdMeta,
        tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('author_device')) {
      context.handle(
        _authorDeviceMeta,
        authorDevice.isAcceptableOrUnknown(
          data['author_device']!,
          _authorDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authorDeviceMeta);
    }
    if (data.containsKey('sig')) {
      context.handle(
        _sigMeta,
        sig.isAcceptableOrUnknown(data['sig']!, _sigMeta),
      );
    } else if (isInserting) {
      context.missing(_sigMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    }
    if (data.containsKey('verified')) {
      context.handle(
        _verifiedMeta,
        verified.isAcceptableOrUnknown(data['verified']!, _verifiedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SignedRecordsLocalData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SignedRecordsLocalData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      tenantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tenant_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}payload'],
      )!,
      authorDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_device'],
      )!,
      sig: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}sig'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hlc'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      ),
      verified: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}verified'],
      )!,
    );
  }

  @override
  $SignedRecordsLocalTable createAlias(String alias) {
    return $SignedRecordsLocalTable(attachedDatabase, alias);
  }
}

class SignedRecordsLocalData extends DataClass
    implements Insertable<SignedRecordsLocalData> {
  /// Record id.
  final String id;

  /// Tenant.
  final String tenantId;

  /// Record kind.
  final String kind;

  /// Payload bytes.
  final Uint8List payload;

  /// Signing device.
  final String authorDevice;

  /// Signature.
  final Uint8List sig;

  /// HLC.
  final int hlc;

  /// Server seq.
  final int? seq;

  /// 1 after verification.
  final int verified;
  const SignedRecordsLocalData({
    required this.id,
    required this.tenantId,
    required this.kind,
    required this.payload,
    required this.authorDevice,
    required this.sig,
    required this.hlc,
    this.seq,
    required this.verified,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['tenant_id'] = Variable<String>(tenantId);
    map['kind'] = Variable<String>(kind);
    map['payload'] = Variable<Uint8List>(payload);
    map['author_device'] = Variable<String>(authorDevice);
    map['sig'] = Variable<Uint8List>(sig);
    map['hlc'] = Variable<int>(hlc);
    if (!nullToAbsent || seq != null) {
      map['seq'] = Variable<int>(seq);
    }
    map['verified'] = Variable<int>(verified);
    return map;
  }

  SignedRecordsLocalCompanion toCompanion(bool nullToAbsent) {
    return SignedRecordsLocalCompanion(
      id: Value(id),
      tenantId: Value(tenantId),
      kind: Value(kind),
      payload: Value(payload),
      authorDevice: Value(authorDevice),
      sig: Value(sig),
      hlc: Value(hlc),
      seq: seq == null && nullToAbsent ? const Value.absent() : Value(seq),
      verified: Value(verified),
    );
  }

  factory SignedRecordsLocalData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SignedRecordsLocalData(
      id: serializer.fromJson<String>(json['id']),
      tenantId: serializer.fromJson<String>(json['tenantId']),
      kind: serializer.fromJson<String>(json['kind']),
      payload: serializer.fromJson<Uint8List>(json['payload']),
      authorDevice: serializer.fromJson<String>(json['authorDevice']),
      sig: serializer.fromJson<Uint8List>(json['sig']),
      hlc: serializer.fromJson<int>(json['hlc']),
      seq: serializer.fromJson<int?>(json['seq']),
      verified: serializer.fromJson<int>(json['verified']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'tenantId': serializer.toJson<String>(tenantId),
      'kind': serializer.toJson<String>(kind),
      'payload': serializer.toJson<Uint8List>(payload),
      'authorDevice': serializer.toJson<String>(authorDevice),
      'sig': serializer.toJson<Uint8List>(sig),
      'hlc': serializer.toJson<int>(hlc),
      'seq': serializer.toJson<int?>(seq),
      'verified': serializer.toJson<int>(verified),
    };
  }

  SignedRecordsLocalData copyWith({
    String? id,
    String? tenantId,
    String? kind,
    Uint8List? payload,
    String? authorDevice,
    Uint8List? sig,
    int? hlc,
    Value<int?> seq = const Value.absent(),
    int? verified,
  }) => SignedRecordsLocalData(
    id: id ?? this.id,
    tenantId: tenantId ?? this.tenantId,
    kind: kind ?? this.kind,
    payload: payload ?? this.payload,
    authorDevice: authorDevice ?? this.authorDevice,
    sig: sig ?? this.sig,
    hlc: hlc ?? this.hlc,
    seq: seq.present ? seq.value : this.seq,
    verified: verified ?? this.verified,
  );
  SignedRecordsLocalData copyWithCompanion(SignedRecordsLocalCompanion data) {
    return SignedRecordsLocalData(
      id: data.id.present ? data.id.value : this.id,
      tenantId: data.tenantId.present ? data.tenantId.value : this.tenantId,
      kind: data.kind.present ? data.kind.value : this.kind,
      payload: data.payload.present ? data.payload.value : this.payload,
      authorDevice: data.authorDevice.present
          ? data.authorDevice.value
          : this.authorDevice,
      sig: data.sig.present ? data.sig.value : this.sig,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      seq: data.seq.present ? data.seq.value : this.seq,
      verified: data.verified.present ? data.verified.value : this.verified,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SignedRecordsLocalData(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('authorDevice: $authorDevice, ')
          ..write('sig: $sig, ')
          ..write('hlc: $hlc, ')
          ..write('seq: $seq, ')
          ..write('verified: $verified')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    tenantId,
    kind,
    $driftBlobEquality.hash(payload),
    authorDevice,
    $driftBlobEquality.hash(sig),
    hlc,
    seq,
    verified,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SignedRecordsLocalData &&
          other.id == this.id &&
          other.tenantId == this.tenantId &&
          other.kind == this.kind &&
          $driftBlobEquality.equals(other.payload, this.payload) &&
          other.authorDevice == this.authorDevice &&
          $driftBlobEquality.equals(other.sig, this.sig) &&
          other.hlc == this.hlc &&
          other.seq == this.seq &&
          other.verified == this.verified);
}

class SignedRecordsLocalCompanion
    extends UpdateCompanion<SignedRecordsLocalData> {
  final Value<String> id;
  final Value<String> tenantId;
  final Value<String> kind;
  final Value<Uint8List> payload;
  final Value<String> authorDevice;
  final Value<Uint8List> sig;
  final Value<int> hlc;
  final Value<int?> seq;
  final Value<int> verified;
  final Value<int> rowid;
  const SignedRecordsLocalCompanion({
    this.id = const Value.absent(),
    this.tenantId = const Value.absent(),
    this.kind = const Value.absent(),
    this.payload = const Value.absent(),
    this.authorDevice = const Value.absent(),
    this.sig = const Value.absent(),
    this.hlc = const Value.absent(),
    this.seq = const Value.absent(),
    this.verified = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SignedRecordsLocalCompanion.insert({
    required String id,
    required String tenantId,
    required String kind,
    required Uint8List payload,
    required String authorDevice,
    required Uint8List sig,
    required int hlc,
    this.seq = const Value.absent(),
    this.verified = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       tenantId = Value(tenantId),
       kind = Value(kind),
       payload = Value(payload),
       authorDevice = Value(authorDevice),
       sig = Value(sig),
       hlc = Value(hlc);
  static Insertable<SignedRecordsLocalData> custom({
    Expression<String>? id,
    Expression<String>? tenantId,
    Expression<String>? kind,
    Expression<Uint8List>? payload,
    Expression<String>? authorDevice,
    Expression<Uint8List>? sig,
    Expression<int>? hlc,
    Expression<int>? seq,
    Expression<int>? verified,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tenantId != null) 'tenant_id': tenantId,
      if (kind != null) 'kind': kind,
      if (payload != null) 'payload': payload,
      if (authorDevice != null) 'author_device': authorDevice,
      if (sig != null) 'sig': sig,
      if (hlc != null) 'hlc': hlc,
      if (seq != null) 'seq': seq,
      if (verified != null) 'verified': verified,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SignedRecordsLocalCompanion copyWith({
    Value<String>? id,
    Value<String>? tenantId,
    Value<String>? kind,
    Value<Uint8List>? payload,
    Value<String>? authorDevice,
    Value<Uint8List>? sig,
    Value<int>? hlc,
    Value<int?>? seq,
    Value<int>? verified,
    Value<int>? rowid,
  }) {
    return SignedRecordsLocalCompanion(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      kind: kind ?? this.kind,
      payload: payload ?? this.payload,
      authorDevice: authorDevice ?? this.authorDevice,
      sig: sig ?? this.sig,
      hlc: hlc ?? this.hlc,
      seq: seq ?? this.seq,
      verified: verified ?? this.verified,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (payload.present) {
      map['payload'] = Variable<Uint8List>(payload.value);
    }
    if (authorDevice.present) {
      map['author_device'] = Variable<String>(authorDevice.value);
    }
    if (sig.present) {
      map['sig'] = Variable<Uint8List>(sig.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<int>(hlc.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (verified.present) {
      map['verified'] = Variable<int>(verified.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SignedRecordsLocalCompanion(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('authorDevice: $authorDevice, ')
          ..write('sig: $sig, ')
          ..write('hlc: $hlc, ')
          ..write('seq: $seq, ')
          ..write('verified: $verified, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoreEpochTable extends StoreEpoch
    with TableInfo<$StoreEpochTable, StoreEpochData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoreEpochTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL CHECK (id = 1)',
  );
  static const VerificationMeta _epochMeta = const VerificationMeta('epoch');
  @override
  late final GeneratedColumn<String> epoch = GeneratedColumn<String>(
    'epoch',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, epoch];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'store_epoch';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoreEpochData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('epoch')) {
      context.handle(
        _epochMeta,
        epoch.isAcceptableOrUnknown(data['epoch']!, _epochMeta),
      );
    } else if (isInserting) {
      context.missing(_epochMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoreEpochData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoreEpochData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      epoch: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}epoch'],
      )!,
    );
  }

  @override
  $StoreEpochTable createAlias(String alias) {
    return $StoreEpochTable(attachedDatabase, alias);
  }
}

class StoreEpochData extends DataClass implements Insertable<StoreEpochData> {
  /// Always 1 — enforces the single row.
  final int id;

  /// The epoch.
  final String epoch;
  const StoreEpochData({required this.id, required this.epoch});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['epoch'] = Variable<String>(epoch);
    return map;
  }

  StoreEpochCompanion toCompanion(bool nullToAbsent) {
    return StoreEpochCompanion(id: Value(id), epoch: Value(epoch));
  }

  factory StoreEpochData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoreEpochData(
      id: serializer.fromJson<int>(json['id']),
      epoch: serializer.fromJson<String>(json['epoch']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'epoch': serializer.toJson<String>(epoch),
    };
  }

  StoreEpochData copyWith({int? id, String? epoch}) =>
      StoreEpochData(id: id ?? this.id, epoch: epoch ?? this.epoch);
  StoreEpochData copyWithCompanion(StoreEpochCompanion data) {
    return StoreEpochData(
      id: data.id.present ? data.id.value : this.id,
      epoch: data.epoch.present ? data.epoch.value : this.epoch,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoreEpochData(')
          ..write('id: $id, ')
          ..write('epoch: $epoch')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, epoch);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoreEpochData &&
          other.id == this.id &&
          other.epoch == this.epoch);
}

class StoreEpochCompanion extends UpdateCompanion<StoreEpochData> {
  final Value<int> id;
  final Value<String> epoch;
  const StoreEpochCompanion({
    this.id = const Value.absent(),
    this.epoch = const Value.absent(),
  });
  StoreEpochCompanion.insert({
    this.id = const Value.absent(),
    required String epoch,
  }) : epoch = Value(epoch);
  static Insertable<StoreEpochData> custom({
    Expression<int>? id,
    Expression<String>? epoch,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (epoch != null) 'epoch': epoch,
    });
  }

  StoreEpochCompanion copyWith({Value<int>? id, Value<String>? epoch}) {
    return StoreEpochCompanion(id: id ?? this.id, epoch: epoch ?? this.epoch);
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (epoch.present) {
      map['epoch'] = Variable<String>(epoch.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoreEpochCompanion(')
          ..write('id: $id, ')
          ..write('epoch: $epoch')
          ..write(')'))
        .toString();
  }
}

class $SyncCursorsTable extends SyncCursors
    with TableInfo<$SyncCursorsTable, SyncCursor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCursorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeqMeta = const VerificationMeta(
    'lastSeq',
  );
  @override
  late final GeneratedColumn<int> lastSeq = GeneratedColumn<int>(
    'last_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [bookId, lastSeq];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_cursors';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncCursor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('last_seq')) {
      context.handle(
        _lastSeqMeta,
        lastSeq.isAcceptableOrUnknown(data['last_seq']!, _lastSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_lastSeqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId};
  @override
  SyncCursor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCursor(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      lastSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seq'],
      )!,
    );
  }

  @override
  $SyncCursorsTable createAlias(String alias) {
    return $SyncCursorsTable(attachedDatabase, alias);
  }
}

class SyncCursor extends DataClass implements Insertable<SyncCursor> {
  /// Book.
  final String bookId;

  /// Highest server seq applied.
  final int lastSeq;
  const SyncCursor({required this.bookId, required this.lastSeq});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['last_seq'] = Variable<int>(lastSeq);
    return map;
  }

  SyncCursorsCompanion toCompanion(bool nullToAbsent) {
    return SyncCursorsCompanion(bookId: Value(bookId), lastSeq: Value(lastSeq));
  }

  factory SyncCursor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCursor(
      bookId: serializer.fromJson<String>(json['bookId']),
      lastSeq: serializer.fromJson<int>(json['lastSeq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'lastSeq': serializer.toJson<int>(lastSeq),
    };
  }

  SyncCursor copyWith({String? bookId, int? lastSeq}) => SyncCursor(
    bookId: bookId ?? this.bookId,
    lastSeq: lastSeq ?? this.lastSeq,
  );
  SyncCursor copyWithCompanion(SyncCursorsCompanion data) {
    return SyncCursor(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      lastSeq: data.lastSeq.present ? data.lastSeq.value : this.lastSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursor(')
          ..write('bookId: $bookId, ')
          ..write('lastSeq: $lastSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bookId, lastSeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCursor &&
          other.bookId == this.bookId &&
          other.lastSeq == this.lastSeq);
}

class SyncCursorsCompanion extends UpdateCompanion<SyncCursor> {
  final Value<String> bookId;
  final Value<int> lastSeq;
  final Value<int> rowid;
  const SyncCursorsCompanion({
    this.bookId = const Value.absent(),
    this.lastSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncCursorsCompanion.insert({
    required String bookId,
    required int lastSeq,
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       lastSeq = Value(lastSeq);
  static Insertable<SyncCursor> custom({
    Expression<String>? bookId,
    Expression<int>? lastSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (lastSeq != null) 'last_seq': lastSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncCursorsCompanion copyWith({
    Value<String>? bookId,
    Value<int>? lastSeq,
    Value<int>? rowid,
  }) {
    return SyncCursorsCompanion(
      bookId: bookId ?? this.bookId,
      lastSeq: lastSeq ?? this.lastSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (lastSeq.present) {
      map['last_seq'] = Variable<int>(lastSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorsCompanion(')
          ..write('bookId: $bookId, ')
          ..write('lastSeq: $lastSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KeyCacheTable extends KeyCache
    with TableInfo<$KeyCacheTable, KeyCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KeyCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyVersionMeta = const VerificationMeta(
    'keyVersion',
  );
  @override
  late final GeneratedColumn<int> keyVersion = GeneratedColumn<int>(
    'key_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wrappedBlobMeta = const VerificationMeta(
    'wrappedBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> wrappedBlob =
      GeneratedColumn<Uint8List>(
        'wrapped_blob',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [bookId, keyVersion, wrappedBlob];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'key_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<KeyCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('key_version')) {
      context.handle(
        _keyVersionMeta,
        keyVersion.isAcceptableOrUnknown(data['key_version']!, _keyVersionMeta),
      );
    } else if (isInserting) {
      context.missing(_keyVersionMeta);
    }
    if (data.containsKey('wrapped_blob')) {
      context.handle(
        _wrappedBlobMeta,
        wrappedBlob.isAcceptableOrUnknown(
          data['wrapped_blob']!,
          _wrappedBlobMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_wrappedBlobMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId, keyVersion};
  @override
  KeyCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KeyCacheData(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      keyVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}key_version'],
      )!,
      wrappedBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}wrapped_blob'],
      )!,
    );
  }

  @override
  $KeyCacheTable createAlias(String alias) {
    return $KeyCacheTable(attachedDatabase, alias);
  }
}

class KeyCacheData extends DataClass implements Insertable<KeyCacheData> {
  /// Book.
  final String bookId;

  /// Key version.
  final int keyVersion;

  /// The wrapped key blob — opaque here.
  final Uint8List wrappedBlob;
  const KeyCacheData({
    required this.bookId,
    required this.keyVersion,
    required this.wrappedBlob,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['key_version'] = Variable<int>(keyVersion);
    map['wrapped_blob'] = Variable<Uint8List>(wrappedBlob);
    return map;
  }

  KeyCacheCompanion toCompanion(bool nullToAbsent) {
    return KeyCacheCompanion(
      bookId: Value(bookId),
      keyVersion: Value(keyVersion),
      wrappedBlob: Value(wrappedBlob),
    );
  }

  factory KeyCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KeyCacheData(
      bookId: serializer.fromJson<String>(json['bookId']),
      keyVersion: serializer.fromJson<int>(json['keyVersion']),
      wrappedBlob: serializer.fromJson<Uint8List>(json['wrappedBlob']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'keyVersion': serializer.toJson<int>(keyVersion),
      'wrappedBlob': serializer.toJson<Uint8List>(wrappedBlob),
    };
  }

  KeyCacheData copyWith({
    String? bookId,
    int? keyVersion,
    Uint8List? wrappedBlob,
  }) => KeyCacheData(
    bookId: bookId ?? this.bookId,
    keyVersion: keyVersion ?? this.keyVersion,
    wrappedBlob: wrappedBlob ?? this.wrappedBlob,
  );
  KeyCacheData copyWithCompanion(KeyCacheCompanion data) {
    return KeyCacheData(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      keyVersion: data.keyVersion.present
          ? data.keyVersion.value
          : this.keyVersion,
      wrappedBlob: data.wrappedBlob.present
          ? data.wrappedBlob.value
          : this.wrappedBlob,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KeyCacheData(')
          ..write('bookId: $bookId, ')
          ..write('keyVersion: $keyVersion, ')
          ..write('wrappedBlob: $wrappedBlob')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(bookId, keyVersion, $driftBlobEquality.hash(wrappedBlob));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KeyCacheData &&
          other.bookId == this.bookId &&
          other.keyVersion == this.keyVersion &&
          $driftBlobEquality.equals(other.wrappedBlob, this.wrappedBlob));
}

class KeyCacheCompanion extends UpdateCompanion<KeyCacheData> {
  final Value<String> bookId;
  final Value<int> keyVersion;
  final Value<Uint8List> wrappedBlob;
  final Value<int> rowid;
  const KeyCacheCompanion({
    this.bookId = const Value.absent(),
    this.keyVersion = const Value.absent(),
    this.wrappedBlob = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KeyCacheCompanion.insert({
    required String bookId,
    required int keyVersion,
    required Uint8List wrappedBlob,
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       keyVersion = Value(keyVersion),
       wrappedBlob = Value(wrappedBlob);
  static Insertable<KeyCacheData> custom({
    Expression<String>? bookId,
    Expression<int>? keyVersion,
    Expression<Uint8List>? wrappedBlob,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (keyVersion != null) 'key_version': keyVersion,
      if (wrappedBlob != null) 'wrapped_blob': wrappedBlob,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KeyCacheCompanion copyWith({
    Value<String>? bookId,
    Value<int>? keyVersion,
    Value<Uint8List>? wrappedBlob,
    Value<int>? rowid,
  }) {
    return KeyCacheCompanion(
      bookId: bookId ?? this.bookId,
      keyVersion: keyVersion ?? this.keyVersion,
      wrappedBlob: wrappedBlob ?? this.wrappedBlob,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (keyVersion.present) {
      map['key_version'] = Variable<int>(keyVersion.value);
    }
    if (wrappedBlob.present) {
      map['wrapped_blob'] = Variable<Uint8List>(wrappedBlob.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KeyCacheCompanion(')
          ..write('bookId: $bookId, ')
          ..write('keyVersion: $keyVersion, ')
          ..write('wrappedBlob: $wrappedBlob, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AttachmentCacheTable extends AttachmentCache
    with TableInfo<$AttachmentCacheTable, AttachmentCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AttachmentCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, bookId, localPath, state];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attachment_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<AttachmentCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AttachmentCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AttachmentCacheData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
    );
  }

  @override
  $AttachmentCacheTable createAlias(String alias) {
    return $AttachmentCacheTable(attachedDatabase, alias);
  }
}

class AttachmentCacheData extends DataClass
    implements Insertable<AttachmentCacheData> {
  /// Attachment id.
  final String id;

  /// Book.
  final String bookId;

  /// Where the decrypted file lives locally.
  final String localPath;

  /// Cache state.
  final String state;
  const AttachmentCacheData({
    required this.id,
    required this.bookId,
    required this.localPath,
    required this.state,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['local_path'] = Variable<String>(localPath);
    map['state'] = Variable<String>(state);
    return map;
  }

  AttachmentCacheCompanion toCompanion(bool nullToAbsent) {
    return AttachmentCacheCompanion(
      id: Value(id),
      bookId: Value(bookId),
      localPath: Value(localPath),
      state: Value(state),
    );
  }

  factory AttachmentCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AttachmentCacheData(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      localPath: serializer.fromJson<String>(json['localPath']),
      state: serializer.fromJson<String>(json['state']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'localPath': serializer.toJson<String>(localPath),
      'state': serializer.toJson<String>(state),
    };
  }

  AttachmentCacheData copyWith({
    String? id,
    String? bookId,
    String? localPath,
    String? state,
  }) => AttachmentCacheData(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    localPath: localPath ?? this.localPath,
    state: state ?? this.state,
  );
  AttachmentCacheData copyWithCompanion(AttachmentCacheCompanion data) {
    return AttachmentCacheData(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      state: data.state.present ? data.state.value : this.state,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentCacheData(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('localPath: $localPath, ')
          ..write('state: $state')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, bookId, localPath, state);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AttachmentCacheData &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.localPath == this.localPath &&
          other.state == this.state);
}

class AttachmentCacheCompanion extends UpdateCompanion<AttachmentCacheData> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<String> localPath;
  final Value<String> state;
  final Value<int> rowid;
  const AttachmentCacheCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.localPath = const Value.absent(),
    this.state = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AttachmentCacheCompanion.insert({
    required String id,
    required String bookId,
    required String localPath,
    required String state,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bookId = Value(bookId),
       localPath = Value(localPath),
       state = Value(state);
  static Insertable<AttachmentCacheData> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<String>? localPath,
    Expression<String>? state,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (localPath != null) 'local_path': localPath,
      if (state != null) 'state': state,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AttachmentCacheCompanion copyWith({
    Value<String>? id,
    Value<String>? bookId,
    Value<String>? localPath,
    Value<String>? state,
    Value<int>? rowid,
  }) {
    return AttachmentCacheCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      localPath: localPath ?? this.localPath,
      state: state ?? this.state,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentCacheCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('localPath: $localPath, ')
          ..write('state: $state, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BooksPTable extends BooksP with TableInfo<$BooksPTable, BooksPData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BooksPTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tenantIdMeta = const VerificationMeta(
    'tenantId',
  );
  @override
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
    'tenant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fyStartMonthMeta = const VerificationMeta(
    'fyStartMonth',
  );
  @override
  late final GeneratedColumn<int> fyStartMonth = GeneratedColumn<int>(
    'fy_start_month',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(4),
  );
  static const VerificationMeta _integrityOkMeta = const VerificationMeta(
    'integrityOk',
  );
  @override
  late final GeneratedColumn<int> integrityOk = GeneratedColumn<int>(
    'integrity_ok',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _needsRebootstrapMeta = const VerificationMeta(
    'needsRebootstrap',
  );
  @override
  late final GeneratedColumn<int> needsRebootstrap = GeneratedColumn<int>(
    'needs_rebootstrap',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    tenantId,
    type,
    name,
    fyStartMonth,
    integrityOk,
    needsRebootstrap,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books_p';
  @override
  VerificationContext validateIntegrity(
    Insertable<BooksPData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('tenant_id')) {
      context.handle(
        _tenantIdMeta,
        tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('fy_start_month')) {
      context.handle(
        _fyStartMonthMeta,
        fyStartMonth.isAcceptableOrUnknown(
          data['fy_start_month']!,
          _fyStartMonthMeta,
        ),
      );
    }
    if (data.containsKey('integrity_ok')) {
      context.handle(
        _integrityOkMeta,
        integrityOk.isAcceptableOrUnknown(
          data['integrity_ok']!,
          _integrityOkMeta,
        ),
      );
    }
    if (data.containsKey('needs_rebootstrap')) {
      context.handle(
        _needsRebootstrapMeta,
        needsRebootstrap.isAcceptableOrUnknown(
          data['needs_rebootstrap']!,
          _needsRebootstrapMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BooksPData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BooksPData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      tenantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tenant_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      fyStartMonth: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fy_start_month'],
      )!,
      integrityOk: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}integrity_ok'],
      )!,
      needsRebootstrap: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}needs_rebootstrap'],
      )!,
    );
  }

  @override
  $BooksPTable createAlias(String alias) {
    return $BooksPTable(attachedDatabase, alias);
  }
}

class BooksPData extends DataClass implements Insertable<BooksPData> {
  /// Book id.
  final String id;

  /// Tenant.
  final String tenantId;

  /// Book type (02 §1.1 wire name).
  final String type;

  /// Display name (ciphertext-side, 03 §4).
  final String name;

  /// Financial-year start month (02 §1.1).
  final int fyStartMonth;

  /// 1 only when every envelope of the book is present, verified and not held
  /// (ADR 05c §6) — gates the Home card.
  final int integrityOk;

  /// 1 when a mirror row failed `blob_hash`: re-bootstrap from the server
  /// (ADR 05c §6). ⚠️ SPEC: column not listed in 03 §3.2; a projection table
  /// may carry it because Recompute derives it from the mirror every time.
  final int needsRebootstrap;
  const BooksPData({
    required this.id,
    required this.tenantId,
    required this.type,
    required this.name,
    required this.fyStartMonth,
    required this.integrityOk,
    required this.needsRebootstrap,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['tenant_id'] = Variable<String>(tenantId);
    map['type'] = Variable<String>(type);
    map['name'] = Variable<String>(name);
    map['fy_start_month'] = Variable<int>(fyStartMonth);
    map['integrity_ok'] = Variable<int>(integrityOk);
    map['needs_rebootstrap'] = Variable<int>(needsRebootstrap);
    return map;
  }

  BooksPCompanion toCompanion(bool nullToAbsent) {
    return BooksPCompanion(
      id: Value(id),
      tenantId: Value(tenantId),
      type: Value(type),
      name: Value(name),
      fyStartMonth: Value(fyStartMonth),
      integrityOk: Value(integrityOk),
      needsRebootstrap: Value(needsRebootstrap),
    );
  }

  factory BooksPData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BooksPData(
      id: serializer.fromJson<String>(json['id']),
      tenantId: serializer.fromJson<String>(json['tenantId']),
      type: serializer.fromJson<String>(json['type']),
      name: serializer.fromJson<String>(json['name']),
      fyStartMonth: serializer.fromJson<int>(json['fyStartMonth']),
      integrityOk: serializer.fromJson<int>(json['integrityOk']),
      needsRebootstrap: serializer.fromJson<int>(json['needsRebootstrap']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'tenantId': serializer.toJson<String>(tenantId),
      'type': serializer.toJson<String>(type),
      'name': serializer.toJson<String>(name),
      'fyStartMonth': serializer.toJson<int>(fyStartMonth),
      'integrityOk': serializer.toJson<int>(integrityOk),
      'needsRebootstrap': serializer.toJson<int>(needsRebootstrap),
    };
  }

  BooksPData copyWith({
    String? id,
    String? tenantId,
    String? type,
    String? name,
    int? fyStartMonth,
    int? integrityOk,
    int? needsRebootstrap,
  }) => BooksPData(
    id: id ?? this.id,
    tenantId: tenantId ?? this.tenantId,
    type: type ?? this.type,
    name: name ?? this.name,
    fyStartMonth: fyStartMonth ?? this.fyStartMonth,
    integrityOk: integrityOk ?? this.integrityOk,
    needsRebootstrap: needsRebootstrap ?? this.needsRebootstrap,
  );
  BooksPData copyWithCompanion(BooksPCompanion data) {
    return BooksPData(
      id: data.id.present ? data.id.value : this.id,
      tenantId: data.tenantId.present ? data.tenantId.value : this.tenantId,
      type: data.type.present ? data.type.value : this.type,
      name: data.name.present ? data.name.value : this.name,
      fyStartMonth: data.fyStartMonth.present
          ? data.fyStartMonth.value
          : this.fyStartMonth,
      integrityOk: data.integrityOk.present
          ? data.integrityOk.value
          : this.integrityOk,
      needsRebootstrap: data.needsRebootstrap.present
          ? data.needsRebootstrap.value
          : this.needsRebootstrap,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BooksPData(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('fyStartMonth: $fyStartMonth, ')
          ..write('integrityOk: $integrityOk, ')
          ..write('needsRebootstrap: $needsRebootstrap')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    tenantId,
    type,
    name,
    fyStartMonth,
    integrityOk,
    needsRebootstrap,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BooksPData &&
          other.id == this.id &&
          other.tenantId == this.tenantId &&
          other.type == this.type &&
          other.name == this.name &&
          other.fyStartMonth == this.fyStartMonth &&
          other.integrityOk == this.integrityOk &&
          other.needsRebootstrap == this.needsRebootstrap);
}

class BooksPCompanion extends UpdateCompanion<BooksPData> {
  final Value<String> id;
  final Value<String> tenantId;
  final Value<String> type;
  final Value<String> name;
  final Value<int> fyStartMonth;
  final Value<int> integrityOk;
  final Value<int> needsRebootstrap;
  final Value<int> rowid;
  const BooksPCompanion({
    this.id = const Value.absent(),
    this.tenantId = const Value.absent(),
    this.type = const Value.absent(),
    this.name = const Value.absent(),
    this.fyStartMonth = const Value.absent(),
    this.integrityOk = const Value.absent(),
    this.needsRebootstrap = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BooksPCompanion.insert({
    required String id,
    required String tenantId,
    required String type,
    required String name,
    this.fyStartMonth = const Value.absent(),
    this.integrityOk = const Value.absent(),
    this.needsRebootstrap = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       tenantId = Value(tenantId),
       type = Value(type),
       name = Value(name);
  static Insertable<BooksPData> custom({
    Expression<String>? id,
    Expression<String>? tenantId,
    Expression<String>? type,
    Expression<String>? name,
    Expression<int>? fyStartMonth,
    Expression<int>? integrityOk,
    Expression<int>? needsRebootstrap,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tenantId != null) 'tenant_id': tenantId,
      if (type != null) 'type': type,
      if (name != null) 'name': name,
      if (fyStartMonth != null) 'fy_start_month': fyStartMonth,
      if (integrityOk != null) 'integrity_ok': integrityOk,
      if (needsRebootstrap != null) 'needs_rebootstrap': needsRebootstrap,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BooksPCompanion copyWith({
    Value<String>? id,
    Value<String>? tenantId,
    Value<String>? type,
    Value<String>? name,
    Value<int>? fyStartMonth,
    Value<int>? integrityOk,
    Value<int>? needsRebootstrap,
    Value<int>? rowid,
  }) {
    return BooksPCompanion(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      type: type ?? this.type,
      name: name ?? this.name,
      fyStartMonth: fyStartMonth ?? this.fyStartMonth,
      integrityOk: integrityOk ?? this.integrityOk,
      needsRebootstrap: needsRebootstrap ?? this.needsRebootstrap,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (fyStartMonth.present) {
      map['fy_start_month'] = Variable<int>(fyStartMonth.value);
    }
    if (integrityOk.present) {
      map['integrity_ok'] = Variable<int>(integrityOk.value);
    }
    if (needsRebootstrap.present) {
      map['needs_rebootstrap'] = Variable<int>(needsRebootstrap.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksPCompanion(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('fyStartMonth: $fyStartMonth, ')
          ..write('integrityOk: $integrityOk, ')
          ..write('needsRebootstrap: $needsRebootstrap, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AccountsPTable extends AccountsP
    with TableInfo<$AccountsPTable, AccountsPData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsPTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountClassMeta = const VerificationMeta(
    'accountClass',
  );
  @override
  late final GeneratedColumn<String> accountClass = GeneratedColumn<String>(
    'class',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _moneySubtypeMeta = const VerificationMeta(
    'moneySubtype',
  );
  @override
  late final GeneratedColumn<String> moneySubtype = GeneratedColumn<String>(
    'money_subtype',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _collectionIncomeAccountIdMeta =
      const VerificationMeta('collectionIncomeAccountId');
  @override
  late final GeneratedColumn<String> collectionIncomeAccountId =
      GeneratedColumn<String>(
        'collection_income_account_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _usualCategoryIdMeta = const VerificationMeta(
    'usualCategoryId',
  );
  @override
  late final GeneratedColumn<String> usualCategoryId = GeneratedColumn<String>(
    'usual_category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<int> archived = GeneratedColumn<int>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _systemRoleMeta = const VerificationMeta(
    'systemRole',
  );
  @override
  late final GeneratedColumn<String> systemRole = GeneratedColumn<String>(
    'system_role',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _memberIdMeta = const VerificationMeta(
    'memberId',
  );
  @override
  late final GeneratedColumn<String> memberId = GeneratedColumn<String>(
    'member_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _counterpartBookIdMeta = const VerificationMeta(
    'counterpartBookId',
  );
  @override
  late final GeneratedColumn<String> counterpartBookId =
      GeneratedColumn<String>(
        'counterpart_book_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdOrderMeta = const VerificationMeta(
    'createdOrder',
  );
  @override
  late final GeneratedColumn<int> createdOrder = GeneratedColumn<int>(
    'created_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    name,
    accountClass,
    moneySubtype,
    collectionIncomeAccountId,
    usualCategoryId,
    archived,
    systemRole,
    memberId,
    counterpartBookId,
    createdOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts_p';
  @override
  VerificationContext validateIntegrity(
    Insertable<AccountsPData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('class')) {
      context.handle(
        _accountClassMeta,
        accountClass.isAcceptableOrUnknown(data['class']!, _accountClassMeta),
      );
    } else if (isInserting) {
      context.missing(_accountClassMeta);
    }
    if (data.containsKey('money_subtype')) {
      context.handle(
        _moneySubtypeMeta,
        moneySubtype.isAcceptableOrUnknown(
          data['money_subtype']!,
          _moneySubtypeMeta,
        ),
      );
    }
    if (data.containsKey('collection_income_account_id')) {
      context.handle(
        _collectionIncomeAccountIdMeta,
        collectionIncomeAccountId.isAcceptableOrUnknown(
          data['collection_income_account_id']!,
          _collectionIncomeAccountIdMeta,
        ),
      );
    }
    if (data.containsKey('usual_category_id')) {
      context.handle(
        _usualCategoryIdMeta,
        usualCategoryId.isAcceptableOrUnknown(
          data['usual_category_id']!,
          _usualCategoryIdMeta,
        ),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    if (data.containsKey('system_role')) {
      context.handle(
        _systemRoleMeta,
        systemRole.isAcceptableOrUnknown(data['system_role']!, _systemRoleMeta),
      );
    }
    if (data.containsKey('member_id')) {
      context.handle(
        _memberIdMeta,
        memberId.isAcceptableOrUnknown(data['member_id']!, _memberIdMeta),
      );
    }
    if (data.containsKey('counterpart_book_id')) {
      context.handle(
        _counterpartBookIdMeta,
        counterpartBookId.isAcceptableOrUnknown(
          data['counterpart_book_id']!,
          _counterpartBookIdMeta,
        ),
      );
    }
    if (data.containsKey('created_order')) {
      context.handle(
        _createdOrderMeta,
        createdOrder.isAcceptableOrUnknown(
          data['created_order']!,
          _createdOrderMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AccountsPData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AccountsPData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      accountClass: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}class'],
      )!,
      moneySubtype: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}money_subtype'],
      ),
      collectionIncomeAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection_income_account_id'],
      ),
      usualCategoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}usual_category_id'],
      ),
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}archived'],
      )!,
      systemRole: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}system_role'],
      ),
      memberId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}member_id'],
      ),
      counterpartBookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}counterpart_book_id'],
      ),
      createdOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_order'],
      )!,
    );
  }

  @override
  $AccountsPTable createAlias(String alias) {
    return $AccountsPTable(attachedDatabase, alias);
  }
}

class AccountsPData extends DataClass implements Insertable<AccountsPData> {
  /// Account id.
  final String id;

  /// Book.
  final String bookId;

  /// Name.
  final String name;

  /// Engine class wire name.
  final String accountClass;

  /// cash | cash_collection | saving | current | od | cc | loan | wallet.
  final String? moneySubtype;

  /// cash_collection: where counts post income (02 §8.2).
  final String? collectionIncomeAccountId;

  /// Usual category for quick entry (02 §1.2).
  final String? usualCategoryId;

  /// 1 when archived.
  final int archived;

  /// equity_system role wire name.
  final String? systemRole;

  /// Member for advance / partner accounts.
  final String? memberId;

  /// Counterpart book for Due to/from accounts (02 §6).
  final String? counterpartBookId;

  /// Creation order within the chart.
  final int createdOrder;
  const AccountsPData({
    required this.id,
    required this.bookId,
    required this.name,
    required this.accountClass,
    this.moneySubtype,
    this.collectionIncomeAccountId,
    this.usualCategoryId,
    required this.archived,
    this.systemRole,
    this.memberId,
    this.counterpartBookId,
    required this.createdOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['name'] = Variable<String>(name);
    map['class'] = Variable<String>(accountClass);
    if (!nullToAbsent || moneySubtype != null) {
      map['money_subtype'] = Variable<String>(moneySubtype);
    }
    if (!nullToAbsent || collectionIncomeAccountId != null) {
      map['collection_income_account_id'] = Variable<String>(
        collectionIncomeAccountId,
      );
    }
    if (!nullToAbsent || usualCategoryId != null) {
      map['usual_category_id'] = Variable<String>(usualCategoryId);
    }
    map['archived'] = Variable<int>(archived);
    if (!nullToAbsent || systemRole != null) {
      map['system_role'] = Variable<String>(systemRole);
    }
    if (!nullToAbsent || memberId != null) {
      map['member_id'] = Variable<String>(memberId);
    }
    if (!nullToAbsent || counterpartBookId != null) {
      map['counterpart_book_id'] = Variable<String>(counterpartBookId);
    }
    map['created_order'] = Variable<int>(createdOrder);
    return map;
  }

  AccountsPCompanion toCompanion(bool nullToAbsent) {
    return AccountsPCompanion(
      id: Value(id),
      bookId: Value(bookId),
      name: Value(name),
      accountClass: Value(accountClass),
      moneySubtype: moneySubtype == null && nullToAbsent
          ? const Value.absent()
          : Value(moneySubtype),
      collectionIncomeAccountId:
          collectionIncomeAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(collectionIncomeAccountId),
      usualCategoryId: usualCategoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(usualCategoryId),
      archived: Value(archived),
      systemRole: systemRole == null && nullToAbsent
          ? const Value.absent()
          : Value(systemRole),
      memberId: memberId == null && nullToAbsent
          ? const Value.absent()
          : Value(memberId),
      counterpartBookId: counterpartBookId == null && nullToAbsent
          ? const Value.absent()
          : Value(counterpartBookId),
      createdOrder: Value(createdOrder),
    );
  }

  factory AccountsPData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AccountsPData(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      name: serializer.fromJson<String>(json['name']),
      accountClass: serializer.fromJson<String>(json['accountClass']),
      moneySubtype: serializer.fromJson<String?>(json['moneySubtype']),
      collectionIncomeAccountId: serializer.fromJson<String?>(
        json['collectionIncomeAccountId'],
      ),
      usualCategoryId: serializer.fromJson<String?>(json['usualCategoryId']),
      archived: serializer.fromJson<int>(json['archived']),
      systemRole: serializer.fromJson<String?>(json['systemRole']),
      memberId: serializer.fromJson<String?>(json['memberId']),
      counterpartBookId: serializer.fromJson<String?>(
        json['counterpartBookId'],
      ),
      createdOrder: serializer.fromJson<int>(json['createdOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'name': serializer.toJson<String>(name),
      'accountClass': serializer.toJson<String>(accountClass),
      'moneySubtype': serializer.toJson<String?>(moneySubtype),
      'collectionIncomeAccountId': serializer.toJson<String?>(
        collectionIncomeAccountId,
      ),
      'usualCategoryId': serializer.toJson<String?>(usualCategoryId),
      'archived': serializer.toJson<int>(archived),
      'systemRole': serializer.toJson<String?>(systemRole),
      'memberId': serializer.toJson<String?>(memberId),
      'counterpartBookId': serializer.toJson<String?>(counterpartBookId),
      'createdOrder': serializer.toJson<int>(createdOrder),
    };
  }

  AccountsPData copyWith({
    String? id,
    String? bookId,
    String? name,
    String? accountClass,
    Value<String?> moneySubtype = const Value.absent(),
    Value<String?> collectionIncomeAccountId = const Value.absent(),
    Value<String?> usualCategoryId = const Value.absent(),
    int? archived,
    Value<String?> systemRole = const Value.absent(),
    Value<String?> memberId = const Value.absent(),
    Value<String?> counterpartBookId = const Value.absent(),
    int? createdOrder,
  }) => AccountsPData(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    name: name ?? this.name,
    accountClass: accountClass ?? this.accountClass,
    moneySubtype: moneySubtype.present ? moneySubtype.value : this.moneySubtype,
    collectionIncomeAccountId: collectionIncomeAccountId.present
        ? collectionIncomeAccountId.value
        : this.collectionIncomeAccountId,
    usualCategoryId: usualCategoryId.present
        ? usualCategoryId.value
        : this.usualCategoryId,
    archived: archived ?? this.archived,
    systemRole: systemRole.present ? systemRole.value : this.systemRole,
    memberId: memberId.present ? memberId.value : this.memberId,
    counterpartBookId: counterpartBookId.present
        ? counterpartBookId.value
        : this.counterpartBookId,
    createdOrder: createdOrder ?? this.createdOrder,
  );
  AccountsPData copyWithCompanion(AccountsPCompanion data) {
    return AccountsPData(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      name: data.name.present ? data.name.value : this.name,
      accountClass: data.accountClass.present
          ? data.accountClass.value
          : this.accountClass,
      moneySubtype: data.moneySubtype.present
          ? data.moneySubtype.value
          : this.moneySubtype,
      collectionIncomeAccountId: data.collectionIncomeAccountId.present
          ? data.collectionIncomeAccountId.value
          : this.collectionIncomeAccountId,
      usualCategoryId: data.usualCategoryId.present
          ? data.usualCategoryId.value
          : this.usualCategoryId,
      archived: data.archived.present ? data.archived.value : this.archived,
      systemRole: data.systemRole.present
          ? data.systemRole.value
          : this.systemRole,
      memberId: data.memberId.present ? data.memberId.value : this.memberId,
      counterpartBookId: data.counterpartBookId.present
          ? data.counterpartBookId.value
          : this.counterpartBookId,
      createdOrder: data.createdOrder.present
          ? data.createdOrder.value
          : this.createdOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AccountsPData(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('name: $name, ')
          ..write('accountClass: $accountClass, ')
          ..write('moneySubtype: $moneySubtype, ')
          ..write('collectionIncomeAccountId: $collectionIncomeAccountId, ')
          ..write('usualCategoryId: $usualCategoryId, ')
          ..write('archived: $archived, ')
          ..write('systemRole: $systemRole, ')
          ..write('memberId: $memberId, ')
          ..write('counterpartBookId: $counterpartBookId, ')
          ..write('createdOrder: $createdOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    name,
    accountClass,
    moneySubtype,
    collectionIncomeAccountId,
    usualCategoryId,
    archived,
    systemRole,
    memberId,
    counterpartBookId,
    createdOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountsPData &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.name == this.name &&
          other.accountClass == this.accountClass &&
          other.moneySubtype == this.moneySubtype &&
          other.collectionIncomeAccountId == this.collectionIncomeAccountId &&
          other.usualCategoryId == this.usualCategoryId &&
          other.archived == this.archived &&
          other.systemRole == this.systemRole &&
          other.memberId == this.memberId &&
          other.counterpartBookId == this.counterpartBookId &&
          other.createdOrder == this.createdOrder);
}

class AccountsPCompanion extends UpdateCompanion<AccountsPData> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<String> name;
  final Value<String> accountClass;
  final Value<String?> moneySubtype;
  final Value<String?> collectionIncomeAccountId;
  final Value<String?> usualCategoryId;
  final Value<int> archived;
  final Value<String?> systemRole;
  final Value<String?> memberId;
  final Value<String?> counterpartBookId;
  final Value<int> createdOrder;
  final Value<int> rowid;
  const AccountsPCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.name = const Value.absent(),
    this.accountClass = const Value.absent(),
    this.moneySubtype = const Value.absent(),
    this.collectionIncomeAccountId = const Value.absent(),
    this.usualCategoryId = const Value.absent(),
    this.archived = const Value.absent(),
    this.systemRole = const Value.absent(),
    this.memberId = const Value.absent(),
    this.counterpartBookId = const Value.absent(),
    this.createdOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountsPCompanion.insert({
    required String id,
    required String bookId,
    required String name,
    required String accountClass,
    this.moneySubtype = const Value.absent(),
    this.collectionIncomeAccountId = const Value.absent(),
    this.usualCategoryId = const Value.absent(),
    this.archived = const Value.absent(),
    this.systemRole = const Value.absent(),
    this.memberId = const Value.absent(),
    this.counterpartBookId = const Value.absent(),
    required int createdOrder,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bookId = Value(bookId),
       name = Value(name),
       accountClass = Value(accountClass),
       createdOrder = Value(createdOrder);
  static Insertable<AccountsPData> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<String>? name,
    Expression<String>? accountClass,
    Expression<String>? moneySubtype,
    Expression<String>? collectionIncomeAccountId,
    Expression<String>? usualCategoryId,
    Expression<int>? archived,
    Expression<String>? systemRole,
    Expression<String>? memberId,
    Expression<String>? counterpartBookId,
    Expression<int>? createdOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (name != null) 'name': name,
      if (accountClass != null) 'class': accountClass,
      if (moneySubtype != null) 'money_subtype': moneySubtype,
      if (collectionIncomeAccountId != null)
        'collection_income_account_id': collectionIncomeAccountId,
      if (usualCategoryId != null) 'usual_category_id': usualCategoryId,
      if (archived != null) 'archived': archived,
      if (systemRole != null) 'system_role': systemRole,
      if (memberId != null) 'member_id': memberId,
      if (counterpartBookId != null) 'counterpart_book_id': counterpartBookId,
      if (createdOrder != null) 'created_order': createdOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountsPCompanion copyWith({
    Value<String>? id,
    Value<String>? bookId,
    Value<String>? name,
    Value<String>? accountClass,
    Value<String?>? moneySubtype,
    Value<String?>? collectionIncomeAccountId,
    Value<String?>? usualCategoryId,
    Value<int>? archived,
    Value<String?>? systemRole,
    Value<String?>? memberId,
    Value<String?>? counterpartBookId,
    Value<int>? createdOrder,
    Value<int>? rowid,
  }) {
    return AccountsPCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      name: name ?? this.name,
      accountClass: accountClass ?? this.accountClass,
      moneySubtype: moneySubtype ?? this.moneySubtype,
      collectionIncomeAccountId:
          collectionIncomeAccountId ?? this.collectionIncomeAccountId,
      usualCategoryId: usualCategoryId ?? this.usualCategoryId,
      archived: archived ?? this.archived,
      systemRole: systemRole ?? this.systemRole,
      memberId: memberId ?? this.memberId,
      counterpartBookId: counterpartBookId ?? this.counterpartBookId,
      createdOrder: createdOrder ?? this.createdOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (accountClass.present) {
      map['class'] = Variable<String>(accountClass.value);
    }
    if (moneySubtype.present) {
      map['money_subtype'] = Variable<String>(moneySubtype.value);
    }
    if (collectionIncomeAccountId.present) {
      map['collection_income_account_id'] = Variable<String>(
        collectionIncomeAccountId.value,
      );
    }
    if (usualCategoryId.present) {
      map['usual_category_id'] = Variable<String>(usualCategoryId.value);
    }
    if (archived.present) {
      map['archived'] = Variable<int>(archived.value);
    }
    if (systemRole.present) {
      map['system_role'] = Variable<String>(systemRole.value);
    }
    if (memberId.present) {
      map['member_id'] = Variable<String>(memberId.value);
    }
    if (counterpartBookId.present) {
      map['counterpart_book_id'] = Variable<String>(counterpartBookId.value);
    }
    if (createdOrder.present) {
      map['created_order'] = Variable<int>(createdOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsPCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('name: $name, ')
          ..write('accountClass: $accountClass, ')
          ..write('moneySubtype: $moneySubtype, ')
          ..write('collectionIncomeAccountId: $collectionIncomeAccountId, ')
          ..write('usualCategoryId: $usualCategoryId, ')
          ..write('archived: $archived, ')
          ..write('systemRole: $systemRole, ')
          ..write('memberId: $memberId, ')
          ..write('counterpartBookId: $counterpartBookId, ')
          ..write('createdOrder: $createdOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EntriesPTable extends EntriesP
    with TableInfo<$EntriesPTable, EntriesPData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntriesPTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountingDateMeta = const VerificationMeta(
    'accountingDate',
  );
  @override
  late final GeneratedColumn<String> accountingDate = GeneratedColumn<String>(
    'accounting_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _channelMeta = const VerificationMeta(
    'channel',
  );
  @override
  late final GeneratedColumn<String> channel = GeneratedColumn<String>(
    'channel',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _partyIdMeta = const VerificationMeta(
    'partyId',
  );
  @override
  late final GeneratedColumn<String> partyId = GeneratedColumn<String>(
    'party_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _advanceRefMeta = const VerificationMeta(
    'advanceRef',
  );
  @override
  late final GeneratedColumn<String> advanceRef = GeneratedColumn<String>(
    'advance_ref',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _transferGroupMeta = const VerificationMeta(
    'transferGroup',
  );
  @override
  late final GeneratedColumn<String> transferGroup = GeneratedColumn<String>(
    'transfer_group',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _amendsMeta = const VerificationMeta('amends');
  @override
  late final GeneratedColumn<String> amends = GeneratedColumn<String>(
    'amends',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reversesMeta = const VerificationMeta(
    'reverses',
  );
  @override
  late final GeneratedColumn<String> reverses = GeneratedColumn<String>(
    'reverses',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _supersededByMeta = const VerificationMeta(
    'supersededBy',
  );
  @override
  late final GeneratedColumn<String> supersededBy = GeneratedColumn<String>(
    'superseded_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reviewStateMeta = const VerificationMeta(
    'reviewState',
  );
  @override
  late final GeneratedColumn<String> reviewState = GeneratedColumn<String>(
    'review_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'none\' CHECK (review_state IN (\'none\',\'open\',\'approved\',\'rejected\'))',
    defaultValue: const CustomExpression('\'none\''),
  );
  static const VerificationMeta _reviewApproverMeta = const VerificationMeta(
    'reviewApprover',
  );
  @override
  late final GeneratedColumn<String> reviewApprover = GeneratedColumn<String>(
    'review_approver',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reviewDecidedHlcMeta = const VerificationMeta(
    'reviewDecidedHlc',
  );
  @override
  late final GeneratedColumn<int> reviewDecidedHlc = GeneratedColumn<int>(
    'review_decided_hlc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reviewReasonMeta = const VerificationMeta(
    'reviewReason',
  );
  @override
  late final GeneratedColumn<String> reviewReason = GeneratedColumn<String>(
    'review_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByUserMeta = const VerificationMeta(
    'createdByUser',
  );
  @override
  late final GeneratedColumn<String> createdByUser = GeneratedColumn<String>(
    'created_by_user',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<int> hlc = GeneratedColumn<int>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    kind,
    status,
    accountingDate,
    note,
    channel,
    partyId,
    advanceRef,
    transferGroup,
    amends,
    reverses,
    supersededBy,
    reviewState,
    reviewApprover,
    reviewDecidedHlc,
    reviewReason,
    createdByUser,
    hlc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entries_p';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntriesPData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('accounting_date')) {
      context.handle(
        _accountingDateMeta,
        accountingDate.isAcceptableOrUnknown(
          data['accounting_date']!,
          _accountingDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_accountingDateMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('channel')) {
      context.handle(
        _channelMeta,
        channel.isAcceptableOrUnknown(data['channel']!, _channelMeta),
      );
    }
    if (data.containsKey('party_id')) {
      context.handle(
        _partyIdMeta,
        partyId.isAcceptableOrUnknown(data['party_id']!, _partyIdMeta),
      );
    }
    if (data.containsKey('advance_ref')) {
      context.handle(
        _advanceRefMeta,
        advanceRef.isAcceptableOrUnknown(data['advance_ref']!, _advanceRefMeta),
      );
    }
    if (data.containsKey('transfer_group')) {
      context.handle(
        _transferGroupMeta,
        transferGroup.isAcceptableOrUnknown(
          data['transfer_group']!,
          _transferGroupMeta,
        ),
      );
    }
    if (data.containsKey('amends')) {
      context.handle(
        _amendsMeta,
        amends.isAcceptableOrUnknown(data['amends']!, _amendsMeta),
      );
    }
    if (data.containsKey('reverses')) {
      context.handle(
        _reversesMeta,
        reverses.isAcceptableOrUnknown(data['reverses']!, _reversesMeta),
      );
    }
    if (data.containsKey('superseded_by')) {
      context.handle(
        _supersededByMeta,
        supersededBy.isAcceptableOrUnknown(
          data['superseded_by']!,
          _supersededByMeta,
        ),
      );
    }
    if (data.containsKey('review_state')) {
      context.handle(
        _reviewStateMeta,
        reviewState.isAcceptableOrUnknown(
          data['review_state']!,
          _reviewStateMeta,
        ),
      );
    }
    if (data.containsKey('review_approver')) {
      context.handle(
        _reviewApproverMeta,
        reviewApprover.isAcceptableOrUnknown(
          data['review_approver']!,
          _reviewApproverMeta,
        ),
      );
    }
    if (data.containsKey('review_decided_hlc')) {
      context.handle(
        _reviewDecidedHlcMeta,
        reviewDecidedHlc.isAcceptableOrUnknown(
          data['review_decided_hlc']!,
          _reviewDecidedHlcMeta,
        ),
      );
    }
    if (data.containsKey('review_reason')) {
      context.handle(
        _reviewReasonMeta,
        reviewReason.isAcceptableOrUnknown(
          data['review_reason']!,
          _reviewReasonMeta,
        ),
      );
    }
    if (data.containsKey('created_by_user')) {
      context.handle(
        _createdByUserMeta,
        createdByUser.isAcceptableOrUnknown(
          data['created_by_user']!,
          _createdByUserMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdByUserMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EntriesPData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntriesPData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      accountingDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}accounting_date'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      channel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel'],
      ),
      partyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}party_id'],
      ),
      advanceRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}advance_ref'],
      ),
      transferGroup: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transfer_group'],
      ),
      amends: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}amends'],
      ),
      reverses: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reverses'],
      ),
      supersededBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}superseded_by'],
      ),
      reviewState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_state'],
      )!,
      reviewApprover: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_approver'],
      ),
      reviewDecidedHlc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}review_decided_hlc'],
      ),
      reviewReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_reason'],
      ),
      createdByUser: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by_user'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hlc'],
      )!,
    );
  }

  @override
  $EntriesPTable createAlias(String alias) {
    return $EntriesPTable(attachedDatabase, alias);
  }
}

class EntriesPData extends DataClass implements Insertable<EntriesPData> {
  /// Entry id.
  final String id;

  /// Book.
  final String bookId;

  /// Verb wire name.
  final String kind;

  /// Effective status wire name: posted | pending | rejected | superseded |
  /// void | in_tray (⚠️ SPEC: 03 §3.2 does not enumerate; these are
  /// `core_ledger.EffectiveStatus` in 02 §1.3 spelling).
  final String status;

  /// ISO date.
  final String accountingDate;

  /// Note.
  final String? note;

  /// Channel tag.
  final String? channel;

  /// Party.
  final String? partyId;

  /// Advance the entry belongs to (02 §7).
  final String? advanceRef;

  /// Inter-book pair id (02 §6).
  final String? transferGroup;

  /// Amended entry.
  final String? amends;

  /// Reversed entry.
  final String? reverses;

  /// The amendment that replaced this entry; null = head of the chain.
  final String? supersededBy;

  /// Review flag (02 §3).
  final String reviewState;

  /// Who must act, then who acted.
  final String? reviewApprover;

  /// HLC of the decision.
  final int? reviewDecidedHlc;

  /// Required on rejected.
  final String? reviewReason;

  /// Author.
  final String createdByUser;

  /// HLC.
  final int hlc;
  const EntriesPData({
    required this.id,
    required this.bookId,
    required this.kind,
    required this.status,
    required this.accountingDate,
    this.note,
    this.channel,
    this.partyId,
    this.advanceRef,
    this.transferGroup,
    this.amends,
    this.reverses,
    this.supersededBy,
    required this.reviewState,
    this.reviewApprover,
    this.reviewDecidedHlc,
    this.reviewReason,
    required this.createdByUser,
    required this.hlc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['kind'] = Variable<String>(kind);
    map['status'] = Variable<String>(status);
    map['accounting_date'] = Variable<String>(accountingDate);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || channel != null) {
      map['channel'] = Variable<String>(channel);
    }
    if (!nullToAbsent || partyId != null) {
      map['party_id'] = Variable<String>(partyId);
    }
    if (!nullToAbsent || advanceRef != null) {
      map['advance_ref'] = Variable<String>(advanceRef);
    }
    if (!nullToAbsent || transferGroup != null) {
      map['transfer_group'] = Variable<String>(transferGroup);
    }
    if (!nullToAbsent || amends != null) {
      map['amends'] = Variable<String>(amends);
    }
    if (!nullToAbsent || reverses != null) {
      map['reverses'] = Variable<String>(reverses);
    }
    if (!nullToAbsent || supersededBy != null) {
      map['superseded_by'] = Variable<String>(supersededBy);
    }
    map['review_state'] = Variable<String>(reviewState);
    if (!nullToAbsent || reviewApprover != null) {
      map['review_approver'] = Variable<String>(reviewApprover);
    }
    if (!nullToAbsent || reviewDecidedHlc != null) {
      map['review_decided_hlc'] = Variable<int>(reviewDecidedHlc);
    }
    if (!nullToAbsent || reviewReason != null) {
      map['review_reason'] = Variable<String>(reviewReason);
    }
    map['created_by_user'] = Variable<String>(createdByUser);
    map['hlc'] = Variable<int>(hlc);
    return map;
  }

  EntriesPCompanion toCompanion(bool nullToAbsent) {
    return EntriesPCompanion(
      id: Value(id),
      bookId: Value(bookId),
      kind: Value(kind),
      status: Value(status),
      accountingDate: Value(accountingDate),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      channel: channel == null && nullToAbsent
          ? const Value.absent()
          : Value(channel),
      partyId: partyId == null && nullToAbsent
          ? const Value.absent()
          : Value(partyId),
      advanceRef: advanceRef == null && nullToAbsent
          ? const Value.absent()
          : Value(advanceRef),
      transferGroup: transferGroup == null && nullToAbsent
          ? const Value.absent()
          : Value(transferGroup),
      amends: amends == null && nullToAbsent
          ? const Value.absent()
          : Value(amends),
      reverses: reverses == null && nullToAbsent
          ? const Value.absent()
          : Value(reverses),
      supersededBy: supersededBy == null && nullToAbsent
          ? const Value.absent()
          : Value(supersededBy),
      reviewState: Value(reviewState),
      reviewApprover: reviewApprover == null && nullToAbsent
          ? const Value.absent()
          : Value(reviewApprover),
      reviewDecidedHlc: reviewDecidedHlc == null && nullToAbsent
          ? const Value.absent()
          : Value(reviewDecidedHlc),
      reviewReason: reviewReason == null && nullToAbsent
          ? const Value.absent()
          : Value(reviewReason),
      createdByUser: Value(createdByUser),
      hlc: Value(hlc),
    );
  }

  factory EntriesPData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntriesPData(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      kind: serializer.fromJson<String>(json['kind']),
      status: serializer.fromJson<String>(json['status']),
      accountingDate: serializer.fromJson<String>(json['accountingDate']),
      note: serializer.fromJson<String?>(json['note']),
      channel: serializer.fromJson<String?>(json['channel']),
      partyId: serializer.fromJson<String?>(json['partyId']),
      advanceRef: serializer.fromJson<String?>(json['advanceRef']),
      transferGroup: serializer.fromJson<String?>(json['transferGroup']),
      amends: serializer.fromJson<String?>(json['amends']),
      reverses: serializer.fromJson<String?>(json['reverses']),
      supersededBy: serializer.fromJson<String?>(json['supersededBy']),
      reviewState: serializer.fromJson<String>(json['reviewState']),
      reviewApprover: serializer.fromJson<String?>(json['reviewApprover']),
      reviewDecidedHlc: serializer.fromJson<int?>(json['reviewDecidedHlc']),
      reviewReason: serializer.fromJson<String?>(json['reviewReason']),
      createdByUser: serializer.fromJson<String>(json['createdByUser']),
      hlc: serializer.fromJson<int>(json['hlc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'kind': serializer.toJson<String>(kind),
      'status': serializer.toJson<String>(status),
      'accountingDate': serializer.toJson<String>(accountingDate),
      'note': serializer.toJson<String?>(note),
      'channel': serializer.toJson<String?>(channel),
      'partyId': serializer.toJson<String?>(partyId),
      'advanceRef': serializer.toJson<String?>(advanceRef),
      'transferGroup': serializer.toJson<String?>(transferGroup),
      'amends': serializer.toJson<String?>(amends),
      'reverses': serializer.toJson<String?>(reverses),
      'supersededBy': serializer.toJson<String?>(supersededBy),
      'reviewState': serializer.toJson<String>(reviewState),
      'reviewApprover': serializer.toJson<String?>(reviewApprover),
      'reviewDecidedHlc': serializer.toJson<int?>(reviewDecidedHlc),
      'reviewReason': serializer.toJson<String?>(reviewReason),
      'createdByUser': serializer.toJson<String>(createdByUser),
      'hlc': serializer.toJson<int>(hlc),
    };
  }

  EntriesPData copyWith({
    String? id,
    String? bookId,
    String? kind,
    String? status,
    String? accountingDate,
    Value<String?> note = const Value.absent(),
    Value<String?> channel = const Value.absent(),
    Value<String?> partyId = const Value.absent(),
    Value<String?> advanceRef = const Value.absent(),
    Value<String?> transferGroup = const Value.absent(),
    Value<String?> amends = const Value.absent(),
    Value<String?> reverses = const Value.absent(),
    Value<String?> supersededBy = const Value.absent(),
    String? reviewState,
    Value<String?> reviewApprover = const Value.absent(),
    Value<int?> reviewDecidedHlc = const Value.absent(),
    Value<String?> reviewReason = const Value.absent(),
    String? createdByUser,
    int? hlc,
  }) => EntriesPData(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    accountingDate: accountingDate ?? this.accountingDate,
    note: note.present ? note.value : this.note,
    channel: channel.present ? channel.value : this.channel,
    partyId: partyId.present ? partyId.value : this.partyId,
    advanceRef: advanceRef.present ? advanceRef.value : this.advanceRef,
    transferGroup: transferGroup.present
        ? transferGroup.value
        : this.transferGroup,
    amends: amends.present ? amends.value : this.amends,
    reverses: reverses.present ? reverses.value : this.reverses,
    supersededBy: supersededBy.present ? supersededBy.value : this.supersededBy,
    reviewState: reviewState ?? this.reviewState,
    reviewApprover: reviewApprover.present
        ? reviewApprover.value
        : this.reviewApprover,
    reviewDecidedHlc: reviewDecidedHlc.present
        ? reviewDecidedHlc.value
        : this.reviewDecidedHlc,
    reviewReason: reviewReason.present ? reviewReason.value : this.reviewReason,
    createdByUser: createdByUser ?? this.createdByUser,
    hlc: hlc ?? this.hlc,
  );
  EntriesPData copyWithCompanion(EntriesPCompanion data) {
    return EntriesPData(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      kind: data.kind.present ? data.kind.value : this.kind,
      status: data.status.present ? data.status.value : this.status,
      accountingDate: data.accountingDate.present
          ? data.accountingDate.value
          : this.accountingDate,
      note: data.note.present ? data.note.value : this.note,
      channel: data.channel.present ? data.channel.value : this.channel,
      partyId: data.partyId.present ? data.partyId.value : this.partyId,
      advanceRef: data.advanceRef.present
          ? data.advanceRef.value
          : this.advanceRef,
      transferGroup: data.transferGroup.present
          ? data.transferGroup.value
          : this.transferGroup,
      amends: data.amends.present ? data.amends.value : this.amends,
      reverses: data.reverses.present ? data.reverses.value : this.reverses,
      supersededBy: data.supersededBy.present
          ? data.supersededBy.value
          : this.supersededBy,
      reviewState: data.reviewState.present
          ? data.reviewState.value
          : this.reviewState,
      reviewApprover: data.reviewApprover.present
          ? data.reviewApprover.value
          : this.reviewApprover,
      reviewDecidedHlc: data.reviewDecidedHlc.present
          ? data.reviewDecidedHlc.value
          : this.reviewDecidedHlc,
      reviewReason: data.reviewReason.present
          ? data.reviewReason.value
          : this.reviewReason,
      createdByUser: data.createdByUser.present
          ? data.createdByUser.value
          : this.createdByUser,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntriesPData(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('accountingDate: $accountingDate, ')
          ..write('note: $note, ')
          ..write('channel: $channel, ')
          ..write('partyId: $partyId, ')
          ..write('advanceRef: $advanceRef, ')
          ..write('transferGroup: $transferGroup, ')
          ..write('amends: $amends, ')
          ..write('reverses: $reverses, ')
          ..write('supersededBy: $supersededBy, ')
          ..write('reviewState: $reviewState, ')
          ..write('reviewApprover: $reviewApprover, ')
          ..write('reviewDecidedHlc: $reviewDecidedHlc, ')
          ..write('reviewReason: $reviewReason, ')
          ..write('createdByUser: $createdByUser, ')
          ..write('hlc: $hlc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    kind,
    status,
    accountingDate,
    note,
    channel,
    partyId,
    advanceRef,
    transferGroup,
    amends,
    reverses,
    supersededBy,
    reviewState,
    reviewApprover,
    reviewDecidedHlc,
    reviewReason,
    createdByUser,
    hlc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntriesPData &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.kind == this.kind &&
          other.status == this.status &&
          other.accountingDate == this.accountingDate &&
          other.note == this.note &&
          other.channel == this.channel &&
          other.partyId == this.partyId &&
          other.advanceRef == this.advanceRef &&
          other.transferGroup == this.transferGroup &&
          other.amends == this.amends &&
          other.reverses == this.reverses &&
          other.supersededBy == this.supersededBy &&
          other.reviewState == this.reviewState &&
          other.reviewApprover == this.reviewApprover &&
          other.reviewDecidedHlc == this.reviewDecidedHlc &&
          other.reviewReason == this.reviewReason &&
          other.createdByUser == this.createdByUser &&
          other.hlc == this.hlc);
}

class EntriesPCompanion extends UpdateCompanion<EntriesPData> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<String> kind;
  final Value<String> status;
  final Value<String> accountingDate;
  final Value<String?> note;
  final Value<String?> channel;
  final Value<String?> partyId;
  final Value<String?> advanceRef;
  final Value<String?> transferGroup;
  final Value<String?> amends;
  final Value<String?> reverses;
  final Value<String?> supersededBy;
  final Value<String> reviewState;
  final Value<String?> reviewApprover;
  final Value<int?> reviewDecidedHlc;
  final Value<String?> reviewReason;
  final Value<String> createdByUser;
  final Value<int> hlc;
  final Value<int> rowid;
  const EntriesPCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.kind = const Value.absent(),
    this.status = const Value.absent(),
    this.accountingDate = const Value.absent(),
    this.note = const Value.absent(),
    this.channel = const Value.absent(),
    this.partyId = const Value.absent(),
    this.advanceRef = const Value.absent(),
    this.transferGroup = const Value.absent(),
    this.amends = const Value.absent(),
    this.reverses = const Value.absent(),
    this.supersededBy = const Value.absent(),
    this.reviewState = const Value.absent(),
    this.reviewApprover = const Value.absent(),
    this.reviewDecidedHlc = const Value.absent(),
    this.reviewReason = const Value.absent(),
    this.createdByUser = const Value.absent(),
    this.hlc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntriesPCompanion.insert({
    required String id,
    required String bookId,
    required String kind,
    required String status,
    required String accountingDate,
    this.note = const Value.absent(),
    this.channel = const Value.absent(),
    this.partyId = const Value.absent(),
    this.advanceRef = const Value.absent(),
    this.transferGroup = const Value.absent(),
    this.amends = const Value.absent(),
    this.reverses = const Value.absent(),
    this.supersededBy = const Value.absent(),
    this.reviewState = const Value.absent(),
    this.reviewApprover = const Value.absent(),
    this.reviewDecidedHlc = const Value.absent(),
    this.reviewReason = const Value.absent(),
    required String createdByUser,
    required int hlc,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bookId = Value(bookId),
       kind = Value(kind),
       status = Value(status),
       accountingDate = Value(accountingDate),
       createdByUser = Value(createdByUser),
       hlc = Value(hlc);
  static Insertable<EntriesPData> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<String>? kind,
    Expression<String>? status,
    Expression<String>? accountingDate,
    Expression<String>? note,
    Expression<String>? channel,
    Expression<String>? partyId,
    Expression<String>? advanceRef,
    Expression<String>? transferGroup,
    Expression<String>? amends,
    Expression<String>? reverses,
    Expression<String>? supersededBy,
    Expression<String>? reviewState,
    Expression<String>? reviewApprover,
    Expression<int>? reviewDecidedHlc,
    Expression<String>? reviewReason,
    Expression<String>? createdByUser,
    Expression<int>? hlc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (kind != null) 'kind': kind,
      if (status != null) 'status': status,
      if (accountingDate != null) 'accounting_date': accountingDate,
      if (note != null) 'note': note,
      if (channel != null) 'channel': channel,
      if (partyId != null) 'party_id': partyId,
      if (advanceRef != null) 'advance_ref': advanceRef,
      if (transferGroup != null) 'transfer_group': transferGroup,
      if (amends != null) 'amends': amends,
      if (reverses != null) 'reverses': reverses,
      if (supersededBy != null) 'superseded_by': supersededBy,
      if (reviewState != null) 'review_state': reviewState,
      if (reviewApprover != null) 'review_approver': reviewApprover,
      if (reviewDecidedHlc != null) 'review_decided_hlc': reviewDecidedHlc,
      if (reviewReason != null) 'review_reason': reviewReason,
      if (createdByUser != null) 'created_by_user': createdByUser,
      if (hlc != null) 'hlc': hlc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntriesPCompanion copyWith({
    Value<String>? id,
    Value<String>? bookId,
    Value<String>? kind,
    Value<String>? status,
    Value<String>? accountingDate,
    Value<String?>? note,
    Value<String?>? channel,
    Value<String?>? partyId,
    Value<String?>? advanceRef,
    Value<String?>? transferGroup,
    Value<String?>? amends,
    Value<String?>? reverses,
    Value<String?>? supersededBy,
    Value<String>? reviewState,
    Value<String?>? reviewApprover,
    Value<int?>? reviewDecidedHlc,
    Value<String?>? reviewReason,
    Value<String>? createdByUser,
    Value<int>? hlc,
    Value<int>? rowid,
  }) {
    return EntriesPCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      accountingDate: accountingDate ?? this.accountingDate,
      note: note ?? this.note,
      channel: channel ?? this.channel,
      partyId: partyId ?? this.partyId,
      advanceRef: advanceRef ?? this.advanceRef,
      transferGroup: transferGroup ?? this.transferGroup,
      amends: amends ?? this.amends,
      reverses: reverses ?? this.reverses,
      supersededBy: supersededBy ?? this.supersededBy,
      reviewState: reviewState ?? this.reviewState,
      reviewApprover: reviewApprover ?? this.reviewApprover,
      reviewDecidedHlc: reviewDecidedHlc ?? this.reviewDecidedHlc,
      reviewReason: reviewReason ?? this.reviewReason,
      createdByUser: createdByUser ?? this.createdByUser,
      hlc: hlc ?? this.hlc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (accountingDate.present) {
      map['accounting_date'] = Variable<String>(accountingDate.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (channel.present) {
      map['channel'] = Variable<String>(channel.value);
    }
    if (partyId.present) {
      map['party_id'] = Variable<String>(partyId.value);
    }
    if (advanceRef.present) {
      map['advance_ref'] = Variable<String>(advanceRef.value);
    }
    if (transferGroup.present) {
      map['transfer_group'] = Variable<String>(transferGroup.value);
    }
    if (amends.present) {
      map['amends'] = Variable<String>(amends.value);
    }
    if (reverses.present) {
      map['reverses'] = Variable<String>(reverses.value);
    }
    if (supersededBy.present) {
      map['superseded_by'] = Variable<String>(supersededBy.value);
    }
    if (reviewState.present) {
      map['review_state'] = Variable<String>(reviewState.value);
    }
    if (reviewApprover.present) {
      map['review_approver'] = Variable<String>(reviewApprover.value);
    }
    if (reviewDecidedHlc.present) {
      map['review_decided_hlc'] = Variable<int>(reviewDecidedHlc.value);
    }
    if (reviewReason.present) {
      map['review_reason'] = Variable<String>(reviewReason.value);
    }
    if (createdByUser.present) {
      map['created_by_user'] = Variable<String>(createdByUser.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<int>(hlc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntriesPCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('accountingDate: $accountingDate, ')
          ..write('note: $note, ')
          ..write('channel: $channel, ')
          ..write('partyId: $partyId, ')
          ..write('advanceRef: $advanceRef, ')
          ..write('transferGroup: $transferGroup, ')
          ..write('amends: $amends, ')
          ..write('reverses: $reverses, ')
          ..write('supersededBy: $supersededBy, ')
          ..write('reviewState: $reviewState, ')
          ..write('reviewApprover: $reviewApprover, ')
          ..write('reviewDecidedHlc: $reviewDecidedHlc, ')
          ..write('reviewReason: $reviewReason, ')
          ..write('createdByUser: $createdByUser, ')
          ..write('hlc: $hlc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EntryLinesPTable extends EntryLinesP
    with TableInfo<$EntryLinesPTable, EntryLinesPData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntryLinesPTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountPaiseMeta = const VerificationMeta(
    'amountPaise',
  );
  @override
  late final GeneratedColumn<int> amountPaise = GeneratedColumn<int>(
    'amount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountingDateMeta = const VerificationMeta(
    'accountingDate',
  );
  @override
  late final GeneratedColumn<String> accountingDate = GeneratedColumn<String>(
    'accounting_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lineIndexMeta = const VerificationMeta(
    'lineIndex',
  );
  @override
  late final GeneratedColumn<int> lineIndex = GeneratedColumn<int>(
    'line_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    entryId,
    accountId,
    amountPaise,
    bookId,
    accountingDate,
    lineIndex,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entry_lines_p';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntryLinesPData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('amount_paise')) {
      context.handle(
        _amountPaiseMeta,
        amountPaise.isAcceptableOrUnknown(
          data['amount_paise']!,
          _amountPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountPaiseMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('accounting_date')) {
      context.handle(
        _accountingDateMeta,
        accountingDate.isAcceptableOrUnknown(
          data['accounting_date']!,
          _accountingDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_accountingDateMeta);
    }
    if (data.containsKey('line_index')) {
      context.handle(
        _lineIndexMeta,
        lineIndex.isAcceptableOrUnknown(data['line_index']!, _lineIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_lineIndexMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entryId, lineIndex};
  @override
  EntryLinesPData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntryLinesPData(
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      amountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_paise'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      accountingDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}accounting_date'],
      )!,
      lineIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}line_index'],
      )!,
    );
  }

  @override
  $EntryLinesPTable createAlias(String alias) {
    return $EntryLinesPTable(attachedDatabase, alias);
  }
}

class EntryLinesPData extends DataClass implements Insertable<EntryLinesPData> {
  /// Entry.
  final String entryId;

  /// Account.
  final String accountId;

  /// Signed paise: + Dr, − Cr.
  final int amountPaise;

  /// Book.
  final String bookId;

  /// ISO date.
  final String accountingDate;

  /// Position within the entry — keeps line order stable across rebuilds.
  final int lineIndex;
  const EntryLinesPData({
    required this.entryId,
    required this.accountId,
    required this.amountPaise,
    required this.bookId,
    required this.accountingDate,
    required this.lineIndex,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entry_id'] = Variable<String>(entryId);
    map['account_id'] = Variable<String>(accountId);
    map['amount_paise'] = Variable<int>(amountPaise);
    map['book_id'] = Variable<String>(bookId);
    map['accounting_date'] = Variable<String>(accountingDate);
    map['line_index'] = Variable<int>(lineIndex);
    return map;
  }

  EntryLinesPCompanion toCompanion(bool nullToAbsent) {
    return EntryLinesPCompanion(
      entryId: Value(entryId),
      accountId: Value(accountId),
      amountPaise: Value(amountPaise),
      bookId: Value(bookId),
      accountingDate: Value(accountingDate),
      lineIndex: Value(lineIndex),
    );
  }

  factory EntryLinesPData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntryLinesPData(
      entryId: serializer.fromJson<String>(json['entryId']),
      accountId: serializer.fromJson<String>(json['accountId']),
      amountPaise: serializer.fromJson<int>(json['amountPaise']),
      bookId: serializer.fromJson<String>(json['bookId']),
      accountingDate: serializer.fromJson<String>(json['accountingDate']),
      lineIndex: serializer.fromJson<int>(json['lineIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entryId': serializer.toJson<String>(entryId),
      'accountId': serializer.toJson<String>(accountId),
      'amountPaise': serializer.toJson<int>(amountPaise),
      'bookId': serializer.toJson<String>(bookId),
      'accountingDate': serializer.toJson<String>(accountingDate),
      'lineIndex': serializer.toJson<int>(lineIndex),
    };
  }

  EntryLinesPData copyWith({
    String? entryId,
    String? accountId,
    int? amountPaise,
    String? bookId,
    String? accountingDate,
    int? lineIndex,
  }) => EntryLinesPData(
    entryId: entryId ?? this.entryId,
    accountId: accountId ?? this.accountId,
    amountPaise: amountPaise ?? this.amountPaise,
    bookId: bookId ?? this.bookId,
    accountingDate: accountingDate ?? this.accountingDate,
    lineIndex: lineIndex ?? this.lineIndex,
  );
  EntryLinesPData copyWithCompanion(EntryLinesPCompanion data) {
    return EntryLinesPData(
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      amountPaise: data.amountPaise.present
          ? data.amountPaise.value
          : this.amountPaise,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      accountingDate: data.accountingDate.present
          ? data.accountingDate.value
          : this.accountingDate,
      lineIndex: data.lineIndex.present ? data.lineIndex.value : this.lineIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntryLinesPData(')
          ..write('entryId: $entryId, ')
          ..write('accountId: $accountId, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('bookId: $bookId, ')
          ..write('accountingDate: $accountingDate, ')
          ..write('lineIndex: $lineIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    entryId,
    accountId,
    amountPaise,
    bookId,
    accountingDate,
    lineIndex,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntryLinesPData &&
          other.entryId == this.entryId &&
          other.accountId == this.accountId &&
          other.amountPaise == this.amountPaise &&
          other.bookId == this.bookId &&
          other.accountingDate == this.accountingDate &&
          other.lineIndex == this.lineIndex);
}

class EntryLinesPCompanion extends UpdateCompanion<EntryLinesPData> {
  final Value<String> entryId;
  final Value<String> accountId;
  final Value<int> amountPaise;
  final Value<String> bookId;
  final Value<String> accountingDate;
  final Value<int> lineIndex;
  final Value<int> rowid;
  const EntryLinesPCompanion({
    this.entryId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.amountPaise = const Value.absent(),
    this.bookId = const Value.absent(),
    this.accountingDate = const Value.absent(),
    this.lineIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntryLinesPCompanion.insert({
    required String entryId,
    required String accountId,
    required int amountPaise,
    required String bookId,
    required String accountingDate,
    required int lineIndex,
    this.rowid = const Value.absent(),
  }) : entryId = Value(entryId),
       accountId = Value(accountId),
       amountPaise = Value(amountPaise),
       bookId = Value(bookId),
       accountingDate = Value(accountingDate),
       lineIndex = Value(lineIndex);
  static Insertable<EntryLinesPData> custom({
    Expression<String>? entryId,
    Expression<String>? accountId,
    Expression<int>? amountPaise,
    Expression<String>? bookId,
    Expression<String>? accountingDate,
    Expression<int>? lineIndex,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entryId != null) 'entry_id': entryId,
      if (accountId != null) 'account_id': accountId,
      if (amountPaise != null) 'amount_paise': amountPaise,
      if (bookId != null) 'book_id': bookId,
      if (accountingDate != null) 'accounting_date': accountingDate,
      if (lineIndex != null) 'line_index': lineIndex,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntryLinesPCompanion copyWith({
    Value<String>? entryId,
    Value<String>? accountId,
    Value<int>? amountPaise,
    Value<String>? bookId,
    Value<String>? accountingDate,
    Value<int>? lineIndex,
    Value<int>? rowid,
  }) {
    return EntryLinesPCompanion(
      entryId: entryId ?? this.entryId,
      accountId: accountId ?? this.accountId,
      amountPaise: amountPaise ?? this.amountPaise,
      bookId: bookId ?? this.bookId,
      accountingDate: accountingDate ?? this.accountingDate,
      lineIndex: lineIndex ?? this.lineIndex,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (amountPaise.present) {
      map['amount_paise'] = Variable<int>(amountPaise.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (accountingDate.present) {
      map['accounting_date'] = Variable<String>(accountingDate.value);
    }
    if (lineIndex.present) {
      map['line_index'] = Variable<int>(lineIndex.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntryLinesPCompanion(')
          ..write('entryId: $entryId, ')
          ..write('accountId: $accountId, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('bookId: $bookId, ')
          ..write('accountingDate: $accountingDate, ')
          ..write('lineIndex: $lineIndex, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PeriodsPTable extends PeriodsP
    with TableInfo<$PeriodsPTable, PeriodsPData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeriodsPTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _monthMeta = const VerificationMeta('month');
  @override
  late final GeneratedColumn<int> month = GeneratedColumn<int>(
    'month',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lockHlcMeta = const VerificationMeta(
    'lockHlc',
  );
  @override
  late final GeneratedColumn<int> lockHlc = GeneratedColumn<int>(
    'lock_hlc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _verificationMeta = const VerificationMeta(
    'verification',
  );
  @override
  late final GeneratedColumn<String> verification = GeneratedColumn<String>(
    'verification',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookId,
    year,
    month,
    state,
    lockHlc,
    verification,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'periods_p';
  @override
  VerificationContext validateIntegrity(
    Insertable<PeriodsPData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    } else if (isInserting) {
      context.missing(_yearMeta);
    }
    if (data.containsKey('month')) {
      context.handle(
        _monthMeta,
        month.isAcceptableOrUnknown(data['month']!, _monthMeta),
      );
    } else if (isInserting) {
      context.missing(_monthMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('lock_hlc')) {
      context.handle(
        _lockHlcMeta,
        lockHlc.isAcceptableOrUnknown(data['lock_hlc']!, _lockHlcMeta),
      );
    }
    if (data.containsKey('verification')) {
      context.handle(
        _verificationMeta,
        verification.isAcceptableOrUnknown(
          data['verification']!,
          _verificationMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId, year, month};
  @override
  PeriodsPData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PeriodsPData(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      )!,
      month: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}month'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      lockHlc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lock_hlc'],
      ),
      verification: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verification'],
      ),
    );
  }

  @override
  $PeriodsPTable createAlias(String alias) {
    return $PeriodsPTable(attachedDatabase, alias);
  }
}

class PeriodsPData extends DataClass implements Insertable<PeriodsPData> {
  /// Book.
  final String bookId;

  /// Calendar year.
  final int year;

  /// Month 1–12.
  final int month;

  /// open | locked.
  final String state;

  /// HLC of the lock in force.
  final int? lockHlc;

  /// This reader's verification of the lock's published vector (ADR 2026-09-05c
  /// §3): verified | mismatch | reader_outdated | certifier_outdated; null when
  /// the lock published no vector or the month is open.
  final String? verification;
  const PeriodsPData({
    required this.bookId,
    required this.year,
    required this.month,
    required this.state,
    this.lockHlc,
    this.verification,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['year'] = Variable<int>(year);
    map['month'] = Variable<int>(month);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || lockHlc != null) {
      map['lock_hlc'] = Variable<int>(lockHlc);
    }
    if (!nullToAbsent || verification != null) {
      map['verification'] = Variable<String>(verification);
    }
    return map;
  }

  PeriodsPCompanion toCompanion(bool nullToAbsent) {
    return PeriodsPCompanion(
      bookId: Value(bookId),
      year: Value(year),
      month: Value(month),
      state: Value(state),
      lockHlc: lockHlc == null && nullToAbsent
          ? const Value.absent()
          : Value(lockHlc),
      verification: verification == null && nullToAbsent
          ? const Value.absent()
          : Value(verification),
    );
  }

  factory PeriodsPData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PeriodsPData(
      bookId: serializer.fromJson<String>(json['bookId']),
      year: serializer.fromJson<int>(json['year']),
      month: serializer.fromJson<int>(json['month']),
      state: serializer.fromJson<String>(json['state']),
      lockHlc: serializer.fromJson<int?>(json['lockHlc']),
      verification: serializer.fromJson<String?>(json['verification']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'year': serializer.toJson<int>(year),
      'month': serializer.toJson<int>(month),
      'state': serializer.toJson<String>(state),
      'lockHlc': serializer.toJson<int?>(lockHlc),
      'verification': serializer.toJson<String?>(verification),
    };
  }

  PeriodsPData copyWith({
    String? bookId,
    int? year,
    int? month,
    String? state,
    Value<int?> lockHlc = const Value.absent(),
    Value<String?> verification = const Value.absent(),
  }) => PeriodsPData(
    bookId: bookId ?? this.bookId,
    year: year ?? this.year,
    month: month ?? this.month,
    state: state ?? this.state,
    lockHlc: lockHlc.present ? lockHlc.value : this.lockHlc,
    verification: verification.present ? verification.value : this.verification,
  );
  PeriodsPData copyWithCompanion(PeriodsPCompanion data) {
    return PeriodsPData(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      year: data.year.present ? data.year.value : this.year,
      month: data.month.present ? data.month.value : this.month,
      state: data.state.present ? data.state.value : this.state,
      lockHlc: data.lockHlc.present ? data.lockHlc.value : this.lockHlc,
      verification: data.verification.present
          ? data.verification.value
          : this.verification,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PeriodsPData(')
          ..write('bookId: $bookId, ')
          ..write('year: $year, ')
          ..write('month: $month, ')
          ..write('state: $state, ')
          ..write('lockHlc: $lockHlc, ')
          ..write('verification: $verification')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(bookId, year, month, state, lockHlc, verification);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PeriodsPData &&
          other.bookId == this.bookId &&
          other.year == this.year &&
          other.month == this.month &&
          other.state == this.state &&
          other.lockHlc == this.lockHlc &&
          other.verification == this.verification);
}

class PeriodsPCompanion extends UpdateCompanion<PeriodsPData> {
  final Value<String> bookId;
  final Value<int> year;
  final Value<int> month;
  final Value<String> state;
  final Value<int?> lockHlc;
  final Value<String?> verification;
  final Value<int> rowid;
  const PeriodsPCompanion({
    this.bookId = const Value.absent(),
    this.year = const Value.absent(),
    this.month = const Value.absent(),
    this.state = const Value.absent(),
    this.lockHlc = const Value.absent(),
    this.verification = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PeriodsPCompanion.insert({
    required String bookId,
    required int year,
    required int month,
    required String state,
    this.lockHlc = const Value.absent(),
    this.verification = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       year = Value(year),
       month = Value(month),
       state = Value(state);
  static Insertable<PeriodsPData> custom({
    Expression<String>? bookId,
    Expression<int>? year,
    Expression<int>? month,
    Expression<String>? state,
    Expression<int>? lockHlc,
    Expression<String>? verification,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (year != null) 'year': year,
      if (month != null) 'month': month,
      if (state != null) 'state': state,
      if (lockHlc != null) 'lock_hlc': lockHlc,
      if (verification != null) 'verification': verification,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PeriodsPCompanion copyWith({
    Value<String>? bookId,
    Value<int>? year,
    Value<int>? month,
    Value<String>? state,
    Value<int?>? lockHlc,
    Value<String?>? verification,
    Value<int>? rowid,
  }) {
    return PeriodsPCompanion(
      bookId: bookId ?? this.bookId,
      year: year ?? this.year,
      month: month ?? this.month,
      state: state ?? this.state,
      lockHlc: lockHlc ?? this.lockHlc,
      verification: verification ?? this.verification,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (month.present) {
      map['month'] = Variable<int>(month.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (lockHlc.present) {
      map['lock_hlc'] = Variable<int>(lockHlc.value);
    }
    if (verification.present) {
      map['verification'] = Variable<String>(verification.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeriodsPCompanion(')
          ..write('bookId: $bookId, ')
          ..write('year: $year, ')
          ..write('month: $month, ')
          ..write('state: $state, ')
          ..write('lockHlc: $lockHlc, ')
          ..write('verification: $verification, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CashCountsPTable extends CashCountsP
    with TableInfo<$CashCountsPTable, CashCountsPData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CashCountsPTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countedAtMeta = const VerificationMeta(
    'countedAt',
  );
  @override
  late final GeneratedColumn<String> countedAt = GeneratedColumn<String>(
    'counted_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countedTotalPaiseMeta = const VerificationMeta(
    'countedTotalPaise',
  );
  @override
  late final GeneratedColumn<int> countedTotalPaise = GeneratedColumn<int>(
    'counted_total_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _breakdownJsonMeta = const VerificationMeta(
    'breakdownJson',
  );
  @override
  late final GeneratedColumn<String> breakdownJson = GeneratedColumn<String>(
    'breakdown_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _postedEntryIdMeta = const VerificationMeta(
    'postedEntryId',
  );
  @override
  late final GeneratedColumn<String> postedEntryId = GeneratedColumn<String>(
    'posted_entry_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _countedByMeta = const VerificationMeta(
    'countedBy',
  );
  @override
  late final GeneratedColumn<String> countedBy = GeneratedColumn<String>(
    'counted_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _witnessMeta = const VerificationMeta(
    'witness',
  );
  @override
  late final GeneratedColumn<String> witness = GeneratedColumn<String>(
    'witness',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    mode,
    countedAt,
    countedTotalPaise,
    breakdownJson,
    postedEntryId,
    countedBy,
    witness,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cash_counts_p';
  @override
  VerificationContext validateIntegrity(
    Insertable<CashCountsPData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('counted_at')) {
      context.handle(
        _countedAtMeta,
        countedAt.isAcceptableOrUnknown(data['counted_at']!, _countedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_countedAtMeta);
    }
    if (data.containsKey('counted_total_paise')) {
      context.handle(
        _countedTotalPaiseMeta,
        countedTotalPaise.isAcceptableOrUnknown(
          data['counted_total_paise']!,
          _countedTotalPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_countedTotalPaiseMeta);
    }
    if (data.containsKey('breakdown_json')) {
      context.handle(
        _breakdownJsonMeta,
        breakdownJson.isAcceptableOrUnknown(
          data['breakdown_json']!,
          _breakdownJsonMeta,
        ),
      );
    }
    if (data.containsKey('posted_entry_id')) {
      context.handle(
        _postedEntryIdMeta,
        postedEntryId.isAcceptableOrUnknown(
          data['posted_entry_id']!,
          _postedEntryIdMeta,
        ),
      );
    }
    if (data.containsKey('counted_by')) {
      context.handle(
        _countedByMeta,
        countedBy.isAcceptableOrUnknown(data['counted_by']!, _countedByMeta),
      );
    }
    if (data.containsKey('witness')) {
      context.handle(
        _witnessMeta,
        witness.isAcceptableOrUnknown(data['witness']!, _witnessMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CashCountsPData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CashCountsPData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      countedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}counted_at'],
      )!,
      countedTotalPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}counted_total_paise'],
      )!,
      breakdownJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}breakdown_json'],
      ),
      postedEntryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}posted_entry_id'],
      ),
      countedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}counted_by'],
      ),
      witness: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}witness'],
      ),
    );
  }

  @override
  $CashCountsPTable createAlias(String alias) {
    return $CashCountsPTable(attachedDatabase, alias);
  }
}

class CashCountsPData extends DataClass implements Insertable<CashCountsPData> {
  /// Count id.
  final String id;

  /// Cash or collection account.
  final String accountId;

  /// verify (cash) | collect (cash_collection).
  final String mode;

  /// ISO date counted.
  final String countedAt;

  /// Counted total in paise.
  final int countedTotalPaise;

  /// Denomination sheet as JSON.
  final String? breakdownJson;

  /// The adjustment / income entry the count led to.
  final String? postedEntryId;

  /// Counter.
  final String? countedBy;

  /// Witness (mandatory for collection accounts).
  final String? witness;
  const CashCountsPData({
    required this.id,
    required this.accountId,
    required this.mode,
    required this.countedAt,
    required this.countedTotalPaise,
    this.breakdownJson,
    this.postedEntryId,
    this.countedBy,
    this.witness,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['account_id'] = Variable<String>(accountId);
    map['mode'] = Variable<String>(mode);
    map['counted_at'] = Variable<String>(countedAt);
    map['counted_total_paise'] = Variable<int>(countedTotalPaise);
    if (!nullToAbsent || breakdownJson != null) {
      map['breakdown_json'] = Variable<String>(breakdownJson);
    }
    if (!nullToAbsent || postedEntryId != null) {
      map['posted_entry_id'] = Variable<String>(postedEntryId);
    }
    if (!nullToAbsent || countedBy != null) {
      map['counted_by'] = Variable<String>(countedBy);
    }
    if (!nullToAbsent || witness != null) {
      map['witness'] = Variable<String>(witness);
    }
    return map;
  }

  CashCountsPCompanion toCompanion(bool nullToAbsent) {
    return CashCountsPCompanion(
      id: Value(id),
      accountId: Value(accountId),
      mode: Value(mode),
      countedAt: Value(countedAt),
      countedTotalPaise: Value(countedTotalPaise),
      breakdownJson: breakdownJson == null && nullToAbsent
          ? const Value.absent()
          : Value(breakdownJson),
      postedEntryId: postedEntryId == null && nullToAbsent
          ? const Value.absent()
          : Value(postedEntryId),
      countedBy: countedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(countedBy),
      witness: witness == null && nullToAbsent
          ? const Value.absent()
          : Value(witness),
    );
  }

  factory CashCountsPData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CashCountsPData(
      id: serializer.fromJson<String>(json['id']),
      accountId: serializer.fromJson<String>(json['accountId']),
      mode: serializer.fromJson<String>(json['mode']),
      countedAt: serializer.fromJson<String>(json['countedAt']),
      countedTotalPaise: serializer.fromJson<int>(json['countedTotalPaise']),
      breakdownJson: serializer.fromJson<String?>(json['breakdownJson']),
      postedEntryId: serializer.fromJson<String?>(json['postedEntryId']),
      countedBy: serializer.fromJson<String?>(json['countedBy']),
      witness: serializer.fromJson<String?>(json['witness']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'accountId': serializer.toJson<String>(accountId),
      'mode': serializer.toJson<String>(mode),
      'countedAt': serializer.toJson<String>(countedAt),
      'countedTotalPaise': serializer.toJson<int>(countedTotalPaise),
      'breakdownJson': serializer.toJson<String?>(breakdownJson),
      'postedEntryId': serializer.toJson<String?>(postedEntryId),
      'countedBy': serializer.toJson<String?>(countedBy),
      'witness': serializer.toJson<String?>(witness),
    };
  }

  CashCountsPData copyWith({
    String? id,
    String? accountId,
    String? mode,
    String? countedAt,
    int? countedTotalPaise,
    Value<String?> breakdownJson = const Value.absent(),
    Value<String?> postedEntryId = const Value.absent(),
    Value<String?> countedBy = const Value.absent(),
    Value<String?> witness = const Value.absent(),
  }) => CashCountsPData(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    mode: mode ?? this.mode,
    countedAt: countedAt ?? this.countedAt,
    countedTotalPaise: countedTotalPaise ?? this.countedTotalPaise,
    breakdownJson: breakdownJson.present
        ? breakdownJson.value
        : this.breakdownJson,
    postedEntryId: postedEntryId.present
        ? postedEntryId.value
        : this.postedEntryId,
    countedBy: countedBy.present ? countedBy.value : this.countedBy,
    witness: witness.present ? witness.value : this.witness,
  );
  CashCountsPData copyWithCompanion(CashCountsPCompanion data) {
    return CashCountsPData(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      mode: data.mode.present ? data.mode.value : this.mode,
      countedAt: data.countedAt.present ? data.countedAt.value : this.countedAt,
      countedTotalPaise: data.countedTotalPaise.present
          ? data.countedTotalPaise.value
          : this.countedTotalPaise,
      breakdownJson: data.breakdownJson.present
          ? data.breakdownJson.value
          : this.breakdownJson,
      postedEntryId: data.postedEntryId.present
          ? data.postedEntryId.value
          : this.postedEntryId,
      countedBy: data.countedBy.present ? data.countedBy.value : this.countedBy,
      witness: data.witness.present ? data.witness.value : this.witness,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CashCountsPData(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('mode: $mode, ')
          ..write('countedAt: $countedAt, ')
          ..write('countedTotalPaise: $countedTotalPaise, ')
          ..write('breakdownJson: $breakdownJson, ')
          ..write('postedEntryId: $postedEntryId, ')
          ..write('countedBy: $countedBy, ')
          ..write('witness: $witness')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    accountId,
    mode,
    countedAt,
    countedTotalPaise,
    breakdownJson,
    postedEntryId,
    countedBy,
    witness,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CashCountsPData &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.mode == this.mode &&
          other.countedAt == this.countedAt &&
          other.countedTotalPaise == this.countedTotalPaise &&
          other.breakdownJson == this.breakdownJson &&
          other.postedEntryId == this.postedEntryId &&
          other.countedBy == this.countedBy &&
          other.witness == this.witness);
}

class CashCountsPCompanion extends UpdateCompanion<CashCountsPData> {
  final Value<String> id;
  final Value<String> accountId;
  final Value<String> mode;
  final Value<String> countedAt;
  final Value<int> countedTotalPaise;
  final Value<String?> breakdownJson;
  final Value<String?> postedEntryId;
  final Value<String?> countedBy;
  final Value<String?> witness;
  final Value<int> rowid;
  const CashCountsPCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.mode = const Value.absent(),
    this.countedAt = const Value.absent(),
    this.countedTotalPaise = const Value.absent(),
    this.breakdownJson = const Value.absent(),
    this.postedEntryId = const Value.absent(),
    this.countedBy = const Value.absent(),
    this.witness = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CashCountsPCompanion.insert({
    required String id,
    required String accountId,
    required String mode,
    required String countedAt,
    required int countedTotalPaise,
    this.breakdownJson = const Value.absent(),
    this.postedEntryId = const Value.absent(),
    this.countedBy = const Value.absent(),
    this.witness = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       accountId = Value(accountId),
       mode = Value(mode),
       countedAt = Value(countedAt),
       countedTotalPaise = Value(countedTotalPaise);
  static Insertable<CashCountsPData> custom({
    Expression<String>? id,
    Expression<String>? accountId,
    Expression<String>? mode,
    Expression<String>? countedAt,
    Expression<int>? countedTotalPaise,
    Expression<String>? breakdownJson,
    Expression<String>? postedEntryId,
    Expression<String>? countedBy,
    Expression<String>? witness,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (mode != null) 'mode': mode,
      if (countedAt != null) 'counted_at': countedAt,
      if (countedTotalPaise != null) 'counted_total_paise': countedTotalPaise,
      if (breakdownJson != null) 'breakdown_json': breakdownJson,
      if (postedEntryId != null) 'posted_entry_id': postedEntryId,
      if (countedBy != null) 'counted_by': countedBy,
      if (witness != null) 'witness': witness,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CashCountsPCompanion copyWith({
    Value<String>? id,
    Value<String>? accountId,
    Value<String>? mode,
    Value<String>? countedAt,
    Value<int>? countedTotalPaise,
    Value<String?>? breakdownJson,
    Value<String?>? postedEntryId,
    Value<String?>? countedBy,
    Value<String?>? witness,
    Value<int>? rowid,
  }) {
    return CashCountsPCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      mode: mode ?? this.mode,
      countedAt: countedAt ?? this.countedAt,
      countedTotalPaise: countedTotalPaise ?? this.countedTotalPaise,
      breakdownJson: breakdownJson ?? this.breakdownJson,
      postedEntryId: postedEntryId ?? this.postedEntryId,
      countedBy: countedBy ?? this.countedBy,
      witness: witness ?? this.witness,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (countedAt.present) {
      map['counted_at'] = Variable<String>(countedAt.value);
    }
    if (countedTotalPaise.present) {
      map['counted_total_paise'] = Variable<int>(countedTotalPaise.value);
    }
    if (breakdownJson.present) {
      map['breakdown_json'] = Variable<String>(breakdownJson.value);
    }
    if (postedEntryId.present) {
      map['posted_entry_id'] = Variable<String>(postedEntryId.value);
    }
    if (countedBy.present) {
      map['counted_by'] = Variable<String>(countedBy.value);
    }
    if (witness.present) {
      map['witness'] = Variable<String>(witness.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CashCountsPCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('mode: $mode, ')
          ..write('countedAt: $countedAt, ')
          ..write('countedTotalPaise: $countedTotalPaise, ')
          ..write('breakdownJson: $breakdownJson, ')
          ..write('postedEntryId: $postedEntryId, ')
          ..write('countedBy: $countedBy, ')
          ..write('witness: $witness, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $YearClosePTable extends YearCloseP
    with TableInfo<$YearClosePTable, YearClosePData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $YearClosePTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fyLabelMeta = const VerificationMeta(
    'fyLabel',
  );
  @override
  late final GeneratedColumn<String> fyLabel = GeneratedColumn<String>(
    'fy_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vectorHashMeta = const VerificationMeta(
    'vectorHash',
  );
  @override
  late final GeneratedColumn<String> vectorHash = GeneratedColumn<String>(
    'vector_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vectorMeta = const VerificationMeta('vector');
  @override
  late final GeneratedColumn<String> vector = GeneratedColumn<String>(
    'vector',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _projectorVersionMeta = const VerificationMeta(
    'projectorVersion',
  );
  @override
  late final GeneratedColumn<int> projectorVersion = GeneratedColumn<int>(
    'projector_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _verificationMeta = const VerificationMeta(
    'verification',
  );
  @override
  late final GeneratedColumn<String> verification = GeneratedColumn<String>(
    'verification',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookId,
    fyLabel,
    state,
    vectorHash,
    vector,
    projectorVersion,
    verification,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'year_close_p';
  @override
  VerificationContext validateIntegrity(
    Insertable<YearClosePData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('fy_label')) {
      context.handle(
        _fyLabelMeta,
        fyLabel.isAcceptableOrUnknown(data['fy_label']!, _fyLabelMeta),
      );
    } else if (isInserting) {
      context.missing(_fyLabelMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('vector_hash')) {
      context.handle(
        _vectorHashMeta,
        vectorHash.isAcceptableOrUnknown(data['vector_hash']!, _vectorHashMeta),
      );
    }
    if (data.containsKey('vector')) {
      context.handle(
        _vectorMeta,
        vector.isAcceptableOrUnknown(data['vector']!, _vectorMeta),
      );
    }
    if (data.containsKey('projector_version')) {
      context.handle(
        _projectorVersionMeta,
        projectorVersion.isAcceptableOrUnknown(
          data['projector_version']!,
          _projectorVersionMeta,
        ),
      );
    }
    if (data.containsKey('verification')) {
      context.handle(
        _verificationMeta,
        verification.isAcceptableOrUnknown(
          data['verification']!,
          _verificationMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId, fyLabel};
  @override
  YearClosePData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return YearClosePData(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      fyLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fy_label'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      vectorHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vector_hash'],
      ),
      vector: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vector'],
      ),
      projectorVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}projector_version'],
      ),
      verification: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verification'],
      ),
    );
  }

  @override
  $YearClosePTable createAlias(String alias) {
    return $YearClosePTable(attachedDatabase, alias);
  }
}

class YearClosePData extends DataClass implements Insertable<YearClosePData> {
  /// Book.
  final String bookId;

  /// `2026-27`.
  final String fyLabel;

  /// open | closed | uncertified.
  final String state;

  /// Hash of the certified vector (core_crypto, M3).
  final String? vectorHash;

  /// The certified vector as JSON `{account_id: paise}`.
  final String? vector;

  /// `core_ledger.projectorVersion` recorded in the close envelope (ADR
  /// 2026-09-05c §3); null for a pre-M2 close.
  final int? projectorVersion;

  /// This reader's verification of the close: verified | mismatch |
  /// reader_outdated ("Update the app to verify this close") |
  /// certifier_outdated. Null while the year is open.
  final String? verification;
  const YearClosePData({
    required this.bookId,
    required this.fyLabel,
    required this.state,
    this.vectorHash,
    this.vector,
    this.projectorVersion,
    this.verification,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['fy_label'] = Variable<String>(fyLabel);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || vectorHash != null) {
      map['vector_hash'] = Variable<String>(vectorHash);
    }
    if (!nullToAbsent || vector != null) {
      map['vector'] = Variable<String>(vector);
    }
    if (!nullToAbsent || projectorVersion != null) {
      map['projector_version'] = Variable<int>(projectorVersion);
    }
    if (!nullToAbsent || verification != null) {
      map['verification'] = Variable<String>(verification);
    }
    return map;
  }

  YearClosePCompanion toCompanion(bool nullToAbsent) {
    return YearClosePCompanion(
      bookId: Value(bookId),
      fyLabel: Value(fyLabel),
      state: Value(state),
      vectorHash: vectorHash == null && nullToAbsent
          ? const Value.absent()
          : Value(vectorHash),
      vector: vector == null && nullToAbsent
          ? const Value.absent()
          : Value(vector),
      projectorVersion: projectorVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(projectorVersion),
      verification: verification == null && nullToAbsent
          ? const Value.absent()
          : Value(verification),
    );
  }

  factory YearClosePData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return YearClosePData(
      bookId: serializer.fromJson<String>(json['bookId']),
      fyLabel: serializer.fromJson<String>(json['fyLabel']),
      state: serializer.fromJson<String>(json['state']),
      vectorHash: serializer.fromJson<String?>(json['vectorHash']),
      vector: serializer.fromJson<String?>(json['vector']),
      projectorVersion: serializer.fromJson<int?>(json['projectorVersion']),
      verification: serializer.fromJson<String?>(json['verification']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'fyLabel': serializer.toJson<String>(fyLabel),
      'state': serializer.toJson<String>(state),
      'vectorHash': serializer.toJson<String?>(vectorHash),
      'vector': serializer.toJson<String?>(vector),
      'projectorVersion': serializer.toJson<int?>(projectorVersion),
      'verification': serializer.toJson<String?>(verification),
    };
  }

  YearClosePData copyWith({
    String? bookId,
    String? fyLabel,
    String? state,
    Value<String?> vectorHash = const Value.absent(),
    Value<String?> vector = const Value.absent(),
    Value<int?> projectorVersion = const Value.absent(),
    Value<String?> verification = const Value.absent(),
  }) => YearClosePData(
    bookId: bookId ?? this.bookId,
    fyLabel: fyLabel ?? this.fyLabel,
    state: state ?? this.state,
    vectorHash: vectorHash.present ? vectorHash.value : this.vectorHash,
    vector: vector.present ? vector.value : this.vector,
    projectorVersion: projectorVersion.present
        ? projectorVersion.value
        : this.projectorVersion,
    verification: verification.present ? verification.value : this.verification,
  );
  YearClosePData copyWithCompanion(YearClosePCompanion data) {
    return YearClosePData(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      fyLabel: data.fyLabel.present ? data.fyLabel.value : this.fyLabel,
      state: data.state.present ? data.state.value : this.state,
      vectorHash: data.vectorHash.present
          ? data.vectorHash.value
          : this.vectorHash,
      vector: data.vector.present ? data.vector.value : this.vector,
      projectorVersion: data.projectorVersion.present
          ? data.projectorVersion.value
          : this.projectorVersion,
      verification: data.verification.present
          ? data.verification.value
          : this.verification,
    );
  }

  @override
  String toString() {
    return (StringBuffer('YearClosePData(')
          ..write('bookId: $bookId, ')
          ..write('fyLabel: $fyLabel, ')
          ..write('state: $state, ')
          ..write('vectorHash: $vectorHash, ')
          ..write('vector: $vector, ')
          ..write('projectorVersion: $projectorVersion, ')
          ..write('verification: $verification')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    bookId,
    fyLabel,
    state,
    vectorHash,
    vector,
    projectorVersion,
    verification,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is YearClosePData &&
          other.bookId == this.bookId &&
          other.fyLabel == this.fyLabel &&
          other.state == this.state &&
          other.vectorHash == this.vectorHash &&
          other.vector == this.vector &&
          other.projectorVersion == this.projectorVersion &&
          other.verification == this.verification);
}

class YearClosePCompanion extends UpdateCompanion<YearClosePData> {
  final Value<String> bookId;
  final Value<String> fyLabel;
  final Value<String> state;
  final Value<String?> vectorHash;
  final Value<String?> vector;
  final Value<int?> projectorVersion;
  final Value<String?> verification;
  final Value<int> rowid;
  const YearClosePCompanion({
    this.bookId = const Value.absent(),
    this.fyLabel = const Value.absent(),
    this.state = const Value.absent(),
    this.vectorHash = const Value.absent(),
    this.vector = const Value.absent(),
    this.projectorVersion = const Value.absent(),
    this.verification = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  YearClosePCompanion.insert({
    required String bookId,
    required String fyLabel,
    required String state,
    this.vectorHash = const Value.absent(),
    this.vector = const Value.absent(),
    this.projectorVersion = const Value.absent(),
    this.verification = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       fyLabel = Value(fyLabel),
       state = Value(state);
  static Insertable<YearClosePData> custom({
    Expression<String>? bookId,
    Expression<String>? fyLabel,
    Expression<String>? state,
    Expression<String>? vectorHash,
    Expression<String>? vector,
    Expression<int>? projectorVersion,
    Expression<String>? verification,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (fyLabel != null) 'fy_label': fyLabel,
      if (state != null) 'state': state,
      if (vectorHash != null) 'vector_hash': vectorHash,
      if (vector != null) 'vector': vector,
      if (projectorVersion != null) 'projector_version': projectorVersion,
      if (verification != null) 'verification': verification,
      if (rowid != null) 'rowid': rowid,
    });
  }

  YearClosePCompanion copyWith({
    Value<String>? bookId,
    Value<String>? fyLabel,
    Value<String>? state,
    Value<String?>? vectorHash,
    Value<String?>? vector,
    Value<int?>? projectorVersion,
    Value<String?>? verification,
    Value<int>? rowid,
  }) {
    return YearClosePCompanion(
      bookId: bookId ?? this.bookId,
      fyLabel: fyLabel ?? this.fyLabel,
      state: state ?? this.state,
      vectorHash: vectorHash ?? this.vectorHash,
      vector: vector ?? this.vector,
      projectorVersion: projectorVersion ?? this.projectorVersion,
      verification: verification ?? this.verification,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (fyLabel.present) {
      map['fy_label'] = Variable<String>(fyLabel.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (vectorHash.present) {
      map['vector_hash'] = Variable<String>(vectorHash.value);
    }
    if (vector.present) {
      map['vector'] = Variable<String>(vector.value);
    }
    if (projectorVersion.present) {
      map['projector_version'] = Variable<int>(projectorVersion.value);
    }
    if (verification.present) {
      map['verification'] = Variable<String>(verification.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('YearClosePCompanion(')
          ..write('bookId: $bookId, ')
          ..write('fyLabel: $fyLabel, ')
          ..write('state: $state, ')
          ..write('vectorHash: $vectorHash, ')
          ..write('vector: $vector, ')
          ..write('projectorVersion: $projectorVersion, ')
          ..write('verification: $verification, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ImportLinesPTable extends ImportLinesP
    with TableInfo<$ImportLinesPTable, ImportLinesPData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportLinesPTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bankAccountIdMeta = const VerificationMeta(
    'bankAccountId',
  );
  @override
  late final GeneratedColumn<String> bankAccountId = GeneratedColumn<String>(
    'bank_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountPaiseMeta = const VerificationMeta(
    'amountPaise',
  );
  @override
  late final GeneratedColumn<int> amountPaise = GeneratedColumn<int>(
    'amount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _matchedEntryMeta = const VerificationMeta(
    'matchedEntry',
  );
  @override
  late final GeneratedColumn<String> matchedEntry = GeneratedColumn<String>(
    'matched_entry',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dedupeHashMeta = const VerificationMeta(
    'dedupeHash',
  );
  @override
  late final GeneratedColumn<String> dedupeHash = GeneratedColumn<String>(
    'dedupe_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    bankAccountId,
    date,
    description,
    amountPaise,
    state,
    matchedEntry,
    dedupeHash,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'import_lines_p';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportLinesPData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('bank_account_id')) {
      context.handle(
        _bankAccountIdMeta,
        bankAccountId.isAcceptableOrUnknown(
          data['bank_account_id']!,
          _bankAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_bankAccountIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('amount_paise')) {
      context.handle(
        _amountPaiseMeta,
        amountPaise.isAcceptableOrUnknown(
          data['amount_paise']!,
          _amountPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountPaiseMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('matched_entry')) {
      context.handle(
        _matchedEntryMeta,
        matchedEntry.isAcceptableOrUnknown(
          data['matched_entry']!,
          _matchedEntryMeta,
        ),
      );
    }
    if (data.containsKey('dedupe_hash')) {
      context.handle(
        _dedupeHashMeta,
        dedupeHash.isAcceptableOrUnknown(data['dedupe_hash']!, _dedupeHashMeta),
      );
    } else if (isInserting) {
      context.missing(_dedupeHashMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ImportLinesPData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportLinesPData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      bankAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bank_account_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      amountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_paise'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      matchedEntry: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}matched_entry'],
      ),
      dedupeHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dedupe_hash'],
      )!,
    );
  }

  @override
  $ImportLinesPTable createAlias(String alias) {
    return $ImportLinesPTable(attachedDatabase, alias);
  }
}

class ImportLinesPData extends DataClass
    implements Insertable<ImportLinesPData> {
  /// Line id.
  final String id;

  /// Book.
  final String bookId;

  /// The bank account imported into.
  final String bankAccountId;

  /// ISO date.
  final String date;

  /// Bank text.
  final String description;

  /// Signed paise.
  final int amountPaise;

  /// State.
  final String state;

  /// Matched entry.
  final String? matchedEntry;

  /// Duplicate hash (ADR 05e §12).
  final String dedupeHash;
  const ImportLinesPData({
    required this.id,
    required this.bookId,
    required this.bankAccountId,
    required this.date,
    required this.description,
    required this.amountPaise,
    required this.state,
    this.matchedEntry,
    required this.dedupeHash,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['bank_account_id'] = Variable<String>(bankAccountId);
    map['date'] = Variable<String>(date);
    map['description'] = Variable<String>(description);
    map['amount_paise'] = Variable<int>(amountPaise);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || matchedEntry != null) {
      map['matched_entry'] = Variable<String>(matchedEntry);
    }
    map['dedupe_hash'] = Variable<String>(dedupeHash);
    return map;
  }

  ImportLinesPCompanion toCompanion(bool nullToAbsent) {
    return ImportLinesPCompanion(
      id: Value(id),
      bookId: Value(bookId),
      bankAccountId: Value(bankAccountId),
      date: Value(date),
      description: Value(description),
      amountPaise: Value(amountPaise),
      state: Value(state),
      matchedEntry: matchedEntry == null && nullToAbsent
          ? const Value.absent()
          : Value(matchedEntry),
      dedupeHash: Value(dedupeHash),
    );
  }

  factory ImportLinesPData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportLinesPData(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      bankAccountId: serializer.fromJson<String>(json['bankAccountId']),
      date: serializer.fromJson<String>(json['date']),
      description: serializer.fromJson<String>(json['description']),
      amountPaise: serializer.fromJson<int>(json['amountPaise']),
      state: serializer.fromJson<String>(json['state']),
      matchedEntry: serializer.fromJson<String?>(json['matchedEntry']),
      dedupeHash: serializer.fromJson<String>(json['dedupeHash']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'bankAccountId': serializer.toJson<String>(bankAccountId),
      'date': serializer.toJson<String>(date),
      'description': serializer.toJson<String>(description),
      'amountPaise': serializer.toJson<int>(amountPaise),
      'state': serializer.toJson<String>(state),
      'matchedEntry': serializer.toJson<String?>(matchedEntry),
      'dedupeHash': serializer.toJson<String>(dedupeHash),
    };
  }

  ImportLinesPData copyWith({
    String? id,
    String? bookId,
    String? bankAccountId,
    String? date,
    String? description,
    int? amountPaise,
    String? state,
    Value<String?> matchedEntry = const Value.absent(),
    String? dedupeHash,
  }) => ImportLinesPData(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    bankAccountId: bankAccountId ?? this.bankAccountId,
    date: date ?? this.date,
    description: description ?? this.description,
    amountPaise: amountPaise ?? this.amountPaise,
    state: state ?? this.state,
    matchedEntry: matchedEntry.present ? matchedEntry.value : this.matchedEntry,
    dedupeHash: dedupeHash ?? this.dedupeHash,
  );
  ImportLinesPData copyWithCompanion(ImportLinesPCompanion data) {
    return ImportLinesPData(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      bankAccountId: data.bankAccountId.present
          ? data.bankAccountId.value
          : this.bankAccountId,
      date: data.date.present ? data.date.value : this.date,
      description: data.description.present
          ? data.description.value
          : this.description,
      amountPaise: data.amountPaise.present
          ? data.amountPaise.value
          : this.amountPaise,
      state: data.state.present ? data.state.value : this.state,
      matchedEntry: data.matchedEntry.present
          ? data.matchedEntry.value
          : this.matchedEntry,
      dedupeHash: data.dedupeHash.present
          ? data.dedupeHash.value
          : this.dedupeHash,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportLinesPData(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('bankAccountId: $bankAccountId, ')
          ..write('date: $date, ')
          ..write('description: $description, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('state: $state, ')
          ..write('matchedEntry: $matchedEntry, ')
          ..write('dedupeHash: $dedupeHash')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    bankAccountId,
    date,
    description,
    amountPaise,
    state,
    matchedEntry,
    dedupeHash,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportLinesPData &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.bankAccountId == this.bankAccountId &&
          other.date == this.date &&
          other.description == this.description &&
          other.amountPaise == this.amountPaise &&
          other.state == this.state &&
          other.matchedEntry == this.matchedEntry &&
          other.dedupeHash == this.dedupeHash);
}

class ImportLinesPCompanion extends UpdateCompanion<ImportLinesPData> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<String> bankAccountId;
  final Value<String> date;
  final Value<String> description;
  final Value<int> amountPaise;
  final Value<String> state;
  final Value<String?> matchedEntry;
  final Value<String> dedupeHash;
  final Value<int> rowid;
  const ImportLinesPCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.bankAccountId = const Value.absent(),
    this.date = const Value.absent(),
    this.description = const Value.absent(),
    this.amountPaise = const Value.absent(),
    this.state = const Value.absent(),
    this.matchedEntry = const Value.absent(),
    this.dedupeHash = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImportLinesPCompanion.insert({
    required String id,
    required String bookId,
    required String bankAccountId,
    required String date,
    required String description,
    required int amountPaise,
    required String state,
    this.matchedEntry = const Value.absent(),
    required String dedupeHash,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bookId = Value(bookId),
       bankAccountId = Value(bankAccountId),
       date = Value(date),
       description = Value(description),
       amountPaise = Value(amountPaise),
       state = Value(state),
       dedupeHash = Value(dedupeHash);
  static Insertable<ImportLinesPData> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<String>? bankAccountId,
    Expression<String>? date,
    Expression<String>? description,
    Expression<int>? amountPaise,
    Expression<String>? state,
    Expression<String>? matchedEntry,
    Expression<String>? dedupeHash,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (bankAccountId != null) 'bank_account_id': bankAccountId,
      if (date != null) 'date': date,
      if (description != null) 'description': description,
      if (amountPaise != null) 'amount_paise': amountPaise,
      if (state != null) 'state': state,
      if (matchedEntry != null) 'matched_entry': matchedEntry,
      if (dedupeHash != null) 'dedupe_hash': dedupeHash,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImportLinesPCompanion copyWith({
    Value<String>? id,
    Value<String>? bookId,
    Value<String>? bankAccountId,
    Value<String>? date,
    Value<String>? description,
    Value<int>? amountPaise,
    Value<String>? state,
    Value<String?>? matchedEntry,
    Value<String>? dedupeHash,
    Value<int>? rowid,
  }) {
    return ImportLinesPCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      bankAccountId: bankAccountId ?? this.bankAccountId,
      date: date ?? this.date,
      description: description ?? this.description,
      amountPaise: amountPaise ?? this.amountPaise,
      state: state ?? this.state,
      matchedEntry: matchedEntry ?? this.matchedEntry,
      dedupeHash: dedupeHash ?? this.dedupeHash,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (bankAccountId.present) {
      map['bank_account_id'] = Variable<String>(bankAccountId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (amountPaise.present) {
      map['amount_paise'] = Variable<int>(amountPaise.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (matchedEntry.present) {
      map['matched_entry'] = Variable<String>(matchedEntry.value);
    }
    if (dedupeHash.present) {
      map['dedupe_hash'] = Variable<String>(dedupeHash.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportLinesPCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('bankAccountId: $bankAccountId, ')
          ..write('date: $date, ')
          ..write('description: $description, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('state: $state, ')
          ..write('matchedEntry: $matchedEntry, ')
          ..write('dedupeHash: $dedupeHash, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RulesPTable extends RulesP with TableInfo<$RulesPTable, RulesPData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RulesPTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _patternMeta = const VerificationMeta(
    'pattern',
  );
  @override
  late final GeneratedColumn<String> pattern = GeneratedColumn<String>(
    'pattern',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetAccountMeta = const VerificationMeta(
    'targetAccount',
  );
  @override
  late final GeneratedColumn<String> targetAccount = GeneratedColumn<String>(
    'target_account',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hitsMeta = const VerificationMeta('hits');
  @override
  late final GeneratedColumn<int> hits = GeneratedColumn<int>(
    'hits',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    pattern,
    targetAccount,
    hits,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rules_p';
  @override
  VerificationContext validateIntegrity(
    Insertable<RulesPData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('pattern')) {
      context.handle(
        _patternMeta,
        pattern.isAcceptableOrUnknown(data['pattern']!, _patternMeta),
      );
    } else if (isInserting) {
      context.missing(_patternMeta);
    }
    if (data.containsKey('target_account')) {
      context.handle(
        _targetAccountMeta,
        targetAccount.isAcceptableOrUnknown(
          data['target_account']!,
          _targetAccountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetAccountMeta);
    }
    if (data.containsKey('hits')) {
      context.handle(
        _hitsMeta,
        hits.isAcceptableOrUnknown(data['hits']!, _hitsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RulesPData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RulesPData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      pattern: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pattern'],
      )!,
      targetAccount: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_account'],
      )!,
      hits: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hits'],
      )!,
    );
  }

  @override
  $RulesPTable createAlias(String alias) {
    return $RulesPTable(attachedDatabase, alias);
  }
}

class RulesPData extends DataClass implements Insertable<RulesPData> {
  /// Rule id.
  final String id;

  /// Book.
  final String bookId;

  /// Pattern.
  final String pattern;

  /// Target account.
  final String targetAccount;

  /// Hit count.
  final int hits;
  const RulesPData({
    required this.id,
    required this.bookId,
    required this.pattern,
    required this.targetAccount,
    required this.hits,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['pattern'] = Variable<String>(pattern);
    map['target_account'] = Variable<String>(targetAccount);
    map['hits'] = Variable<int>(hits);
    return map;
  }

  RulesPCompanion toCompanion(bool nullToAbsent) {
    return RulesPCompanion(
      id: Value(id),
      bookId: Value(bookId),
      pattern: Value(pattern),
      targetAccount: Value(targetAccount),
      hits: Value(hits),
    );
  }

  factory RulesPData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RulesPData(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      pattern: serializer.fromJson<String>(json['pattern']),
      targetAccount: serializer.fromJson<String>(json['targetAccount']),
      hits: serializer.fromJson<int>(json['hits']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'pattern': serializer.toJson<String>(pattern),
      'targetAccount': serializer.toJson<String>(targetAccount),
      'hits': serializer.toJson<int>(hits),
    };
  }

  RulesPData copyWith({
    String? id,
    String? bookId,
    String? pattern,
    String? targetAccount,
    int? hits,
  }) => RulesPData(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    pattern: pattern ?? this.pattern,
    targetAccount: targetAccount ?? this.targetAccount,
    hits: hits ?? this.hits,
  );
  RulesPData copyWithCompanion(RulesPCompanion data) {
    return RulesPData(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      pattern: data.pattern.present ? data.pattern.value : this.pattern,
      targetAccount: data.targetAccount.present
          ? data.targetAccount.value
          : this.targetAccount,
      hits: data.hits.present ? data.hits.value : this.hits,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RulesPData(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('pattern: $pattern, ')
          ..write('targetAccount: $targetAccount, ')
          ..write('hits: $hits')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, bookId, pattern, targetAccount, hits);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RulesPData &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.pattern == this.pattern &&
          other.targetAccount == this.targetAccount &&
          other.hits == this.hits);
}

class RulesPCompanion extends UpdateCompanion<RulesPData> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<String> pattern;
  final Value<String> targetAccount;
  final Value<int> hits;
  final Value<int> rowid;
  const RulesPCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.pattern = const Value.absent(),
    this.targetAccount = const Value.absent(),
    this.hits = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RulesPCompanion.insert({
    required String id,
    required String bookId,
    required String pattern,
    required String targetAccount,
    this.hits = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bookId = Value(bookId),
       pattern = Value(pattern),
       targetAccount = Value(targetAccount);
  static Insertable<RulesPData> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<String>? pattern,
    Expression<String>? targetAccount,
    Expression<int>? hits,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (pattern != null) 'pattern': pattern,
      if (targetAccount != null) 'target_account': targetAccount,
      if (hits != null) 'hits': hits,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RulesPCompanion copyWith({
    Value<String>? id,
    Value<String>? bookId,
    Value<String>? pattern,
    Value<String>? targetAccount,
    Value<int>? hits,
    Value<int>? rowid,
  }) {
    return RulesPCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      pattern: pattern ?? this.pattern,
      targetAccount: targetAccount ?? this.targetAccount,
      hits: hits ?? this.hits,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (pattern.present) {
      map['pattern'] = Variable<String>(pattern.value);
    }
    if (targetAccount.present) {
      map['target_account'] = Variable<String>(targetAccount.value);
    }
    if (hits.present) {
      map['hits'] = Variable<int>(hits.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RulesPCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('pattern: $pattern, ')
          ..write('targetAccount: $targetAccount, ')
          ..write('hits: $hits, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BalancesTable extends Balances with TableInfo<$BalancesTable, Balance> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BalancesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _balancePaiseMeta = const VerificationMeta(
    'balancePaise',
  );
  @override
  late final GeneratedColumn<int> balancePaise = GeneratedColumn<int>(
    'balance_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _asOfHlcMeta = const VerificationMeta(
    'asOfHlc',
  );
  @override
  late final GeneratedColumn<int> asOfHlc = GeneratedColumn<int>(
    'as_of_hlc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, balancePaise, asOfHlc];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'balances';
  @override
  VerificationContext validateIntegrity(
    Insertable<Balance> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('balance_paise')) {
      context.handle(
        _balancePaiseMeta,
        balancePaise.isAcceptableOrUnknown(
          data['balance_paise']!,
          _balancePaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_balancePaiseMeta);
    }
    if (data.containsKey('as_of_hlc')) {
      context.handle(
        _asOfHlcMeta,
        asOfHlc.isAcceptableOrUnknown(data['as_of_hlc']!, _asOfHlcMeta),
      );
    } else if (isInserting) {
      context.missing(_asOfHlcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId};
  @override
  Balance map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Balance(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      balancePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}balance_paise'],
      )!,
      asOfHlc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}as_of_hlc'],
      )!,
    );
  }

  @override
  $BalancesTable createAlias(String alias) {
    return $BalancesTable(attachedDatabase, alias);
  }
}

class Balance extends DataClass implements Insertable<Balance> {
  /// Account.
  final String accountId;

  /// Signed paise.
  final int balancePaise;

  /// HLC of the last applied envelope.
  final int asOfHlc;
  const Balance({
    required this.accountId,
    required this.balancePaise,
    required this.asOfHlc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['balance_paise'] = Variable<int>(balancePaise);
    map['as_of_hlc'] = Variable<int>(asOfHlc);
    return map;
  }

  BalancesCompanion toCompanion(bool nullToAbsent) {
    return BalancesCompanion(
      accountId: Value(accountId),
      balancePaise: Value(balancePaise),
      asOfHlc: Value(asOfHlc),
    );
  }

  factory Balance.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Balance(
      accountId: serializer.fromJson<String>(json['accountId']),
      balancePaise: serializer.fromJson<int>(json['balancePaise']),
      asOfHlc: serializer.fromJson<int>(json['asOfHlc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'balancePaise': serializer.toJson<int>(balancePaise),
      'asOfHlc': serializer.toJson<int>(asOfHlc),
    };
  }

  Balance copyWith({String? accountId, int? balancePaise, int? asOfHlc}) =>
      Balance(
        accountId: accountId ?? this.accountId,
        balancePaise: balancePaise ?? this.balancePaise,
        asOfHlc: asOfHlc ?? this.asOfHlc,
      );
  Balance copyWithCompanion(BalancesCompanion data) {
    return Balance(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      balancePaise: data.balancePaise.present
          ? data.balancePaise.value
          : this.balancePaise,
      asOfHlc: data.asOfHlc.present ? data.asOfHlc.value : this.asOfHlc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Balance(')
          ..write('accountId: $accountId, ')
          ..write('balancePaise: $balancePaise, ')
          ..write('asOfHlc: $asOfHlc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, balancePaise, asOfHlc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Balance &&
          other.accountId == this.accountId &&
          other.balancePaise == this.balancePaise &&
          other.asOfHlc == this.asOfHlc);
}

class BalancesCompanion extends UpdateCompanion<Balance> {
  final Value<String> accountId;
  final Value<int> balancePaise;
  final Value<int> asOfHlc;
  final Value<int> rowid;
  const BalancesCompanion({
    this.accountId = const Value.absent(),
    this.balancePaise = const Value.absent(),
    this.asOfHlc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BalancesCompanion.insert({
    required String accountId,
    required int balancePaise,
    required int asOfHlc,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       balancePaise = Value(balancePaise),
       asOfHlc = Value(asOfHlc);
  static Insertable<Balance> custom({
    Expression<String>? accountId,
    Expression<int>? balancePaise,
    Expression<int>? asOfHlc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (balancePaise != null) 'balance_paise': balancePaise,
      if (asOfHlc != null) 'as_of_hlc': asOfHlc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BalancesCompanion copyWith({
    Value<String>? accountId,
    Value<int>? balancePaise,
    Value<int>? asOfHlc,
    Value<int>? rowid,
  }) {
    return BalancesCompanion(
      accountId: accountId ?? this.accountId,
      balancePaise: balancePaise ?? this.balancePaise,
      asOfHlc: asOfHlc ?? this.asOfHlc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (balancePaise.present) {
      map['balance_paise'] = Variable<int>(balancePaise.value);
    }
    if (asOfHlc.present) {
      map['as_of_hlc'] = Variable<int>(asOfHlc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BalancesCompanion(')
          ..write('accountId: $accountId, ')
          ..write('balancePaise: $balancePaise, ')
          ..write('asOfHlc: $asOfHlc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DailySnapshotsTable extends DailySnapshots
    with TableInfo<$DailySnapshotsTable, DailySnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailySnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _balancePaiseMeta = const VerificationMeta(
    'balancePaise',
  );
  @override
  late final GeneratedColumn<int> balancePaise = GeneratedColumn<int>(
    'balance_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, date, balancePaise];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailySnapshot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('balance_paise')) {
      context.handle(
        _balancePaiseMeta,
        balancePaise.isAcceptableOrUnknown(
          data['balance_paise']!,
          _balancePaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_balancePaiseMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, date};
  @override
  DailySnapshot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailySnapshot(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      balancePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}balance_paise'],
      )!,
    );
  }

  @override
  $DailySnapshotsTable createAlias(String alias) {
    return $DailySnapshotsTable(attachedDatabase, alias);
  }
}

class DailySnapshot extends DataClass implements Insertable<DailySnapshot> {
  /// Account.
  final String accountId;

  /// ISO date.
  final String date;

  /// Signed paise at end of day.
  final int balancePaise;
  const DailySnapshot({
    required this.accountId,
    required this.date,
    required this.balancePaise,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['date'] = Variable<String>(date);
    map['balance_paise'] = Variable<int>(balancePaise);
    return map;
  }

  DailySnapshotsCompanion toCompanion(bool nullToAbsent) {
    return DailySnapshotsCompanion(
      accountId: Value(accountId),
      date: Value(date),
      balancePaise: Value(balancePaise),
    );
  }

  factory DailySnapshot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailySnapshot(
      accountId: serializer.fromJson<String>(json['accountId']),
      date: serializer.fromJson<String>(json['date']),
      balancePaise: serializer.fromJson<int>(json['balancePaise']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'date': serializer.toJson<String>(date),
      'balancePaise': serializer.toJson<int>(balancePaise),
    };
  }

  DailySnapshot copyWith({
    String? accountId,
    String? date,
    int? balancePaise,
  }) => DailySnapshot(
    accountId: accountId ?? this.accountId,
    date: date ?? this.date,
    balancePaise: balancePaise ?? this.balancePaise,
  );
  DailySnapshot copyWithCompanion(DailySnapshotsCompanion data) {
    return DailySnapshot(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      date: data.date.present ? data.date.value : this.date,
      balancePaise: data.balancePaise.present
          ? data.balancePaise.value
          : this.balancePaise,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailySnapshot(')
          ..write('accountId: $accountId, ')
          ..write('date: $date, ')
          ..write('balancePaise: $balancePaise')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, date, balancePaise);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailySnapshot &&
          other.accountId == this.accountId &&
          other.date == this.date &&
          other.balancePaise == this.balancePaise);
}

class DailySnapshotsCompanion extends UpdateCompanion<DailySnapshot> {
  final Value<String> accountId;
  final Value<String> date;
  final Value<int> balancePaise;
  final Value<int> rowid;
  const DailySnapshotsCompanion({
    this.accountId = const Value.absent(),
    this.date = const Value.absent(),
    this.balancePaise = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailySnapshotsCompanion.insert({
    required String accountId,
    required String date,
    required int balancePaise,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       date = Value(date),
       balancePaise = Value(balancePaise);
  static Insertable<DailySnapshot> custom({
    Expression<String>? accountId,
    Expression<String>? date,
    Expression<int>? balancePaise,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (date != null) 'date': date,
      if (balancePaise != null) 'balance_paise': balancePaise,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailySnapshotsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? date,
    Value<int>? balancePaise,
    Value<int>? rowid,
  }) {
    return DailySnapshotsCompanion(
      accountId: accountId ?? this.accountId,
      date: date ?? this.date,
      balancePaise: balancePaise ?? this.balancePaise,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (balancePaise.present) {
      map['balance_paise'] = Variable<int>(balancePaise.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailySnapshotsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('date: $date, ')
          ..write('balancePaise: $balancePaise, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LedgerDatabase extends GeneratedDatabase {
  _$LedgerDatabase(QueryExecutor e) : super(e);
  $LedgerDatabaseManager get managers => $LedgerDatabaseManager(this);
  late final $EnvelopesLocalTable envelopesLocal = $EnvelopesLocalTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final $AuthorSeqLocalTable authorSeqLocal = $AuthorSeqLocalTable(this);
  late final $AuthorGapsTable authorGaps = $AuthorGapsTable(this);
  late final $AuthorDuplicatesTable authorDuplicates = $AuthorDuplicatesTable(
    this,
  );
  late final $SignedRecordsLocalTable signedRecordsLocal =
      $SignedRecordsLocalTable(this);
  late final $StoreEpochTable storeEpoch = $StoreEpochTable(this);
  late final $SyncCursorsTable syncCursors = $SyncCursorsTable(this);
  late final $KeyCacheTable keyCache = $KeyCacheTable(this);
  late final $AttachmentCacheTable attachmentCache = $AttachmentCacheTable(
    this,
  );
  late final $BooksPTable booksP = $BooksPTable(this);
  late final $AccountsPTable accountsP = $AccountsPTable(this);
  late final $EntriesPTable entriesP = $EntriesPTable(this);
  late final $EntryLinesPTable entryLinesP = $EntryLinesPTable(this);
  late final $PeriodsPTable periodsP = $PeriodsPTable(this);
  late final $CashCountsPTable cashCountsP = $CashCountsPTable(this);
  late final $YearClosePTable yearCloseP = $YearClosePTable(this);
  late final $ImportLinesPTable importLinesP = $ImportLinesPTable(this);
  late final $RulesPTable rulesP = $RulesPTable(this);
  late final $BalancesTable balances = $BalancesTable(this);
  late final $DailySnapshotsTable dailySnapshots = $DailySnapshotsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    envelopesLocal,
    outbox,
    authorSeqLocal,
    authorGaps,
    authorDuplicates,
    signedRecordsLocal,
    storeEpoch,
    syncCursors,
    keyCache,
    attachmentCache,
    booksP,
    accountsP,
    entriesP,
    entryLinesP,
    periodsP,
    cashCountsP,
    yearCloseP,
    importLinesP,
    rulesP,
    balances,
    dailySnapshots,
  ];
}

typedef $$EnvelopesLocalTableCreateCompanionBuilder =
    EnvelopesLocalCompanion Function({
      required String envelopeId,
      required String bookId,
      required String objectId,
      required String objectType,
      required int keyVersion,
      required int hlc,
      Value<int?> seq,
      required String authorDevice,
      required int authorSeq,
      required Uint8List envelopeBlob,
      required Uint8List blobHash,
      Value<int> verified,
      Value<int> quarantined,
      Value<String?> quarantineReason,
      Value<int> held,
      Value<String?> heldFor,
      Value<int> rowid,
    });
typedef $$EnvelopesLocalTableUpdateCompanionBuilder =
    EnvelopesLocalCompanion Function({
      Value<String> envelopeId,
      Value<String> bookId,
      Value<String> objectId,
      Value<String> objectType,
      Value<int> keyVersion,
      Value<int> hlc,
      Value<int?> seq,
      Value<String> authorDevice,
      Value<int> authorSeq,
      Value<Uint8List> envelopeBlob,
      Value<Uint8List> blobHash,
      Value<int> verified,
      Value<int> quarantined,
      Value<String?> quarantineReason,
      Value<int> held,
      Value<String?> heldFor,
      Value<int> rowid,
    });

class $$EnvelopesLocalTableFilterComposer
    extends Composer<_$LedgerDatabase, $EnvelopesLocalTable> {
  $$EnvelopesLocalTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get envelopeId => $composableBuilder(
    column: $table.envelopeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get objectId => $composableBuilder(
    column: $table.objectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get objectType => $composableBuilder(
    column: $table.objectType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get keyVersion => $composableBuilder(
    column: $table.keyVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorDevice => $composableBuilder(
    column: $table.authorDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get authorSeq => $composableBuilder(
    column: $table.authorSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get envelopeBlob => $composableBuilder(
    column: $table.envelopeBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get blobHash => $composableBuilder(
    column: $table.blobHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get verified => $composableBuilder(
    column: $table.verified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quarantined => $composableBuilder(
    column: $table.quarantined,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quarantineReason => $composableBuilder(
    column: $table.quarantineReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get held => $composableBuilder(
    column: $table.held,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get heldFor => $composableBuilder(
    column: $table.heldFor,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EnvelopesLocalTableOrderingComposer
    extends Composer<_$LedgerDatabase, $EnvelopesLocalTable> {
  $$EnvelopesLocalTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get envelopeId => $composableBuilder(
    column: $table.envelopeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get objectId => $composableBuilder(
    column: $table.objectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get objectType => $composableBuilder(
    column: $table.objectType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get keyVersion => $composableBuilder(
    column: $table.keyVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorDevice => $composableBuilder(
    column: $table.authorDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get authorSeq => $composableBuilder(
    column: $table.authorSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get envelopeBlob => $composableBuilder(
    column: $table.envelopeBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get blobHash => $composableBuilder(
    column: $table.blobHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get verified => $composableBuilder(
    column: $table.verified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quarantined => $composableBuilder(
    column: $table.quarantined,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quarantineReason => $composableBuilder(
    column: $table.quarantineReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get held => $composableBuilder(
    column: $table.held,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get heldFor => $composableBuilder(
    column: $table.heldFor,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EnvelopesLocalTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $EnvelopesLocalTable> {
  $$EnvelopesLocalTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get envelopeId => $composableBuilder(
    column: $table.envelopeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get objectId =>
      $composableBuilder(column: $table.objectId, builder: (column) => column);

  GeneratedColumn<String> get objectType => $composableBuilder(
    column: $table.objectType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get keyVersion => $composableBuilder(
    column: $table.keyVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get authorDevice => $composableBuilder(
    column: $table.authorDevice,
    builder: (column) => column,
  );

  GeneratedColumn<int> get authorSeq =>
      $composableBuilder(column: $table.authorSeq, builder: (column) => column);

  GeneratedColumn<Uint8List> get envelopeBlob => $composableBuilder(
    column: $table.envelopeBlob,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get blobHash =>
      $composableBuilder(column: $table.blobHash, builder: (column) => column);

  GeneratedColumn<int> get verified =>
      $composableBuilder(column: $table.verified, builder: (column) => column);

  GeneratedColumn<int> get quarantined => $composableBuilder(
    column: $table.quarantined,
    builder: (column) => column,
  );

  GeneratedColumn<String> get quarantineReason => $composableBuilder(
    column: $table.quarantineReason,
    builder: (column) => column,
  );

  GeneratedColumn<int> get held =>
      $composableBuilder(column: $table.held, builder: (column) => column);

  GeneratedColumn<String> get heldFor =>
      $composableBuilder(column: $table.heldFor, builder: (column) => column);
}

class $$EnvelopesLocalTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $EnvelopesLocalTable,
          EnvelopesLocalData,
          $$EnvelopesLocalTableFilterComposer,
          $$EnvelopesLocalTableOrderingComposer,
          $$EnvelopesLocalTableAnnotationComposer,
          $$EnvelopesLocalTableCreateCompanionBuilder,
          $$EnvelopesLocalTableUpdateCompanionBuilder,
          (
            EnvelopesLocalData,
            BaseReferences<
              _$LedgerDatabase,
              $EnvelopesLocalTable,
              EnvelopesLocalData
            >,
          ),
          EnvelopesLocalData,
          PrefetchHooks Function()
        > {
  $$EnvelopesLocalTableTableManager(
    _$LedgerDatabase db,
    $EnvelopesLocalTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EnvelopesLocalTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EnvelopesLocalTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EnvelopesLocalTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> envelopeId = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> objectId = const Value.absent(),
                Value<String> objectType = const Value.absent(),
                Value<int> keyVersion = const Value.absent(),
                Value<int> hlc = const Value.absent(),
                Value<int?> seq = const Value.absent(),
                Value<String> authorDevice = const Value.absent(),
                Value<int> authorSeq = const Value.absent(),
                Value<Uint8List> envelopeBlob = const Value.absent(),
                Value<Uint8List> blobHash = const Value.absent(),
                Value<int> verified = const Value.absent(),
                Value<int> quarantined = const Value.absent(),
                Value<String?> quarantineReason = const Value.absent(),
                Value<int> held = const Value.absent(),
                Value<String?> heldFor = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EnvelopesLocalCompanion(
                envelopeId: envelopeId,
                bookId: bookId,
                objectId: objectId,
                objectType: objectType,
                keyVersion: keyVersion,
                hlc: hlc,
                seq: seq,
                authorDevice: authorDevice,
                authorSeq: authorSeq,
                envelopeBlob: envelopeBlob,
                blobHash: blobHash,
                verified: verified,
                quarantined: quarantined,
                quarantineReason: quarantineReason,
                held: held,
                heldFor: heldFor,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String envelopeId,
                required String bookId,
                required String objectId,
                required String objectType,
                required int keyVersion,
                required int hlc,
                Value<int?> seq = const Value.absent(),
                required String authorDevice,
                required int authorSeq,
                required Uint8List envelopeBlob,
                required Uint8List blobHash,
                Value<int> verified = const Value.absent(),
                Value<int> quarantined = const Value.absent(),
                Value<String?> quarantineReason = const Value.absent(),
                Value<int> held = const Value.absent(),
                Value<String?> heldFor = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EnvelopesLocalCompanion.insert(
                envelopeId: envelopeId,
                bookId: bookId,
                objectId: objectId,
                objectType: objectType,
                keyVersion: keyVersion,
                hlc: hlc,
                seq: seq,
                authorDevice: authorDevice,
                authorSeq: authorSeq,
                envelopeBlob: envelopeBlob,
                blobHash: blobHash,
                verified: verified,
                quarantined: quarantined,
                quarantineReason: quarantineReason,
                held: held,
                heldFor: heldFor,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$EnvelopesLocalTable, EnvelopesLocalData>(table),
                  BaseReferences<
                    _$LedgerDatabase,
                    $EnvelopesLocalTable,
                    EnvelopesLocalData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EnvelopesLocalTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $EnvelopesLocalTable,
      EnvelopesLocalData,
      $$EnvelopesLocalTableFilterComposer,
      $$EnvelopesLocalTableOrderingComposer,
      $$EnvelopesLocalTableAnnotationComposer,
      $$EnvelopesLocalTableCreateCompanionBuilder,
      $$EnvelopesLocalTableUpdateCompanionBuilder,
      (
        EnvelopesLocalData,
        BaseReferences<
          _$LedgerDatabase,
          $EnvelopesLocalTable,
          EnvelopesLocalData
        >,
      ),
      EnvelopesLocalData,
      PrefetchHooks Function()
    >;
typedef $$OutboxTableCreateCompanionBuilder = OutboxCompanion Function({
  required String envelopeId,
  required String bookId,
  required Uint8List envelopeBlob,
  required int createdAt,
  required String pushState,
  Value<int?> ackedSeq,
  Value<String?> rejectReason,
  Value<int> rowid,
});
typedef $$OutboxTableUpdateCompanionBuilder = OutboxCompanion Function({
  Value<String> envelopeId,
  Value<String> bookId,
  Value<Uint8List> envelopeBlob,
  Value<int> createdAt,
  Value<String> pushState,
  Value<int?> ackedSeq,
  Value<String?> rejectReason,
  Value<int> rowid,
});

class $$OutboxTableFilterComposer
    extends Composer<_$LedgerDatabase, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get envelopeId => $composableBuilder(
    column: $table.envelopeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get envelopeBlob => $composableBuilder(
    column: $table.envelopeBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pushState => $composableBuilder(
    column: $table.pushState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ackedSeq => $composableBuilder(
    column: $table.ackedSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rejectReason => $composableBuilder(
    column: $table.rejectReason,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxTableOrderingComposer
    extends Composer<_$LedgerDatabase, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get envelopeId => $composableBuilder(
    column: $table.envelopeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get envelopeBlob => $composableBuilder(
    column: $table.envelopeBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pushState => $composableBuilder(
    column: $table.pushState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ackedSeq => $composableBuilder(
    column: $table.ackedSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rejectReason => $composableBuilder(
    column: $table.rejectReason,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get envelopeId => $composableBuilder(
    column: $table.envelopeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<Uint8List> get envelopeBlob => $composableBuilder(
    column: $table.envelopeBlob,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get pushState =>
      $composableBuilder(column: $table.pushState, builder: (column) => column);

  GeneratedColumn<int> get ackedSeq =>
      $composableBuilder(column: $table.ackedSeq, builder: (column) => column);

  GeneratedColumn<String> get rejectReason => $composableBuilder(
    column: $table.rejectReason,
    builder: (column) => column,
  );
}

class $$OutboxTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $OutboxTable,
          OutboxData,
          $$OutboxTableFilterComposer,
          $$OutboxTableOrderingComposer,
          $$OutboxTableAnnotationComposer,
          $$OutboxTableCreateCompanionBuilder,
          $$OutboxTableUpdateCompanionBuilder,
          (
            OutboxData,
            BaseReferences<_$LedgerDatabase, $OutboxTable, OutboxData>,
          ),
          OutboxData,
          PrefetchHooks Function()
        > {
  $$OutboxTableTableManager(_$LedgerDatabase db, $OutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> envelopeId = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<Uint8List> envelopeBlob = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String> pushState = const Value.absent(),
                Value<int?> ackedSeq = const Value.absent(),
                Value<String?> rejectReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxCompanion(
                envelopeId: envelopeId,
                bookId: bookId,
                envelopeBlob: envelopeBlob,
                createdAt: createdAt,
                pushState: pushState,
                ackedSeq: ackedSeq,
                rejectReason: rejectReason,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String envelopeId,
                required String bookId,
                required Uint8List envelopeBlob,
                required int createdAt,
                required String pushState,
                Value<int?> ackedSeq = const Value.absent(),
                Value<String?> rejectReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxCompanion.insert(
                envelopeId: envelopeId,
                bookId: bookId,
                envelopeBlob: envelopeBlob,
                createdAt: createdAt,
                pushState: pushState,
                ackedSeq: ackedSeq,
                rejectReason: rejectReason,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxTable, OutboxData>(table),
                  BaseReferences<_$LedgerDatabase, $OutboxTable, OutboxData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $OutboxTable,
      OutboxData,
      $$OutboxTableFilterComposer,
      $$OutboxTableOrderingComposer,
      $$OutboxTableAnnotationComposer,
      $$OutboxTableCreateCompanionBuilder,
      $$OutboxTableUpdateCompanionBuilder,
      (OutboxData, BaseReferences<_$LedgerDatabase, $OutboxTable, OutboxData>),
      OutboxData,
      PrefetchHooks Function()
    >;
typedef $$AuthorSeqLocalTableCreateCompanionBuilder =
    AuthorSeqLocalCompanion Function({
      required String bookId,
      required String deviceId,
      required int nextSeq,
      Value<int> rowid,
    });
typedef $$AuthorSeqLocalTableUpdateCompanionBuilder =
    AuthorSeqLocalCompanion Function({
      Value<String> bookId,
      Value<String> deviceId,
      Value<int> nextSeq,
      Value<int> rowid,
    });

class $$AuthorSeqLocalTableFilterComposer
    extends Composer<_$LedgerDatabase, $AuthorSeqLocalTable> {
  $$AuthorSeqLocalTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextSeq => $composableBuilder(
    column: $table.nextSeq,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AuthorSeqLocalTableOrderingComposer
    extends Composer<_$LedgerDatabase, $AuthorSeqLocalTable> {
  $$AuthorSeqLocalTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextSeq => $composableBuilder(
    column: $table.nextSeq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AuthorSeqLocalTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $AuthorSeqLocalTable> {
  $$AuthorSeqLocalTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get nextSeq =>
      $composableBuilder(column: $table.nextSeq, builder: (column) => column);
}

class $$AuthorSeqLocalTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $AuthorSeqLocalTable,
          AuthorSeqLocalData,
          $$AuthorSeqLocalTableFilterComposer,
          $$AuthorSeqLocalTableOrderingComposer,
          $$AuthorSeqLocalTableAnnotationComposer,
          $$AuthorSeqLocalTableCreateCompanionBuilder,
          $$AuthorSeqLocalTableUpdateCompanionBuilder,
          (
            AuthorSeqLocalData,
            BaseReferences<
              _$LedgerDatabase,
              $AuthorSeqLocalTable,
              AuthorSeqLocalData
            >,
          ),
          AuthorSeqLocalData,
          PrefetchHooks Function()
        > {
  $$AuthorSeqLocalTableTableManager(
    _$LedgerDatabase db,
    $AuthorSeqLocalTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AuthorSeqLocalTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AuthorSeqLocalTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AuthorSeqLocalTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> nextSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AuthorSeqLocalCompanion(
                bookId: bookId,
                deviceId: deviceId,
                nextSeq: nextSeq,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required String deviceId,
                required int nextSeq,
                Value<int> rowid = const Value.absent(),
              }) => AuthorSeqLocalCompanion.insert(
                bookId: bookId,
                deviceId: deviceId,
                nextSeq: nextSeq,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AuthorSeqLocalTable, AuthorSeqLocalData>(table),
                  BaseReferences<
                    _$LedgerDatabase,
                    $AuthorSeqLocalTable,
                    AuthorSeqLocalData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AuthorSeqLocalTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $AuthorSeqLocalTable,
      AuthorSeqLocalData,
      $$AuthorSeqLocalTableFilterComposer,
      $$AuthorSeqLocalTableOrderingComposer,
      $$AuthorSeqLocalTableAnnotationComposer,
      $$AuthorSeqLocalTableCreateCompanionBuilder,
      $$AuthorSeqLocalTableUpdateCompanionBuilder,
      (
        AuthorSeqLocalData,
        BaseReferences<
          _$LedgerDatabase,
          $AuthorSeqLocalTable,
          AuthorSeqLocalData
        >,
      ),
      AuthorSeqLocalData,
      PrefetchHooks Function()
    >;
typedef $$AuthorGapsTableCreateCompanionBuilder = AuthorGapsCompanion Function({
  required String bookId,
  required String authorDevice,
  required int expectedSeq,
  required int sinceHlc,
  Value<int> rowid,
});
typedef $$AuthorGapsTableUpdateCompanionBuilder = AuthorGapsCompanion Function({
  Value<String> bookId,
  Value<String> authorDevice,
  Value<int> expectedSeq,
  Value<int> sinceHlc,
  Value<int> rowid,
});

class $$AuthorGapsTableFilterComposer
    extends Composer<_$LedgerDatabase, $AuthorGapsTable> {
  $$AuthorGapsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorDevice => $composableBuilder(
    column: $table.authorDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedSeq => $composableBuilder(
    column: $table.expectedSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sinceHlc => $composableBuilder(
    column: $table.sinceHlc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AuthorGapsTableOrderingComposer
    extends Composer<_$LedgerDatabase, $AuthorGapsTable> {
  $$AuthorGapsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorDevice => $composableBuilder(
    column: $table.authorDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedSeq => $composableBuilder(
    column: $table.expectedSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sinceHlc => $composableBuilder(
    column: $table.sinceHlc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AuthorGapsTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $AuthorGapsTable> {
  $$AuthorGapsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get authorDevice => $composableBuilder(
    column: $table.authorDevice,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expectedSeq => $composableBuilder(
    column: $table.expectedSeq,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sinceHlc =>
      $composableBuilder(column: $table.sinceHlc, builder: (column) => column);
}

class $$AuthorGapsTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $AuthorGapsTable,
          AuthorGap,
          $$AuthorGapsTableFilterComposer,
          $$AuthorGapsTableOrderingComposer,
          $$AuthorGapsTableAnnotationComposer,
          $$AuthorGapsTableCreateCompanionBuilder,
          $$AuthorGapsTableUpdateCompanionBuilder,
          (
            AuthorGap,
            BaseReferences<_$LedgerDatabase, $AuthorGapsTable, AuthorGap>,
          ),
          AuthorGap,
          PrefetchHooks Function()
        > {
  $$AuthorGapsTableTableManager(_$LedgerDatabase db, $AuthorGapsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AuthorGapsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AuthorGapsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AuthorGapsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<String> authorDevice = const Value.absent(),
                Value<int> expectedSeq = const Value.absent(),
                Value<int> sinceHlc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AuthorGapsCompanion(
                bookId: bookId,
                authorDevice: authorDevice,
                expectedSeq: expectedSeq,
                sinceHlc: sinceHlc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required String authorDevice,
                required int expectedSeq,
                required int sinceHlc,
                Value<int> rowid = const Value.absent(),
              }) => AuthorGapsCompanion.insert(
                bookId: bookId,
                authorDevice: authorDevice,
                expectedSeq: expectedSeq,
                sinceHlc: sinceHlc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AuthorGapsTable, AuthorGap>(table),
                  BaseReferences<_$LedgerDatabase, $AuthorGapsTable, AuthorGap>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AuthorGapsTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $AuthorGapsTable,
      AuthorGap,
      $$AuthorGapsTableFilterComposer,
      $$AuthorGapsTableOrderingComposer,
      $$AuthorGapsTableAnnotationComposer,
      $$AuthorGapsTableCreateCompanionBuilder,
      $$AuthorGapsTableUpdateCompanionBuilder,
      (
        AuthorGap,
        BaseReferences<_$LedgerDatabase, $AuthorGapsTable, AuthorGap>,
      ),
      AuthorGap,
      PrefetchHooks Function()
    >;
typedef $$AuthorDuplicatesTableCreateCompanionBuilder =
    AuthorDuplicatesCompanion Function({
      required String bookId,
      required String authorDevice,
      required int authorSeq,
      required String keptEnvelopeId,
      required String duplicateEnvelopeId,
      Value<int> rowid,
    });
typedef $$AuthorDuplicatesTableUpdateCompanionBuilder =
    AuthorDuplicatesCompanion Function({
      Value<String> bookId,
      Value<String> authorDevice,
      Value<int> authorSeq,
      Value<String> keptEnvelopeId,
      Value<String> duplicateEnvelopeId,
      Value<int> rowid,
    });

class $$AuthorDuplicatesTableFilterComposer
    extends Composer<_$LedgerDatabase, $AuthorDuplicatesTable> {
  $$AuthorDuplicatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorDevice => $composableBuilder(
    column: $table.authorDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get authorSeq => $composableBuilder(
    column: $table.authorSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keptEnvelopeId => $composableBuilder(
    column: $table.keptEnvelopeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get duplicateEnvelopeId => $composableBuilder(
    column: $table.duplicateEnvelopeId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AuthorDuplicatesTableOrderingComposer
    extends Composer<_$LedgerDatabase, $AuthorDuplicatesTable> {
  $$AuthorDuplicatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorDevice => $composableBuilder(
    column: $table.authorDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get authorSeq => $composableBuilder(
    column: $table.authorSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keptEnvelopeId => $composableBuilder(
    column: $table.keptEnvelopeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get duplicateEnvelopeId => $composableBuilder(
    column: $table.duplicateEnvelopeId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AuthorDuplicatesTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $AuthorDuplicatesTable> {
  $$AuthorDuplicatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get authorDevice => $composableBuilder(
    column: $table.authorDevice,
    builder: (column) => column,
  );

  GeneratedColumn<int> get authorSeq =>
      $composableBuilder(column: $table.authorSeq, builder: (column) => column);

  GeneratedColumn<String> get keptEnvelopeId => $composableBuilder(
    column: $table.keptEnvelopeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get duplicateEnvelopeId => $composableBuilder(
    column: $table.duplicateEnvelopeId,
    builder: (column) => column,
  );
}

class $$AuthorDuplicatesTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $AuthorDuplicatesTable,
          AuthorDuplicate,
          $$AuthorDuplicatesTableFilterComposer,
          $$AuthorDuplicatesTableOrderingComposer,
          $$AuthorDuplicatesTableAnnotationComposer,
          $$AuthorDuplicatesTableCreateCompanionBuilder,
          $$AuthorDuplicatesTableUpdateCompanionBuilder,
          (
            AuthorDuplicate,
            BaseReferences<
              _$LedgerDatabase,
              $AuthorDuplicatesTable,
              AuthorDuplicate
            >,
          ),
          AuthorDuplicate,
          PrefetchHooks Function()
        > {
  $$AuthorDuplicatesTableTableManager(
    _$LedgerDatabase db,
    $AuthorDuplicatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AuthorDuplicatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AuthorDuplicatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AuthorDuplicatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<String> authorDevice = const Value.absent(),
                Value<int> authorSeq = const Value.absent(),
                Value<String> keptEnvelopeId = const Value.absent(),
                Value<String> duplicateEnvelopeId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AuthorDuplicatesCompanion(
                bookId: bookId,
                authorDevice: authorDevice,
                authorSeq: authorSeq,
                keptEnvelopeId: keptEnvelopeId,
                duplicateEnvelopeId: duplicateEnvelopeId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required String authorDevice,
                required int authorSeq,
                required String keptEnvelopeId,
                required String duplicateEnvelopeId,
                Value<int> rowid = const Value.absent(),
              }) => AuthorDuplicatesCompanion.insert(
                bookId: bookId,
                authorDevice: authorDevice,
                authorSeq: authorSeq,
                keptEnvelopeId: keptEnvelopeId,
                duplicateEnvelopeId: duplicateEnvelopeId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AuthorDuplicatesTable, AuthorDuplicate>(table),
                  BaseReferences<
                    _$LedgerDatabase,
                    $AuthorDuplicatesTable,
                    AuthorDuplicate
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AuthorDuplicatesTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $AuthorDuplicatesTable,
      AuthorDuplicate,
      $$AuthorDuplicatesTableFilterComposer,
      $$AuthorDuplicatesTableOrderingComposer,
      $$AuthorDuplicatesTableAnnotationComposer,
      $$AuthorDuplicatesTableCreateCompanionBuilder,
      $$AuthorDuplicatesTableUpdateCompanionBuilder,
      (
        AuthorDuplicate,
        BaseReferences<
          _$LedgerDatabase,
          $AuthorDuplicatesTable,
          AuthorDuplicate
        >,
      ),
      AuthorDuplicate,
      PrefetchHooks Function()
    >;
typedef $$SignedRecordsLocalTableCreateCompanionBuilder =
    SignedRecordsLocalCompanion Function({
      required String id,
      required String tenantId,
      required String kind,
      required Uint8List payload,
      required String authorDevice,
      required Uint8List sig,
      required int hlc,
      Value<int?> seq,
      Value<int> verified,
      Value<int> rowid,
    });
typedef $$SignedRecordsLocalTableUpdateCompanionBuilder =
    SignedRecordsLocalCompanion Function({
      Value<String> id,
      Value<String> tenantId,
      Value<String> kind,
      Value<Uint8List> payload,
      Value<String> authorDevice,
      Value<Uint8List> sig,
      Value<int> hlc,
      Value<int?> seq,
      Value<int> verified,
      Value<int> rowid,
    });

class $$SignedRecordsLocalTableFilterComposer
    extends Composer<_$LedgerDatabase, $SignedRecordsLocalTable> {
  $$SignedRecordsLocalTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorDevice => $composableBuilder(
    column: $table.authorDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get sig => $composableBuilder(
    column: $table.sig,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get verified => $composableBuilder(
    column: $table.verified,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SignedRecordsLocalTableOrderingComposer
    extends Composer<_$LedgerDatabase, $SignedRecordsLocalTable> {
  $$SignedRecordsLocalTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorDevice => $composableBuilder(
    column: $table.authorDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get sig => $composableBuilder(
    column: $table.sig,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get verified => $composableBuilder(
    column: $table.verified,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SignedRecordsLocalTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $SignedRecordsLocalTable> {
  $$SignedRecordsLocalTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get tenantId =>
      $composableBuilder(column: $table.tenantId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get authorDevice => $composableBuilder(
    column: $table.authorDevice,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get sig =>
      $composableBuilder(column: $table.sig, builder: (column) => column);

  GeneratedColumn<int> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<int> get verified =>
      $composableBuilder(column: $table.verified, builder: (column) => column);
}

class $$SignedRecordsLocalTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $SignedRecordsLocalTable,
          SignedRecordsLocalData,
          $$SignedRecordsLocalTableFilterComposer,
          $$SignedRecordsLocalTableOrderingComposer,
          $$SignedRecordsLocalTableAnnotationComposer,
          $$SignedRecordsLocalTableCreateCompanionBuilder,
          $$SignedRecordsLocalTableUpdateCompanionBuilder,
          (
            SignedRecordsLocalData,
            BaseReferences<
              _$LedgerDatabase,
              $SignedRecordsLocalTable,
              SignedRecordsLocalData
            >,
          ),
          SignedRecordsLocalData,
          PrefetchHooks Function()
        > {
  $$SignedRecordsLocalTableTableManager(
    _$LedgerDatabase db,
    $SignedRecordsLocalTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SignedRecordsLocalTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SignedRecordsLocalTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SignedRecordsLocalTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> tenantId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<Uint8List> payload = const Value.absent(),
                Value<String> authorDevice = const Value.absent(),
                Value<Uint8List> sig = const Value.absent(),
                Value<int> hlc = const Value.absent(),
                Value<int?> seq = const Value.absent(),
                Value<int> verified = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SignedRecordsLocalCompanion(
                id: id,
                tenantId: tenantId,
                kind: kind,
                payload: payload,
                authorDevice: authorDevice,
                sig: sig,
                hlc: hlc,
                seq: seq,
                verified: verified,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String tenantId,
                required String kind,
                required Uint8List payload,
                required String authorDevice,
                required Uint8List sig,
                required int hlc,
                Value<int?> seq = const Value.absent(),
                Value<int> verified = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SignedRecordsLocalCompanion.insert(
                id: id,
                tenantId: tenantId,
                kind: kind,
                payload: payload,
                authorDevice: authorDevice,
                sig: sig,
                hlc: hlc,
                seq: seq,
                verified: verified,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SignedRecordsLocalTable, SignedRecordsLocalData>(
                    table,
                  ),
                  BaseReferences<
                    _$LedgerDatabase,
                    $SignedRecordsLocalTable,
                    SignedRecordsLocalData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SignedRecordsLocalTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $SignedRecordsLocalTable,
      SignedRecordsLocalData,
      $$SignedRecordsLocalTableFilterComposer,
      $$SignedRecordsLocalTableOrderingComposer,
      $$SignedRecordsLocalTableAnnotationComposer,
      $$SignedRecordsLocalTableCreateCompanionBuilder,
      $$SignedRecordsLocalTableUpdateCompanionBuilder,
      (
        SignedRecordsLocalData,
        BaseReferences<
          _$LedgerDatabase,
          $SignedRecordsLocalTable,
          SignedRecordsLocalData
        >,
      ),
      SignedRecordsLocalData,
      PrefetchHooks Function()
    >;
typedef $$StoreEpochTableCreateCompanionBuilder = StoreEpochCompanion Function({
  Value<int> id,
  required String epoch,
});
typedef $$StoreEpochTableUpdateCompanionBuilder = StoreEpochCompanion Function({
  Value<int> id,
  Value<String> epoch,
});

class $$StoreEpochTableFilterComposer
    extends Composer<_$LedgerDatabase, $StoreEpochTable> {
  $$StoreEpochTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get epoch => $composableBuilder(
    column: $table.epoch,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoreEpochTableOrderingComposer
    extends Composer<_$LedgerDatabase, $StoreEpochTable> {
  $$StoreEpochTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get epoch => $composableBuilder(
    column: $table.epoch,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoreEpochTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $StoreEpochTable> {
  $$StoreEpochTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get epoch =>
      $composableBuilder(column: $table.epoch, builder: (column) => column);
}

class $$StoreEpochTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $StoreEpochTable,
          StoreEpochData,
          $$StoreEpochTableFilterComposer,
          $$StoreEpochTableOrderingComposer,
          $$StoreEpochTableAnnotationComposer,
          $$StoreEpochTableCreateCompanionBuilder,
          $$StoreEpochTableUpdateCompanionBuilder,
          (
            StoreEpochData,
            BaseReferences<_$LedgerDatabase, $StoreEpochTable, StoreEpochData>,
          ),
          StoreEpochData,
          PrefetchHooks Function()
        > {
  $$StoreEpochTableTableManager(_$LedgerDatabase db, $StoreEpochTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoreEpochTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoreEpochTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoreEpochTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> epoch = const Value.absent(),
          }) => StoreEpochCompanion(id: id, epoch: epoch),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String epoch,
          }) => StoreEpochCompanion.insert(id: id, epoch: epoch),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StoreEpochTable, StoreEpochData>(table),
                  BaseReferences<
                    _$LedgerDatabase,
                    $StoreEpochTable,
                    StoreEpochData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoreEpochTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $StoreEpochTable,
      StoreEpochData,
      $$StoreEpochTableFilterComposer,
      $$StoreEpochTableOrderingComposer,
      $$StoreEpochTableAnnotationComposer,
      $$StoreEpochTableCreateCompanionBuilder,
      $$StoreEpochTableUpdateCompanionBuilder,
      (
        StoreEpochData,
        BaseReferences<_$LedgerDatabase, $StoreEpochTable, StoreEpochData>,
      ),
      StoreEpochData,
      PrefetchHooks Function()
    >;
typedef $$SyncCursorsTableCreateCompanionBuilder =
    SyncCursorsCompanion Function({
      required String bookId,
      required int lastSeq,
      Value<int> rowid,
    });
typedef $$SyncCursorsTableUpdateCompanionBuilder =
    SyncCursorsCompanion Function({
      Value<String> bookId,
      Value<int> lastSeq,
      Value<int> rowid,
    });

class $$SyncCursorsTableFilterComposer
    extends Composer<_$LedgerDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeq => $composableBuilder(
    column: $table.lastSeq,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncCursorsTableOrderingComposer
    extends Composer<_$LedgerDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeq => $composableBuilder(
    column: $table.lastSeq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncCursorsTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<int> get lastSeq =>
      $composableBuilder(column: $table.lastSeq, builder: (column) => column);
}

class $$SyncCursorsTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $SyncCursorsTable,
          SyncCursor,
          $$SyncCursorsTableFilterComposer,
          $$SyncCursorsTableOrderingComposer,
          $$SyncCursorsTableAnnotationComposer,
          $$SyncCursorsTableCreateCompanionBuilder,
          $$SyncCursorsTableUpdateCompanionBuilder,
          (
            SyncCursor,
            BaseReferences<_$LedgerDatabase, $SyncCursorsTable, SyncCursor>,
          ),
          SyncCursor,
          PrefetchHooks Function()
        > {
  $$SyncCursorsTableTableManager(_$LedgerDatabase db, $SyncCursorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCursorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCursorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCursorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<int> lastSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorsCompanion(
                bookId: bookId,
                lastSeq: lastSeq,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required int lastSeq,
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorsCompanion.insert(
                bookId: bookId,
                lastSeq: lastSeq,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncCursorsTable, SyncCursor>(table),
                  BaseReferences<
                    _$LedgerDatabase,
                    $SyncCursorsTable,
                    SyncCursor
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncCursorsTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $SyncCursorsTable,
      SyncCursor,
      $$SyncCursorsTableFilterComposer,
      $$SyncCursorsTableOrderingComposer,
      $$SyncCursorsTableAnnotationComposer,
      $$SyncCursorsTableCreateCompanionBuilder,
      $$SyncCursorsTableUpdateCompanionBuilder,
      (
        SyncCursor,
        BaseReferences<_$LedgerDatabase, $SyncCursorsTable, SyncCursor>,
      ),
      SyncCursor,
      PrefetchHooks Function()
    >;
typedef $$KeyCacheTableCreateCompanionBuilder = KeyCacheCompanion Function({
  required String bookId,
  required int keyVersion,
  required Uint8List wrappedBlob,
  Value<int> rowid,
});
typedef $$KeyCacheTableUpdateCompanionBuilder = KeyCacheCompanion Function({
  Value<String> bookId,
  Value<int> keyVersion,
  Value<Uint8List> wrappedBlob,
  Value<int> rowid,
});

class $$KeyCacheTableFilterComposer
    extends Composer<_$LedgerDatabase, $KeyCacheTable> {
  $$KeyCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get keyVersion => $composableBuilder(
    column: $table.keyVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get wrappedBlob => $composableBuilder(
    column: $table.wrappedBlob,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KeyCacheTableOrderingComposer
    extends Composer<_$LedgerDatabase, $KeyCacheTable> {
  $$KeyCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get keyVersion => $composableBuilder(
    column: $table.keyVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get wrappedBlob => $composableBuilder(
    column: $table.wrappedBlob,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KeyCacheTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $KeyCacheTable> {
  $$KeyCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<int> get keyVersion => $composableBuilder(
    column: $table.keyVersion,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get wrappedBlob => $composableBuilder(
    column: $table.wrappedBlob,
    builder: (column) => column,
  );
}

class $$KeyCacheTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $KeyCacheTable,
          KeyCacheData,
          $$KeyCacheTableFilterComposer,
          $$KeyCacheTableOrderingComposer,
          $$KeyCacheTableAnnotationComposer,
          $$KeyCacheTableCreateCompanionBuilder,
          $$KeyCacheTableUpdateCompanionBuilder,
          (
            KeyCacheData,
            BaseReferences<_$LedgerDatabase, $KeyCacheTable, KeyCacheData>,
          ),
          KeyCacheData,
          PrefetchHooks Function()
        > {
  $$KeyCacheTableTableManager(_$LedgerDatabase db, $KeyCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KeyCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KeyCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KeyCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<int> keyVersion = const Value.absent(),
                Value<Uint8List> wrappedBlob = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KeyCacheCompanion(
                bookId: bookId,
                keyVersion: keyVersion,
                wrappedBlob: wrappedBlob,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required int keyVersion,
                required Uint8List wrappedBlob,
                Value<int> rowid = const Value.absent(),
              }) => KeyCacheCompanion.insert(
                bookId: bookId,
                keyVersion: keyVersion,
                wrappedBlob: wrappedBlob,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KeyCacheTable, KeyCacheData>(table),
                  BaseReferences<
                    _$LedgerDatabase,
                    $KeyCacheTable,
                    KeyCacheData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KeyCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $KeyCacheTable,
      KeyCacheData,
      $$KeyCacheTableFilterComposer,
      $$KeyCacheTableOrderingComposer,
      $$KeyCacheTableAnnotationComposer,
      $$KeyCacheTableCreateCompanionBuilder,
      $$KeyCacheTableUpdateCompanionBuilder,
      (
        KeyCacheData,
        BaseReferences<_$LedgerDatabase, $KeyCacheTable, KeyCacheData>,
      ),
      KeyCacheData,
      PrefetchHooks Function()
    >;
typedef $$AttachmentCacheTableCreateCompanionBuilder =
    AttachmentCacheCompanion Function({
      required String id,
      required String bookId,
      required String localPath,
      required String state,
      Value<int> rowid,
    });
typedef $$AttachmentCacheTableUpdateCompanionBuilder =
    AttachmentCacheCompanion Function({
      Value<String> id,
      Value<String> bookId,
      Value<String> localPath,
      Value<String> state,
      Value<int> rowid,
    });

class $$AttachmentCacheTableFilterComposer
    extends Composer<_$LedgerDatabase, $AttachmentCacheTable> {
  $$AttachmentCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AttachmentCacheTableOrderingComposer
    extends Composer<_$LedgerDatabase, $AttachmentCacheTable> {
  $$AttachmentCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AttachmentCacheTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $AttachmentCacheTable> {
  $$AttachmentCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);
}

class $$AttachmentCacheTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $AttachmentCacheTable,
          AttachmentCacheData,
          $$AttachmentCacheTableFilterComposer,
          $$AttachmentCacheTableOrderingComposer,
          $$AttachmentCacheTableAnnotationComposer,
          $$AttachmentCacheTableCreateCompanionBuilder,
          $$AttachmentCacheTableUpdateCompanionBuilder,
          (
            AttachmentCacheData,
            BaseReferences<
              _$LedgerDatabase,
              $AttachmentCacheTable,
              AttachmentCacheData
            >,
          ),
          AttachmentCacheData,
          PrefetchHooks Function()
        > {
  $$AttachmentCacheTableTableManager(
    _$LedgerDatabase db,
    $AttachmentCacheTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AttachmentCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AttachmentCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AttachmentCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentCacheCompanion(
                id: id,
                bookId: bookId,
                localPath: localPath,
                state: state,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String bookId,
                required String localPath,
                required String state,
                Value<int> rowid = const Value.absent(),
              }) => AttachmentCacheCompanion.insert(
                id: id,
                bookId: bookId,
                localPath: localPath,
                state: state,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AttachmentCacheTable, AttachmentCacheData>(
                    table,
                  ),
                  BaseReferences<
                    _$LedgerDatabase,
                    $AttachmentCacheTable,
                    AttachmentCacheData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AttachmentCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $AttachmentCacheTable,
      AttachmentCacheData,
      $$AttachmentCacheTableFilterComposer,
      $$AttachmentCacheTableOrderingComposer,
      $$AttachmentCacheTableAnnotationComposer,
      $$AttachmentCacheTableCreateCompanionBuilder,
      $$AttachmentCacheTableUpdateCompanionBuilder,
      (
        AttachmentCacheData,
        BaseReferences<
          _$LedgerDatabase,
          $AttachmentCacheTable,
          AttachmentCacheData
        >,
      ),
      AttachmentCacheData,
      PrefetchHooks Function()
    >;
typedef $$BooksPTableCreateCompanionBuilder = BooksPCompanion Function({
  required String id,
  required String tenantId,
  required String type,
  required String name,
  Value<int> fyStartMonth,
  Value<int> integrityOk,
  Value<int> needsRebootstrap,
  Value<int> rowid,
});
typedef $$BooksPTableUpdateCompanionBuilder = BooksPCompanion Function({
  Value<String> id,
  Value<String> tenantId,
  Value<String> type,
  Value<String> name,
  Value<int> fyStartMonth,
  Value<int> integrityOk,
  Value<int> needsRebootstrap,
  Value<int> rowid,
});

class $$BooksPTableFilterComposer
    extends Composer<_$LedgerDatabase, $BooksPTable> {
  $$BooksPTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fyStartMonth => $composableBuilder(
    column: $table.fyStartMonth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get integrityOk => $composableBuilder(
    column: $table.integrityOk,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get needsRebootstrap => $composableBuilder(
    column: $table.needsRebootstrap,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BooksPTableOrderingComposer
    extends Composer<_$LedgerDatabase, $BooksPTable> {
  $$BooksPTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fyStartMonth => $composableBuilder(
    column: $table.fyStartMonth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get integrityOk => $composableBuilder(
    column: $table.integrityOk,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get needsRebootstrap => $composableBuilder(
    column: $table.needsRebootstrap,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BooksPTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $BooksPTable> {
  $$BooksPTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get tenantId =>
      $composableBuilder(column: $table.tenantId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get fyStartMonth => $composableBuilder(
    column: $table.fyStartMonth,
    builder: (column) => column,
  );

  GeneratedColumn<int> get integrityOk => $composableBuilder(
    column: $table.integrityOk,
    builder: (column) => column,
  );

  GeneratedColumn<int> get needsRebootstrap => $composableBuilder(
    column: $table.needsRebootstrap,
    builder: (column) => column,
  );
}

class $$BooksPTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $BooksPTable,
          BooksPData,
          $$BooksPTableFilterComposer,
          $$BooksPTableOrderingComposer,
          $$BooksPTableAnnotationComposer,
          $$BooksPTableCreateCompanionBuilder,
          $$BooksPTableUpdateCompanionBuilder,
          (
            BooksPData,
            BaseReferences<_$LedgerDatabase, $BooksPTable, BooksPData>,
          ),
          BooksPData,
          PrefetchHooks Function()
        > {
  $$BooksPTableTableManager(_$LedgerDatabase db, $BooksPTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BooksPTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BooksPTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BooksPTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> tenantId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> fyStartMonth = const Value.absent(),
                Value<int> integrityOk = const Value.absent(),
                Value<int> needsRebootstrap = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksPCompanion(
                id: id,
                tenantId: tenantId,
                type: type,
                name: name,
                fyStartMonth: fyStartMonth,
                integrityOk: integrityOk,
                needsRebootstrap: needsRebootstrap,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String tenantId,
                required String type,
                required String name,
                Value<int> fyStartMonth = const Value.absent(),
                Value<int> integrityOk = const Value.absent(),
                Value<int> needsRebootstrap = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksPCompanion.insert(
                id: id,
                tenantId: tenantId,
                type: type,
                name: name,
                fyStartMonth: fyStartMonth,
                integrityOk: integrityOk,
                needsRebootstrap: needsRebootstrap,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BooksPTable, BooksPData>(table),
                  BaseReferences<_$LedgerDatabase, $BooksPTable, BooksPData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BooksPTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $BooksPTable,
      BooksPData,
      $$BooksPTableFilterComposer,
      $$BooksPTableOrderingComposer,
      $$BooksPTableAnnotationComposer,
      $$BooksPTableCreateCompanionBuilder,
      $$BooksPTableUpdateCompanionBuilder,
      (BooksPData, BaseReferences<_$LedgerDatabase, $BooksPTable, BooksPData>),
      BooksPData,
      PrefetchHooks Function()
    >;
typedef $$AccountsPTableCreateCompanionBuilder = AccountsPCompanion Function({
  required String id,
  required String bookId,
  required String name,
  required String accountClass,
  Value<String?> moneySubtype,
  Value<String?> collectionIncomeAccountId,
  Value<String?> usualCategoryId,
  Value<int> archived,
  Value<String?> systemRole,
  Value<String?> memberId,
  Value<String?> counterpartBookId,
  required int createdOrder,
  Value<int> rowid,
});
typedef $$AccountsPTableUpdateCompanionBuilder = AccountsPCompanion Function({
  Value<String> id,
  Value<String> bookId,
  Value<String> name,
  Value<String> accountClass,
  Value<String?> moneySubtype,
  Value<String?> collectionIncomeAccountId,
  Value<String?> usualCategoryId,
  Value<int> archived,
  Value<String?> systemRole,
  Value<String?> memberId,
  Value<String?> counterpartBookId,
  Value<int> createdOrder,
  Value<int> rowid,
});

class $$AccountsPTableFilterComposer
    extends Composer<_$LedgerDatabase, $AccountsPTable> {
  $$AccountsPTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountClass => $composableBuilder(
    column: $table.accountClass,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get moneySubtype => $composableBuilder(
    column: $table.moneySubtype,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collectionIncomeAccountId => $composableBuilder(
    column: $table.collectionIncomeAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get usualCategoryId => $composableBuilder(
    column: $table.usualCategoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get systemRole => $composableBuilder(
    column: $table.systemRole,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get memberId => $composableBuilder(
    column: $table.memberId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get counterpartBookId => $composableBuilder(
    column: $table.counterpartBookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdOrder => $composableBuilder(
    column: $table.createdOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AccountsPTableOrderingComposer
    extends Composer<_$LedgerDatabase, $AccountsPTable> {
  $$AccountsPTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountClass => $composableBuilder(
    column: $table.accountClass,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get moneySubtype => $composableBuilder(
    column: $table.moneySubtype,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collectionIncomeAccountId => $composableBuilder(
    column: $table.collectionIncomeAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get usualCategoryId => $composableBuilder(
    column: $table.usualCategoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get systemRole => $composableBuilder(
    column: $table.systemRole,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get memberId => $composableBuilder(
    column: $table.memberId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get counterpartBookId => $composableBuilder(
    column: $table.counterpartBookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdOrder => $composableBuilder(
    column: $table.createdOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountsPTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $AccountsPTable> {
  $$AccountsPTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get accountClass => $composableBuilder(
    column: $table.accountClass,
    builder: (column) => column,
  );

  GeneratedColumn<String> get moneySubtype => $composableBuilder(
    column: $table.moneySubtype,
    builder: (column) => column,
  );

  GeneratedColumn<String> get collectionIncomeAccountId => $composableBuilder(
    column: $table.collectionIncomeAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get usualCategoryId => $composableBuilder(
    column: $table.usualCategoryId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<String> get systemRole => $composableBuilder(
    column: $table.systemRole,
    builder: (column) => column,
  );

  GeneratedColumn<String> get memberId =>
      $composableBuilder(column: $table.memberId, builder: (column) => column);

  GeneratedColumn<String> get counterpartBookId => $composableBuilder(
    column: $table.counterpartBookId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdOrder => $composableBuilder(
    column: $table.createdOrder,
    builder: (column) => column,
  );
}

class $$AccountsPTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $AccountsPTable,
          AccountsPData,
          $$AccountsPTableFilterComposer,
          $$AccountsPTableOrderingComposer,
          $$AccountsPTableAnnotationComposer,
          $$AccountsPTableCreateCompanionBuilder,
          $$AccountsPTableUpdateCompanionBuilder,
          (
            AccountsPData,
            BaseReferences<_$LedgerDatabase, $AccountsPTable, AccountsPData>,
          ),
          AccountsPData,
          PrefetchHooks Function()
        > {
  $$AccountsPTableTableManager(_$LedgerDatabase db, $AccountsPTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountsPTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountsPTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountsPTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> accountClass = const Value.absent(),
                Value<String?> moneySubtype = const Value.absent(),
                Value<String?> collectionIncomeAccountId = const Value.absent(),
                Value<String?> usualCategoryId = const Value.absent(),
                Value<int> archived = const Value.absent(),
                Value<String?> systemRole = const Value.absent(),
                Value<String?> memberId = const Value.absent(),
                Value<String?> counterpartBookId = const Value.absent(),
                Value<int> createdOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsPCompanion(
                id: id,
                bookId: bookId,
                name: name,
                accountClass: accountClass,
                moneySubtype: moneySubtype,
                collectionIncomeAccountId: collectionIncomeAccountId,
                usualCategoryId: usualCategoryId,
                archived: archived,
                systemRole: systemRole,
                memberId: memberId,
                counterpartBookId: counterpartBookId,
                createdOrder: createdOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String bookId,
                required String name,
                required String accountClass,
                Value<String?> moneySubtype = const Value.absent(),
                Value<String?> collectionIncomeAccountId = const Value.absent(),
                Value<String?> usualCategoryId = const Value.absent(),
                Value<int> archived = const Value.absent(),
                Value<String?> systemRole = const Value.absent(),
                Value<String?> memberId = const Value.absent(),
                Value<String?> counterpartBookId = const Value.absent(),
                required int createdOrder,
                Value<int> rowid = const Value.absent(),
              }) => AccountsPCompanion.insert(
                id: id,
                bookId: bookId,
                name: name,
                accountClass: accountClass,
                moneySubtype: moneySubtype,
                collectionIncomeAccountId: collectionIncomeAccountId,
                usualCategoryId: usualCategoryId,
                archived: archived,
                systemRole: systemRole,
                memberId: memberId,
                counterpartBookId: counterpartBookId,
                createdOrder: createdOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AccountsPTable, AccountsPData>(table),
                  BaseReferences<
                    _$LedgerDatabase,
                    $AccountsPTable,
                    AccountsPData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AccountsPTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $AccountsPTable,
      AccountsPData,
      $$AccountsPTableFilterComposer,
      $$AccountsPTableOrderingComposer,
      $$AccountsPTableAnnotationComposer,
      $$AccountsPTableCreateCompanionBuilder,
      $$AccountsPTableUpdateCompanionBuilder,
      (
        AccountsPData,
        BaseReferences<_$LedgerDatabase, $AccountsPTable, AccountsPData>,
      ),
      AccountsPData,
      PrefetchHooks Function()
    >;
typedef $$EntriesPTableCreateCompanionBuilder = EntriesPCompanion Function({
  required String id,
  required String bookId,
  required String kind,
  required String status,
  required String accountingDate,
  Value<String?> note,
  Value<String?> channel,
  Value<String?> partyId,
  Value<String?> advanceRef,
  Value<String?> transferGroup,
  Value<String?> amends,
  Value<String?> reverses,
  Value<String?> supersededBy,
  Value<String> reviewState,
  Value<String?> reviewApprover,
  Value<int?> reviewDecidedHlc,
  Value<String?> reviewReason,
  required String createdByUser,
  required int hlc,
  Value<int> rowid,
});
typedef $$EntriesPTableUpdateCompanionBuilder = EntriesPCompanion Function({
  Value<String> id,
  Value<String> bookId,
  Value<String> kind,
  Value<String> status,
  Value<String> accountingDate,
  Value<String?> note,
  Value<String?> channel,
  Value<String?> partyId,
  Value<String?> advanceRef,
  Value<String?> transferGroup,
  Value<String?> amends,
  Value<String?> reverses,
  Value<String?> supersededBy,
  Value<String> reviewState,
  Value<String?> reviewApprover,
  Value<int?> reviewDecidedHlc,
  Value<String?> reviewReason,
  Value<String> createdByUser,
  Value<int> hlc,
  Value<int> rowid,
});

class $$EntriesPTableFilterComposer
    extends Composer<_$LedgerDatabase, $EntriesPTable> {
  $$EntriesPTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountingDate => $composableBuilder(
    column: $table.accountingDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get partyId => $composableBuilder(
    column: $table.partyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get advanceRef => $composableBuilder(
    column: $table.advanceRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transferGroup => $composableBuilder(
    column: $table.transferGroup,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get amends => $composableBuilder(
    column: $table.amends,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reverses => $composableBuilder(
    column: $table.reverses,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get supersededBy => $composableBuilder(
    column: $table.supersededBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reviewState => $composableBuilder(
    column: $table.reviewState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reviewApprover => $composableBuilder(
    column: $table.reviewApprover,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reviewDecidedHlc => $composableBuilder(
    column: $table.reviewDecidedHlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reviewReason => $composableBuilder(
    column: $table.reviewReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdByUser => $composableBuilder(
    column: $table.createdByUser,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EntriesPTableOrderingComposer
    extends Composer<_$LedgerDatabase, $EntriesPTable> {
  $$EntriesPTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountingDate => $composableBuilder(
    column: $table.accountingDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get partyId => $composableBuilder(
    column: $table.partyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get advanceRef => $composableBuilder(
    column: $table.advanceRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transferGroup => $composableBuilder(
    column: $table.transferGroup,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get amends => $composableBuilder(
    column: $table.amends,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reverses => $composableBuilder(
    column: $table.reverses,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get supersededBy => $composableBuilder(
    column: $table.supersededBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reviewState => $composableBuilder(
    column: $table.reviewState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reviewApprover => $composableBuilder(
    column: $table.reviewApprover,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reviewDecidedHlc => $composableBuilder(
    column: $table.reviewDecidedHlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reviewReason => $composableBuilder(
    column: $table.reviewReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdByUser => $composableBuilder(
    column: $table.createdByUser,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EntriesPTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $EntriesPTable> {
  $$EntriesPTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get accountingDate => $composableBuilder(
    column: $table.accountingDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get channel =>
      $composableBuilder(column: $table.channel, builder: (column) => column);

  GeneratedColumn<String> get partyId =>
      $composableBuilder(column: $table.partyId, builder: (column) => column);

  GeneratedColumn<String> get advanceRef => $composableBuilder(
    column: $table.advanceRef,
    builder: (column) => column,
  );

  GeneratedColumn<String> get transferGroup => $composableBuilder(
    column: $table.transferGroup,
    builder: (column) => column,
  );

  GeneratedColumn<String> get amends =>
      $composableBuilder(column: $table.amends, builder: (column) => column);

  GeneratedColumn<String> get reverses =>
      $composableBuilder(column: $table.reverses, builder: (column) => column);

  GeneratedColumn<String> get supersededBy => $composableBuilder(
    column: $table.supersededBy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reviewState => $composableBuilder(
    column: $table.reviewState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reviewApprover => $composableBuilder(
    column: $table.reviewApprover,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reviewDecidedHlc => $composableBuilder(
    column: $table.reviewDecidedHlc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reviewReason => $composableBuilder(
    column: $table.reviewReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdByUser => $composableBuilder(
    column: $table.createdByUser,
    builder: (column) => column,
  );

  GeneratedColumn<int> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);
}

class $$EntriesPTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $EntriesPTable,
          EntriesPData,
          $$EntriesPTableFilterComposer,
          $$EntriesPTableOrderingComposer,
          $$EntriesPTableAnnotationComposer,
          $$EntriesPTableCreateCompanionBuilder,
          $$EntriesPTableUpdateCompanionBuilder,
          (
            EntriesPData,
            BaseReferences<_$LedgerDatabase, $EntriesPTable, EntriesPData>,
          ),
          EntriesPData,
          PrefetchHooks Function()
        > {
  $$EntriesPTableTableManager(_$LedgerDatabase db, $EntriesPTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntriesPTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntriesPTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntriesPTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> accountingDate = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> channel = const Value.absent(),
                Value<String?> partyId = const Value.absent(),
                Value<String?> advanceRef = const Value.absent(),
                Value<String?> transferGroup = const Value.absent(),
                Value<String?> amends = const Value.absent(),
                Value<String?> reverses = const Value.absent(),
                Value<String?> supersededBy = const Value.absent(),
                Value<String> reviewState = const Value.absent(),
                Value<String?> reviewApprover = const Value.absent(),
                Value<int?> reviewDecidedHlc = const Value.absent(),
                Value<String?> reviewReason = const Value.absent(),
                Value<String> createdByUser = const Value.absent(),
                Value<int> hlc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntriesPCompanion(
                id: id,
                bookId: bookId,
                kind: kind,
                status: status,
                accountingDate: accountingDate,
                note: note,
                channel: channel,
                partyId: partyId,
                advanceRef: advanceRef,
                transferGroup: transferGroup,
                amends: amends,
                reverses: reverses,
                supersededBy: supersededBy,
                reviewState: reviewState,
                reviewApprover: reviewApprover,
                reviewDecidedHlc: reviewDecidedHlc,
                reviewReason: reviewReason,
                createdByUser: createdByUser,
                hlc: hlc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String bookId,
                required String kind,
                required String status,
                required String accountingDate,
                Value<String?> note = const Value.absent(),
                Value<String?> channel = const Value.absent(),
                Value<String?> partyId = const Value.absent(),
                Value<String?> advanceRef = const Value.absent(),
                Value<String?> transferGroup = const Value.absent(),
                Value<String?> amends = const Value.absent(),
                Value<String?> reverses = const Value.absent(),
                Value<String?> supersededBy = const Value.absent(),
                Value<String> reviewState = const Value.absent(),
                Value<String?> reviewApprover = const Value.absent(),
                Value<int?> reviewDecidedHlc = const Value.absent(),
                Value<String?> reviewReason = const Value.absent(),
                required String createdByUser,
                required int hlc,
                Value<int> rowid = const Value.absent(),
              }) => EntriesPCompanion.insert(
                id: id,
                bookId: bookId,
                kind: kind,
                status: status,
                accountingDate: accountingDate,
                note: note,
                channel: channel,
                partyId: partyId,
                advanceRef: advanceRef,
                transferGroup: transferGroup,
                amends: amends,
                reverses: reverses,
                supersededBy: supersededBy,
                reviewState: reviewState,
                reviewApprover: reviewApprover,
                reviewDecidedHlc: reviewDecidedHlc,
                reviewReason: reviewReason,
                createdByUser: createdByUser,
                hlc: hlc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$EntriesPTable, EntriesPData>(table),
                  BaseReferences<
                    _$LedgerDatabase,
                    $EntriesPTable,
                    EntriesPData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EntriesPTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $EntriesPTable,
      EntriesPData,
      $$EntriesPTableFilterComposer,
      $$EntriesPTableOrderingComposer,
      $$EntriesPTableAnnotationComposer,
      $$EntriesPTableCreateCompanionBuilder,
      $$EntriesPTableUpdateCompanionBuilder,
      (
        EntriesPData,
        BaseReferences<_$LedgerDatabase, $EntriesPTable, EntriesPData>,
      ),
      EntriesPData,
      PrefetchHooks Function()
    >;
typedef $$EntryLinesPTableCreateCompanionBuilder =
    EntryLinesPCompanion Function({
      required String entryId,
      required String accountId,
      required int amountPaise,
      required String bookId,
      required String accountingDate,
      required int lineIndex,
      Value<int> rowid,
    });
typedef $$EntryLinesPTableUpdateCompanionBuilder =
    EntryLinesPCompanion Function({
      Value<String> entryId,
      Value<String> accountId,
      Value<int> amountPaise,
      Value<String> bookId,
      Value<String> accountingDate,
      Value<int> lineIndex,
      Value<int> rowid,
    });

class $$EntryLinesPTableFilterComposer
    extends Composer<_$LedgerDatabase, $EntryLinesPTable> {
  $$EntryLinesPTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountingDate => $composableBuilder(
    column: $table.accountingDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lineIndex => $composableBuilder(
    column: $table.lineIndex,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EntryLinesPTableOrderingComposer
    extends Composer<_$LedgerDatabase, $EntryLinesPTable> {
  $$EntryLinesPTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountingDate => $composableBuilder(
    column: $table.accountingDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lineIndex => $composableBuilder(
    column: $table.lineIndex,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EntryLinesPTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $EntryLinesPTable> {
  $$EntryLinesPTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entryId =>
      $composableBuilder(column: $table.entryId, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get accountingDate => $composableBuilder(
    column: $table.accountingDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lineIndex =>
      $composableBuilder(column: $table.lineIndex, builder: (column) => column);
}

class $$EntryLinesPTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $EntryLinesPTable,
          EntryLinesPData,
          $$EntryLinesPTableFilterComposer,
          $$EntryLinesPTableOrderingComposer,
          $$EntryLinesPTableAnnotationComposer,
          $$EntryLinesPTableCreateCompanionBuilder,
          $$EntryLinesPTableUpdateCompanionBuilder,
          (
            EntryLinesPData,
            BaseReferences<
              _$LedgerDatabase,
              $EntryLinesPTable,
              EntryLinesPData
            >,
          ),
          EntryLinesPData,
          PrefetchHooks Function()
        > {
  $$EntryLinesPTableTableManager(_$LedgerDatabase db, $EntryLinesPTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntryLinesPTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntryLinesPTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntryLinesPTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entryId = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<int> amountPaise = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> accountingDate = const Value.absent(),
                Value<int> lineIndex = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntryLinesPCompanion(
                entryId: entryId,
                accountId: accountId,
                amountPaise: amountPaise,
                bookId: bookId,
                accountingDate: accountingDate,
                lineIndex: lineIndex,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entryId,
                required String accountId,
                required int amountPaise,
                required String bookId,
                required String accountingDate,
                required int lineIndex,
                Value<int> rowid = const Value.absent(),
              }) => EntryLinesPCompanion.insert(
                entryId: entryId,
                accountId: accountId,
                amountPaise: amountPaise,
                bookId: bookId,
                accountingDate: accountingDate,
                lineIndex: lineIndex,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$EntryLinesPTable, EntryLinesPData>(table),
                  BaseReferences<
                    _$LedgerDatabase,
                    $EntryLinesPTable,
                    EntryLinesPData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EntryLinesPTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $EntryLinesPTable,
      EntryLinesPData,
      $$EntryLinesPTableFilterComposer,
      $$EntryLinesPTableOrderingComposer,
      $$EntryLinesPTableAnnotationComposer,
      $$EntryLinesPTableCreateCompanionBuilder,
      $$EntryLinesPTableUpdateCompanionBuilder,
      (
        EntryLinesPData,
        BaseReferences<_$LedgerDatabase, $EntryLinesPTable, EntryLinesPData>,
      ),
      EntryLinesPData,
      PrefetchHooks Function()
    >;
typedef $$PeriodsPTableCreateCompanionBuilder = PeriodsPCompanion Function({
  required String bookId,
  required int year,
  required int month,
  required String state,
  Value<int?> lockHlc,
  Value<String?> verification,
  Value<int> rowid,
});
typedef $$PeriodsPTableUpdateCompanionBuilder = PeriodsPCompanion Function({
  Value<String> bookId,
  Value<int> year,
  Value<int> month,
  Value<String> state,
  Value<int?> lockHlc,
  Value<String?> verification,
  Value<int> rowid,
});

class $$PeriodsPTableFilterComposer
    extends Composer<_$LedgerDatabase, $PeriodsPTable> {
  $$PeriodsPTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get month => $composableBuilder(
    column: $table.month,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lockHlc => $composableBuilder(
    column: $table.lockHlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verification => $composableBuilder(
    column: $table.verification,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PeriodsPTableOrderingComposer
    extends Composer<_$LedgerDatabase, $PeriodsPTable> {
  $$PeriodsPTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get month => $composableBuilder(
    column: $table.month,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lockHlc => $composableBuilder(
    column: $table.lockHlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verification => $composableBuilder(
    column: $table.verification,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PeriodsPTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $PeriodsPTable> {
  $$PeriodsPTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<int> get month =>
      $composableBuilder(column: $table.month, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get lockHlc =>
      $composableBuilder(column: $table.lockHlc, builder: (column) => column);

  GeneratedColumn<String> get verification => $composableBuilder(
    column: $table.verification,
    builder: (column) => column,
  );
}

class $$PeriodsPTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $PeriodsPTable,
          PeriodsPData,
          $$PeriodsPTableFilterComposer,
          $$PeriodsPTableOrderingComposer,
          $$PeriodsPTableAnnotationComposer,
          $$PeriodsPTableCreateCompanionBuilder,
          $$PeriodsPTableUpdateCompanionBuilder,
          (
            PeriodsPData,
            BaseReferences<_$LedgerDatabase, $PeriodsPTable, PeriodsPData>,
          ),
          PeriodsPData,
          PrefetchHooks Function()
        > {
  $$PeriodsPTableTableManager(_$LedgerDatabase db, $PeriodsPTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeriodsPTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeriodsPTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeriodsPTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<int> year = const Value.absent(),
                Value<int> month = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int?> lockHlc = const Value.absent(),
                Value<String?> verification = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeriodsPCompanion(
                bookId: bookId,
                year: year,
                month: month,
                state: state,
                lockHlc: lockHlc,
                verification: verification,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required int year,
                required int month,
                required String state,
                Value<int?> lockHlc = const Value.absent(),
                Value<String?> verification = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeriodsPCompanion.insert(
                bookId: bookId,
                year: year,
                month: month,
                state: state,
                lockHlc: lockHlc,
                verification: verification,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PeriodsPTable, PeriodsPData>(table),
                  BaseReferences<
                    _$LedgerDatabase,
                    $PeriodsPTable,
                    PeriodsPData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PeriodsPTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $PeriodsPTable,
      PeriodsPData,
      $$PeriodsPTableFilterComposer,
      $$PeriodsPTableOrderingComposer,
      $$PeriodsPTableAnnotationComposer,
      $$PeriodsPTableCreateCompanionBuilder,
      $$PeriodsPTableUpdateCompanionBuilder,
      (
        PeriodsPData,
        BaseReferences<_$LedgerDatabase, $PeriodsPTable, PeriodsPData>,
      ),
      PeriodsPData,
      PrefetchHooks Function()
    >;
typedef $$CashCountsPTableCreateCompanionBuilder =
    CashCountsPCompanion Function({
      required String id,
      required String accountId,
      required String mode,
      required String countedAt,
      required int countedTotalPaise,
      Value<String?> breakdownJson,
      Value<String?> postedEntryId,
      Value<String?> countedBy,
      Value<String?> witness,
      Value<int> rowid,
    });
typedef $$CashCountsPTableUpdateCompanionBuilder =
    CashCountsPCompanion Function({
      Value<String> id,
      Value<String> accountId,
      Value<String> mode,
      Value<String> countedAt,
      Value<int> countedTotalPaise,
      Value<String?> breakdownJson,
      Value<String?> postedEntryId,
      Value<String?> countedBy,
      Value<String?> witness,
      Value<int> rowid,
    });

class $$CashCountsPTableFilterComposer
    extends Composer<_$LedgerDatabase, $CashCountsPTable> {
  $$CashCountsPTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get countedAt => $composableBuilder(
    column: $table.countedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get countedTotalPaise => $composableBuilder(
    column: $table.countedTotalPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get breakdownJson => $composableBuilder(
    column: $table.breakdownJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get postedEntryId => $composableBuilder(
    column: $table.postedEntryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get countedBy => $composableBuilder(
    column: $table.countedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get witness => $composableBuilder(
    column: $table.witness,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CashCountsPTableOrderingComposer
    extends Composer<_$LedgerDatabase, $CashCountsPTable> {
  $$CashCountsPTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get countedAt => $composableBuilder(
    column: $table.countedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get countedTotalPaise => $composableBuilder(
    column: $table.countedTotalPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get breakdownJson => $composableBuilder(
    column: $table.breakdownJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get postedEntryId => $composableBuilder(
    column: $table.postedEntryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get countedBy => $composableBuilder(
    column: $table.countedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get witness => $composableBuilder(
    column: $table.witness,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CashCountsPTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $CashCountsPTable> {
  $$CashCountsPTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get countedAt =>
      $composableBuilder(column: $table.countedAt, builder: (column) => column);

  GeneratedColumn<int> get countedTotalPaise => $composableBuilder(
    column: $table.countedTotalPaise,
    builder: (column) => column,
  );

  GeneratedColumn<String> get breakdownJson => $composableBuilder(
    column: $table.breakdownJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get postedEntryId => $composableBuilder(
    column: $table.postedEntryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get countedBy =>
      $composableBuilder(column: $table.countedBy, builder: (column) => column);

  GeneratedColumn<String> get witness =>
      $composableBuilder(column: $table.witness, builder: (column) => column);
}

class $$CashCountsPTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $CashCountsPTable,
          CashCountsPData,
          $$CashCountsPTableFilterComposer,
          $$CashCountsPTableOrderingComposer,
          $$CashCountsPTableAnnotationComposer,
          $$CashCountsPTableCreateCompanionBuilder,
          $$CashCountsPTableUpdateCompanionBuilder,
          (
            CashCountsPData,
            BaseReferences<
              _$LedgerDatabase,
              $CashCountsPTable,
              CashCountsPData
            >,
          ),
          CashCountsPData,
          PrefetchHooks Function()
        > {
  $$CashCountsPTableTableManager(_$LedgerDatabase db, $CashCountsPTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CashCountsPTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CashCountsPTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CashCountsPTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String> countedAt = const Value.absent(),
                Value<int> countedTotalPaise = const Value.absent(),
                Value<String?> breakdownJson = const Value.absent(),
                Value<String?> postedEntryId = const Value.absent(),
                Value<String?> countedBy = const Value.absent(),
                Value<String?> witness = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CashCountsPCompanion(
                id: id,
                accountId: accountId,
                mode: mode,
                countedAt: countedAt,
                countedTotalPaise: countedTotalPaise,
                breakdownJson: breakdownJson,
                postedEntryId: postedEntryId,
                countedBy: countedBy,
                witness: witness,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String accountId,
                required String mode,
                required String countedAt,
                required int countedTotalPaise,
                Value<String?> breakdownJson = const Value.absent(),
                Value<String?> postedEntryId = const Value.absent(),
                Value<String?> countedBy = const Value.absent(),
                Value<String?> witness = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CashCountsPCompanion.insert(
                id: id,
                accountId: accountId,
                mode: mode,
                countedAt: countedAt,
                countedTotalPaise: countedTotalPaise,
                breakdownJson: breakdownJson,
                postedEntryId: postedEntryId,
                countedBy: countedBy,
                witness: witness,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CashCountsPTable, CashCountsPData>(table),
                  BaseReferences<
                    _$LedgerDatabase,
                    $CashCountsPTable,
                    CashCountsPData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CashCountsPTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $CashCountsPTable,
      CashCountsPData,
      $$CashCountsPTableFilterComposer,
      $$CashCountsPTableOrderingComposer,
      $$CashCountsPTableAnnotationComposer,
      $$CashCountsPTableCreateCompanionBuilder,
      $$CashCountsPTableUpdateCompanionBuilder,
      (
        CashCountsPData,
        BaseReferences<_$LedgerDatabase, $CashCountsPTable, CashCountsPData>,
      ),
      CashCountsPData,
      PrefetchHooks Function()
    >;
typedef $$YearClosePTableCreateCompanionBuilder = YearClosePCompanion Function({
  required String bookId,
  required String fyLabel,
  required String state,
  Value<String?> vectorHash,
  Value<String?> vector,
  Value<int?> projectorVersion,
  Value<String?> verification,
  Value<int> rowid,
});
typedef $$YearClosePTableUpdateCompanionBuilder = YearClosePCompanion Function({
  Value<String> bookId,
  Value<String> fyLabel,
  Value<String> state,
  Value<String?> vectorHash,
  Value<String?> vector,
  Value<int?> projectorVersion,
  Value<String?> verification,
  Value<int> rowid,
});

class $$YearClosePTableFilterComposer
    extends Composer<_$LedgerDatabase, $YearClosePTable> {
  $$YearClosePTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fyLabel => $composableBuilder(
    column: $table.fyLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vectorHash => $composableBuilder(
    column: $table.vectorHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vector => $composableBuilder(
    column: $table.vector,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get projectorVersion => $composableBuilder(
    column: $table.projectorVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verification => $composableBuilder(
    column: $table.verification,
    builder: (column) => ColumnFilters(column),
  );
}

class $$YearClosePTableOrderingComposer
    extends Composer<_$LedgerDatabase, $YearClosePTable> {
  $$YearClosePTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fyLabel => $composableBuilder(
    column: $table.fyLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vectorHash => $composableBuilder(
    column: $table.vectorHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vector => $composableBuilder(
    column: $table.vector,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get projectorVersion => $composableBuilder(
    column: $table.projectorVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verification => $composableBuilder(
    column: $table.verification,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$YearClosePTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $YearClosePTable> {
  $$YearClosePTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get fyLabel =>
      $composableBuilder(column: $table.fyLabel, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get vectorHash => $composableBuilder(
    column: $table.vectorHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get vector =>
      $composableBuilder(column: $table.vector, builder: (column) => column);

  GeneratedColumn<int> get projectorVersion => $composableBuilder(
    column: $table.projectorVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get verification => $composableBuilder(
    column: $table.verification,
    builder: (column) => column,
  );
}

class $$YearClosePTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $YearClosePTable,
          YearClosePData,
          $$YearClosePTableFilterComposer,
          $$YearClosePTableOrderingComposer,
          $$YearClosePTableAnnotationComposer,
          $$YearClosePTableCreateCompanionBuilder,
          $$YearClosePTableUpdateCompanionBuilder,
          (
            YearClosePData,
            BaseReferences<_$LedgerDatabase, $YearClosePTable, YearClosePData>,
          ),
          YearClosePData,
          PrefetchHooks Function()
        > {
  $$YearClosePTableTableManager(_$LedgerDatabase db, $YearClosePTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$YearClosePTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$YearClosePTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$YearClosePTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<String> fyLabel = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> vectorHash = const Value.absent(),
                Value<String?> vector = const Value.absent(),
                Value<int?> projectorVersion = const Value.absent(),
                Value<String?> verification = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => YearClosePCompanion(
                bookId: bookId,
                fyLabel: fyLabel,
                state: state,
                vectorHash: vectorHash,
                vector: vector,
                projectorVersion: projectorVersion,
                verification: verification,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required String fyLabel,
                required String state,
                Value<String?> vectorHash = const Value.absent(),
                Value<String?> vector = const Value.absent(),
                Value<int?> projectorVersion = const Value.absent(),
                Value<String?> verification = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => YearClosePCompanion.insert(
                bookId: bookId,
                fyLabel: fyLabel,
                state: state,
                vectorHash: vectorHash,
                vector: vector,
                projectorVersion: projectorVersion,
                verification: verification,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$YearClosePTable, YearClosePData>(table),
                  BaseReferences<
                    _$LedgerDatabase,
                    $YearClosePTable,
                    YearClosePData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$YearClosePTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $YearClosePTable,
      YearClosePData,
      $$YearClosePTableFilterComposer,
      $$YearClosePTableOrderingComposer,
      $$YearClosePTableAnnotationComposer,
      $$YearClosePTableCreateCompanionBuilder,
      $$YearClosePTableUpdateCompanionBuilder,
      (
        YearClosePData,
        BaseReferences<_$LedgerDatabase, $YearClosePTable, YearClosePData>,
      ),
      YearClosePData,
      PrefetchHooks Function()
    >;
typedef $$ImportLinesPTableCreateCompanionBuilder =
    ImportLinesPCompanion Function({
      required String id,
      required String bookId,
      required String bankAccountId,
      required String date,
      required String description,
      required int amountPaise,
      required String state,
      Value<String?> matchedEntry,
      required String dedupeHash,
      Value<int> rowid,
    });
typedef $$ImportLinesPTableUpdateCompanionBuilder =
    ImportLinesPCompanion Function({
      Value<String> id,
      Value<String> bookId,
      Value<String> bankAccountId,
      Value<String> date,
      Value<String> description,
      Value<int> amountPaise,
      Value<String> state,
      Value<String?> matchedEntry,
      Value<String> dedupeHash,
      Value<int> rowid,
    });

class $$ImportLinesPTableFilterComposer
    extends Composer<_$LedgerDatabase, $ImportLinesPTable> {
  $$ImportLinesPTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bankAccountId => $composableBuilder(
    column: $table.bankAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get matchedEntry => $composableBuilder(
    column: $table.matchedEntry,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dedupeHash => $composableBuilder(
    column: $table.dedupeHash,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ImportLinesPTableOrderingComposer
    extends Composer<_$LedgerDatabase, $ImportLinesPTable> {
  $$ImportLinesPTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bankAccountId => $composableBuilder(
    column: $table.bankAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get matchedEntry => $composableBuilder(
    column: $table.matchedEntry,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dedupeHash => $composableBuilder(
    column: $table.dedupeHash,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ImportLinesPTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $ImportLinesPTable> {
  $$ImportLinesPTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get bankAccountId => $composableBuilder(
    column: $table.bankAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get matchedEntry => $composableBuilder(
    column: $table.matchedEntry,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dedupeHash => $composableBuilder(
    column: $table.dedupeHash,
    builder: (column) => column,
  );
}

class $$ImportLinesPTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $ImportLinesPTable,
          ImportLinesPData,
          $$ImportLinesPTableFilterComposer,
          $$ImportLinesPTableOrderingComposer,
          $$ImportLinesPTableAnnotationComposer,
          $$ImportLinesPTableCreateCompanionBuilder,
          $$ImportLinesPTableUpdateCompanionBuilder,
          (
            ImportLinesPData,
            BaseReferences<
              _$LedgerDatabase,
              $ImportLinesPTable,
              ImportLinesPData
            >,
          ),
          ImportLinesPData,
          PrefetchHooks Function()
        > {
  $$ImportLinesPTableTableManager(_$LedgerDatabase db, $ImportLinesPTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImportLinesPTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImportLinesPTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImportLinesPTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> bankAccountId = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int> amountPaise = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> matchedEntry = const Value.absent(),
                Value<String> dedupeHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImportLinesPCompanion(
                id: id,
                bookId: bookId,
                bankAccountId: bankAccountId,
                date: date,
                description: description,
                amountPaise: amountPaise,
                state: state,
                matchedEntry: matchedEntry,
                dedupeHash: dedupeHash,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String bookId,
                required String bankAccountId,
                required String date,
                required String description,
                required int amountPaise,
                required String state,
                Value<String?> matchedEntry = const Value.absent(),
                required String dedupeHash,
                Value<int> rowid = const Value.absent(),
              }) => ImportLinesPCompanion.insert(
                id: id,
                bookId: bookId,
                bankAccountId: bankAccountId,
                date: date,
                description: description,
                amountPaise: amountPaise,
                state: state,
                matchedEntry: matchedEntry,
                dedupeHash: dedupeHash,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ImportLinesPTable, ImportLinesPData>(table),
                  BaseReferences<
                    _$LedgerDatabase,
                    $ImportLinesPTable,
                    ImportLinesPData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ImportLinesPTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $ImportLinesPTable,
      ImportLinesPData,
      $$ImportLinesPTableFilterComposer,
      $$ImportLinesPTableOrderingComposer,
      $$ImportLinesPTableAnnotationComposer,
      $$ImportLinesPTableCreateCompanionBuilder,
      $$ImportLinesPTableUpdateCompanionBuilder,
      (
        ImportLinesPData,
        BaseReferences<_$LedgerDatabase, $ImportLinesPTable, ImportLinesPData>,
      ),
      ImportLinesPData,
      PrefetchHooks Function()
    >;
typedef $$RulesPTableCreateCompanionBuilder = RulesPCompanion Function({
  required String id,
  required String bookId,
  required String pattern,
  required String targetAccount,
  Value<int> hits,
  Value<int> rowid,
});
typedef $$RulesPTableUpdateCompanionBuilder = RulesPCompanion Function({
  Value<String> id,
  Value<String> bookId,
  Value<String> pattern,
  Value<String> targetAccount,
  Value<int> hits,
  Value<int> rowid,
});

class $$RulesPTableFilterComposer
    extends Composer<_$LedgerDatabase, $RulesPTable> {
  $$RulesPTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pattern => $composableBuilder(
    column: $table.pattern,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetAccount => $composableBuilder(
    column: $table.targetAccount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hits => $composableBuilder(
    column: $table.hits,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RulesPTableOrderingComposer
    extends Composer<_$LedgerDatabase, $RulesPTable> {
  $$RulesPTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pattern => $composableBuilder(
    column: $table.pattern,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetAccount => $composableBuilder(
    column: $table.targetAccount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hits => $composableBuilder(
    column: $table.hits,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RulesPTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $RulesPTable> {
  $$RulesPTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get pattern =>
      $composableBuilder(column: $table.pattern, builder: (column) => column);

  GeneratedColumn<String> get targetAccount => $composableBuilder(
    column: $table.targetAccount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get hits =>
      $composableBuilder(column: $table.hits, builder: (column) => column);
}

class $$RulesPTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $RulesPTable,
          RulesPData,
          $$RulesPTableFilterComposer,
          $$RulesPTableOrderingComposer,
          $$RulesPTableAnnotationComposer,
          $$RulesPTableCreateCompanionBuilder,
          $$RulesPTableUpdateCompanionBuilder,
          (
            RulesPData,
            BaseReferences<_$LedgerDatabase, $RulesPTable, RulesPData>,
          ),
          RulesPData,
          PrefetchHooks Function()
        > {
  $$RulesPTableTableManager(_$LedgerDatabase db, $RulesPTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RulesPTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RulesPTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RulesPTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> pattern = const Value.absent(),
                Value<String> targetAccount = const Value.absent(),
                Value<int> hits = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RulesPCompanion(
                id: id,
                bookId: bookId,
                pattern: pattern,
                targetAccount: targetAccount,
                hits: hits,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String bookId,
                required String pattern,
                required String targetAccount,
                Value<int> hits = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RulesPCompanion.insert(
                id: id,
                bookId: bookId,
                pattern: pattern,
                targetAccount: targetAccount,
                hits: hits,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RulesPTable, RulesPData>(table),
                  BaseReferences<_$LedgerDatabase, $RulesPTable, RulesPData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RulesPTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $RulesPTable,
      RulesPData,
      $$RulesPTableFilterComposer,
      $$RulesPTableOrderingComposer,
      $$RulesPTableAnnotationComposer,
      $$RulesPTableCreateCompanionBuilder,
      $$RulesPTableUpdateCompanionBuilder,
      (RulesPData, BaseReferences<_$LedgerDatabase, $RulesPTable, RulesPData>),
      RulesPData,
      PrefetchHooks Function()
    >;
typedef $$BalancesTableCreateCompanionBuilder = BalancesCompanion Function({
  required String accountId,
  required int balancePaise,
  required int asOfHlc,
  Value<int> rowid,
});
typedef $$BalancesTableUpdateCompanionBuilder = BalancesCompanion Function({
  Value<String> accountId,
  Value<int> balancePaise,
  Value<int> asOfHlc,
  Value<int> rowid,
});

class $$BalancesTableFilterComposer
    extends Composer<_$LedgerDatabase, $BalancesTable> {
  $$BalancesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get balancePaise => $composableBuilder(
    column: $table.balancePaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get asOfHlc => $composableBuilder(
    column: $table.asOfHlc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BalancesTableOrderingComposer
    extends Composer<_$LedgerDatabase, $BalancesTable> {
  $$BalancesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get balancePaise => $composableBuilder(
    column: $table.balancePaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get asOfHlc => $composableBuilder(
    column: $table.asOfHlc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BalancesTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $BalancesTable> {
  $$BalancesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<int> get balancePaise => $composableBuilder(
    column: $table.balancePaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get asOfHlc =>
      $composableBuilder(column: $table.asOfHlc, builder: (column) => column);
}

class $$BalancesTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $BalancesTable,
          Balance,
          $$BalancesTableFilterComposer,
          $$BalancesTableOrderingComposer,
          $$BalancesTableAnnotationComposer,
          $$BalancesTableCreateCompanionBuilder,
          $$BalancesTableUpdateCompanionBuilder,
          (Balance, BaseReferences<_$LedgerDatabase, $BalancesTable, Balance>),
          Balance,
          PrefetchHooks Function()
        > {
  $$BalancesTableTableManager(_$LedgerDatabase db, $BalancesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BalancesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BalancesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BalancesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<int> balancePaise = const Value.absent(),
                Value<int> asOfHlc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BalancesCompanion(
                accountId: accountId,
                balancePaise: balancePaise,
                asOfHlc: asOfHlc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required int balancePaise,
                required int asOfHlc,
                Value<int> rowid = const Value.absent(),
              }) => BalancesCompanion.insert(
                accountId: accountId,
                balancePaise: balancePaise,
                asOfHlc: asOfHlc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BalancesTable, Balance>(table),
                  BaseReferences<_$LedgerDatabase, $BalancesTable, Balance>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BalancesTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $BalancesTable,
      Balance,
      $$BalancesTableFilterComposer,
      $$BalancesTableOrderingComposer,
      $$BalancesTableAnnotationComposer,
      $$BalancesTableCreateCompanionBuilder,
      $$BalancesTableUpdateCompanionBuilder,
      (Balance, BaseReferences<_$LedgerDatabase, $BalancesTable, Balance>),
      Balance,
      PrefetchHooks Function()
    >;
typedef $$DailySnapshotsTableCreateCompanionBuilder =
    DailySnapshotsCompanion Function({
      required String accountId,
      required String date,
      required int balancePaise,
      Value<int> rowid,
    });
typedef $$DailySnapshotsTableUpdateCompanionBuilder =
    DailySnapshotsCompanion Function({
      Value<String> accountId,
      Value<String> date,
      Value<int> balancePaise,
      Value<int> rowid,
    });

class $$DailySnapshotsTableFilterComposer
    extends Composer<_$LedgerDatabase, $DailySnapshotsTable> {
  $$DailySnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get balancePaise => $composableBuilder(
    column: $table.balancePaise,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailySnapshotsTableOrderingComposer
    extends Composer<_$LedgerDatabase, $DailySnapshotsTable> {
  $$DailySnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get balancePaise => $composableBuilder(
    column: $table.balancePaise,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailySnapshotsTableAnnotationComposer
    extends Composer<_$LedgerDatabase, $DailySnapshotsTable> {
  $$DailySnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get balancePaise => $composableBuilder(
    column: $table.balancePaise,
    builder: (column) => column,
  );
}

class $$DailySnapshotsTableTableManager
    extends
        RootTableManager<
          _$LedgerDatabase,
          $DailySnapshotsTable,
          DailySnapshot,
          $$DailySnapshotsTableFilterComposer,
          $$DailySnapshotsTableOrderingComposer,
          $$DailySnapshotsTableAnnotationComposer,
          $$DailySnapshotsTableCreateCompanionBuilder,
          $$DailySnapshotsTableUpdateCompanionBuilder,
          (
            DailySnapshot,
            BaseReferences<
              _$LedgerDatabase,
              $DailySnapshotsTable,
              DailySnapshot
            >,
          ),
          DailySnapshot,
          PrefetchHooks Function()
        > {
  $$DailySnapshotsTableTableManager(
    _$LedgerDatabase db,
    $DailySnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailySnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailySnapshotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailySnapshotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<int> balancePaise = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailySnapshotsCompanion(
                accountId: accountId,
                date: date,
                balancePaise: balancePaise,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String date,
                required int balancePaise,
                Value<int> rowid = const Value.absent(),
              }) => DailySnapshotsCompanion.insert(
                accountId: accountId,
                date: date,
                balancePaise: balancePaise,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DailySnapshotsTable, DailySnapshot>(table),
                  BaseReferences<
                    _$LedgerDatabase,
                    $DailySnapshotsTable,
                    DailySnapshot
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailySnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$LedgerDatabase,
      $DailySnapshotsTable,
      DailySnapshot,
      $$DailySnapshotsTableFilterComposer,
      $$DailySnapshotsTableOrderingComposer,
      $$DailySnapshotsTableAnnotationComposer,
      $$DailySnapshotsTableCreateCompanionBuilder,
      $$DailySnapshotsTableUpdateCompanionBuilder,
      (
        DailySnapshot,
        BaseReferences<_$LedgerDatabase, $DailySnapshotsTable, DailySnapshot>,
      ),
      DailySnapshot,
      PrefetchHooks Function()
    >;

class $LedgerDatabaseManager {
  final _$LedgerDatabase _db;
  $LedgerDatabaseManager(this._db);
  $$EnvelopesLocalTableTableManager get envelopesLocal =>
      $$EnvelopesLocalTableTableManager(_db, _db.envelopesLocal);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
  $$AuthorSeqLocalTableTableManager get authorSeqLocal =>
      $$AuthorSeqLocalTableTableManager(_db, _db.authorSeqLocal);
  $$AuthorGapsTableTableManager get authorGaps =>
      $$AuthorGapsTableTableManager(_db, _db.authorGaps);
  $$AuthorDuplicatesTableTableManager get authorDuplicates =>
      $$AuthorDuplicatesTableTableManager(_db, _db.authorDuplicates);
  $$SignedRecordsLocalTableTableManager get signedRecordsLocal =>
      $$SignedRecordsLocalTableTableManager(_db, _db.signedRecordsLocal);
  $$StoreEpochTableTableManager get storeEpoch =>
      $$StoreEpochTableTableManager(_db, _db.storeEpoch);
  $$SyncCursorsTableTableManager get syncCursors =>
      $$SyncCursorsTableTableManager(_db, _db.syncCursors);
  $$KeyCacheTableTableManager get keyCache =>
      $$KeyCacheTableTableManager(_db, _db.keyCache);
  $$AttachmentCacheTableTableManager get attachmentCache =>
      $$AttachmentCacheTableTableManager(_db, _db.attachmentCache);
  $$BooksPTableTableManager get booksP =>
      $$BooksPTableTableManager(_db, _db.booksP);
  $$AccountsPTableTableManager get accountsP =>
      $$AccountsPTableTableManager(_db, _db.accountsP);
  $$EntriesPTableTableManager get entriesP =>
      $$EntriesPTableTableManager(_db, _db.entriesP);
  $$EntryLinesPTableTableManager get entryLinesP =>
      $$EntryLinesPTableTableManager(_db, _db.entryLinesP);
  $$PeriodsPTableTableManager get periodsP =>
      $$PeriodsPTableTableManager(_db, _db.periodsP);
  $$CashCountsPTableTableManager get cashCountsP =>
      $$CashCountsPTableTableManager(_db, _db.cashCountsP);
  $$YearClosePTableTableManager get yearCloseP =>
      $$YearClosePTableTableManager(_db, _db.yearCloseP);
  $$ImportLinesPTableTableManager get importLinesP =>
      $$ImportLinesPTableTableManager(_db, _db.importLinesP);
  $$RulesPTableTableManager get rulesP =>
      $$RulesPTableTableManager(_db, _db.rulesP);
  $$BalancesTableTableManager get balances =>
      $$BalancesTableTableManager(_db, _db.balances);
  $$DailySnapshotsTableTableManager get dailySnapshots =>
      $$DailySnapshotsTableTableManager(_db, _db.dailySnapshots);
}
