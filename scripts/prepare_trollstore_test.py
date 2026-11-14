#!/usr/bin/env python3
"""仅使用 Python 标准库；配置修改只发生在云端临时 checkout。"""
import base64
import binascii
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
OLD = "com.zhangruilin.yuedureader"
PROJECT = ROOT / "Yuedu-Reader.xcodeproj/project.pbxproj"
ENTITLEMENTS = {
    "": "Resources/Yuedu-Reader.entitlements",
    ".shareextension": "ShareExtension/Yuedu-Reader-ShareExtension.entitlements",
    ".widget": "Widget/Yuedu-Reader-Widget.entitlements",
}


def need(condition, message):
    if not condition:
        raise ValueError(message)


def load(path):
    with Path(path).open("rb") as stream:
        return plistlib.load(stream)


def save(path, value):
    Path(path).write_bytes(plistlib.dumps(value, sort_keys=False))


def private_dir():
    return Path(os.environ["TROLLSTORE_PRIVATE_DIR"])


def cloud_only():
    need(sys.platform == "darwin" and os.environ.get("GITHUB_ACTIONS") == "true",
         "配置修改及打包仅允许在 GitHub Actions macOS 临时 checkout 中执行。")


def identity():
    bid = os.environ.get("TEST_BUNDLE_ID", "com.local.readerpreview")
    name = os.environ.get("TEST_DISPLAY_NAME", "书架试用版")
    need(re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+){2,}", bid)
         and len(bid) <= 150 and not bid.lower().startswith(OLD.lower()),
         "新的 Bundle ID 格式不正确，或仍在原应用标识命名空间下。")
    need(1 <= len(name) <= 40 and not any(ord(c) < 32 or c in '\\"' for c in name),
         "显示名称需为 1–40 个字符，不能含控制字符、引号或反斜杠。")
    return bid, name


def firebase(bid):
    # 自用版不接入账号、Crashlytics、Firestore 或云同步；仍提供合法 plist，
    # 让 Xcode 的 Firebase 资源阶段能够完成，所有开关均关闭，不使用官方配置。
    data = {
        "API_KEY": "LOCAL_ONLY_DISABLED",
        "GCM_SENDER_ID": "000000000000",
        "PLIST_VERSION": "1",
        "BUNDLE_ID": bid,
        "PROJECT_ID": "local-reader-preview",
        "STORAGE_BUCKET": "local-reader-preview.appspot.com",
        "IS_ADS_ENABLED": False,
        "IS_ANALYTICS_ENABLED": False,
        "IS_APPINVITE_ENABLED": False,
        "IS_GCM_ENABLED": False,
        "IS_SIGNIN_ENABLED": False,
        "GOOGLE_APP_ID": "1:000000000000:ios:0000000000000000",
    }
    (private_dir() / "redactions.json").write_text(json.dumps([data["API_KEY"]]), encoding="utf-8")
    return data


