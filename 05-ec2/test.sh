#!/bin/bash

#Set parameters
YAMLLOCATION="file:///Users/zachery.cox/Documents/Code/Github/stelligent-u/05-ec2/ec2.yaml"
YAMLPARAMSLOCATION="file:///Users/zachery.cox/Documents/Code/Github/stelligent-u/05-ec2/params.json"
STACKNAME="lab5-zach"
REGION="us-east-1"
PROFILE="labs-mfa"

# prints colored text
print_style () {
    # params: text, color

    #Light Blue
    if [ "$2" == "info" ] ; then
        COLOR="96m";
    #Blue
    elif [ "$2" == "blue" ] ; then
        COLOR="94m";
    #Green
    elif [ "$2" == "success" ] ; then
        COLOR="92m";
    #Yellow
    elif [ "$2" == "warning" ] ; then
        COLOR="93m";
    #Light Blue with Blue background
    elif [ "$2" == "policy" ] ; then
        COLOR="44m\e[96m";
    #Red
    elif [ "$2" == "danger" ] ; then
        COLOR="91m";
    #Blinking Red
    elif [ "$2" == "blink red" ] ; then
        COLOR="5m\e[91m";
    #Blinking Yellow
    elif [ "$2" == "blink yellow" ] ; then
        COLOR="5m\e[93m";
    #Default color
    else 
        COLOR="0m";
    fi

    STARTCOLOR="\e[$COLOR";
    ENDCOLOR="\e[0m";

    printf "$STARTCOLOR%b$ENDCOLOR\n" "$1";
}

delete_stack () {

    if [[ "$1" == '' ]]
        then
            stack=$STACKNAME
        else
            stack=$1
    fi

    print_style  "Deleting Stack..." "danger"

    aws --profile $PROFILE --region $REGION cloudformation describe-stacks --stack-name "$stack"
    if [[ "$?" != '0' ]]
        then
            #Exit if the stack does not exist
            print_style  "Stack does not exist!" "danger"
            exit 1
    fi

    aws cloudformation delete-stack --stack-name "$stack" --profile $PROFILE --region $REGION 

    print_style  "Check status by running 'cfn $stack' " "info"
    print_style  "For S3 buckets that do not delete due to objects, please run 'aws --profile $PROFILE --region $REGION s3 rb --force s3://BUCKETNAME/'" "info"

    aws --profile $PROFILE --region $REGION cloudformation wait stack-delete-complete --stack-name $stack
}

update_stack () {
    #stack_name, yaml_location, yaml_param_location, profile
    if [[ "$4" == '' ]]
        then
            profile=$PROFILE
        else
            profile=$4
    fi

    print_style  "Updating Stack $1..." "info"
    stackid=$(aws cloudformation update-stack --stack-name "$1" --profile $profile --region $REGION --template-body $2  --parameters "$3" --capabilities CAPABILITY_NAMED_IAM )

    print_style  "$stackid" "warning" 

    aws --profile $profile --region $REGION cloudformation wait stack-update-complete --stack-name $(echo $stackid | jq -r '.StackId')

    if [[ "$?" != '0' ]]
        then
            aws --profile $profile --region $REGION cloudformation describe-stack-events --stack $stackid | jq -r '.StackEvents' | jq -r '.[] | {LogicalResourceId, ResourceStatus, ResourceStatusReason}'
            while true; do
                read -r -p "Issues exist. Enter 1 to delete the stack, 2 to exit, Enter to continue: " answer
                case $answer in
                    [1]* ) delete_stack $stackid; exit 1; break;;
                    [2]* ) exit 1;;
                    "" ) print_style  "Continue..." "info"; break;;
                    * ) echo "Please answer 1, 2, or Enter";;
                esac
            done
    fi

}

create_stack () {
    #stack_name, yaml_location, yaml_param_location, profile
    if [[ "$4" == '' ]]
        then
            profile=$PROFILE
        else
            profile=$4
    fi

    aws --profile $profile --region $REGION cloudformation describe-stacks --stack-name "$1" --max-items 1 

    if [[ "$?" != '0' ]]
        then
            print_style  "Creating Stack $1..." "info"
            stackid=$(aws cloudformation create-stack --stack-name $1 --profile $profile --region $REGION --template-body $2 --capabilities CAPABILITY_NAMED_IAM --parameters "$3")
            # echo $stackid
            # echo $stackid | jq -r '.StackId'
            aws --profile $profile --region $REGION cloudformation wait stack-create-complete --stack-name $(echo $stackid | jq -r '.StackId')

            if [[ "$?" != '0' ]]
                then
                    aws --profile $profile --region $REGION cloudformation describe-stack-events --stack $stackid | jq -r '.StackEvents' | jq -r '.[] | {LogicalResourceId, ResourceStatus, ResourceStatusReason}'
                    while true; do
                        read -r -p "Issues exist. Enter 1 to delete the stack, 2 to exit, Enter to continue: " answer
                        case $answer in
                            [1]* ) delete_stack $1; exit 1; break;;
                            [2]* ) exit 1;;
                            "" ) print_style  "Continue..." "info"; break;;
                            * ) echo "Please answer 1, 2, or Enter";;
                        esac
                    done

            fi
        else
            # read -p "Stack already exists! Enter 1 to update the stack, enter anything else to exit: " policytype && [[ $policytype == [1] ]] || exit 1
            update_stack "$1" "$2" "$3" $profile
    fi

    
}

