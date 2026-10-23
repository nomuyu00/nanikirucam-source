"""期限付き審査コードをローカル生成する。出力ファイルはGitへ追加しない。"""
import argparse
import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--days", type=int, default=60)
    parser.add_argument("--output", type=Path, default=Path("review_access_code.local.txt"))
    args = parser.parse_args()
    if not 1 <= args.days <= 90:
        parser.error("有効期間は1〜90日にしてください")
    # 上書きによる既存コードの紛失を防ぐ。
    code = secrets.token_urlsafe(32)
    expires = (datetime.now(timezone.utc) + timedelta(days=args.days)).strftime("%Y-%m-%dT%H:%M:%SZ")
    with args.output.open("x", encoding="utf-8") as output:
        output.write(
            "Google Play審査メモにだけ記載するコード（Git・ログへ掲載しない）\n"
            f"Code: {code}\n\n"
            "Codemagicへ設定するビルド変数（平文コードはビルドに渡さない）\n"
            f"REVIEW_ACCESS_CODE_SHA256={hashlib.sha256(code.encode()).hexdigest()}\n"
            f"REVIEW_ACCESS_EXPIRES_AT={expires}\n"
        )
    print(f"生成しました: {args.output}（値はログに表示しません）")


if __name__ == "__main__":
    main()
