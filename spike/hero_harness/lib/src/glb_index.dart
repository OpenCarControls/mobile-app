import 'dart:convert';
import 'dart:typed_data';

/// A primitive of a mesh entity: the entity's name and the primitive index.
typedef PrimitiveRef = ({String entityName, int primitive});

/// Names read from a GLB's JSON chunk, for renderers that can only look up
/// entities by name (no material-name lookup).
///
/// An entity's name is its glTF node name, or the mesh name for an unnamed
/// node. That fallback is what Filament's gltfio does; meshopt quantization
/// wraps every mesh in an unnamed child node, so the compressed model needs
/// it.
class GlbIndex {
  GlbIndex._(this.materials, this.nodeMeshes, this.extensionsUsed);

  /// Material name → every primitive that uses it.
  final Map<String, List<PrimitiveRef>> materials;

  /// Node name → the mesh entities in its subtree (itself included).
  final Map<String, List<String>> nodeMeshes;

  final List<String> extensionsUsed;

  static GlbIndex parse(Uint8List glb) {
    final bytes = ByteData.sublistView(glb);
    if (bytes.getUint32(0, Endian.little) != 0x46546C67) {
      throw const FormatException('Not a GLB file');
    }
    final jsonLength = bytes.getUint32(12, Endian.little);
    final json =
        jsonDecode(utf8.decode(glb.sublist(20, 20 + jsonLength)))
            as Map<String, dynamic>;

    final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
    final meshes = (json['meshes'] as List).cast<Map<String, dynamic>>();
    final materialDefs = (json['materials'] as List)
        .cast<Map<String, dynamic>>();

    String? entityName(Map<String, dynamic> node) {
      final name = node['name'] as String?;
      if (name != null) return name;
      final mesh = node['mesh'] as int?;
      return mesh == null ? null : meshes[mesh]['name'] as String?;
    }

    final materials = <String, List<PrimitiveRef>>{};
    for (final node in nodes) {
      final mesh = node['mesh'] as int?;
      final name = entityName(node);
      if (mesh == null || name == null) continue;
      final primitives = (meshes[mesh]['primitives'] as List)
          .cast<Map<String, dynamic>>();
      for (var i = 0; i < primitives.length; i++) {
        final material = primitives[i]['material'] as int?;
        if (material == null) continue;
        final materialName = materialDefs[material]['name'] as String?;
        if (materialName == null) continue;
        materials.putIfAbsent(materialName, () => []).add((
          entityName: name,
          primitive: i,
        ));
      }
    }

    List<String> subtreeMeshes(int index) {
      final node = nodes[index];
      final name = entityName(node);
      return [
        if (node['mesh'] != null && name != null) name,
        for (final child in (node['children'] as List? ?? []).cast<int>())
          ...subtreeMeshes(child),
      ];
    }

    final nodeMeshes = <String, List<String>>{};
    for (var i = 0; i < nodes.length; i++) {
      final name = nodes[i]['name'] as String?;
      if (name != null) nodeMeshes[name] = subtreeMeshes(i);
    }

    return GlbIndex._(
      materials,
      nodeMeshes,
      (json['extensionsUsed'] as List? ?? []).cast<String>(),
    );
  }
}