assume_role () {
    #Set sts credentials Lab 3
    print_style  "Setting credentials" "info"
    creds=$(aws sts assume-role --role-arn arn:aws:iam::324320755747:role/zachroleplzdelete --role-session-name "test" --profile $PROFILE)

    aws configure set aws_access_key_id $(echo $creds | jq -r '.Credentials.AccessKeyId') --profile test
    aws configure set aws_secret_access_key $(echo $creds | jq -r '.Credentials.SecretAccessKey') --profile test
    aws configure set aws_session_token $(echo $creds | jq -r '.Credentials.SessionToken') --profile test
}



if [[ "$1" == 'delete' ]]
    then
        delete_stack
        exit 1
fi

if [[ "$1" == 'sts' ]]
    then
        assume_role
fi

#Set Environment
print_style  "Setting environment" "info"
print_style  "Key Pair Creation" "info"
aws --profile $PROFILE --region $REGION ec2 describe-key-pairs --key-name zacherycox
if [[ "$?" != '0' ]]
    then
        print_style  "Creating Key Pair..." "info"
        chmod 744 ./zacherycox.pem
        aws --profile $PROFILE --region $REGION ec2 create-key-pair --key-name zacherycox | jq -r '.KeyMaterial' > zacherycox.pem
fi
chmod 400 zacherycox.pem

cw_config='''
{
	"agent": {
		"metrics_collection_interval": 60,
		"run_as_user": "root"
	},
	"metrics": {
		"metrics_collected": {
			"collectd": {
				"metrics_aggregation_interval": 60
			},
			"disk": {
				"measurement": [
					"used_percent"
				],
				"metrics_collection_interval": 60,
				"resources": [
					"*"
				]
			},
			"mem": {
				"measurement": [
					"mem_used_percent"
				],
				"metrics_collection_interval": 60
			},
			"statsd": {
				"metrics_aggregation_interval": 60,
				"metrics_collection_interval": 10,
				"service_address": ":8125"
			}
		}
	}
}
'''



windows_ami=$(aws --profile $PROFILE --region $REGION ec2 describe-images --owners 'amazon' --filters 'Name=name,Values=Windows_Server-2012-R2_RTM-English-64Bit-Base*' --query 'sort_by(Images, &CreationDate)[-1].[ImageId]' | jq -r '.[]')

ubuntu_ami=$(aws --profile $PROFILE --region $REGION ec2 describe-images --owners 099720109477 --filters Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-* --query 'sort_by(Images,&CreationDate)[-1].ImageId' | jq -r '.')

this_params=$(cat ./params.json | jq -r ". += [{\"ParameterKey\": \"LinAMI\",\"ParameterValue\": \"$ubuntu_ami\"},{\"ParameterKey\": \"WinAMI\",\"ParameterValue\": \"$windows_ami\"}]")


# echo $ubuntu_ami 
# echo $windows_ami
# echo "$this_params"
create_stack $STACKNAME $YAMLLOCATION "$(echo $this_params)"


#Tests
print_style  "Describe Stack" "info"
aws --profile $PROFILE --region $REGION cloudformation describe-stacks --stack $STACKNAME  | jq -r '.Stacks'

print_style  "Describe Stack Resources" "info"
aws --profile $PROFILE --region $REGION cloudformation describe-stack-resources --stack $STACKNAME | jq -r '.StackResources' | jq -r '.[] | {LogicalResourceId, ResourceType, ResourceStatus, DriftInformation}'

print_style  "Describe Stack Events" "info"
aws --profile $PROFILE --region $REGION cloudformation describe-stack-events --stack $STACKNAME | jq -r '.StackEvents' | jq -r '.[] | {LogicalResourceId, ResourceStatus, ResourceStatusReason}'


this_instances=$(aws --profile $PROFILE --region $REGION cloudformation describe-stack-resources --stack $STACKNAME | jq -r '.StackResources' | jq -r '.[] | select(.ResourceType=="AWS::EC2::Instance") | .PhysicalResourceId')

print_style  "Describe EC2 Instance" "info"
for i in $this_instances
do
    aws --profile $PROFILE --region $REGION ec2 describe-instances --instance-ids $i | jq -r '.Reservations | .[].Instances | .[]' 
    echo "\n"
    sgs=$(aws --profile $PROFILE --region $REGION ec2 describe-instances --instance-ids $i | jq -r '.Reservations | .[].Instances | .[].SecurityGroups' | jq -r '.[].GroupId')
    print_style  "\nSecurity Group" "info"
    for j in $sgs
        do
            aws --profile $PROFILE --region $REGION ec2 describe-security-groups --group-ids $j | jq -r '.SecurityGroups | .[] | {GroupName, Description, GroupId, VpcId, IpPermissions, IpPermissionsEgress}'
            echo "\n"
    done

done


eip=$(aws --profile $PROFILE --region $REGION cloudformation describe-stacks --stack-name $STACKNAME --max-items 1 | jq -r '.[]' | jq -r '.[].Outputs'| jq -r '.[] | select(.OutputKey=="EIP") | .OutputValue')

ping -c 4 $eip

# ssh ubuntu@$eip -i ./zacherycox.pem

read -p "Complete: Enter 1 to delete stack, anything else to exit: " policytype && [[ $policytype == [1] ]] || exit 1

# aws --profile $PROFILE --region $REGION ssm delete-parameter --name AmazonCloudWatch-ZachTest

print_style  "Deleting Key Pair" "info"
aws --profile $PROFILE --region $REGION ec2 delete-key-pair --key-name zacherycox
rm -rf ./zacherycox.pem
delete_stack

