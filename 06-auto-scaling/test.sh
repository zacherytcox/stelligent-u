#!/bin/bash


#Set parameters
YAMLLOCATION="file:///Users/zachery.cox/Documents/Code/Github/stelligent-u/06-auto-scaling/asg.yaml"
YAMLPARAMSLOCATION="file:///Users/zachery.cox/Documents/Code/Github/stelligent-u/06-auto-scaling/params.json"
STACKNAME="lab6-zach"
REGION="us-east-1"
PROFILE="labs-mfa"


#automate todo
# Launch template version. get latest and add it as a parameter
# determine if an EC2 instance is created and if it is, create ssh key
# determine if S3 buckets are being deleted, if so, empty them.



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
    #Dark Grey
    elif [ "$2" == "background" ] ; then
        COLOR="1;30m";
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

package_check () {
    aws --version;aws=$?
    if [[ "$aws" != '0' ]]
        then
            print_style "aws is not installed! Please install and try again." "danger"
            exit 1
        else
            print_style "aws installed" "success"
    fi


    jq --version;jq=$?
    if [[ "$jq" != '0' ]]
        then
            print_style "jq is not installed! Please install and try again." "danger"
            exit 1
        else
            print_style "jq installed" "success"
    fi
}

#Delete CloudFormation Stack
delete_stack () {

    if [[ "$1" == '' ]]
        then
            stack=$STACKNAME
        else
            stack=$1
    fi

    print_style  "Deleting Key Pair" "background"
    aws --profile $PROFILE --region $REGION ec2 delete-key-pair --key-name zacherycox
    rm -rf ./zacherycox.pem

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

#Update CloudFormation Stack
update_stack () {
    #stack_name, yaml_location, yaml_param_location, profile
    if [[ "$4" == '' ]]
        then
            profile=$PROFILE
        else
            profile=$4
    fi

 
    print_style  "Updating Stack $1..." "info"
    stackid=$(aws cloudformation update-stack --stack-name "$1" --profile $profile --region $REGION --template-body $2  --parameters "$3" --capabilities CAPABILITY_NAMED_IAM | jq -r '.StackId')

    aws --profile $profile --region $REGION cloudformation wait stack-update-complete --stack-name $stackid
    if [[ "$?" != '0' ]]
        then
            print_style  "$(aws --profile $profile --region $REGION cloudformation describe-stacks --stack $STACKNAME | jq -r '.Stacks | .[].StackStatus')" "info"

            aws --profile $profile --region $REGION cloudformation describe-stack-events --stack $stackid | jq -r '.StackEvents' | jq -r '.[] | {LogicalResourceId, ResourceStatus, ResourceStatusReason}'

            status=$(aws --profile $profile --region $REGION cloudformation describe-stacks --stack $STACKNAME | jq -r '.Stacks | .[].StackStatus')

            while true; do
                read -r -p "[$status] Issues exist. Enter 1 to delete the stack, 2 to try updating, 3 to exit, Enter to continue: " answer
                case $answer in
                    [1]* ) delete_stack $stackid; exit 1; break;;
                    [2]* ) update_stack "$1" "$2" "$3" $profile; break;;
                    [3]* ) exit 1;;
                    "" ) print_style  "Continue..." "background"; break;;
                    * ) echo "Please answer 1, 2, or Enter";;
                esac
            done
    fi

}

