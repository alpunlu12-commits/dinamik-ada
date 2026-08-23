#!/usr/bin/env python3
"""Regenerate DynamicIsland.xcodeproj from the sources on disk.

Scans DynamicIsland/{App,System,Island,UI,Settings} for .swift files and writes
a complete project.pbxproj plus a shared scheme. Object IDs are derived from
each file's path, so re-running this produces a byte-identical project unless
the file set actually changed — the diff stays readable.

Usage:
    python3 tools/generate_pbxproj.py
"""

from __future__ import annotations

import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PROJECT_NAME = "DynamicIsland"
# What the built .app is called, and what Finder and the Dock show. Kept apart
# from PROJECT_NAME on purpose: the target, the source folder, the scheme and
# every path stay "DynamicIsland", so renaming the product does not churn the
# project. Only the bundle the user sees changes.
DISPLAY_NAME = "Dinamik Ada"
BUNDLE_ID = "com.abacusisland.dynamicisland"
DEPLOYMENT_TARGET = "13.0"
SWIFT_VERSION = "5.0"

SOURCE_GROUPS = ["App", "System", "Island", "UI", "Settings"]
RESOURCE_FILES = ["Info.plist", "DynamicIsland.entitlements", "AppIcon.icns"]

# Of those, the ones that need a Copy Resources step. Info.plist and the
# entitlements are consumed through build settings and must NOT be copied in;
# the icon is an actual file in the bundle.
COPIED_RESOURCES = ["AppIcon.icns"]

# Third-party artefacts copied verbatim into the app bundle's Resources.
# Lives at DynamicIsland/Vendor, alongside Resources.
# Currently the mediaremote-adapter framework + Perl script (see Vendor/README.md).
# The directory is normally empty in a fresh clone: when it is, the generated
# project is byte-identical to one produced without this feature, so nobody who
# has not vendored the adapter sees a diff.
VENDOR_DIR = "Vendor"


def oid(key: str) -> str:
    """Deterministic 24-char hex object identifier."""
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()


def swift_sources() -> dict[str, list[str]]:
    """Map of group name -> sorted .swift file names."""
    found = {}
    for group in SOURCE_GROUPS:
        directory = os.path.join(ROOT, PROJECT_NAME, group)
        if not os.path.isdir(directory):
            continue
        names = sorted(n for n in os.listdir(directory) if n.endswith(".swift"))
        if names:
            found[group] = names
    return found


def vendor_files() -> list[str]:
    """Names of the things in Vendor/ that should ship inside the app."""
    directory = os.path.join(ROOT, PROJECT_NAME, VENDOR_DIR)
    if not os.path.isdir(directory):
        return []
    return sorted(
        n for n in os.listdir(directory)
        if not n.startswith(".") and n != "README.md"
    )


def file_type(name: str) -> str:
    if name.endswith(".swift"):
        return "sourcecode.swift"
    if name.endswith(".plist"):
        return "text.plist.xml"
    if name.endswith(".entitlements"):
        return "text.plist.entitlements"
    if name.endswith(".framework"):
        # Deliberately "folder", not "wrapper.framework": this framework is never
        # linked, only handed to perl as a path. Declaring it a wrapper makes
        # Xcode try to link and re-sign it; as a folder it is copied verbatim,
        # which is exactly what the adapter needs.
        return "folder"
    if name.endswith(".pl"):
        return "text.script.perl"
    if name.endswith(".icns"):
        return "image.icns"
    return "text"


