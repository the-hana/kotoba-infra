import boto3
import os


def handler(event, context):
    rds = boto3.client("rds")
    try:
        rds.stop_db_instance(DBInstanceIdentifier=os.environ["RDS_INSTANCE_ID"])
    except rds.exceptions.InvalidDBInstanceStateFault:
        pass  # すでに停止中