#Create CloudFormation Stack
create_stack () {
    #stack_name, yaml_location, yaml_param_location, profile
    if [[ "$4" == '' ]]
        then
            profile=$PROFILE
        else
            profile=$4
    fi

    print_style  "Key Pair Creation" "background"
    aws --profile $PROFILE --region $REGION ec2 describe-key-pairs --key-name zacherycox
    if [[ "$?" != '0' ]]
        then
            print_style  "Creating Key Pair..." "background"
            chmod 744 ./zacherycox.pem
            aws --profile $PROFILE --region $REGION ec2 create-key-pair --key-name zacherycox | jq -r '.KeyMaterial' > zacherycox.pem
    fi
    chmod 400 zacherycox.pem

    aws --profile $profile --region $REGION cloudformation describe-stacks --stack-name "$1" --max-items 1 

    if [[ "$?" != '0' ]]
        then
            print_style  "Creating Stack $1..." "info"
            stackid=$(aws cloudformation create-stack --stack-name $1 --profile $profile --region $REGION --template-body $2 --capabilities CAPABILITY_NAMED_IAM --parameters "$3")

            aws --profile $profile --region $REGION cloudformation wait stack-create-complete --stack-name $(echo $stackid | jq -r '.StackId')


            if [[ "$?" != '0' ]]
                then
                    aws --profile $profile --region $REGION cloudformation describe-stack-events --stack $stackid | jq -r '.StackEvents' | jq -r '.[] | {LogicalResourceId, ResourceStatus, ResourceStatusReason}'

                    status=$(aws --profile $profile --region $REGION cloudformation describe-stacks --stack $STACKNAME | jq -r '.Stacks | .[].StackStatus')

                    if [[ "$status" == 'ROLLBACK_COMPLETE' ]]
                        then
                            print_style  "Stack $1 Failed! Deleting and exiting..." "danger"
                            delete_stack $1; exit 1
                    fi

                    while true; do
                        read -r -p "[$status] Issues exist. Enter 1 to delete the stack, 2 to try updating, 3 to exit, Enter to continue: " answer
                        case $answer in
                            [1]* ) delete_stack $1; exit 1; break;;
                            [2]* ) update_stack "$1" "$2" "$3" $profile; break;;
                            [3]* ) exit 1;;
                            "" ) print_style  "Continue..." "background"; break;;
                            * ) echo "Please answer 1, 2, 3, or Enter";;
                        esac
                    done

            fi
        else
            print_style  "Stack $1 already exists! Updating stack..." "info"
            update_stack "$1" "$2" "$3" $profile
    fi

}

#Set sts credentials Lab 3
assume_role () {
    
    print_style  "Setting credentials" "background"
    creds=$(aws sts assume-role --role-arn arn:aws:iam::324320755747:role/zachroleplzdelete --role-session-name "test" --profile $PROFILE)

    aws configure set aws_access_key_id $(echo $creds | jq -r '.Credentials.AccessKeyId') --profile test
    aws configure set aws_secret_access_key $(echo $creds | jq -r '.Credentials.SecretAccessKey') --profile test
    aws configure set aws_session_token $(echo $creds | jq -r '.Credentials.SessionToken') --profile test
}

#Performs tasks before tests can be performed
init () {
    :
}

