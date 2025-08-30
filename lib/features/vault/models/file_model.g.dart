// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FileModelAdapter extends TypeAdapter<FileModel> {
  @override
  final int typeId = 2;

  @override
  FileModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FileModel(
      id: fields[0] as String,
      name: fields[1] as String,
      originalName: fields[2] as String,
      path: fields[3] as String,
      size: fields[4] as int,
      mimeType: fields[5] as String,
      uploadedAt: fields[6] as DateTime,
      description: fields[7] as String?,
      tags: (fields[8] as List).cast<String>(),
      isEncrypted: fields[9] as bool,
      siaFilename: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, FileModel obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.originalName)
      ..writeByte(3)
      ..write(obj.path)
      ..writeByte(4)
      ..write(obj.size)
      ..writeByte(5)
      ..write(obj.mimeType)
      ..writeByte(6)
      ..write(obj.uploadedAt)
      ..writeByte(7)
      ..write(obj.description)
      ..writeByte(8)
      ..write(obj.tags)
      ..writeByte(9)
      ..write(obj.isEncrypted)
      ..writeByte(10)
      ..write(obj.siaFilename);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
