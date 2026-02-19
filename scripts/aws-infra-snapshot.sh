#!/usr/bin/env bash
set -euo pipefail
#
# AWS Infrastructure Snapshot — Read-Only, No Data Exposure
#
# Captures infrastructure metadata for diagramming. Zero data plane access.
# No CloudTrail, CloudWatch logs, RDS data, S3 objects, Athena, or secrets.
#
# Usage:
#   ./aws-infra-snapshot.sh                          # default: us-east-2
#   ./aws-infra-snapshot.sh us-east-1                # specific region
#   AWS_PROFILE=dev ./aws-infra-snapshot.sh          # specific profile
#
# Output: ./infra-snapshot-{account}-{region}-{date}/

REGION="${1:-us-east-2}"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text --region "$REGION")
DATE=$(date +%Y%m%d-%H%M%S)
OUTDIR="./infra-snapshot-${ACCOUNT}-${REGION}-${DATE}"

mkdir -p "$OUTDIR"
echo "Account: $ACCOUNT | Region: $REGION | Output: $OUTDIR"

run() {
  local name="$1"; shift
  echo "  Querying $name..."
  "$@" --region "$REGION" --output json > "$OUTDIR/${name}.json" 2>/dev/null || echo "  ⚠ $name failed (may not exist in this account)"
}

# ── Networking ──────────────────────────────────────────────────
echo "=== Networking ==="
run vpcs                    aws ec2 describe-vpcs
run subnets                 aws ec2 describe-subnets
run route-tables            aws ec2 describe-route-tables
run internet-gateways       aws ec2 describe-internet-gateways
run nat-gateways            aws ec2 describe-nat-gateways
run vpc-peering             aws ec2 describe-vpc-peering-connections
run vpc-endpoints           aws ec2 describe-vpc-endpoints
run security-groups         aws ec2 describe-security-groups
run network-acls            aws ec2 describe-network-acls
run elastic-ips             aws ec2 describe-addresses

# ── Compute (metadata only — no console output, no user data) ──
echo "=== Compute ==="
run ec2-instances           aws ec2 describe-instances --query 'Reservations[].Instances[].{InstanceId:InstanceId,InstanceType:InstanceType,State:State.Name,SubnetId:SubnetId,VpcId:VpcId,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress,SecurityGroups:SecurityGroups,Tags:Tags,IamInstanceProfile:IamInstanceProfile,LaunchTime:LaunchTime}'
run ecs-clusters            aws ecs list-clusters
run autoscaling-groups      aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[].{Name:AutoScalingGroupName,MinSize:MinSize,MaxSize:MaxSize,DesiredCapacity:DesiredCapacity,VPCZoneIdentifier:VPCZoneIdentifier,LaunchTemplate:LaunchTemplate,Tags:Tags}'

# ── ECS detail (if clusters exist) ──
if [ -f "$OUTDIR/ecs-clusters.json" ]; then
  CLUSTERS=$(python3 -c "import json; d=json.load(open('$OUTDIR/ecs-clusters.json')); print(' '.join(d.get('clusterArns',[])))" 2>/dev/null || true)
  if [ -n "$CLUSTERS" ]; then
    echo "=== ECS Detail ==="
    run ecs-cluster-detail   aws ecs describe-clusters --clusters $CLUSTERS --include STATISTICS ATTACHMENTS
    for CLUSTER_ARN in $CLUSTERS; do
      CLUSTER_NAME=$(basename "$CLUSTER_ARN")
      SERVICES=$(aws ecs list-services --cluster "$CLUSTER_ARN" --region "$REGION" --query 'serviceArns[]' --output text 2>/dev/null || true)
      if [ -n "$SERVICES" ]; then
        run "ecs-services-${CLUSTER_NAME}" aws ecs describe-services --cluster "$CLUSTER_ARN" --services $SERVICES
      fi
    done
  fi
fi

# ── Load Balancing ──────────────────────────────────────────────
echo "=== Load Balancing ==="
run albs                    aws elbv2 describe-load-balancers
run target-groups           aws elbv2 describe-target-groups
run classic-lbs             aws elb describe-load-balancers

