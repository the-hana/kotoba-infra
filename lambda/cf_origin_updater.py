import boto3
import os


def handler(event, context):
    instance_id = event["detail"]["instance-id"]

    ec2 = boto3.client("ec2")
    resp = ec2.describe_instances(InstanceIds=[instance_id])
    public_ip = resp["Reservations"][0]["Instances"][0].get("PublicIpAddress")
    if not public_ip:
        print(f"No public IP for {instance_id}, skipping")
        return

    ssm = boto3.client("ssm")
    dist_id = ssm.get_parameter(Name=os.environ["CF_DIST_ID_PARAM"])["Parameter"]["Value"]

    cf = boto3.client("cloudfront")
    resp = cf.get_distribution_config(Id=dist_id)
    config = resp["DistributionConfig"]
    etag = resp["ETag"]

    for origin in config["Origins"]["Items"]:
        if origin["Id"] == "ec2-api":
            origin["DomainName"] = public_ip
            break

    cf.update_distribution(DistributionConfig=config, Id=dist_id, IfMatch=etag)
    print(f"Updated CF origin to {public_ip}")
    return {"status": "updated", "ip": public_ip}
