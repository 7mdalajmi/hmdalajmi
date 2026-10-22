#!/usr/bin/env python3
"""Write Sakka.xcodeproj from scratch: the app target and its unit tests, on synchronized folders.

Usage (from the repository root):  python3 tools/make_project.py

- Sakka/ is the app's synchronized folder: every Swift file, the asset catalog, the fonts and the privacy manifest
  in it belong to the app, with nothing listed by hand. SakkaTests/ is the test target's.
- Version and build live in Config/Sakka.xcconfig, outside the .xcodeproj (main reference, «تطبيق جديد»), so the
  targets must never set MARKETING_VERSION or CURRENT_PROJECT_VERSION themselves.
- Config/Info.plist only adds what build settings cannot: the launch colour and one window.
- Object ids are fixed (from their names), and each section is sorted by id the way Xcode 27 writes it, so running
  this again gives the same file byte for byte and Xcode does not rewrite it on open.
- It also writes the shared scheme Sakka (tests not in parallel) and the workspace file.
Check the result with tools/check_pbxproj.py.
"""
import hashlib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ = os.path.join(ROOT, "Sakka.xcodeproj")

APP = "Sakka"
TESTS = "SakkaTests"
BUNDLE_ID = "Hmd.Sakka"
DISPLAY_NAME = "صكة"
DEPLOYMENT = "26.0"


def oid(name):
    return hashlib.md5(("sakka:" + name).encode()).hexdigest()[:24].upper()


def q(value):
    """Quote a pbxproj string the way Xcode does."""
    s = str(value)
    if s and re.fullmatch(r"[A-Za-z0-9_$./]+", s):
        return s
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return '"' + s + '"'


def settings_block(d, indent):
    pad = "\t" * indent
    lines = []
    for k in sorted(d):
        v = d[k]
        if isinstance(v, list):
            lines.append(f"{pad}{q(k)} = (")
            for item in v:
                lines.append(f"{pad}\t{q(item)},")
            lines.append(f"{pad});")
        else:
            lines.append(f"{pad}{q(k)} = {q(v)};")
    return "\n".join(lines)


IDS = {n: oid(n) for n in [
    "project", "mainGroup", "productsGroup", "configGroup", "appSync", "testSync",
    "appProduct", "testProduct", "xcconfig", "infoPlist",
    "appTarget", "testTarget", "appSources", "appFrameworks", "appResources",
    "testSources", "testFrameworks", "testResources", "proxy", "dependency",
    "projectConfigs", "projectDebug", "projectRelease",
    "appConfigs", "appDebug", "appRelease", "testConfigs", "testDebug", "testRelease",
]}

PROJECT_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
    "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES",
    "CLANG_WARN_COMMA": "YES",
    "CLANG_WARN_CONSTANT_CONVERSION": "YES",
    "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
    "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_EMPTY_BODY": "YES",
    "CLANG_WARN_ENUM_CONVERSION": "YES",
    "CLANG_WARN_INFINITE_RECURSION": "YES",
    "CLANG_WARN_INT_CONVERSION": "YES",
    "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
    "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
    "CLANG_WARN_STRICT_PROTOTYPES": "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT,
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "iphoneos",
    "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
}

PROJECT_DEBUG = dict(PROJECT_COMMON, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})

PROJECT_RELEASE = dict(PROJECT_COMMON, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
})

SWIFT = {
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
    "SWIFT_VERSION": "6.0",
}

APP_SETTINGS = dict(SWIFT, **{
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic",
    # Hamad's team, as he set it in Signing & Capabilities on the MacBook Air (build 3, 8 Oct 2026).
    "DEVELOPMENT_TEAM": "Y9947WYZ9L",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Config/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": DISPLAY_NAME,
    "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.card-games",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "TARGETED_DEVICE_FAMILY": "1,2",
})

