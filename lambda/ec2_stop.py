import boto3
import os


def handler(event, context):
    ecs = boto3.client("ecs")
    ec2 = boto3.client("ec2")
    rds = boto3.client("rds")

    ecs.update_service(
        cluster=os.environ["ECS_CLUSTER"],
        service=os.environ["ECS_SERVICE"],
        desiredCount=0,
    )
    ec2.stop_instances(InstanceIds=[os.environ["EC2_INSTANCE_ID"]])
    try:
        rds.stop_db_instance(DBInstanceIdentifier=os.environ["RDS_INSTANCE_ID"])
    except rds.exceptions.InvalidDBInstanceStateFault:
        pass  # すでに停止中
