import boto3
import os
from botocore.exceptions import ClientError


def handler(event, context):
    ecs = boto3.client("ecs")
    ec2 = boto3.client("ec2")
    rds = boto3.client("rds")

    ecs.update_service(
        cluster=os.environ["ECS_CLUSTER"],
        service=os.environ["ECS_SERVICE"],
        desiredCount=0,
    )

    # EC2 停止失敗でも RDS は必ず停止するため、エラーを一時保持して後で再送出する
    ec2_error = None
    try:
        ec2.stop_instances(InstanceIds=[os.environ["EC2_INSTANCE_ID"]])
    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code not in ("IncorrectInstanceState", "InvalidInstanceID.NotFound"):
            ec2_error = e

    try:
        rds.stop_db_instance(DBInstanceIdentifier=os.environ["RDS_INSTANCE_ID"])
    except rds.exceptions.InvalidDBInstanceStateFault:
        pass  # すでに停止中

    if ec2_error:
        raise ec2_error