TEST_SETTINGS = dict(SWIFT, **{
    "BUNDLE_LOADER": "$(TEST_HOST)",
    "CODE_SIGN_STYLE": "Automatic",
    "GENERATE_INFOPLIST_FILE": "YES",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + "Tests",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO",
    "TARGETED_DEVICE_FAMILY": "1,2",
    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Sakka.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Sakka",
})


def build_objects():
    I = IDS
    objs = {}  # isa -> list of (id, comment, body lines)

    def add(isa, ident, comment, body):
        objs.setdefault(isa, []).append((ident, comment, body))

    add("PBXContainerItemProxy", I["proxy"], "PBXContainerItemProxy", [
        "isa = PBXContainerItemProxy;",
        f"containerPortal = {I['project']} /* Project object */;",
        "proxyType = 1;",
        f"remoteGlobalIDString = {I['appTarget']};",
        f"remoteInfo = {APP};",
    ])
    add("PBXFileReference", I["appProduct"], "Sakka.app", None)
    add("PBXFileReference", I["testProduct"], "SakkaTests.xctest", None)
    add("PBXFileReference", I["xcconfig"], "Sakka.xcconfig", None)
    add("PBXFileReference", I["infoPlist"], "Info.plist", None)
    add("PBXFileSystemSynchronizedRootGroup", I["appSync"], APP, [
        "isa = PBXFileSystemSynchronizedRootGroup;", f"path = {APP};", 'sourceTree = "<group>";'])
    add("PBXFileSystemSynchronizedRootGroup", I["testSync"], TESTS, [
        "isa = PBXFileSystemSynchronizedRootGroup;", f"path = {TESTS};", 'sourceTree = "<group>";'])
    for key in ("appFrameworks", "testFrameworks"):
        add("PBXFrameworksBuildPhase", I[key], "Frameworks", [
            "isa = PBXFrameworksBuildPhase;", "buildActionMask = 2147483647;", "files = (", ");",
            "runOnlyForDeploymentPostprocessing = 0;"])
    add("PBXGroup", I["mainGroup"], None, [
        "isa = PBXGroup;", "children = (",
        f"\t{I['configGroup']} /* Config */,",
        f"\t{I['appSync']} /* {APP} */,",
        f"\t{I['testSync']} /* {TESTS} */,",
        f"\t{I['productsGroup']} /* Products */,",
        ");", 'sourceTree = "<group>";'])
    add("PBXGroup", I["configGroup"], "Config", [
        "isa = PBXGroup;", "children = (",
        f"\t{I['infoPlist']} /* Info.plist */,",
        f"\t{I['xcconfig']} /* Sakka.xcconfig */,",
        ");", "path = Config;", 'sourceTree = "<group>";'])
    add("PBXGroup", I["productsGroup"], "Products", [
        "isa = PBXGroup;", "children = (",
        f"\t{I['appProduct']} /* Sakka.app */,",
        f"\t{I['testProduct']} /* SakkaTests.xctest */,",
        ");", "name = Products;", 'sourceTree = "<group>";'])
    add("PBXNativeTarget", I["appTarget"], APP, [
        "isa = PBXNativeTarget;",
        f'buildConfigurationList = {I["appConfigs"]} /* Build configuration list for PBXNativeTarget "{APP}" */;',
        "buildPhases = (",
        f"\t{I['appSources']} /* Sources */,", f"\t{I['appFrameworks']} /* Frameworks */,", f"\t{I['appResources']} /* Resources */,",
        ");", "buildRules = (", ");", "dependencies = (", ");",
        "fileSystemSynchronizedGroups = (", f"\t{I['appSync']} /* {APP} */,", ");",
        f"name = {APP};", "packageProductDependencies = (", ");", f"productName = {APP};",
        f"productReference = {I['appProduct']} /* Sakka.app */;",
        'productType = "com.apple.product-type.application";'])
    add("PBXNativeTarget", I["testTarget"], TESTS, [
        "isa = PBXNativeTarget;",
        f'buildConfigurationList = {I["testConfigs"]} /* Build configuration list for PBXNativeTarget "{TESTS}" */;',
        "buildPhases = (",
        f"\t{I['testSources']} /* Sources */,", f"\t{I['testFrameworks']} /* Frameworks */,", f"\t{I['testResources']} /* Resources */,",
        ");", "buildRules = (", ");", "dependencies = (", f"\t{I['dependency']} /* PBXTargetDependency */,", ");",
        "fileSystemSynchronizedGroups = (", f"\t{I['testSync']} /* {TESTS} */,", ");",
        f"name = {TESTS};", "packageProductDependencies = (", ");", f"productName = {TESTS};",
        f"productReference = {I['testProduct']} /* SakkaTests.xctest */;",
        'productType = "com.apple.product-type.bundle.unit-test";'])
    add("PBXProject", I["project"], "Project object", [
        "isa = PBXProject;", "attributes = {",
        "\tBuildIndependentTargetsInParallel = 1;", "\tLastSwiftUpdateCheck = 2700;", "\tLastUpgradeCheck = 2700;",
        "\tTargetAttributes = {",
        f"\t\t{I['appTarget']} = {{", "\t\t\tCreatedOnToolsVersion = 27.0;", "\t\t};",
        f"\t\t{I['testTarget']} = {{", "\t\t\tCreatedOnToolsVersion = 27.0;", f"\t\t\tTestTargetID = {I['appTarget']};", "\t\t};",
        "\t};", "};",
        f'buildConfigurationList = {I["projectConfigs"]} /* Build configuration list for PBXProject "{APP}" */;',
        "developmentRegion = ar;", "hasScannedForEncodings = 0;", "knownRegions = (", "\tar,", "\tBase,", ");",
        f"mainGroup = {I['mainGroup']};", "minimizedProjectReferenceProxies = 1;", "preferredProjectObjectVersion = 77;",
        f"productRefGroup = {I['productsGroup']} /* Products */;", 'projectDirPath = "";', 'projectRoot = "";',
        "targets = (", f"\t{I['appTarget']} /* {APP} */,", f"\t{I['testTarget']} /* {TESTS} */,", ");"])
    for key in ("appResources", "testResources"):
        add("PBXResourcesBuildPhase", I[key], "Resources", [
            "isa = PBXResourcesBuildPhase;", "buildActionMask = 2147483647;", "files = (", ");",
            "runOnlyForDeploymentPostprocessing = 0;"])
    for key in ("appSources", "testSources"):
        add("PBXSourcesBuildPhase", I[key], "Sources", [
            "isa = PBXSourcesBuildPhase;", "buildActionMask = 2147483647;", "files = (", ");",
            "runOnlyForDeploymentPostprocessing = 0;"])
    add("PBXTargetDependency", I["dependency"], "PBXTargetDependency", [
        "isa = PBXTargetDependency;", f"target = {I['appTarget']} /* {APP} */;",
        f"targetProxy = {I['proxy']} /* PBXContainerItemProxy */;"])

    def config(key, name, settings, base=True):
        body = ["isa = XCBuildConfiguration;"]
        if base:
            body.append(f"baseConfigurationReference = {I['xcconfig']} /* Sakka.xcconfig */;")
        body.append("buildSettings = {")
        body.extend("\t" + line for line in settings_block(settings, 0).split("\n"))
        body.append("};")
        body.append(f"name = {name};")
        add("XCBuildConfiguration", I[key], name, body)

    config("projectDebug", "Debug", PROJECT_DEBUG, base=False)
    config("projectRelease", "Release", PROJECT_RELEASE, base=False)
    config("appDebug", "Debug", APP_SETTINGS)
    config("appRelease", "Release", APP_SETTINGS)
    config("testDebug", "Debug", dict(TEST_SETTINGS, IPHONEOS_DEPLOYMENT_TARGET=DEPLOYMENT))
    config("testRelease", "Release", dict(TEST_SETTINGS, IPHONEOS_DEPLOYMENT_TARGET=DEPLOYMENT))

    def config_list(key, owner, debug, release):
        add("XCConfigurationList", I[key], f"Build configuration list for {owner}", [
            "isa = XCConfigurationList;", "buildConfigurations = (",
            f"\t{I[debug]} /* Debug */,", f"\t{I[release]} /* Release */,", ");",
            "defaultConfigurationIsVisible = 0;", "defaultConfigurationName = Release;"])

    config_list("projectConfigs", f'PBXProject "{APP}"', "projectDebug", "projectRelease")
    config_list("appConfigs", f'PBXNativeTarget "{APP}"', "appDebug", "appRelease")
    config_list("testConfigs", f'PBXNativeTarget "{TESTS}"', "testDebug", "testRelease")
    return objs


