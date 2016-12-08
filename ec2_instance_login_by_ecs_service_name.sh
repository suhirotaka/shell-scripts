#!/bin/bash

DEFAULT_PRIVATE_KEY_FILE=~/.ssh/ecs_development.pem
DEFAULT_CLUSTER_NAME=default

# show usage
usage() {
  cat <<__EOS__
Login to ECS instance or ECS container by ECS service name
Usage:
  $(basename $0) [-f PRIVATE_KEY_FILE_NAME] [-c ECS_CLUSTER_NAME] [-d] ECS_SERVICE_NAME

Options:
  -f private key file name
  -c ECS cluster name
  -d directly login to ECS container
  -h print this
__EOS__
}

# get options
if [ $# -eq 0 ]; then
  usage
  exit 0
fi

while getopts f:c:dh OPT
do
  case $OPT in
    f)  PRIVATE_KEY_FILE=$OPTARG
        ;;
    c)  CLUSTER_NAME=$OPTARG
        ;;
    d)  CONTAINER_LOGIN=1
        ;;
    h)  usage
        exit 0
        ;;
    \?) usage
        exit 1
        ;;
  esac
done

shift $((OPTIND - 1))
ECS_SERVICE_NAME=$1

if [ -z "${PRIVATE_KEY_FILE+a}" ]; then
  PRIVATE_KEY_FILE=$DEFAULT_PRIVATE_KEY_FILE
fi

if [ -z "${CLUSTER_NAME+a}" ]; then
  CLUSTER_NAME=$DEFAULT_CLUSTER_NAME
fi

# check environment
raise_error=0

if [ -z "$ECS_SERVICE_NAME" ]; then
  echo "Error: ECS service name not found."
  raise_error=1
fi

if ! type "jq" > /dev/null 2>&1; then
  echo "Error: jq command not found."
  raise_error=1
fi

if ! type "aws" > /dev/null 2>&1; then
  echo "Error: aws command not found."
  raise_error=1
fi

if [ ! -e $PRIVATE_KEY_FILE ]; then
  echo "Error: private key file not found."
  raise_error=1
fi

if [ -z "$(aws configure get aws_access_key_id)" ]; then
  echo 'Error: aws access key id not found. try `env AWS_ACCESS_KEY_ID=YOUR_AWS_ACCESS_KEY_ID`'
  raise_error=1
fi

if [ -z "$(aws configure get aws_secret_access_key)" ]; then
  echo 'Error: aws secret access key not found. try `env AWS_SECRET_ACCESS_KEY=YOUR_AWS_SECRET_ACCESS_KEY`'
  raise_error=1
fi

if [ -z "$(aws configure get region)" ]; then
  echo 'Error: aws region not found. try `env AWS_DEFAULT_REGION=YOUR_AWS_REGION`'
  raise_error=1
fi

if [ $raise_error -eq 1 ]; then
  exit 1
fi

# get public IP from ECS service name
echo Start to process login ...

task_definition_arn=$(aws ecs describe-services --output json --service $ECS_SERVICE_NAME | jq '.services[].taskDefinition')
if [ -z "$task_definition_arn" ]; then
  echo 'Error: task definition not found. (wrong service name?)'
  exit 1
fi
task_definition=$(echo $task_definition_arn | sed -e 's/"[^"\/]*\/\([^"\/]*\)"/\1/')

task_arns=$(aws ecs list-tasks --output json --cluster $CLUSTER_NAME | jq '.taskArns[]')
if [ -z "$task_arns" ]; then
  echo 'Error: no ECS tasks found. (wrong cluster name?)'
  exit 1
fi
task_ids=$(echo $task_arns | sed -e 's/"[^"\/]*\/\([^"\/]*\)"/\1/g')
tasks_json=$(aws ecs describe-tasks --output json --cluster $CLUSTER_NAME --tasks $task_ids | jq .tasks)
if [ -z "$tasks_json" ]; then
  echo 'Error: desired ECS tasks not found.'
  exit 1
fi
tasks_length=$(echo $tasks_json | jq length)
for i in $( seq 0 $(($tasks_length - 1)) ); do
  task_json=$(echo $tasks_json | jq .[$i])
  task_definition_looped=$(echo $task_json | jq .taskDefinitionArn | sed -e 's/"[^"\/]*\/\([^"\/]*\)"/\1/')
  if [ "$task_definition" =  "$task_definition_looped" ]; then
    container_instance_arn=$(echo $task_json | jq .containerInstanceArn)
    break
  fi
done

container_instance_id=$(echo $container_instance_arn | sed -e 's/"[^"\/]*\/\([^"\/]*\)"/\1/g')
ec2_instance_id=$(aws ecs describe-container-instances --output json --cluster $CLUSTER_NAME --container-instances $container_instance_id | jq .containerInstances[].ec2InstanceId | sed -e 's/"//g')
if [ -z "$ec2_instance_id" ]; then
  echo 'Error: desired container instance not found.'
  exit 1
fi

public_ip=$(aws ec2 describe-instances --output json --instance-ids $ec2_instance_id | jq .Reservations[].Instances[].PublicIpAddress | sed -e 's/"//g')
if [ -z "$public_ip" ]; then
  echo 'Error: desired EC2 instance not found.'
  exit 1
fi

# SSH to EC2 instance
container_type=$(echo $task_definition | sed -e 's/.*-\([^\-\:]*\):[0-9]*/\1/')
container_name="ecs-$(echo $task_definition | sed -e 's/:/-/')-${container_type}"
docker_command="docker exec -it \$(docker ps --filter name=${container_name} -q | head -1) bash"
if [ -n "${CONTAINER_LOGIN+a}" ] && [ $CONTAINER_LOGIN -eq 1 ]; then
  echo SSH to container $container_name@$public_ip ...
  ssh -t -i $PRIVATE_KEY_FILE ec2-user@$public_ip $docker_command
else
  echo SSH to $public_ip ...
  ssh -i $PRIVATE_KEY_FILE ec2-user@$public_ip
fi
