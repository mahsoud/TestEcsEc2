# AWS ECS orchestration

A test project for setting up an ECS cluster with EC2 launch type via CloudFormation template; launching services within the cluster. 

## Getting Started

Clone the repository to your local directory and launch shell script from command line.

```
Launch.sh --stackname=MyTestStack --accesskey=AKI00000000000000000 --secretaccesskey=0000000000000000000000000000000000000000 --region=us-west-2 --containername=nginx --containerurl=nginx
```

### Prerequisites

The script was tested on Ubuntu 16.04; this assumes you have a valid set of credentials for accessing Amazon Web Services. 