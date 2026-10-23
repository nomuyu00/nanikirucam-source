"""審査用の任意ビルド設定を検証する。値はログに表示しない。"""
import os
import re
from datetime import datetime, timedelta, timezone


def validate(environ):
    digest = environ.get("REVIEW_ACCESS_CODE_SHA256", "")
    expires = environ.get("REVIEW_ACCESS_EXPIRES_AT", "")
    if not digest and not expires:
        return
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("REVIEW_ACCESS_CODE_SHA256 must be a lowercase SHA-256 digest")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", expires):
        raise ValueError("REVIEW_ACCESS_EXPIRES_AT must use UTC YYYY-MM-DDTHH:MM:SSZ")
    until = datetime.strptime(expires, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    now = datetime.now(timezone.utc)
    if not now < until <= now + timedelta(days=90):
        raise ValueError("Review access must expire in the next 90 days")


if __name__ == "__main__":
    try:
        validate(os.environ)
    except ValueError as error:
        raise SystemExit(str(error)) from None
    print("Review access configuration: valid (or disabled)")