def make_icon(directory):
    # 原创几何书籍图标：不使用第三方图片，不含透明通道。
    directory.mkdir(parents=True, exist_ok=True)
    size = 1024
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            color = (30, 65, 78)
            if 210 <= x <= 494 and 240 <= y <= 780:
                color = (246, 236, 209)
            if 530 <= x <= 814 and 240 <= y <= 780:
                color = (246, 236, 209)
            if ((260 <= x <= 444) or (580 <= x <= 764)) and any(a <= y <= a + 12 for a in (350, 440, 530, 620)):
                color = (107, 146, 151)
            rows.extend(color)
    def chunk(kind, value):
        return struct.pack(">I", len(value)) + kind + value + struct.pack(">I", zlib.crc32(kind + value) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")
    (directory / "Preview.png").write_bytes(png)
    (directory / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "Preview.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1}}, indent=2), encoding="utf-8")


def prepare():
    cloud_only()
    bid, name = identity()
    config = firebase(bid)
    original = PROJECT.read_text(encoding="utf-8")
    changed, count = re.subn(r"(PRODUCT_BUNDLE_IDENTIFIER\s*=\s*)" + re.escape(OLD) + r"([A-Za-z0-9.-]*)(;)",
                            lambda m: m[1] + bid + m[2] + m[3], original)
    need(count == 10, "项目 Bundle ID 配置数量已变化；请人工复核后调整准备脚本。")
    changed, names = re.subn(r'INFOPLIST_KEY_CFBundleDisplayName\s*=\s*"[^"]*";',
                            lambda _: 'INFOPLIST_KEY_CFBundleDisplayName = "' + name + '";', changed)
    need(names == 2, "主应用显示名称配置已变化。")
    changed, icons = re.subn(r"ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
                            "ASSETCATALOG_COMPILER_APPICON_NAME = PreviewIcon;", changed)
    need(icons == 2, "主应用图标配置已变化。")
    need(re.findall(r"IPHONEOS_DEPLOYMENT_TARGET\s*=\s*[^;]+", original)
         == re.findall(r"IPHONEOS_DEPLOYMENT_TARGET\s*=\s*[^;]+", changed), "部署目标意外变化。")
    PROJECT.write_text(changed, encoding="utf-8")
    # 仅替换完整的 App Group / iCloud 容器字面值，不改授权或付费分支。
    paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
    for relative in paths:
        path = ROOT / relative
        if path.suffix not in (".swift", ".entitlements"):
            continue
        text = path.read_text(encoding="utf-8")
        updated = text.replace("group." + OLD, "group." + bid).replace("iCloud." + OLD, "iCloud." + bid)
        if updated != text:
            path.write_text(updated, encoding="utf-8")
    info = load(ROOT / "Info.plist")
    # 不注册原版 yuedu/legado scheme，也不残留官方 Google 回调。
    info["CFBundleURLTypes"] = []
    info.pop("GIDClientID", None)
    info.pop("GIDServerClientID", None)
    if config.get("CLIENT_ID"):
        info["GIDClientID"] = config["CLIENT_ID"]
        info["CFBundleURLTypes"] = [{"CFBundleTypeRole": "Editor", "CFBundleURLSchemes": [config["REVERSED_CLIENT_ID"]]}]
    info["CFBundleDisplayName"] = name
    info["ReaderStandalone"] = True
    info["FirebaseDataCollectionDefaultEnabled"] = False
    info["FirebaseCrashlyticsCollectionEnabled"] = False
    info["FIREBASE_ANALYTICS_COLLECTION_ENABLED"] = False
    info["FirebaseMessagingAutoInitEnabled"] = False
    info["GatewayBaseURL"] = ""
    save(ROOT / "Info.plist", info)
    for relative, suffix in (("ShareExtension/Info.plist", " · 分享"), ("Widget/Info.plist", " · 小组件")):
        info = load(ROOT / relative)
        info["CFBundleDisplayName"] = name + suffix
        save(ROOT / relative, info)
    for relative in paths:
        if not relative.endswith("/InfoPlist.strings"):
            continue
        path = ROOT / relative
        text = path.read_text(encoding="utf-8")
        display = name + (" · 分享" if relative.startswith("ShareExtension/") else "")
        text = re.sub(r'("?CFBundleDisplayName"?\s*=\s*)"(?:[^"\\]|\\.)*"',
                      lambda m: m[1] + '"' + display + '"', text)
        path.write_text(text, encoding="utf-8")
    make_icon(ROOT / "Resources/Assets.xcassets/PreviewIcon.appiconset")
    save(ROOT / "GoogleService-Info.plist", config)
    (ROOT / "GoogleService-Info.plist").chmod(0o600)
    print("配置准备完成：新 Bundle ID、共享组、桌面名称、独立图标及 Google 回调已同步；未修改部署目标或付费逻辑。")


def select_xcode():
    candidates = list(Path("/Applications").glob("Xcode*.app/Contents/Developer"))
    selected = []
    for path in candidates:
        result = subprocess.run([str(path / "usr/bin/xcodebuild"), "-version"], capture_output=True, text=True)
        match = re.search(r"Xcode (\d+)\.(\d+)(?:\.(\d+))?", result.stdout)
        if result.returncode == 0 and match:
            version = tuple(int(x or 0) for x in match.groups())
            if version >= (27, 1, 0):
                selected.append((version, str(path)))
    need(selected, "当前 runner 没有 Xcode 27.1 或更新版本。xcode-27 是可变镜像标签；请等待镜像更新或选择满足要求的普通托管 runner，不能降低工程工具链要求。")
    print(max(selected)[1])


def settings(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    need(isinstance(data, list), "showBuildSettings JSON 格式无效。")
    return [item["buildSettings"] for item in data if isinstance(item, dict) and "buildSettings" in item]


def locate(source, destination):
    bid, _ = identity()
    matches = [s for s in settings(source) if s.get("PRODUCT_BUNDLE_IDENTIFIER") == bid and s.get("WRAPPER_EXTENSION") == "app"]
    need(len(matches) == 1, "构建设置中无法唯一定位新主应用。")
    item = matches[0]
    need(item.get("BUILT_PRODUCTS_DIR") and item.get("WRAPPER_NAME"), "构建设置缺少 BUILT_PRODUCTS_DIR 或 WRAPPER_NAME。")
    need(Path(item["WRAPPER_NAME"]).name == item["WRAPPER_NAME"] and item["WRAPPER_NAME"].endswith(".app"), "应用包装目录无效。")
    app = Path(item["BUILT_PRODUCTS_DIR"]) / item["WRAPPER_NAME"]
    need(app.resolve().is_relative_to(private_dir().resolve()), "应用输出路径不在私有构建目录中。")
    Path(destination).write_text(str(app), encoding="utf-8")
    print("已从 showBuildSettings JSON 定位应用路径；未以预先完整编译获取路径。")


def version(value):
    need(isinstance(value, str) and re.fullmatch(r"\d+(?:\.\d+){0,2}", value), "最低 iOS 版本字段无效。")
    parts = [int(x) for x in value.split(".")]
    return tuple((parts + [0, 0])[:3])


def run(*args):
    return subprocess.check_output([str(x) for x in args], stderr=subprocess.STDOUT, text=True)


def check_binary(path):
    description = run("/usr/bin/file", "-b", path)
    need("Mach-O" in description, "目标可执行文件不是 Mach-O：" + path.name)
    arches = run("xcrun", "lipo", "-archs", path).split()
    need("arm64" in arches and set(arches) <= {"arm64", "arm64e"}, "产物缺少真机 arm64 或混入模拟器架构：" + path.name)
    commands = run("xcrun", "otool", "-l", path)
    minimums = []
    for block in re.split(r"Load command \d+", commands):
        if re.search(r"cmd LC_BUILD_VERSION\b", block):
            platform = re.search(r"\bplatform (\S+)", block)
            minimum = re.search(r"\bminos ([0-9.]+)", block)
            need(platform and platform[1].upper() in ("2", "IOS") and minimum,
                 "Mach-O 不是 iOS 真机平台，或缺少 minos：" + path.name)
            minimums.append(minimum[1])
        elif re.search(r"cmd LC_VERSION_MIN_IPHONEOS\b", block):
            minimum = re.search(r"\bversion ([0-9.]+)", block)
            need(minimum, "Mach-O 缺少最低 iOS 版本：" + path.name)
            minimums.append(minimum[1])
    need(minimums and all(version(v) <= (17, 0, 0) for v in minimums),
         "Mach-O 最低系统版本高于 iOS 17.0 或无法确认：" + path.name + "，实际版本：" + ", ".join(minimums))
    print("真机二进制复核通过：" + path.name + "；最低 iOS " + ", ".join(minimums))


def package(source, path_file, output):
    cloud_only()
    bid, _ = identity()
    app = Path(Path(path_file).read_text(encoding="utf-8"))
    need(app.is_dir() and app.suffix == ".app", "完整编译没有生成真实 .app，停止打包。")
    need(app.resolve().is_relative_to(private_dir().resolve()), "应用路径超出私有构建目录。")
    # 同时检查设置未被另一个 configuration 或目标污染。
    actual = [s for s in settings(source) if s.get("PRODUCT_BUNDLE_IDENTIFIER") == bid]
    need(len(actual) == 1 and actual[0].get("CONFIGURATION") == "Debug", "打包配置不是预期的 Debug。")
    stage = private_dir() / "打包"
    payload = stage / "Payload"
    payload.mkdir(parents=True)
    staged = payload / app.name
    run("/usr/bin/ditto", "--norsrc", app, staged)
    from ipa_compatibility import clean_unused_stubs, validate, normalize_permissions
    removed = clean_unused_stubs(staged)
    print("已移除无代码且未被引用的 Xcode 占位框架：" + (", ".join(removed) or "无"))
    normalize_permissions(staged)
    print("严格验证真机二进制数量：" + str(validate(staged)))
    bundles = [staged] + sorted(staged.rglob("*.appex"))
    found = set()
    for bundle in bundles:
        info = load(bundle / "Info.plist")
        identifier = info.get("CFBundleIdentifier")
        suffix = next((s for s in ENTITLEMENTS if identifier == bid + s), None)
        need(suffix is not None and suffix not in found, "发现未识别或重复的应用/扩展 Bundle ID。")
        found.add(suffix)
        need(info.get("CFBundlePackageType") == ("APPL" if suffix == "" else "XPC!"),
             "应用或扩展的注册包类型缺失：" + bundle.name)
        need(info.get("CFBundleInfoDictionaryVersion") == "6.0", "应用注册信息版本缺失：" + bundle.name)
        need(version(info.get("MinimumOSVersion")) == (17, 0, 0), "应用或扩展的最低 iOS 版本不再是 17.0。")
        exe = info.get("CFBundleExecutable")
        need(isinstance(exe, str) and Path(exe).name == exe and (bundle / exe).is_file(), "应用或扩展缺少真实可执行文件。")
        check_binary(bundle / exe)
    need(found == set(ENTITLEMENTS), "主应用、分享扩展或 Widget 缺失。")
    config = load(staged / "GoogleService-Info.plist")
    need(config.get("BUNDLE_ID") == bid, "产物内 Firebase BUNDLE_ID 不一致。")
    info = load(staged / "Info.plist")
    schemes = [s for item in info.get("CFBundleURLTypes", []) for s in item.get("CFBundleURLSchemes", [])]
    expected = [config["REVERSED_CLIENT_ID"]] if config.get("CLIENT_ID") else []
    need(schemes == expected and info.get("GIDClientID") == config.get("CLIENT_ID"), "产物 URL 回调与新 Firebase 配置不一致。")
    # 复核所有嵌套 Mach-O，不只检查主程序。
    magic = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}
    for path in staged.rglob("*"):
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as stream:
                header = stream.read(4)
            if header in magic:
                check_binary(path)
    nested = list(staged.rglob("*.framework")) + list(staged.rglob("*.dylib"))
    for path in sorted(nested, key=lambda p: len(p.parts), reverse=True):
        if not path.is_symlink():
            run("/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", path)
            run("/usr/bin/codesign", "--verify", "--strict", path)
    for bundle in sorted(bundles, key=lambda p: len(p.parts), reverse=True):
        identifier = load(bundle / "Info.plist")["CFBundleIdentifier"]
        suffix = identifier[len(bid):]
        ent = load(ROOT / ENTITLEMENTS[suffix])
        need(ent.get("com.apple.security.application-groups") == ["group." + bid], "签名权限的 App Group 不一致。")
        # 自用版停用账号、Apple 登录、推送及 CloudKit，只保留扩展共享组。
        if load(staged / "Info.plist").get("ReaderStandalone"):
            ent = {"com.apple.security.application-groups": ["group." + bid]}
        entfile = private_dir() / (bundle.name + ".entitlements")
        save(entfile, ent)
        run("/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", "--generate-entitlement-der", "--entitlements", entfile, bundle)
        run("/usr/bin/codesign", "--verify", "--strict", bundle)
    normalize_permissions(staged)
    payload.chmod(0o755)
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", staged)
    temporary = private_dir() / "已复核.ipa"
    run("/usr/bin/ditto", "-c", "-k", "--norsrc", "--keepParent", payload, temporary)
    import zipfile
    with zipfile.ZipFile(temporary) as archive:
        need(archive.testzip() is None, "IPA ZIP 完整性验证失败。")
        need(f"Payload/{app.name}/Info.plist" in archive.namelist(), "IPA 缺少 Payload 应用目录。")
    shutil.copyfile(temporary, output)
    print("IPA 已由真实编译产物生成并完成 ad-hoc 签名复核；不代表已经真机安装或获得 Apple 云服务授权。")


def redact(source, destination):
    text = Path(source).read_text(encoding="utf-8", errors="replace")
    hidden_file = private_dir() / "redactions.json"
    hidden = json.loads(hidden_file.read_text(encoding="utf-8")) if hidden_file.exists() else []
    encoded = os.environ.get("GOOGLE_SERVICE_INFO_BASE64", "")
    if encoded:
        hidden += [encoded, re.sub(r"\s+", "", encoded)]
    for value in sorted(set(hidden), key=len, reverse=True):
        if value:
            text = text.replace(value, "[已隐藏 Firebase 配置值]")
    # 防御工具意外输出完整 plist 或常见 API Key。
    text = re.sub(r"<\?xml[\s\S]*?</plist>", "[已隐藏 plist 正文]", text)
    text = re.sub(r"<plist\b[\s\S]*?</plist>", "[已隐藏 plist 正文]", text)
    text = re.sub(r"AIza[A-Za-z0-9_-]{20,}", "[已隐藏 API_KEY]", text)
    Path(destination).write_text(text, encoding="utf-8")


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "prepare" and len(sys.argv) == 2:
        prepare()
    elif command == "select-xcode" and len(sys.argv) == 2:
        select_xcode()
    elif command == "locate" and len(sys.argv) == 4:
        locate(*sys.argv[2:])
    elif command == "package" and len(sys.argv) == 5:
        package(*sys.argv[2:])
    elif command == "redact" and len(sys.argv) == 4:
        redact(*sys.argv[2:])
    else:
        raise ValueError("请通过 scripts/build_trollstore_test.sh 执行云端构建；本地仅做语法与静态检查。")


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print("错误：" + str(error), file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError:
        # 命令输出可能含 plist / 路径配置，禁止直接回显异常对象。
        print("错误：Apple 工具命令失败，已停止打包；不会交付未复核 IPA。", file=sys.stderr)
        sys.exit(1)
    except Exception:
        print("错误：配置读取或文件处理失败，已停止；为保护配置未输出异常正文。", file=sys.stderr)
        sys.exit(1)
