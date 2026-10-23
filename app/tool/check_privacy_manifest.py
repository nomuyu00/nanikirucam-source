#!/usr/bin/env python3
"""ios/Runner/PrivacyInfo.xcprivacy を検査する（macOS の plutil / Xcode が無い環境用）。

    py -3.12 app/tool/check_privacy_manifest.py

確かめること:
  1. plist として読める。必須キー（NSPrivacyTracking / NSPrivacyTrackingDomains /
     NSPrivacyCollectedDataTypes / NSPrivacyAccessedAPITypes）がある。
  2. 値が Apple の許可リストにある（Xcode は独自の値だとプライバシー レポートを正しく作れない）。
     NSPrivacyTracking が true なら、ドメインの欄の型が配列であること（空でも可。理由は privacy_labels.md 2.3）。
  3. project.pbxproj の Runner の「Resources」に登録されている（入っていないとアプリに同梱されない）。
  4. docs/store/privacy_labels.md 2.2 の表（App Store の申告）と、収集するデータの種類・ユーザにリンク・追跡・目的が一致する。
終了コードは問題があれば 1。
"""
from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
MANIFEST = APP / "ios" / "Runner" / "PrivacyInfo.xcprivacy"
PBXPROJ = APP / "ios" / "Runner.xcodeproj" / "project.pbxproj"
LABELS_DOC = APP.parent / "docs" / "store" / "privacy_labels.md"

DATA_TYPES = {
    "Name", "EmailAddress", "PhoneNumber", "PhysicalAddress", "OtherUserContactInfo", "Health", "Fitness",
    "PaymentInfo", "CreditInfo", "OtherFinancialInfo", "PreciseLocation", "CoarseLocation", "SensitiveInfo",
    "Contacts", "EmailsOrTextMessages", "PhotosOrVideos", "AudioData", "GameplayContent", "CustomerSupport",
    "OtherUserContent", "BrowsingHistory", "SearchHistory", "UserID", "DeviceID", "PurchaseHistory",
    "ProductInteraction", "AdvertisingData", "OtherUsageData", "CrashData", "PerformanceData",
    "OtherDiagnosticData", "EnvironmentScanning", "Hands", "Head", "OtherDataTypes",
}
PURPOSES = {"ThirdPartyAdvertising", "DeveloperAdvertising", "Analytics", "ProductPersonalization",
            "AppFunctionality", "Other"}