def build_pbxproj(groups: dict[str, list[str]]) -> str:
    sources = [(g, n) for g, names in groups.items() for n in names]
    vendor = vendor_files()
    if not sources:
        sys.exit("error: no Swift sources found under %s/" % PROJECT_NAME)

    ids = {
        "project": oid("project"),
        "target": oid("target"),
        "product": oid("product"),
        "main_group": oid("group:main"),
        "products_group": oid("group:Products"),
        "root_group": oid("group:%s" % PROJECT_NAME),
        "resources_group": oid("group:Resources"),
        "vendor_group": oid("group:Vendor"),
        "sources_phase": oid("phase:sources"),
        "frameworks_phase": oid("phase:frameworks"),
        "resources_phase": oid("phase:resources"),
        "project_config_list": oid("configlist:project"),
        "target_config_list": oid("configlist:target"),
        "project_debug": oid("config:project:Debug"),
        "project_release": oid("config:project:Release"),
        "target_debug": oid("config:target:Debug"),
        "target_release": oid("config:target:Release"),
    }

    out = []
    w = out.append

    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {")
    w("\t};")
    w("\tobjectVersion = 56;")
    w("\tobjects = {")

    # PBXBuildFile
    w("")
    w("/* Begin PBXBuildFile section */")
    for group, name in sources:
        path = "%s/%s" % (group, name)
        w("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
          % (oid("buildfile:" + path), name, oid("fileref:" + path), name))
    for name in COPIED_RESOURCES:
        path = "Resources/%s" % name
        w('\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };'
          % (oid("buildfile:" + path), name, oid("fileref:" + path), name))
    for name in vendor:
        path = "%s/%s" % (VENDOR_DIR, name)
        w('\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };'
          % (oid("buildfile:" + path), name, oid("fileref:" + path), name))
    w("/* End PBXBuildFile section */")

    # PBXFileReference
    w("")
    w("/* Begin PBXFileReference section */")
    w('\t\t%s /* %s.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; '
      'includeInIndex = 0; path = %s.app; sourceTree = BUILT_PRODUCTS_DIR; };'
      % (ids["product"], PROJECT_NAME, PROJECT_NAME))
    for group, name in sources:
        path = "%s/%s" % (group, name)
        w('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = "<group>"; };'
          % (oid("fileref:" + path), name, file_type(name), name))
    for name in RESOURCE_FILES:
        path = "Resources/%s" % name
        w('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = "<group>"; };'
          % (oid("fileref:" + path), name, file_type(name), name))
    for name in vendor:
        path = "%s/%s" % (VENDOR_DIR, name)
        w('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = "<group>"; };'
          % (oid("fileref:" + path), name, file_type(name), name))
    w("/* End PBXFileReference section */")

    # PBXFrameworksBuildPhase
    w("")
    w("/* Begin PBXFrameworksBuildPhase section */")
    w("\t\t%s /* Frameworks */ = {" % ids["frameworks_phase"])
    w("\t\t\tisa = PBXFrameworksBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXFrameworksBuildPhase section */")

    # PBXGroup
    w("")
    w("/* Begin PBXGroup section */")

    w("\t\t%s = {" % ids["main_group"])
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w("\t\t\t\t%s /* %s */," % (ids["root_group"], PROJECT_NAME))
    w("\t\t\t\t%s /* Products */," % ids["products_group"])
    w("\t\t\t);")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

    w("\t\t%s /* Products */ = {" % ids["products_group"])
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w("\t\t\t\t%s /* %s.app */," % (ids["product"], PROJECT_NAME))
    w("\t\t\t);")
    w("\t\t\tname = Products;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

    w("\t\t%s /* %s */ = {" % (ids["root_group"], PROJECT_NAME))
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for group in SOURCE_GROUPS:
        if group in groups:
            w("\t\t\t\t%s /* %s */," % (oid("group:" + group), group))
    w("\t\t\t\t%s /* Resources */," % ids["resources_group"])
    if vendor:
        w("\t\t\t\t%s /* Vendor */," % ids["vendor_group"])
    w("\t\t\t);")
    w("\t\t\tpath = %s;" % PROJECT_NAME)
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

    for group in SOURCE_GROUPS:
        if group not in groups:
            continue
        w("\t\t%s /* %s */ = {" % (oid("group:" + group), group))
        w("\t\t\tisa = PBXGroup;")
        w("\t\t\tchildren = (")
        for name in groups[group]:
            w("\t\t\t\t%s /* %s */," % (oid("fileref:%s/%s" % (group, name)), name))
        w("\t\t\t);")
        w("\t\t\tpath = %s;" % group)
        w("\t\t\tsourceTree = \"<group>\";")
        w("\t\t};")

    w("\t\t%s /* Resources */ = {" % ids["resources_group"])
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for name in RESOURCE_FILES:
        w("\t\t\t\t%s /* %s */," % (oid("fileref:Resources/%s" % name), name))
    w("\t\t\t);")
    w("\t\t\tpath = Resources;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

    if vendor:
        w("\t\t%s /* Vendor */ = {" % ids["vendor_group"])
        w("\t\t\tisa = PBXGroup;")
        w("\t\t\tchildren = (")
        for name in vendor:
            w("\t\t\t\t%s /* %s */," % (oid("fileref:%s/%s" % (VENDOR_DIR, name)), name))
        w("\t\t\t);")
        w("\t\t\tpath = %s;" % VENDOR_DIR)
        w("\t\t\tsourceTree = \"<group>\";")
        w("\t\t};")
    w("/* End PBXGroup section */")

    # PBXNativeTarget
    w("")
    w("/* Begin PBXNativeTarget section */")
    w("\t\t%s /* %s */ = {" % (ids["target"], PROJECT_NAME))
    w("\t\t\tisa = PBXNativeTarget;")
    w("\t\t\tbuildConfigurationList = %s;" % ids["target_config_list"])
    w("\t\t\tbuildPhases = (")
    w("\t\t\t\t%s /* Sources */," % ids["sources_phase"])
    w("\t\t\t\t%s /* Frameworks */," % ids["frameworks_phase"])
    w("\t\t\t\t%s /* Resources */," % ids["resources_phase"])
    w("\t\t\t);")
    w("\t\t\tbuildRules = (")
    w("\t\t\t);")
    w("\t\t\tdependencies = (")
    w("\t\t\t);")
    w("\t\t\tname = %s;" % PROJECT_NAME)
    w("\t\t\tproductName = %s;" % PROJECT_NAME)
    w("\t\t\tproductReference = %s /* %s.app */;" % (ids["product"], PROJECT_NAME))
    w("\t\t\tproductType = \"com.apple.product-type.application\";")
    w("\t\t};")
    w("/* End PBXNativeTarget section */")

    # PBXProject
    w("")
    w("/* Begin PBXProject section */")
    w("\t\t%s /* Project object */ = {" % ids["project"])
    w("\t\t\tisa = PBXProject;")
    w("\t\t\tattributes = {")
    w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    w("\t\t\t\tLastSwiftUpdateCheck = 1500;")
    w("\t\t\t\tLastUpgradeCheck = 1500;")
    w("\t\t\t\tTargetAttributes = {")
    w("\t\t\t\t\t%s = {" % ids["target"])
    w("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    w("\t\t\t\t\t};")
    w("\t\t\t\t};")
    w("\t\t\t};")
    w("\t\t\tbuildConfigurationList = %s;" % ids["project_config_list"])
    w("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    w("\t\t\tdevelopmentRegion = en;")
    w("\t\t\thasScannedForEncodings = 0;")
    w("\t\t\tknownRegions = (")
    w("\t\t\t\ten,")
    w("\t\t\t\tBase,")
    w("\t\t\t);")
    w("\t\t\tmainGroup = %s;" % ids["main_group"])
    w("\t\t\tproductRefGroup = %s /* Products */;" % ids["products_group"])
    w("\t\t\tprojectDirPath = \"\";")
    w("\t\t\tprojectRoot = \"\";")
    w("\t\t\ttargets = (")
    w("\t\t\t\t%s /* %s */," % (ids["target"], PROJECT_NAME))
    w("\t\t\t);")
    w("\t\t};")
    w("/* End PBXProject section */")

    # PBXResourcesBuildPhase
    w("")
    w("/* Begin PBXResourcesBuildPhase section */")
    w("\t\t%s /* Resources */ = {" % ids["resources_phase"])
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for name in COPIED_RESOURCES:
        w("\t\t\t\t%s /* %s in Resources */," % (oid("buildfile:Resources/%s" % name), name))
    for name in vendor:
        w("\t\t\t\t%s /* %s in Resources */," % (oid("buildfile:%s/%s" % (VENDOR_DIR, name)), name))
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXResourcesBuildPhase section */")

    # PBXSourcesBuildPhase
    w("")
    w("/* Begin PBXSourcesBuildPhase section */")
    w("\t\t%s /* Sources */ = {" % ids["sources_phase"])
    w("\t\t\tisa = PBXSourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for group, name in sources:
        w("\t\t\t\t%s /* %s in Sources */," % (oid("buildfile:%s/%s" % (group, name)), name))
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXSourcesBuildPhase section */")

    # XCBuildConfiguration
    project_common = [
        ("ALWAYS_SEARCH_USER_PATHS", "NO"),
        ("CLANG_ENABLE_MODULES", "YES"),
        ("CLANG_ENABLE_OBJC_ARC", "YES"),
        ("COPY_PHASE_STRIP", "NO"),
        ("ENABLE_STRICT_OBJC_MSGSEND", "YES"),
        ("GCC_NO_COMMON_BLOCKS", "YES"),
        ("MACOSX_DEPLOYMENT_TARGET", DEPLOYMENT_TARGET),
        ("SDKROOT", "macosx"),
    ]
    target_common = [
        ("CODE_SIGN_ENTITLEMENTS", "%s/Resources/DynamicIsland.entitlements" % PROJECT_NAME),
        ("CODE_SIGN_IDENTITY", '"-"'),
        ("CODE_SIGN_STYLE", "Manual"),
        ("COMBINE_HIDPI_IMAGES", "YES"),
        ("CURRENT_PROJECT_VERSION", "1"),
        ("DEVELOPMENT_TEAM", '""'),
        ("ENABLE_HARDENED_RUNTIME", "YES"),
        ("ENABLE_PREVIEWS", "YES"),
        ("GENERATE_INFOPLIST_FILE", "NO"),
        ("INFOPLIST_FILE", "%s/Resources/Info.plist" % PROJECT_NAME),
        ("LD_RUNPATH_SEARCH_PATHS", '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/../Frameworks",\n\t\t\t\t)'),
        ("MARKETING_VERSION", "1.0"),
        ("PRODUCT_BUNDLE_IDENTIFIER", BUNDLE_ID),
        ("PRODUCT_NAME", '"%s"' % DISPLAY_NAME),
        # Pinned so a display name with a space cannot leak into the Swift
        # module name, which would rename the module to "Dinamik_Ada".
        ("PRODUCT_MODULE_NAME", PROJECT_NAME),
        ("PROVISIONING_PROFILE_SPECIFIER", '""'),
        ("SWIFT_EMIT_LOC_STRINGS", "YES"),
        ("SWIFT_VERSION", SWIFT_VERSION),
    ]

    def config_block(object_id, name, settings):
        w("\t\t%s /* %s */ = {" % (object_id, name))
        w("\t\t\tisa = XCBuildConfiguration;")
        w("\t\t\tbuildSettings = {")
        for key, value in settings:
            w("\t\t\t\t%s = %s;" % (key, value))
        w("\t\t\t};")
        w("\t\t\tname = %s;" % name)
        w("\t\t};")

    w("")
    w("/* Begin XCBuildConfiguration section */")
    config_block(ids["project_debug"], "Debug", project_common + [
        ("DEBUG_INFORMATION_FORMAT", "dwarf"),
        ("ENABLE_TESTABILITY", "YES"),
        ("GCC_OPTIMIZATION_LEVEL", "0"),
        ("GCC_PREPROCESSOR_DEFINITIONS", '(\n\t\t\t\t\t"DEBUG=1",\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t)'),
        ("MTL_ENABLE_DEBUG_INFO", "INCLUDE_SOURCE"),
        ("ONLY_ACTIVE_ARCH", "YES"),
        ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", '"DEBUG $(inherited)"'),
        ("SWIFT_OPTIMIZATION_LEVEL", '"-Onone"'),
    ])
    config_block(ids["project_release"], "Release", project_common + [
        ("DEBUG_INFORMATION_FORMAT", '"dwarf-with-dsym"'),
        ("ENABLE_NS_ASSERTIONS", "NO"),
        ("MTL_ENABLE_DEBUG_INFO", "NO"),
        ("SWIFT_COMPILATION_MODE", "wholemodule"),
        ("SWIFT_OPTIMIZATION_LEVEL", '"-O"'),
    ])
    config_block(ids["target_debug"], "Debug", target_common)
    config_block(ids["target_release"], "Release", target_common)
    w("/* End XCBuildConfiguration section */")

    # XCConfigurationList
    w("")
    w("/* Begin XCConfigurationList section */")
    for list_id, label, debug_id, release_id in (
        (ids["project_config_list"], "PBXProject \"%s\"" % PROJECT_NAME,
         ids["project_debug"], ids["project_release"]),
        (ids["target_config_list"], "PBXNativeTarget \"%s\"" % PROJECT_NAME,
         ids["target_debug"], ids["target_release"]),
    ):
        w("\t\t%s /* Build configuration list for %s */ = {" % (list_id, label))
        w("\t\t\tisa = XCConfigurationList;")
        w("\t\t\tbuildConfigurations = (")
        w("\t\t\t\t%s /* Debug */," % debug_id)
        w("\t\t\t\t%s /* Release */," % release_id)
        w("\t\t\t);")
        w("\t\t\tdefaultConfigurationIsVisible = 0;")
        w("\t\t\tdefaultConfigurationName = Release;")
        w("\t\t};")
    w("/* End XCConfigurationList section */")

    w("\t};")
    w("\trootObject = %s /* Project object */;" % ids["project"])
    w("}")
    w("")

    return "\n".join(out)


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target}"
               BuildableName = "{name}.app"
               BlueprintName = "{name}"
               ReferencedContainer = "container:{name}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target}"
            BuildableName = "{name}.app"
            BlueprintName = "{name}"
            ReferencedContainer = "container:{name}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target}"
            BuildableName = "{name}.app"
            BlueprintName = "{name}"
            ReferencedContainer = "container:{name}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def main() -> None:
    groups = swift_sources()
    project_dir = os.path.join(ROOT, "%s.xcodeproj" % PROJECT_NAME)
    scheme_dir = os.path.join(project_dir, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)

    with open(os.path.join(project_dir, "project.pbxproj"), "w") as handle:
        handle.write(build_pbxproj(groups))

    with open(os.path.join(scheme_dir, "%s.xcscheme" % PROJECT_NAME), "w") as handle:
        handle.write(SCHEME.format(target=oid("target"), name=PROJECT_NAME))

    total = sum(len(v) for v in groups.values())
    print("Wrote %s.xcodeproj (%d Swift files across %d groups)"
          % (PROJECT_NAME, total, len(groups)))


if __name__ == "__main__":
    main()
