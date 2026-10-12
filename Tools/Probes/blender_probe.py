# Reborn / T001 - Blender CLI capability probe (read-only)
#
# Purpose: establish ground truth about what the installed Blender can do from a
# headless command line BEFORE any Blender-MCP implementation is chosen or any
# production asset work starts.
#
# This script deliberately:
#   - does NOT write, save, export or delete anything
#   - reads only the in-memory factory-startup scene
#
# Invocation (from the Reborn project root, absolute path, PowerShell):
#   & 'D:\SoftWare\Blender\blender.exe' --background --factory-startup --python 'E:\Reborn\Tools\Probes\blender_probe.py'
#
# Evidence contract: every line starting with "PROBE|" is a machine-readable
# key=value fact to be copied into Docs/Evidence/T001.md.

import sys
import bpy

P = "PROBE|"


def emit(key, value):
    sys.stdout.write("{0}{1}={2}\n".format(P, key, value))


emit("blender_version", bpy.app.version_string)
emit("blender_version_tuple", ".".join(str(v) for v in bpy.app.version))
emit("binary_path", bpy.app.binary_path)
emit("python_version", sys.version.split()[0])

# Scene / unit facts that T005 (static round-trip) will depend on.
scene = bpy.context.scene
emit("unit_system", scene.unit_settings.system)
emit("unit_scale_length", scene.unit_settings.scale_length)
emit("unit_length_unit", scene.unit_settings.length_unit)

# Factory-startup object inventory (expected: Cube, Camera, Light).
names = sorted(o.name for o in bpy.data.objects)
emit("object_count", len(bpy.data.objects))
emit("object_names", "|".join(names))
for obj in sorted(bpy.data.objects, key=lambda o: o.name):
    emit(
        "object.{0}.type_dimensions".format(obj.name),
        "{0}|{1}".format(obj.type, "x".join("{0:.6f}".format(d) for d in obj.dimensions)),
    )

# Capability booleans: what API surfaces exist in this build.
emit("has_bpy_ops_export_fbx", hasattr(bpy.ops.export_scene, "fbx"))
emit("has_bpy_ops_import_fbx", hasattr(bpy.ops.import_scene, "fbx"))
emit("has_bpy_ops_wm_save_mainfile", hasattr(bpy.ops.wm, "save_as_mainfile"))
emit("has_bpy_data_armatures", hasattr(bpy.data, "armatures"))
emit("addons_enabled", "|".join(sorted(bpy.context.preferences.addons.keys())))

sys.stdout.write("{0}probe_complete=1\n".format(P))
