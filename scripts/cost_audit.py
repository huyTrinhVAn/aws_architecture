"""
Scans the AWS account for resources that are technically running but
provide no value -- the kind of waste a NAT Gateway or an idle EC2
instance racks up quietly every month. Read-only: it only ever calls
Describe*/List*/Get* APIs, never modifies anything.

Run with the same `terraform-admin` credentials already configured via
`aws configure` (or any credentials with read access to EC2/CloudWatch/S3).
"""

from datetime import datetime, timedelta, timezone

import boto3
from botocore.exceptions import ClientError

REGION = "us-east-1"

ec2 = boto3.client("ec2", region_name=REGION)
cloudwatch = boto3.client("cloudwatch", region_name=REGION)
s3 = boto3.client("s3", region_name=REGION)


def find_unattached_ebs_volumes():
    """
    Return EBS volumes in the 'available' state (i.e. not attached to any
    instance). These are billed per GB-month even though nothing is using
    them -- usually leftovers from a terminated instance that didn't have
    "delete on termination" set.

    TODO: call ec2.describe_volumes(Filters=[{"Name": "status", "Values": ["available"]}])
    and return a list of dicts like {"volume_id": ..., "size_gb": ..., "volume_type": ...}.
    """
    response = ec2.describe_volumes(Filters=[{"Name": "status", "Values": ["available"]}])
    result = []
    for v in response["Volumes"]:
        volume_info = {
            "volume_id": v["VolumeId"],
            "size_gb": v["Size"],
            "volume_type": v["VolumeType"],
        }
        result.append(volume_info)
    return result


def find_unassociated_eips():
    """
    Return Elastic IPs that aren't associated with a running instance.
    AWS bills for an EIP that isn't attached to a running instance --
    the exact opposite of what most people assume ("it's just an IP,
    why would it cost anything").

    TODO: call ec2.describe_addresses() and return entries where
    'AssociationId' / 'InstanceId' is missing.
    """
    response = ec2.describe_addresses()
    result = []
    for v in response["Addresses"]: 
        if v.get("AssociationId") is None :
            result.append(v)
    return result


def find_idle_instances(cpu_threshold_percent=5.0, days=7):
    """
    Return running EC2 instances whose average CPU utilization over the
    last `days` days is below `cpu_threshold_percent` -- candidates for
    downsizing or moving to Spot.

    TODO:
    1. ec2.describe_instances(Filters=[{"Name": "instance-state-name", "Values": ["running"]}])
       to get instance IDs.
    2. For each instance, cloudwatch.get_metric_statistics(
           Namespace="AWS/EC2", MetricName="CPUUtilization",
           Dimensions=[{"Name": "InstanceId", "Value": instance_id}],
           StartTime=..., EndTime=..., Period=86400, Statistics=["Average"])
       (use datetime.utcnow() - timedelta(days=days) for StartTime).
    3. Average the returned datapoints; if below the threshold, include it.
    """
    ec2s = ec2.describe_instances(Filters=[{"Name": "instance-state-name", "Values": ["running"]}])
    res = []
    for reservation in ec2s["Reservations"]:
        for instance in reservation["Instances"]:
            instance_id = instance["InstanceId"]
            end_time = datetime.now(timezone.utc)
            start_time = end_time - timedelta(days=days)
            stats = cloudwatch.get_metric_statistics(
                Namespace="AWS/EC2",
                MetricName="CPUUtilization",
                Dimensions=[{"Name": "InstanceId", "Value": instance_id}],
                StartTime=start_time,
                EndTime=end_time,
                Period=86400,
                Statistics=["Average"],
            )
            datapoints = stats["Datapoints"]
            if not datapoints:
                continue
            total_cpu = 0
            for dp in datapoints:
                total_cpu = total_cpu + dp["Average"]
            avg_cpu = total_cpu / len(datapoints)
            if avg_cpu < cpu_threshold_percent:
                res.append({"instance_id": instance_id, "avg_cpu": avg_cpu})
    return res

def find_buckets_without_lifecycle():
    """
    Return S3 buckets that have no lifecycle configuration at all --
    data sitting in Standard storage forever instead of aging into
    cheaper tiers.

    TODO:
    1. s3.list_buckets() to get all bucket names.
    2. For each, try s3.get_bucket_lifecycle_configuration(Bucket=name).
       It raises a ClientError with code "NoSuchLifecycleConfiguration"
       when there's no lifecycle rule -- catch that specifically (don't
       swallow other errors) and count it as a finding.
    """
    response = s3.list_buckets()
    buckets = response["Buckets"]

    result = []
    for bucket in buckets:
        bucket_name = bucket["Name"]

        try:
            s3.get_bucket_lifecycle_configuration(Bucket=bucket_name)
        except ClientError as error:
            error_code = error.response["Error"]["Code"]
            if error_code == "NoSuchLifecycleConfiguration":
                result.append(bucket_name)
            else:
                # some other real error (permissions, throttling...) --
                # don't silently treat it as "no lifecycle configured"
                raise

    return result


def print_report():
    print("=== AWS Cost Audit ===\n")

    volumes = find_unattached_ebs_volumes()
    print(f"Unattached EBS volumes: {len(volumes)}")
    for v in volumes:
        print(f"  - {v}")

    eips = find_unassociated_eips()
    print(f"\nUnassociated Elastic IPs: {len(eips)}")
    for e in eips:
        print(f"  - {e}")

    idle = find_idle_instances()
    print(f"\nIdle instances (low CPU): {len(idle)}")
    for i in idle:
        print(f"  - {i}")

    no_lifecycle = find_buckets_without_lifecycle()
    print(f"\nS3 buckets without a lifecycle policy: {len(no_lifecycle)}")
    for b in no_lifecycle:
        print(f"  - {b}")


if __name__ == "__main__":
    print_report()