FILE_REFS = {
    "appProduct": "{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Sakka.app; sourceTree = BUILT_PRODUCTS_DIR; };",
    "testProduct": "{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = SakkaTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };",
    "xcconfig": '{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Sakka.xcconfig; sourceTree = "<group>"; };',
    "infoPlist": '{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };',
}


def render(objs):
    out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 77;", "\tobjects = {", ""]
    ref_key = {IDS[k]: k for k in FILE_REFS}
    for isa in sorted(objs):
        out.append(f"/* Begin {isa} section */")
        for ident, comment, body in sorted(objs[isa], key=lambda o: o[0]):
            head = f"\t\t{ident}" + (f" /* {comment} */" if comment else "")
            if body is None:
                out.append(f"{head} = {FILE_REFS[ref_key[ident]]}")
                continue
            out.append(f"{head} = {{")
            for line in body:
                out.append("\t\t\t" + line)
            out.append("\t\t};")
        out.append(f"/* End {isa} section */")
        out.append("")
    # Xcode 27 puts no blank line after the last section, and removed it on the first open (build 3 on the Mac).
    out.pop()
    out.append("\t};")
    out.append(f"\trootObject = {IDS['project']} /* Project object */;")
    out.append("}")
    return "\n".join(out) + "\n"


def buildable(target_key, name, product, column):
    """A BuildableReference whose tag starts at `column`, nested the way Xcode writes it: attributes three
    spaces further in, the closing tag at the tag's own column. Xcode 27 rewrites a scheme nested otherwise
    on the first Run (دُرزة, round 3), which would change the file and leave the git tree dirty."""
    inner = " " * (column + 3)
    return (f"<BuildableReference\n"
            f'{inner}BuildableIdentifier = "primary"\n'
            f'{inner}BlueprintIdentifier = "{IDS[target_key]}"\n'
            f'{inner}BuildableName = "{product}"\n'
            f'{inner}BlueprintName = "{name}"\n'
            f'{inner}ReferencedContainer = "container:Sakka.xcodeproj">\n'
            f"{' ' * column}</BuildableReference>")


def scheme():
    app_ref = buildable("appTarget", APP, "Sakka.app", 12)
    test_ref = buildable("testTarget", TESTS, "SakkaTests.xctest", 12)
    run_ref = buildable("appTarget", APP, "Sakka.app", 9)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2700"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {app_ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "NO">
            {test_ref}
         </TestableReference>
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
         {run_ref}
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
         {run_ref}
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


WORKSPACE = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def main():
    for folder in (APP, TESTS, "Config"):
        if not os.path.isdir(os.path.join(ROOT, folder)):
            sys.exit(f"missing folder {folder}/")
    write(os.path.join(PROJ, "project.pbxproj"), render(build_objects()))
    write(os.path.join(PROJ, "project.xcworkspace", "contents.xcworkspacedata"), WORKSPACE)
    write(os.path.join(PROJ, "xcshareddata", "xcschemes", "Sakka.xcscheme"), scheme())
    print("wrote", os.path.relpath(PROJ, ROOT))


if __name__ == "__main__":
    main()