#Perform Tests after stack creation
tests () {

    # print_style  "Describe Stack" "info"
    # aws --profile $PROFILE --region $REGION cloudformation describe-stacks --stack $STACKNAME  | jq -r '.Stacks'

    # print_style  "Describe Stack Resources" "info"
    # aws --profile $PROFILE --region $REGION cloudformation describe-stack-resources --stack $STACKNAME | jq -r '.StackResources' | jq -r '.[] | {LogicalResourceId, ResourceType, ResourceStatus, DriftInformation}'

    # print_style  "Describe Stack Events" "info"
    # aws --profile $PROFILE --region $REGION cloudformation describe-stack-events --stack $STACKNAME | jq -r '.StackEvents' | jq -r '.[] | {LogicalResourceId, ResourceStatus, ResourceStatusReason}'

    this_asg=$(aws --profile $PROFILE --region $REGION cloudformation describe-stack-resources --stack-name $STACKNAME | jq -r '.StackResources | .[] | select(.ResourceType=="AWS::AutoScaling::AutoScalingGroup") | .PhysicalResourceId')
    
    this_instances=$(aws --profile $PROFILE --region $REGION autoscaling describe-auto-scaling-groups --auto-scaling-group-names $this_asg | jq -r '.AutoScalingGroups | .[] | .Instances | .[].InstanceId')

    print_style "$this_instances" "info"

    this_instance=`echo "${this_instances}" | head -1`


    # First test
    # aws --profile $PROFILE --region $REGION autoscaling enter-standby --instance-ids $this_instance --auto-scaling-group-name $this_asg --should-decrement-desired-capacity

    # aws --profile $PROFILE --region $REGION autoscaling describe-auto-scaling-instances --instance-ids $this_instance

    # read -p "Test 1. Press anything to continue" temp && [[ $temp == [1] ]]

    # aws --profile $PROFILE --region $REGION autoscaling exit-standby --instance-ids $this_instance --auto-scaling-group-name $this_asg   



    #Second test
    aws --profile $PROFILE --region $REGION autoscaling suspend-processes --auto-scaling-group-name $this_asg --scaling-processes Launch


    aws --profile $PROFILE --region $REGION autoscaling enter-standby --instance-ids $this_instance --auto-scaling-group-name $this_asg --should-decrement-desired-capacity

    aws --profile $PROFILE --region $REGION autoscaling describe-auto-scaling-instances --instance-ids $this_instance

    read -p "Test 2. Press anything to continue" temp && [[ $temp == [1] ]]

    aws --profile $PROFILE --region $REGION autoscaling resume-processes --auto-scaling-group-name $this_asg --scaling-processes Launch

    aws --profile $PROFILE --region $REGION autoscaling exit-standby --instance-ids $this_instance --auto-scaling-group-name $this_asg  








    # aws --profile $PROFILE --region $REGION ec2 terminate-instances --instance-ids $this_instances

    # while true; do
    #     print_style "$(aws --profile $PROFILE --region $REGION autoscaling describe-auto-scaling-groups --auto-scaling-group-names $this_asg | jq -r '.AutoScalingGroups | .[] | .Instances | .[].InstanceId')" "info"
    #     read -r -p "Enter 1 exit loop or Enter to try CLI call again: " answer
    #     case $answer in
    #         [1]* ) break;;
    #         "" ) : ;;
    #         * ) print_style  "Please answer 1 or Enter" "danger";;
    #     esac
    # done


    # this_instances=$(aws --profile $PROFILE --region $REGION cloudformation describe-stack-resources --stack $STACKNAME | jq -r '.StackResources' | jq -r '.[] | select(.ResourceType=="AWS::EC2::Instance") | .PhysicalResourceId')

    # print_style  "Describe EC2 Instance" "info"
    # for i in $this_instances
    # do
    #     aws --profile $PROFILE --region $REGION ec2 describe-instances --instance-ids $i | jq -r '.Reservations | .[].Instances | .[]' 
    #     echo "\n"
    #     sgs=$(aws --profile $PROFILE --region $REGION ec2 describe-instances --instance-ids $i | jq -r '.Reservations | .[].Instances | .[].SecurityGroups' | jq -r '.[].GroupId')
    #     print_style  "\nSecurity Group" "info"
    #     for j in $sgs
    #         do
    #             aws --profile $PROFILE --region $REGION ec2 describe-security-groups --group-ids $j | jq -r '.SecurityGroups | .[] | {GroupName, Description, GroupId, VpcId, IpPermissions, IpPermissionsEgress}'
    #             echo "\n"
    #     done

    # done

    # aws --profile labs-mfa --region us-east-1 autoscaling create-auto-scaling-group --auto-scaling-group-name lab6-zach  --instance-id i-088f9c2958b055832 --min-size 1 --max-size 1



    # eip=$(aws --profile $PROFILE --region $REGION cloudformation describe-stacks --stack-name $STACKNAME --max-items 1 | jq -r '.[]' | jq -r '.[].Outputs'| jq -r '.[] | select(.OutputKey=="EIP") | .OutputValue')

    # ping -c 4 $eip

    # ssh admin@$eip -i ./zacherycox.pem


    print_style  "Test Complete!" "success"

}

#Script Start
package_check

#Function to delete all stacks
if [[ "$1" == 'delete' ]]
    then
        delete_stack; exit 1
fi

#Function to add the assume_role to logic
if [[ "$1" == 'sts' ]]
    then
        assume_role
fi


#Main Loop
while true; do
    create_stack $STACKNAME $YAMLLOCATION $YAMLPARAMSLOCATION
    tests
    read -r -p "Enter 1 to delete the stack, 2 to update stack + test again, Enter to exit: " answer
    case $answer in
        [1]* ) delete_stack; exit 1;;
        [2]* ) : ;;
        "" ) exit 1;;
        * ) print_style  "Please answer 1, 2, or Enter" "danger";;
    esac
done