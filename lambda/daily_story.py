import os
import urllib.request
import urllib.error
import boto3

# SSM client はコールドスタート時に初期化してキャッシュ
ssm = boto3.client("ssm")


def _get_internal_token():
    # SSM Parameter Store から内部認証トークンを取得
    # WithDecryption=True で SecureString を復号化
    name = os.environ["INTERNAL_API_KEY_PARAM"]
    try:
        res = ssm.get_parameter(Name=name, WithDecryption=True)
        return res["Parameter"]["Value"]
    except ssm.exceptions.ParameterNotFound:
        raise RuntimeError(f"SSM parameter not found: {name}")
    except Exception as e:
        raise RuntimeError(f"SSM parameter fetch failed: {e}")


def handler(event, context):
    url = os.environ["WEBHOOK_URL"]
    token = _get_internal_token()
    req = urllib.request.Request(
        url,
        data=b"{}",
        headers={"Content-Type": "application/json", "X-Internal-Token": token},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as res:
            return {"statusCode": res.status}
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"webhook failed: {e.code} {e.reason}")
