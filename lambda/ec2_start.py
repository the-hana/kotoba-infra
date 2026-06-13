import boto3
import os


def handler(event, context):
    rds = boto3.client("rds")
    ec2 = boto3.client("ec2")
    ecs = boto3.client("ecs")

    # RDS を先に起動し、EC2 コンテナが DB に接続できる状態を早める
    try:
        rds.start_db_instance(DBInstanceIdentifier=os.environ["RDS_INSTANCE_ID"])
    except rds.exceptions.InvalidDBInstanceStateFault:
        pass  # すでに起動中
    ec2.start_instances(InstanceIds=[os.environ["EC2_INSTANCE_ID"]])
    ecs.update_service(
        cluster=os.environ["ECS_CLUSTER"],
        service=os.environ["ECS_SERVICE"],
        desiredCount=1,
    )
