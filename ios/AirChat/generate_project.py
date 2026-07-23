#!/usr/bin/env python3
"""Generates AirChat.xcodeproj/project.pbxproj for the native iOS app.
Run from anywhere; output is written next to this file.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
APP_DIR = os.path.join(HERE, "AirChat")

# (group, filename) for Swift sources, relative to APP_DIR
SOURCES = [
    ("App", "AirChatApp.swift"),
    ("Core", "AppConstants.swift"),
    ("Core", "ChatStore.swift"),
    ("Models", "AirChatMessage.swift"),
    ("Crypto", "XORCipher.swift"),
    ("Crypto", "MeshCrypto.swift"),
    ("Networking", "AirChatServer.swift"),
    ("Networking", "HTTPRequest.swift"),
    ("Networking", "WebSocketFrame.swift"),
    ("Networking", "ClientConnection.swift"),
    ("Networking", "WebSocketClient.swift"),
    ("Mesh", "MeshManager.swift"),
    ("Sensors", "LocationManager.swift"),
    ("Sensors", "DeviceSensors.swift"),
    ("UI", "Theme.swift"),
    ("UI", "Components.swift"),
    ("UI", "StartView.swift"),
    ("UI", "JoinView.swift"),
    ("UI", "HostSetupView.swift"),
    ("UI", "ChatView.swift"),
    ("UI", "MessageRow.swift"),
    ("UI", "ComposerBar.swift"),
    ("UI", "UsersSheet.swift"),
    ("UI", "CompassSheet.swift"),
]

WEB_FILES = ["index.html", "app.js", "style.css", "manifest.json", "sw.js"]

_id_counter = [0xA00000]
def nid(prefix=""):
    _id_counter[0] += 1
    return ("%024X" % _id_counter[0])

# Fixed IDs for structural objects
P_PROJECT      = nid()
G_MAIN         = nid()
G_PRODUCTS     = nid()
G_APP          = nid()  # "AirChat" group (path = AirChat)
G_RESOURCES    = nid()
PRODUCT_REF    = nid()
TARGET         = nid()
PHASE_SOURCES  = nid()
PHASE_FRAMEWORKS = nid()
PHASE_RESOURCES  = nid()
CL_PROJECT     = nid()
CL_TARGET      = nid()
CFG_PROJ_DEBUG = nid()
CFG_PROJ_REL   = nid()
CFG_TGT_DEBUG  = nid()
CFG_TGT_REL    = nid()
VARIANT_GROUP  = nid()
EN_REF         = nid()
RO_REF         = nid()
ASSETS_REF     = nid()
BUILD_ASSETS   = nid()
BUILD_VARIANT  = nid()
WEB_REFS       = {}
WEB_BUILDS     = {}

# group name -> id
GROUPS = {}
for g in sorted(set(s[0] for s in SOURCES)):
    GROUPS[g] = nid()

SRC_REF = {}   # path -> id
SRC_BUILD = {} # path -> id
for g, f in SOURCES:
    rid = nid(); bid = nid()
    SRC_REF[(g, f)] = rid
    SRC_BUILD[(g, f)] = bid

for wf in WEB_FILES:
    WEB_REFS[wf] = nid()
    WEB_BUILDS[wf] = nid()

# ---- emit ----
L = []
def w(s=""): L.append(s)

w("// !$*UTF8*$!")
w("{")
w("\tarchiveVersion = 1;")
w("\tclasses = {}")
w("\tobjectVersion = 56;")
w("\tobjects = {")
w()

# PBXBuildFile
w("/* Begin PBXBuildFile section */")
for (g, f) in SOURCES:
    w(f"\t\t{SRC_BUILD[(g,f)]} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {SRC_REF[(g,f)]} /* {f} */; }};")
w(f"\t\t{BUILD_ASSETS} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {ASSETS_REF} /* Assets.xcassets */; }};")
for wf in WEB_FILES:
    w(f"\t\t{WEB_BUILDS[wf]} /* {wf} in Resources */ = {{isa = PBXBuildFile; fileRef = {WEB_REFS[wf]} /* {wf} */; }};")
w(f"\t\t{BUILD_VARIANT} /* Localizable.strings in Resources */ = {{isa = PBXBuildFile; fileRef = {VARIANT_GROUP} /* Localizable.strings */; }};")
w("/* End PBXBuildFile section */")
w()

# PBXFileReference
w("/* Begin PBXFileReference section */")
w(f"\t\t{PRODUCT_REF} /* AirChat.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = AirChat.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
for (g, f) in SOURCES:
    w(f"\t\t{SRC_REF[(g,f)]} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = \"<group>\"; }};")
w(f"\t\t{ASSETS_REF} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder; name = Assets.xcassets; path = Resources/Assets.xcassets; sourceTree = \"<group>\"; }};")
ext_map = {"html":"text.html","js":"sourcecode.javascript","css":"text.css","json":"text.json","svg":"image.svg"}
for wf in WEB_FILES:
    ext = wf.split(".")[-1]
    lft = ext_map.get(ext, "text")
    w(f"\t\t{WEB_REFS[wf]} /* {wf} */ = {{isa = PBXFileReference; lastKnownFileType = {lft}; path = Resources/Web/{wf}; sourceTree = \"<group>\"; }};")
w(f"\t\t{EN_REF} /* en */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = en; path = Resources/en.lproj/Localizable.strings; sourceTree = \"<group>\"; }};")
w(f"\t\t{RO_REF} /* ro */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = ro; path = Resources/ro.lproj/Localizable.strings; sourceTree = \"<group>\"; }};")
w("/* End PBXFileReference section */")
w()

# PBXFrameworksBuildPhase
w("/* Begin PBXFrameworksBuildPhase section */")
w(f"\t\t{PHASE_FRAMEWORKS} /* Frameworks */ = {{")
w("\t\t\tisa = PBXFrameworksBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXFrameworksBuildPhase section */")
w()

# PBXVariantGroup
w("/* Begin PBXVariantGroup section */")
w(f"\t\t{VARIANT_GROUP} /* Localizable.strings */ = {{")
w("\t\t\tisa = PBXVariantGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{EN_REF} /* en */,")
w(f"\t\t\t\t{RO_REF} /* ro */,")
w("\t\t\t);")
w("\t\t\tname = Localizable.strings;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w("/* End PBXVariantGroup section */")
w()

# PBXGroup
w("/* Begin PBXGroup section */")
def group_children(group_id, children_ids):
    w(f"\t\t{group_id} = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for c in children_ids:
        w(f"\t\t\t\t{c[0]} /* {c[1]} */,")
    w("\t\t\t);")
    if group_id == G_MAIN:
        w(f"\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

# subgroups for each source group, listing their file refs
group_files = {}
for (g, f) in SOURCES:
    group_files.setdefault(g, []).append(f)

# Build group definitions
# Resources group
res_children = [(ASSETS_REF, "Assets.xcassets")] + [(WEB_REFS[wf], wf) for wf in WEB_FILES] + [(VARIANT_GROUP, "Localizable.strings")]

w(f"\t\t{G_RESOURCES} /* Resources */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{ASSETS_REF} /* Assets.xcassets */,")
for wf in WEB_FILES:
    w(f"\t\t\t\t{WEB_REFS[wf]} /* {wf} */,")
w(f"\t\t\t\t{VARIANT_GROUP} /* Localizable.strings */,")
w("\t\t\t);")
w("\t\t\tpath = Resources;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")

# each source subgroup
for g in sorted(group_files.keys()):
    w(f"\t\t{GROUPS[g]} /* {g} */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for f in group_files[g]:
        w(f"\t\t\t\t{SRC_REF[(g,f)]} /* {f} */,")
    w("\t\t\t);")
    w(f"\t\t\tpath = {g};")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

# App group (AirChat)
w(f"\t\t{G_APP} /* AirChat */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
for g in sorted(group_files.keys()):
    w(f"\t\t\t\t{GROUPS[g]} /* {g} */,")
w(f"\t\t\t\t{G_RESOURCES} /* Resources */,")
w("\t\t\t);")
w("\t\t\tpath = AirChat;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")

# Products group
w(f"\t\t{G_PRODUCTS} /* Products */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{PRODUCT_REF} /* AirChat.app */,")
w("\t\t\t);")
w("\t\t\tname = Products;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")

# Main group
w(f"\t\t{G_MAIN} = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{G_APP} /* AirChat */,")
w(f"\t\t\t\t{G_PRODUCTS} /* Products */,")
w("\t\t\t);")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w("/* End PBXGroup section */")
w()

# PBXNativeTarget
w("/* Begin PBXNativeTarget section */")
w(f"\t\t{TARGET} /* AirChat */ = {{")
w("\t\t\tisa = PBXNativeTarget;")
w("\t\t\tbuildConfigurationList = " + CL_TARGET + " /* Build configuration list for PBXNativeTarget \"AirChat\" */;")
w("\t\t\tbuildPhases = (")
w(f"\t\t\t\t{PHASE_SOURCES} /* Sources */,")
w(f"\t\t\t\t{PHASE_FRAMEWORKS} /* Frameworks */,")
w(f"\t\t\t\t{PHASE_RESOURCES} /* Resources */,")
w("\t\t\t);")
w("\t\t\tbuildRules = (")
w("\t\t\t);")
w("\t\t\tdependencies = (")
w("\t\t\t);")
w("\t\t\tname = AirChat;")
w("\t\t\tproductName = AirChat;")
w(f"\t\t\tproductReference = {PRODUCT_REF} /* AirChat.app */;")
w("\t\t\tproductType = \"com.apple.product-type.application\";")
w("\t\t};")
w("/* End PBXNativeTarget section */")
w()

# PBXProject
w("/* Begin PBXProject section */")
w(f"\t\t{P_PROJECT} /* Project object */ = {{")
w("\t\t\tisa = PBXProject;")
w("\t\t\tattributes = {")
w("\t\t\t\tLastSwiftUpdateCheck = 1500;")
w("\t\t\t\tLastUpgradeCheck = 1500;")
w("\t\t\t\tTargetAttributes = {")
w(f"\t\t\t\t\t{TARGET} = {{")
w("\t\t\t\t\t\tCreatedOnToolsVersion = 1500;")
w("\t\t\t\t\t};")
w("\t\t\t\t};")
w("\t\t\t};")
w(f"\t\t\tbuildConfigurationList = {CL_PROJECT} /* Build configuration list for PBXProject \"AirChat\" */;")
w("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
w("\t\t\tdevelopmentRegion = en;")
w("\t\t\thasScannedForEncodings = 0;")
w("\t\t\tknownRegions = (")
w("\t\t\t\ten,")
w("\t\t\t\tBase,")
w("\t\t\t\tro,")
w("\t\t\t);")
w(f"\t\t\tmainGroup = {G_MAIN};")
w(f"\t\t\tproductRefGroup = {G_PRODUCTS} /* Products */;")
w("\t\t\tprojectDirPath = \"\";")
w("\t\t\tprojectRoot = \"\";")
w("\t\t\ttargets = (")
w(f"\t\t\t\t{TARGET} /* AirChat */,")
w("\t\t\t);")
w("\t\t};")
w("/* End PBXProject section */")
w()

# PBXResourcesBuildPhase
w("/* Begin PBXResourcesBuildPhase section */")
w(f"\t\t{PHASE_RESOURCES} /* Resources */ = {{")
w("\t\t\tisa = PBXResourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
w(f"\t\t\t\t{BUILD_ASSETS} /* Assets.xcassets in Resources */,")
for wf in WEB_FILES:
    w(f"\t\t\t\t{WEB_BUILDS[wf]} /* {wf} in Resources */,")
w(f"\t\t\t\t{BUILD_VARIANT} /* Localizable.strings in Resources */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXResourcesBuildPhase section */")
w()

# PBXSourcesBuildPhase
w("/* Begin PBXSourcesBuildPhase section */")
w(f"\t\t{PHASE_SOURCES} /* Sources */ = {{")
w("\t\t\tisa = PBXSourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
for (g, f) in SOURCES:
    w(f"\t\t\t\t{SRC_BUILD[(g,f)]} /* {f} in Sources */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXSourcesBuildPhase section */")
w()

# XCBuildConfiguration
def common_target_settings():
    return [
        ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
        ("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME", "AccentColor"),
        ("CODE_SIGN_STYLE", "Automatic"),
        ("CURRENT_PROJECT_VERSION", "1"),
        ("DEVELOPMENT_TEAM", ""),
        ("ENABLE_USER_SCRIPT_SANDBOXING", "NO"),
        ("GENERATE_INFOPLIST_FILE", "NO"),
        ("INFOPLIST_FILE", "AirChat/Resources/Info.plist"),
        ("INFOPLIST_KEY_UIApplicationSceneManifest_Generation", "YES"),
        ("INFOPLIST_KEY_UIStatusBarStyle", ""),
        ("IPHONEOS_DEPLOYMENT_TARGET", "17.0"),
        ("LD_RUNPATH_SEARCH_PATHS", "\"$(inherited) @executable_path/Frameworks\""),
        ("MARKETING_VERSION", "1.0"),
        ("PRODUCT_BUNDLE_IDENTIFIER", "com.skidropz.airchat"),
        ("PRODUCT_NAME", "$(TARGET_NAME)"),
        ("SWIFT_EMIT_LOC_STRINGS", "YES"),
        ("SWIFT_VERSION", "5.0"),
        ("TARGETED_DEVICE_FAMILY", "\"1,2\""),
    ]

w("/* Begin XCBuildConfiguration section */")
w(f"\t\t{CFG_PROJ_DEBUG} /* Debug */ = {{")
w("\t\t\tisa = XCBuildConfiguration;")
w("\t\t\tbuildSettings = {")
w("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
w("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
w("\t\t\t\tCOPY_PHASE_STRIP = NO;")
w("\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
w("\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
w("\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
w("\t\t\t\tONLY_ACTIVE_ARCH = YES;")
w("\t\t\t\tSDKROOT = iphoneos;")
w("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
w("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
w("\t\t\t};")
w("\t\t\tname = Debug;")
w("\t\t};")
w(f"\t\t{CFG_PROJ_REL} /* Release */ = {{")
w("\t\t\tisa = XCBuildConfiguration;")
w("\t\t\tbuildSettings = {")
w("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
w("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
w("\t\t\t\tCOPY_PHASE_STRIP = NO;")
w("\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";")
w("\t\t\t\tENABLE_NS_ASSERTIONS = NO;")
w("\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
w("\t\t\t\tSDKROOT = iphoneos;")
w("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
w("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";")
w("\t\t\t\tVALIDATE_PRODUCT = YES;")
w("\t\t\t};")
w("\t\t\tname = Release;")
w("\t\t};")

def emit_target_cfg(cfg_id, name, extra):
    w(f"\t\t{cfg_id} /* {name} */ = {{")
    w("\t\t\tisa = XCBuildConfiguration;")
    w("\t\t\tbuildSettings = {")
    for k, v in common_target_settings():
        w(f"\t\t\t\t{k} = {v};")
    for k, v in extra:
        w(f"\t\t\t\t{k} = {v};")
    w("\t\t\t};")
    w(f"\t\t\tname = {name};")
    w("\t\t};")

emit_target_cfg(CFG_TGT_DEBUG, "Debug", [
    ("CODE_SIGN_IDENTITY", "\"-\""),
    ("ENABLE_PREVIEWS", "YES"),
    ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEBUG"),
    ("SWIFT_OPTIMIZATION_LEVEL", "-Onone"),
])
emit_target_cfg(CFG_TGT_REL, "Release", [
    ("CODE_SIGN_IDENTITY", "\"\""),
    ("ENABLE_PREVIEWS", "YES"),
    ("SWIFT_COMPILATION_MODE", "wholemodule"),
    ("SWIFT_OPTIMIZATION_LEVEL", "-O"),
    ("VALIDATE_PRODUCT", "YES"),
])
w("/* End XCBuildConfiguration section */")
w()

# XCConfigurationList
w("/* Begin XCConfigurationList section */")
w(f"\t\t{CL_PROJECT} /* Build configuration list for PBXProject \"AirChat\" */ = {{")
w("\t\t\tisa = XCConfigurationList;")
w("\t\t\tbuildConfigurations = (")
w(f"\t\t\t\t{CFG_PROJ_DEBUG} /* Debug */,")
w(f"\t\t\t\t{CFG_PROJ_REL} /* Release */,")
w("\t\t\t);")
w("\t\t\tdefaultConfigurationIsVisible = 0;")
w("\t\t\tdefaultConfigurationName = Release;")
w("\t\t};")
w(f"\t\t{CL_TARGET} /* Build configuration list for PBXNativeTarget \"AirChat\" */ = {{")
w("\t\t\tisa = XCConfigurationList;")
w("\t\t\tbuildConfigurations = (")
w(f"\t\t\t\t{CFG_TGT_DEBUG} /* Debug */,")
w(f"\t\t\t\t{CFG_TGT_REL} /* Release */,")
w("\t\t\t);")
w("\t\t\tdefaultConfigurationIsVisible = 0;")
w("\t\t\tdefaultConfigurationName = Release;")
w("\t\t};")
w("/* End XCConfigurationList section */")
w()

w("\t};")
w(f"\trootObject = {P_PROJECT} /* Project object */;")
w("}")

out_dir = os.path.join(HERE, "AirChat.xcodeproj")
os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, "project.pbxproj"), "w") as fp:
    fp.write("\n".join(L) + "\n")

print("Wrote", os.path.join(out_dir, "project.pbxproj"))
print("Source files:", len(SOURCES))
