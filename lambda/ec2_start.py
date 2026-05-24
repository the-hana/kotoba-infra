import boto3
import os


def handler(event, context):
    boto3.client("ecs").update_service(
        cluster=os.environ["ECS_CLUSTER"],
        service=os.environ["ECS_SERVICE"],
        desiredCount=1,
    )
