#!/bin/bash

set -e

for i in "$@"
    do
        case $i in
            -n=*|--stackname=*)
            AWS_STACK_NAME="${i#*=}"
            ;;
            -k=*|--accesskey=*)
            AWS_ACCESS_KEY_ID="${i#*=}"
            ;;
            -s=*|--secretaccesskey=*)
            AWS_SECRET_ACCESS_KEY="${i#*=}"
            ;;
            -r=*|--region=*)
            AWS_DEFAULT_REGION="${i#*=}"
            ;;
            -c=*|--containername=*)
            CONTAINER_NAME="${i#*=}"
            ;;
            -u=*|--containerurl=*)
            CONTAINER_URL="${i#*=}"
            ;;
            *)
            printf 'Unknown argument provided.'
            exit 1
            ;;
    esac
done
    
printf 'Validating script arguments...\n'
    echo $AWS_STACK_NAME | grep -E -q '^[a-zA-Z0-9][-a-zA-Z0-9]{0,127}$' || ( printf 'A valid, arbitrary stack name must be specified.' && exit 1 )
    echo $AWS_SECRET_ACCESS_KEY | grep -E -q '^[0-9A-Za-z/+=]{40}$' || ( printf 'Existing AWS secret access key must be specified.' && exit 1 )
    echo $AWS_ACCESS_KEY_ID | grep -E -q '^[0-9A-Z]{20}$' || ( printf 'Existing AWS access key ID must be specified.' && exit 1 )
    
    AWS_KNOWN_REGIONS=(us-west-1 us-west-2 us-east-1 us-east-2 eu-west-1 eu-west-2 eu-west-3 eu-central-1)
    if [[ ! " ${AWS_KNOWN_REGIONS[@]} " =~ " ${AWS_DEFAULT_REGION} " ]] ; then
        printf 'Specified region is not found in the defined list of regions, please see script for details.' && exit 1
    fi

    echo $CONTAINER_NAME | grep -E -q '^[a-zA-Z0-9][a-zA-Z0-9_.-]{1,29}$'  || ( printf 'A valid container name must be specified.' && exit 1 )
    CONTAINER_URL="${CONTAINER_URL:-$CONTAINER_NAME}"
    
printf 'Checking environment...\n'
    sudo apt update
    if [ -x /usr/bin/python ] ; then
        printf 'Python is installed.\n'
        python -V
    else
        printf 'Installing Python...\n'
        sudo apt --yes install python
    fi

    if [ -x /usr/local/aws ] ; then
        printf 'AWS CLI is installed.\n'
        aws --version
    else
        printf 'Installing AWS CLI...\n'
        
        if [ ! -x /usr/bin/unzip ] ; then
            printf 'Installing unzip...\n'
            sudo apt --yes install unzip
        fi

        curl 'https://s3.amazonaws.com/aws-cli/awscli-bundle.zip' -o 'awscli-bundle.zip'
        unzip awscli-bundle.zip
        sudo ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws
        aws --version
    fi

printf 'Configuring AWS CLI defaults via environmnet variables...\n'
    export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
    export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
    export AWS_DEFAULT_OUTPUT=text

printf 'Determining AMI image id...\n'
    IMAGE_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=ubuntu*" "Name=block-device-mapping.volume-size,Values=1,2,3,4,5,6,7,8,9,10" \
        --query 'Images[*].[ImageId,CreationDate]' \
        --output text \
        | sort -k2 -r \
        | head -n1 \
        | awk '{printf $1;}' )
    printf 'Latest Ubuntu image eligible for free tier: %s \n' $IMAGE_ID

# printf 'Obtaining CloudFormation Templates...\n'
    # curl 'https://.../cluster.yaml' -o 'cluster.yaml'
    # curl 'https://.../service.yaml' -o 'service.yaml'

wait-cloudformation-commplete() {
    printf 'Waiting for creation of %s stack to complete...\n' $1
    aws cloudformation wait stack-create-complete --stack-name $1
}

printf 'Setting up ECS cluster...\n'
    if [ ! -f cluster.yaml ] ; then
        printf 'CloudFormation template for ECS Cluster not found!' && exit 1
    fi
    aws cloudformation create-stack \
        --stack-name $AWS_STACK_NAME \
        --template-body file://./cluster.yaml \
        --capabilities CAPABILITY_IAM \
        --parameters ParameterKey=Image,ParameterValue=$IMAGE_ID

    wait-cloudformation-commplete $AWS_STACK_NAME
    
printf 'Initializing ECS and tasks...\n'
    if [ ! -f service.yaml ] ; then
        printf 'CloudFormation template for ECS tasks not found!' && exit 1
    fi
    
    AWS_SERVICES_STACK_NAME="${AWS_STACK_NAME}Services"

    aws cloudformation create-stack \
        --stack-name $AWS_SERVICES_STACK_NAME \
        --template-body file://./service.yaml \
        --parameters \
            ParameterKey=StackName,ParameterValue=$AWS_STACK_NAME \
            ParameterKey=ImageUrl,ParameterValue=$CONTAINER_URL \
            ParameterKey=ServiceName,ParameterValue=$CONTAINER_NAME

    wait-cloudformation-commplete $AWS_SERVICES_STACK_NAME

printf 'Validate stack via Load Balancer...\n'
    
    EXTERNAL_URL=$(aws cloudformation list-exports \
        --query "Exports[?Name == '${AWS_STACK_NAME}:ExternalUrl'].Value" \
        --output text )

    printf 'Confirming service is available via %s .\n' $EXTERNAL_URL
    curl -sSf $EXTERNAL_URL > /dev/null

printf 'Done.'