import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

class ObjToGlb {
  static bool looksLikeObj(String text) {
    return RegExp(r'^v\s+-?\d', multiLine: true).hasMatch(text) &&
        RegExp(r'^f\s+\d', multiLine: true).hasMatch(text);
  }

  static Uint8List? convert(String objText) {
    final pos = <double>[];
    final idx = <int>[];

    for (final raw in const LineSplitter().convert(objText)) {
      final line = raw.trim();
      if (line.startsWith('v ')) {
        final p = line.split(RegExp(r'\s+'));
        if (p.length >= 4) {
          final x = double.tryParse(p[1]);
          final y = double.tryParse(p[2]);
          final z = double.tryParse(p[3]);
          if (x != null && y != null && z != null) pos.addAll([x, y, z]);
        }
      } else if (line.startsWith('f ')) {
        final p = line.split(RegExp(r'\s+'));
        final vc = pos.length ~/ 3;
        final face = <int>[];
        for (int i = 1; i < p.length; i++) {
          final v = int.tryParse(p[i].split('/')[0]);
          if (v != null) {
            final k = v > 0 ? v - 1 : vc + v;
            if (k >= 0 && k < vc) face.add(k);
          }
        }
        for (int i = 1; i + 1 < face.length; i++) {
          idx.addAll([face[0], face[i], face[i + 1]]);
        }
      }
    }

    final vc = pos.length ~/ 3;
    if (vc < 3 || idx.length < 3) return null;

    double minX = pos[0], maxX = pos[0];
    double minY = pos[1], maxY = pos[1];
    double minZ = pos[2], maxZ = pos[2];
    for (int i = 0; i < pos.length; i += 3) {
      minX = math.min(minX, pos[i]);
      maxX = math.max(maxX, pos[i]);
      minY = math.min(minY, pos[i + 1]);
      maxY = math.max(maxY, pos[i + 1]);
      minZ = math.min(minZ, pos[i + 2]);
      maxZ = math.max(maxZ, pos[i + 2]);
    }

    final positions = Float32List.fromList(pos);
    final normals = Float32List(pos.length);
    final indices = Uint32List.fromList(idx);

    for (int i = 0; i < indices.length; i += 3) {
      final i0 = indices[i] * 3, i1 = indices[i + 1] * 3, i2 = indices[i + 2] * 3;
      final ax = positions[i1] - positions[i0];
      final ay = positions[i1 + 1] - positions[i0 + 1];
      final az = positions[i1 + 2] - positions[i0 + 2];
      final bx = positions[i2] - positions[i0];
      final by = positions[i2 + 1] - positions[i0 + 1];
      final bz = positions[i2 + 2] - positions[i0 + 2];
      final nx = ay * bz - az * by;
      final ny = az * bx - ax * bz;
      final nz = ax * by - ay * bx;
      for (final j in [i0, i1, i2]) {
        normals[j] += nx;
        normals[j + 1] += ny;
        normals[j + 2] += nz;
      }
    }

    for (int i = 0; i < normals.length; i += 3) {
      final len = math.sqrt(
        normals[i] * normals[i] +
            normals[i + 1] * normals[i + 1] +
            normals[i + 2] * normals[i + 2],
      );
      if (len > 1e-8) {
        normals[i] /= len;
        normals[i + 1] /= len;
        normals[i + 2] /= len;
      } else {
        normals[i + 1] = 1.0;
      }
    }

    final pLen = positions.length * 4;
    final nLen = normals.length * 4;
    final iLen = indices.length * 4;
    final binLen = pLen + nLen + iLen;
    final bin = ByteData(binLen);
    int off = 0;
    for (final v in positions) { bin.setFloat32(off, v, Endian.little); off += 4; }
    for (final v in normals) { bin.setFloat32(off, v, Endian.little); off += 4; }
    for (final v in indices) { bin.setUint32(off, v, Endian.little); off += 4; }

    final gltf = {
      'asset': {'version': '2.0', 'generator': 'My3D AI Studio'},
      'scene': 0,
      'scenes': [{'nodes': [0]}],
      'nodes': [{'mesh': 0}],
      'materials': [{
        'pbrMetallicRoughness': {
          'baseColorFactor': [0.85, 0.85, 0.88, 1.0],
          'metallicFactor': 0.1,
          'roughnessFactor': 0.7,
        },
        'doubleSided': true,
      }],
      'meshes': [{'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1}, 'indices': 2, 'material': 0}]}],
      'buffers': [{'byteLength': binLen}],
      'bufferViews': [
        {'buffer': 0, 'byteOffset': 0, 'byteLength': pLen, 'target': 34962},
        {'buffer': 0, 'byteOffset': pLen, 'byteLength': nLen, 'target': 34962},
        {'buffer': 0, 'byteOffset': pLen + nLen, 'byteLength': iLen, 'target': 34963},
      ],
      'accessors': [
        {'bufferView': 0, 'componentType': 5126, 'count': vc, 'type': 'VEC3', 'min': [minX, minY, minZ], 'max': [maxX, maxY, maxZ]},
        {'bufferView': 1, 'componentType': 5126, 'count': vc, 'type': 'VEC3'},
        {'bufferView': 2, 'componentType': 5125, 'count': indices.length, 'type': 'SCALAR'},
      ],
    };

    final jRaw = utf8.encode(jsonEncode(gltf));
    final jPad = (4 - (jRaw.length % 4)) % 4;
    final jLen = jRaw.length + jPad;
    final total = 12 + 8 + jLen + 8 + binLen;
    final out = Uint8List(total);
    final h = ByteData.sublistView(out);
    h.setUint32(0, 0x46546C67, Endian.little);
    h.setUint32(4, 2, Endian.little);
    h.setUint32(8, total, Endian.little);
    h.setUint32(12, jLen, Endian.little);
    h.setUint32(16, 0x4E4F534A, Endian.little);
    out.setRange(20, 20 + jRaw.length, jRaw);
    for (int i = 0; i < jPad; i++) { out[20 + jRaw.length + i] = 0x20; }
    final bOff = 20 + jLen;
    h.setUint32(bOff, binLen, Endian.little);
    h.setUint32(bOff + 4, 0x004E4942, Endian.little);
    out.setRange(bOff + 8, bOff + 8 + binLen, bin.buffer.asUint8List());
    return out;
  }
}
