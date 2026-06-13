import boto3
import os
from datetime import datetime, timezone, timedelta

JST = timezone(timedelta(hours=9))


def handler(event, context):
    hour = datetime.now(JST).hour
    # ec2_start によるスケジュール起動 (JST 18:00–23:59) は停止しない
    # それ以外の時間帯に RDS-EVENT-0088 が来た場合は AWS 自動再起動なので即停止
    if 18 <= hour <= 23:
        return
    rds = boto3.client("rds")
    try:
        rds.stop_db_instance(DBInstanceIdentifier=os.environ["RDS_INSTANCE_ID"])
    except rds.exceptions.InvalidDBInstanceStateFault:
        pass  # すでに停止中
