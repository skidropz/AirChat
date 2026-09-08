#!/usr/bin/env python3
"""
generate_project.py — writes ios/AirChat/AirChat.xcodeproj/project.pbxproj.

Xcode project files are plain text but fussy: every source file needs a
PBXFileReference, a PBXBuildFile and a group entry, all with matching 24-hex ids.
Instead of hand-maintaining that, this script derives the whole project from the
files that are actually on disk, with a real nested group tree.

Run it after adding or removing files:

    python3 ios/AirChat/scripts/generate_project.py

`project.yml` next to it is the readable XcodeGen spec for the same target, in case
you prefer `xcodegen generate` (both produce an identical build).

Layout produced (all paths relative to ios/AirChat):

    AirChat.xcodeproj/            + this file
    AirChat/Info.plist
    AirChat/AirChat.entitlements
    AirChat/Sources/**/*.swift
    AirChat/WebApp/               <- folder reference, synced from app/src/main/assets
    AirChat/Resources/Assets.xcassets
"""
import os
import hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                       # ios/AirChat
SRC_ROOT = os.path.join(ROOT, "AirChat")           # ios/AirChat/AirChat
PROJECT = os.path.join(ROOT, "AirChat.xcodeproj")

BUNDLE_ID = "com.skidropz.airchat"
TEAM = ""                       # empty on purpose: free personal Apple ID, no $99 account
DEPLOYMENT = "15.0"
MARKETING = "3.0.0"


def make_id(*parts):
    """Stable 24-char uppercase hex id, so regenerating does not churn the diff."""
    return hashlib.sha1("|".join(parts).encode()).hexdigest().upper()[:24]


def swift_files():
    base = os.path.join(SRC_ROOT, "Sources")
    out = []
    for dirpath, _dirnames, filenames in os.walk(base):
        for name in filenames:
            if name.endswith(".swift"):
                rel = os.path.relpath(os.path.join(dirpath, name), base)
                out.append(rel.replace(os.sep, "/"))
    if not out:
        raise SystemExit("no Swift sources under " + base)
    return sorted(out)


def section(name, entries):
    return "/* Begin %s section */\n%s\n/* End %s section */\n" % (name, "\n".join(entries), name)


def quote(value):
    return value if all(c.isalnum() or c in "._-" for c in value) else '"%s"' % value


class Tree:
    """Group tree of (name -> Tree) with file ids as leaves."""

    def __init__(self, path=None):
        self.path = path
        self.children = {}      # name -> Tree
        self.files = []         # list of (id, name)

    def add(self, rel, file_id):
        parts = rel.split("/")
        node = self
        for part in parts[:-1]:
            node = node.children.setdefault(part, Tree(part))
        node.files.append((file_id, parts[-1]))
        return node


