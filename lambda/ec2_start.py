import boto3
import os
from botocore.exceptions import ClientError


def handler(event, context):
    rds = boto3.client("rds")
    ec2 = boto3.client("ec2")
    ecs = boto3.client("ecs")

    # RDS と EC2 を同時に起動リクエスト (どちらも即時返却・非同期)
    try:
        rds.start_db_instance(DBInstanceIdentifier=os.environ["RDS_INSTANCE_ID"])
    except rds.exceptions.InvalidDBInstanceStateFault:
        pass  # すでに起動中

    try:
        ec2.start_instances(InstanceIds=[os.environ["EC2_INSTANCE_ID"]])
    except ClientError as e:
        code = e.response["Error"]["Code"]
        # 遷移状態 (stopping/terminated) またはすでに起動中は無視、権限エラー等は再送出
        if code not in ("IncorrectInstanceState", "InvalidInstanceID.NotFound"):
            raise

    # RDS が available になるまで待機してから ECS を起動する
    # start_db_instance は即時返却するが RDS の起動完了まで 3–7 分かかる。
    # ECS より先に待機することで、Rails コンテナの初回 DB 接続失敗を防ぐ。
    waiter = rds.get_waiter("db_instance_available")
    waiter.wait(
        DBInstanceIdentifier=os.environ["RDS_INSTANCE_ID"],
        WaiterConfig={"Delay": 15, "MaxAttempts": 40},  # 最大 10 分
    )

    ecs.update_service(
        cluster=os.environ["ECS_CLUSTER"],
        service=os.environ["ECS_SERVICE"],
        desiredCount=1,
    )