API_REASONS = {
    "FileTimestamp": {"DDA9.1", "C617.1", "3B52.1", "0A2A.1"},
    "SystemBootTime": {"35F9.1", "8FFB.1", "3D61.1"},
    "DiskSpace": {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
    "ActiveKeyboards": {"3EC4.1", "54BD.1"},
    "UserDefaults": {"CA92.1", "1C8F.1", "C56D.1", "AC6B.1"},
}
# privacy_labels.md 2.2 の「データタイプ」列の末尾の名前 → マニフェストの値
LABEL_TO_TYPE = {
    "ユーザ ID": "UserID", "デバイス ID": "DeviceID", "購入履歴": "PurchaseHistory",
    "その他のユーザコンテンツ": "OtherUserContent", "製品の操作": "ProductInteraction",
    "広告データ": "AdvertisingData", "おおよその位置情報": "CoarseLocation",
    "クラッシュデータ": "CrashData", "パフォーマンスデータ": "PerformanceData",
}
LABEL_TO_PURPOSE = {
    "サードパーティ広告": "ThirdPartyAdvertising", "分析": "Analytics", "App の機能": "AppFunctionality",
    "デベロッパの広告": "DeveloperAdvertising", "製品のパーソナライズ": "ProductPersonalization",
}


def labels_table() -> dict[str, dict]:
    """privacy_labels.md 2.2 の表を {マニフェストの型: {linked, tracking, purposes}} にする。"""
    text = LABELS_DOC.read_text(encoding="utf-8")
    section = text.split("### 2.2", 1)[1].split("### 2.3", 1)[0]
    rows: dict[str, dict] = {}
    for line in section.splitlines():
        if not line.startswith("|") or line.startswith("| ---") or line.startswith("| データタイプ"):
            continue
        cols = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cols) < 5:
            continue
        name = re.sub(r"[*`]", "", cols[0]).split(">")[-1].strip()
        if name not in LABEL_TO_TYPE:
            raise SystemExit(f"privacy_labels.md 2.2 の未知のデータタイプ: {name!r}（LABEL_TO_TYPE に足す）")
        purposes = set()
        for part in re.split(r"[、,]", cols[4]):
            part = part.strip()
            if part not in LABEL_TO_PURPOSE:
                raise SystemExit(f"privacy_labels.md 2.2 の未知の目的: {part!r}（LABEL_TO_PURPOSE に足す）")
            purposes.add(LABEL_TO_PURPOSE[part])
        rows[LABEL_TO_TYPE[name]] = {
            "linked": "はい" in cols[2],
            "tracking": "はい" in cols[3],
            "purposes": purposes,
        }
    return rows


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    problems: list[str] = []
    data = plistlib.loads(MANIFEST.read_bytes())

    for key in ("NSPrivacyTracking", "NSPrivacyTrackingDomains", "NSPrivacyCollectedDataTypes",
                "NSPrivacyAccessedAPITypes"):
        if key not in data:
            problems.append(f"必須キーがない: {key}")
    if not isinstance(data.get("NSPrivacyTracking"), bool):
        problems.append("NSPrivacyTracking は真偽値")
    if not isinstance(data.get("NSPrivacyTrackingDomains"), list):
        problems.append("NSPrivacyTrackingDomains は配列")

    collected: dict[str, dict] = {}
    for item in data.get("NSPrivacyCollectedDataTypes", []):
        t = str(item.get("NSPrivacyCollectedDataType", "")).removeprefix("NSPrivacyCollectedDataType")
        if t not in DATA_TYPES:
            problems.append(f"許可リストにないデータタイプ: {t!r}")
        purposes = {str(p).removeprefix("NSPrivacyCollectedDataTypePurpose")
                    for p in item.get("NSPrivacyCollectedDataTypePurposes", [])}
        for p in purposes - PURPOSES:
            problems.append(f"{t}: 許可リストにない目的 {p!r}")
        if not purposes:
            problems.append(f"{t}: 目的が空")
        for flag in ("NSPrivacyCollectedDataTypeLinked", "NSPrivacyCollectedDataTypeTracking"):
            if not isinstance(item.get(flag), bool):
                problems.append(f"{t}: {flag} は真偽値")
        if t in collected:
            problems.append(f"データタイプが重複: {t}")
        collected[t] = {
            "linked": item.get("NSPrivacyCollectedDataTypeLinked"),
            "tracking": item.get("NSPrivacyCollectedDataTypeTracking"),
            "purposes": purposes,
        }

    for item in data.get("NSPrivacyAccessedAPITypes", []):
        cat = str(item.get("NSPrivacyAccessedAPIType", "")).removeprefix("NSPrivacyAccessedAPICategory")
        if cat not in API_REASONS:
            problems.append(f"許可リストにない API の分類: {cat!r}")
            continue
        for r in item.get("NSPrivacyAccessedAPITypeReasons", []):
            if r not in API_REASONS[cat]:
                problems.append(f"{cat}: 許可リストにない理由 {r!r}")
        if not item.get("NSPrivacyAccessedAPITypeReasons"):
            problems.append(f"{cat}: 理由が空")

    pbx = PBXPROJ.read_text(encoding="utf-8")
    if not re.search(r"PrivacyInfo\.xcprivacy in Resources \*/ = \{isa = PBXBuildFile;", pbx):
        problems.append("project.pbxproj の Resources に PrivacyInfo.xcprivacy が入っていない")

    if LABELS_DOC.exists():
        expected = labels_table()
        for t in sorted(set(expected) | set(collected)):
            if t not in collected:
                problems.append(f"申告（privacy_labels.md 2.2）にあるがマニフェストにない: {t}")
            elif t not in expected:
                problems.append(f"マニフェストにあるが申告（privacy_labels.md 2.2）にない: {t}")
            elif collected[t] != expected[t]:
                problems.append(f"{t}: マニフェスト {collected[t]} と申告 {expected[t]} が違う")
        tracked = any(v["tracking"] for v in expected.values())
        if tracked != bool(data.get("NSPrivacyTracking")):
            problems.append("NSPrivacyTracking が、申告の「追跡に使用」の有無と合っていない")

    print(f"{MANIFEST.name}: 追跡={data.get('NSPrivacyTracking')}、ドメイン {len(data.get('NSPrivacyTrackingDomains', []))} 個、"
          f"データタイプ {len(collected)} 個、API の分類 {len(data.get('NSPrivacyAccessedAPITypes', []))} 個")
    if problems:
        print("問題あり:")
        for p in problems:
            print(" -", p)
        return 1
    print("OK: 許可リスト・Runner のリソース登録・privacy_labels.md 2.2 との一致に問題なし")
    return 0


if __name__ == "__main__":
    sys.exit(main())