def build():
    sources = swift_files()
    ids = {rel: (make_id("file", rel), make_id("build", rel)) for rel in sources}

    tree = Tree()
    for rel in sources:
        tree.add(rel, ids[rel][0])

    # ---------------------------------------------------------------- ids
    webapp_id = make_id("folder", "WebApp")
    assets_id = make_id("folder", "Assets.xcassets")
    webapp_build = make_id("build", "WebApp")
    assets_build = make_id("build", "Assets.xcassets")
    plist_id = make_id("file", "Info.plist")
    ent_id = make_id("file", "AirChat.entitlements")
    airchat_group = make_id("group", "AirChat")
    products_group = make_id("group", "Products")
    main_group = make_id("group", "main")
    app_proxy = make_id("file", "AirChat.app")
    target_id = make_id("target", "AirChat")
    proj_id = make_id("project", "AirChat")
    cfg_list_proj = make_id("cfglist", "project")
    cfg_list_target = make_id("cfglist", "target")
    dbg_proj, rel_proj = make_id("cfg", "project", "Debug"), make_id("cfg", "project", "Release")
    dbg_tgt, rel_tgt = make_id("cfg", "target", "Debug"), make_id("cfg", "target", "Release")
    phase_sources = make_id("phase", "sources")
    phase_frameworks = make_id("phase", "frameworks")
    phase_resources = make_id("phase", "resources")
    phase_script = make_id("phase", "script")

    # ---------------------------------------------------- PBXBuildFile
    build_files = []
    source_file_ids = []
    for rel in sources:
        fid, bid = ids[rel]
        name = os.path.basename(rel)
        build_files.append("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };" % (bid, name, fid, name))
        source_file_ids.append("%s /* %s in Sources */" % (bid, name))
    resource_file_ids = []
    build_files.append("\t\t%s /* WebApp in Resources */ = {isa = PBXBuildFile; fileRef = %s /* WebApp */; };" % (webapp_build, webapp_id))
    resource_file_ids.append("%s /* WebApp in Resources */" % webapp_build)
    build_files.append("\t\t%s /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = %s /* Assets.xcassets */; };" % (assets_build, assets_id))
    resource_file_ids.append("%s /* Assets.xcassets in Resources */" % assets_build)

    # ------------------------------------------------- PBXFileReference
    file_refs = []
    for rel in sources:
        fid, _bid = ids[rel]
        name = os.path.basename(rel)
        file_refs.append("\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = \"<group>\"; };"
                         % (fid, name, quote(name)))
    file_refs.append("\t\t%s /* WebApp */ = {isa = PBXFileReference; lastKnownFileType = folder; path = WebApp; sourceTree = \"<group>\"; };" % webapp_id)
    file_refs.append("\t\t%s /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; };" % assets_id)
    file_refs.append("\t\t%s /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; };" % plist_id)
    file_refs.append("\t\t%s /* AirChat.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = AirChat.entitlements; sourceTree = \"<group>\"; };" % ent_id)
    file_refs.append("\t\t%s /* AirChat.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = AirChat.app; sourceTree = BUILT_PRODUCTS_DIR; };" % app_proxy)

    # --------------------------------------------------------- PBXGroup
    groups = []
    group_ids = {}

    def emit(node, relpath):
        """relpath = directory path relative to the AirChat folder (e.g. Sources/Net).
        Each group carries only its own last component as `path`, because Xcode
        resolves group paths relative to their parent."""
        gid = make_id("group", relpath)
        group_ids[relpath] = gid
        children = []
        for fid, name in sorted(node.files, key=lambda x: x[1]):
            children.append("\t\t\t\t%s /* %s */," % (fid, name))
        for child_name in sorted(node.children):
            child = node.children[child_name]
            child_rel = (relpath + "/" + child_name) if relpath else child_name
            emit(child, child_rel)
            children.append("\t\t\t\t%s /* %s */," % (group_ids[child_rel], child_name))
        leaf = relpath.split("/")[-1] if relpath else ""
        groups.append(
            "\t\t%s /* %s */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\n\t\t\t);\n"
            "\t\t\tpath = %s;\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
            % (gid, leaf, "\n".join(children), quote(leaf)))
        return gid

    sources_group_id = emit(tree, "Sources")

    # Resources group holds the asset catalog (shareable artifacts live in WebApp/share).
    resources_group_id = make_id("group", "Resources")
    groups.append(
        "\t\t%s /* Resources */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
        "\t\t\t\t%s /* Assets.xcassets */,\n\t\t\t);\n\t\t\tpath = Resources;\n"
        "\t\t\tsourceTree = \"<group>\";\n\t\t};" % (resources_group_id, assets_id))

    groups.append(
        "\t\t%s /* AirChat */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
        "\t\t\t\t%s /* Info.plist */,\n\t\t\t\t%s /* AirChat.entitlements */,\n"
        "\t\t\t\t%s /* Sources */,\n\t\t\t\t%s /* WebApp */,\n\t\t\t\t%s /* Resources */,\n"
        "\t\t\t);\n\t\t\tpath = AirChat;\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
        % (airchat_group, plist_id, ent_id, sources_group_id, webapp_id, resources_group_id))
    groups.append(
        "\t\t%s /* Products */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t%s /* AirChat.app */,\n"
        "\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
        % (products_group, app_proxy))
    groups.append(
        "\t\t%s = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t%s /* AirChat */,\n"
        "\t\t\t\t%s /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
        % (main_group, airchat_group, products_group))


    # ------------------------------------------------------ build phases
    def id_list(items):
        return "\n".join("\t\t\t\t%s," % item for item in items)

    script_phase = (
        "\t\t%s /* Sync shared web app */ = {\n\t\t\tisa = PBXShellScriptBuildPhase;\n\t\t\talwaysOutOfDate = 1;\n"
        "\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n"
        "\t\t\tinputFileListPaths = (\n\t\t\t);\n\t\t\tinputPaths = (\n\t\t\t\t\"$(SRCROOT)/../../app/src/main/assets/index.html\",\n\t\t\t);\n"
        "\t\t\tname = \"Sync shared web app\";\n\t\t\toutputFileListPaths = (\n\t\t\t);\n"
        "\t\t\toutputPaths = (\n\t\t\t\t\"$(SRCROOT)/AirChat/WebApp/index.html\",\n\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t\tshellPath = /bin/bash;\n"
        "\t\t\tshellScript = \"\\\"${SRCROOT}/scripts/sync_web_assets.sh\\\"\\n\";\n\t\t};"
        % phase_script)

    # ------------------------------------------------------ configurations
    common = [
        ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
        ("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME", "AccentColor"),
        ("CODE_SIGN_ENTITLEMENTS", "AirChat/AirChat.entitlements"),
        ("CODE_SIGN_IDENTITY", '"iPhone Developer"'),
        ("CODE_SIGN_STYLE", "Automatic"),
        ("COPY_PHASE_STRIP", "NO"),
        ("CURRENT_PROJECT_VERSION", "1"),
        ("DEVELOPMENT_TEAM", '"%s"' % TEAM),
        ("ENABLE_USER_SCRIPT_SANDBOXING", "NO"),
        ("GENERATE_INFOPLIST_FILE", "NO"),
        ("INFOPLIST_FILE", "AirChat/Info.plist"),
        ("IPHONEOS_DEPLOYMENT_TARGET", quote(DEPLOYMENT)),
        ("LD_RUNPATH_SEARCH_PATHS", '"$(inherited) @executable_path/Frameworks"'),
        ("MARKETING_VERSION", quote(MARKETING)),
        ("PRODUCT_BUNDLE_IDENTIFIER", BUNDLE_ID),
        ("PRODUCT_NAME", "AirChat"),
        ("SWIFT_EMIT_LOC_STRINGS", "NO"),
        ("SWIFT_VERSION", "5.0"),
        ("TARGETED_DEVICE_FAMILY", "1"),
    ]

    def config(cid, name, pairs):
        body = "\n".join("\t\t\t\t%s = %s;" % (k, v) for k, v in pairs)
        return ("\t\t%s /* %s */ = {\n\t\t\tisa = XCBuildConfiguration;\n"
                "\t\t\tbuildSettings = {\n%s\n\t\t\t};\n\t\t\tname = %s;\n\t\t};"
                % (cid, name, body, name))

    project_debug = config(dbg_proj, "Debug", [
        ("ALWAYS_SEARCH_USER_PATHS", "NO"),
        ("CLANG_ANALYZER_NONNULL", "YES"),
        ("CLANG_ENABLE_MODULES", "YES"),
        ("CLANG_ENABLE_OBJC_ARC", "YES"),
        ("COPY_PHASE_STRIP", "NO"),
        ("ENABLE_STRICT_OBJC_MSGSEND", "YES"),
        ("GCC_C_LANGUAGE_STANDARD", "gnu17"),
        ("IPHONEOS_DEPLOYMENT_TARGET", quote(DEPLOYMENT)),
        ("ONLY_ACTIVE_ARCH", "YES"),
        ("SDKROOT", "iphoneos"),
        ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", '"DEBUG $(inherited)"'),
        ("SWIFT_OPTIMIZATION_LEVEL", "-Onone"),
    ])
    project_release = config(rel_proj, "Release", [
        ("ALWAYS_SEARCH_USER_PATHS", "NO"),
        ("CLANG_ENABLE_MODULES", "YES"),
        ("CLANG_ENABLE_OBJC_ARC", "YES"),
        ("ENABLE_NS_ASSERTIONS", "NO"),
        ("IPHONEOS_DEPLOYMENT_TARGET", quote(DEPLOYMENT)),
        ("SDKROOT", "iphoneos"),
        ("SWIFT_OPTIMIZATION_LEVEL", "-O"),
        ("VALIDATE_PRODUCT", "YES"),
    ])
    target_debug = config(dbg_tgt, "Debug", common + [
        ("ONLY_ACTIVE_ARCH", "YES"),
        ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", '"DEBUG $(inherited)"'),
    ])
    target_release = config(rel_tgt, "Release", common + [
        ("DEAD_CODE_STRIPPING", "YES"),
        ("VALIDATE_PRODUCT", "YES"),
    ])

    native_target = (
        "\t\t%s /* AirChat */ = {\n\t\t\tisa = PBXNativeTarget;\n"
        "\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"AirChat\" */;\n"
        "\t\t\tbuildPhases = (\n\t\t\t\t%s /* Sync shared web app */,\n\t\t\t\t%s /* Sources */,\n"
        "\t\t\t\t%s /* Frameworks */,\n\t\t\t\t%s /* Resources */,\n\t\t\t);\n"
        "\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = AirChat;\n"
        "\t\t\tpackageProductDependencies = (\n\t\t\t);\n\t\t\tproductName = AirChat;\n"
        "\t\t\tproductReference = %s /* AirChat.app */;\n"
        "\t\t\tproductType = \"com.apple.product-type.application\";\n\t\t};"
        % (target_id, cfg_list_target, phase_script, phase_sources, phase_frameworks, phase_resources, app_proxy)
    )

    project_obj = (
        "\t\t%s /* AirChat */ = {\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {\n"
        "\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 1500;\n"
        "\t\t\t\tLastUpgradeCheck = 1500;\n\t\t\t\tTargetAttributes = {\n\t\t\t\t\t%s = {\n"
        "\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;\n\t\t\t\t\t\tProvisioningStyle = Automatic;\n\t\t\t\t\t};\n\t\t\t\t};\n\t\t\t};\n"
        "\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject \"AirChat\" */;\n"
        "\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n\t\t\tdevelopmentRegion = en;\n"
        "\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tro,\n\t\t\t\tBase,\n\t\t\t);\n"
        "\t\t\tmainGroup = %s;\n\t\t\tproductRefGroup = %s /* Products */;\n\t\t\tprojectDirPath = \"\";\n"
        "\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n\t\t\t\t%s /* AirChat */,\n\t\t\t);\n\t\t};"
        % (proj_id, target_id, cfg_list_proj, main_group, products_group, target_id)
    )

    sections = [
        section("PBXBuildFile", build_files),
        section("PBXFileReference", file_refs),
        section("PBXFrameworksBuildPhase", [
            "\t\t%s /* Frameworks */ = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0; };" % phase_frameworks
        ]),
        section("PBXGroup", groups),
        section("PBXNativeTarget", [native_target]),
        section("PBXProject", [project_obj]),
        section("PBXResourcesBuildPhase", [
            "\t\t%s /* Resources */ = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647;\n\t\t\tfiles = (\n%s\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};"
            % (phase_resources, id_list(resource_file_ids))
        ]),
        section("PBXShellScriptBuildPhase", [script_phase]),
        section("PBXSourcesBuildPhase", [
            "\t\t%s /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647;\n\t\t\tfiles = (\n%s\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};"
            % (phase_sources, id_list(source_file_ids))
        ]),
        section("XCBuildConfiguration", [project_debug, project_release, target_debug, target_release]),
        section("XCConfigurationList", [
            "\t\t%s /* Build configuration list for PBXProject \"AirChat\" */ = {isa = XCConfigurationList; buildConfigurations = (\n\t\t\t%s /* Debug */,\n\t\t\t%s /* Release */,\n\t\t\t); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };"
            % (cfg_list_proj, dbg_proj, rel_proj),
            "\t\t%s /* Build configuration list for PBXNativeTarget \"AirChat\" */ = {isa = XCConfigurationList; buildConfigurations = (\n\t\t\t%s /* Debug */,\n\t\t\t%s /* Release */,\n\t\t\t); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };"
            % (cfg_list_target, dbg_tgt, rel_tgt),
        ]),
    ]

    body = ("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n"
            "\tobjects = {\n\n" + "\n\n".join(sections) + "\n\t};\n\trootObject = %s /* AirChat */;\n}\n" % proj_id)

    for sub in (os.path.join(PROJECT, "xcshareddata", "xcschemes"),
                os.path.join(PROJECT, "project.xcworkspace")):
        os.makedirs(sub, exist_ok=True)

    with open(os.path.join(PROJECT, "project.pbxproj"), "w") as f:
        f.write(body)
    with open(os.path.join(PROJECT, "project.xcworkspace", "contents.xcworkspacedata"), "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version = "1.0">\n   <FileRef location = "self:">\n   </FileRef>\n</Workspace>\n')
    scheme = open(os.path.join(HERE, "AirChat.xcscheme.template")).read()
    scheme = scheme.replace("__TARGET_ID__", target_id)
    with open(os.path.join(PROJECT, "xcshareddata", "xcschemes", "AirChat.xcscheme"), "w") as f:
        f.write(scheme)

    print("wrote %s (%d sources)" % (os.path.relpath(PROJECT, os.getcwd()), len(sources)))


if __name__ == "__main__":
    build()