# ALB listeners + rules
if [ -f "$OUTDIR/albs.json" ]; then
  ALB_ARNS=$(python3 -c "import json; d=json.load(open('$OUTDIR/albs.json')); print(' '.join(lb['LoadBalancerArn'] for lb in d.get('LoadBalancers',[])))" 2>/dev/null || true)
  for ARN in $ALB_ARNS; do
    LB_NAME=$(python3 -c "import json; d=json.load(open('$OUTDIR/albs.json')); print(next(lb['LoadBalancerName'] for lb in d['LoadBalancers'] if lb['LoadBalancerArn']=='$ARN'))" 2>/dev/null)
    run "alb-listeners-${LB_NAME}" aws elbv2 describe-listeners --load-balancer-arn "$ARN"
  done
fi

# ── DNS ─────────────────────────────────────────────────────────
echo "=== DNS ==="
run hosted-zones            aws route53 list-hosted-zones
if [ -f "$OUTDIR/hosted-zones.json" ]; then
  ZONE_IDS=$(python3 -c "import json; d=json.load(open('$OUTDIR/hosted-zones.json')); print(' '.join(z['Id'].split('/')[-1] for z in d.get('HostedZones',[])))" 2>/dev/null || true)
  for ZID in $ZONE_IDS; do
    ZNAME=$(python3 -c "import json; d=json.load(open('$OUTDIR/hosted-zones.json')); print(next(z['Name'].rstrip('.') for z in d['HostedZones'] if z['Id'].endswith('$ZID')))" 2>/dev/null)
    run "dns-records-${ZNAME}" aws route53 list-resource-record-sets --hosted-zone-id "$ZID"
  done
fi

# ── Certificates ────────────────────────────────────────────────
echo "=== Certificates ==="
run acm-certs               aws acm list-certificates --query 'CertificateSummaryList[].{DomainName:DomainName,CertificateArn:CertificateArn,Status:Status}'

# ── IAM (global, not regional — but useful for trust relationships) ──
echo "=== IAM ==="
run iam-roles               aws iam list-roles --query 'Roles[].{RoleName:RoleName,Arn:Arn,AssumeRolePolicyDocument:AssumeRolePolicyDocument,CreateDate:CreateDate}'
run iam-instance-profiles   aws iam list-instance-profiles --query 'InstanceProfiles[].{Name:InstanceProfileName,Arn:Arn,Roles:Roles[].RoleName}'

# ── ElastiCache (endpoints + SGs only, no data) ────────────────
echo "=== ElastiCache ==="
run elasticache-clusters    aws elasticache describe-cache-clusters --query 'CacheClusters[].{CacheClusterId:CacheClusterId,Engine:Engine,EngineVersion:EngineVersion,CacheNodeType:CacheNodeType,NumCacheNodes:NumCacheNodes,CacheSubnetGroupName:CacheSubnetGroupName,SecurityGroups:SecurityGroups,ConfigurationEndpoint:ConfigurationEndpoint}'
run elasticache-replication aws elasticache describe-replication-groups --query 'ReplicationGroups[].{ReplicationGroupId:ReplicationGroupId,Status:Status,NodeGroups:NodeGroups,AtRestEncryptionEnabled:AtRestEncryptionEnabled,TransitEncryptionEnabled:TransitEncryptionEnabled}'
run elasticache-subnets     aws elasticache describe-cache-subnet-groups

# ── S3 (bucket list + policy/location only — NO object access) ──
echo "=== S3 (metadata only) ==="
run s3-buckets              aws s3api list-buckets --query 'Buckets[].{Name:Name,CreationDate:CreationDate}'

# ── CloudFront ──────────────────────────────────────────────────
echo "=== CloudFront ==="
run cloudfront-distros      aws cloudfront list-distributions --query 'DistributionList.Items[].{Id:Id,DomainName:DomainName,Aliases:Aliases.Items,Origins:Origins.Items[].{Id:Id,DomainName:DomainName},Status:Status,Enabled:Enabled}'

# ── Summary ─────────────────────────────────────────────────────
echo ""
echo "Done. Files:"
ls -1 "$OUTDIR"/ | while read f; do
  SIZE=$(wc -c < "$OUTDIR/$f" | tr -d ' ')
  echo "  $f (${SIZE}b)"
done
echo ""
echo "Total: $(ls -1 "$OUTDIR" | wc -l | tr -d ' ') files in $OUTDIR"
echo ""
echo "To review before sharing:"
echo "  ls $OUTDIR/"
echo "  cat $OUTDIR/vpcs.json | python3 -m json.tool"
