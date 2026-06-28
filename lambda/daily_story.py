import os
import urllib.request
import urllib.error
import boto3

ssm = boto3.client("ssm")


def _get_internal_token():
    name = os.environ["INTERNAL_API_KEY_PARAM"]
    res = ssm.get_parameter(Name=name, WithDecryption=True)
    return res["Parameter"]["Value"]


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
