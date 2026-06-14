import boto3
import os


def handler(event, context):
    instance_id = event["detail"]["instance-id"]

    ec2 = boto3.client("ec2")
    resp = ec2.describe_instances(InstanceIds=[instance_id])
    instance = resp["Reservations"][0]["Instances"][0]
    public_dns = instance.get("PublicDnsName")
    if not public_dns:
        print(f"No public DNS for {instance_id}, skipping")
        return

    dist_id = os.environ["CF_DISTRIBUTION_ID"]

    cf = boto3.client("cloudfront")
    resp = cf.get_distribution_config(Id=dist_id)
    config = resp["DistributionConfig"]
    etag = resp["ETag"]

    for origin in config["Origins"]["Items"]:
        if origin["Id"] == "ec2-api":
            origin["DomainName"] = public_dns
            break

    cf.update_distribution(DistributionConfig=config, Id=dist_id, IfMatch=etag)
    print(f"Updated CF origin to {public_dns}")
    return {"status": "updated", "dns": public_dns}
