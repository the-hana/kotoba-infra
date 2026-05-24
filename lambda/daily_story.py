import os
import urllib.request
import urllib.error


def handler(event, context):
    url = os.environ["WEBHOOK_URL"]
    req = urllib.request.Request(
        url,
        data=b"{}",
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as res:
            return {"statusCode": res.status}
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"webhook failed: {e.code} {e.reason}")
