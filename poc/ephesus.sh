#!/bin/bash
# s3, datapipeline -> sns -> sqs -> autoscaling -> ec2 -> s3
#set -o errexit

ALARM_DESCRIPTION="alarm_description"
ALARM_NAME="ephesus_alarm_name"
AUTOSCALING_GROUP_NAME="ephesus_autoscaling_group_name"
AVAILABILITY_ZONES="us-west-2"
AWS_ACCOUNT_ID=""
SITE_BUCKET="ephesus_site"
CACHE_CONTROL=""
GRANTS=""
IAM_INSTANCE_PROFILE=""
IMAGE_ID="ami-b8f69f88"
INSTANCE_TYPE="t1.micro"
KEY_NAME="ephesus-key"
LAUNCH_CONFIG_NAME="ephesus_launch_config_name"
OTHER_QUEUE_ATTRIBUTES=""
PIPELINE_DEFINITION_JSON="file://pipeline.json"
PIPELINE_DESCRIPTION="pipeline_description"
PIPELINE_ID="ephesus_pipeline_id"
PIPELINE_NAME="ephesus_pipeline_name"
POLICY_NAME="ephesus_policy_name"
QUEUE_NAME="ephesus_queue_name"
QUEUE_PERMISSION_LABEL=""
QUEUE_POLICY="file://queue_policy.json"
QUEUE_URL=""
READ_ACCESS=""
SECURITY_GROUPS="default"
SOURCE_BUCKET="ephesus.source.bucket"
SINK_BUCKET="ephesus.sink.bucket"
TEMP_SITE=""
TOPIC_NAME="ephesus_topic_name2323"
USER_DATA=""

run () {
	eval $1=$($2 | jq .$1)
	if [[ -z ${!1} ]] ; then
		echo error with "${2}"
		exit
	fi
}

# set up pre-signed URL? actually needs to be renewed regularly so don't do it here
#aws s3 mb "s3://${SOURCE_BUCKET}" || { echo "error making bucket"; exit 1; }

#aws s3 mb "s3://${SINK_BUCKET}" || { echo "error making bucket"; exit 1; }

run TopicArn "aws sns create-topic --name ${TOPIC_NAME}"

aws datapipeline create-pipeline --name "${PIPELINE_NAME}" --unique-id "${PIPELINE_ID}" --description "${PIPELINE_DESCRIPTION}"

aws datapipeline put-pipeline-definition --pipeline-id "${PIPELINE_ID}" --pipeline-definition "${PIPELINE_DEFINITION_JSON}"

aws datapipeline activate-pipeline --pipeline-id "${PIPELINE_ID}" || { echo "error activating pipeline"; exit 1; }

run QueueArn "aws sqs create-queue --queue-name ${QUEUE_NAME} --attributes Policy=${QUEUE_POLICY}"

# aws sqs add-permission --queue-url "${QUEUE_URL}" --label "${QUEUE_PERMISSION_LABEL}" --aws-account-ids "${AWS_ACCOUNT_ID}" --actions send-message

aws sns subscribe --topic-arn "${TopicArn}" --protocol sqs --notification-endpoint "${QueueArn}"

aws autoscaling create-launch-configuration --launch-configuration-name "${LAUNCH_CONFIG_NAME}" --image-id "${IMAGE_ID}" --key-name "${KEY_NAME}" \
  --security-groups "${SECURITY_GROUPS}" --user-data "${USER_DATA}" --instance-type "${INSTANCE_TYPE}" --instance-monitoring Enabled=false \
#  --iam-instance-profile "${IAM_INSTANCE_PROFILE}"

aws autoscaling create-auto-scaling-group --auto-scaling-group-name "${AUTOSCALING_GROUP_NAME}" --launch-configuration-name "${LAUNCH_CONFIG_NAME}" \
  --min-size 0 --max-size 1 --availability-zones "${AVAILABILITY_ZONES}"

aws autoscaling put-scaling-policy --auto-scaling-group-name "${AUTOSCALING_GROUP_NAME}" --policy-name "${POLICY_NAME}" --scaling-adjustment 1 \
  --adjustment-type ExactCapacity

aws cloudwatch put-metric-alarm --alarm-name "${ALARM_NAME}" --alarm-description "${ALARM_DESCRIPTION}" --actions-enabled --alarm-actions "${PolicyArn}" \
  --metric-name ApproximateNumberOfMessagesVisible --namespace AWS/SQS --statistic Average --dimensions QueueName="${QUEUE_NAME}" --period 15 \
  --evaluation-periods 1 --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold

aws s3 mv "${TEMP_SITE}" "${SITE_BUCKET}" --content-type "text/html" #--quiet --acl "${READ_ACCESS}" --cache-control "${CACHE_CONTROL}" --grants "${GRANTS}"
