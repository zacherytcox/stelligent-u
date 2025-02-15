#!/bin/bash


#Set parameters
YAMLLOCATION="file:///Users/zachery.cox/Documents/Code/Github/stelligent-u/11-parameter-store/ps.yaml"
YAMLPARAMSLOCATION="file:///Users/zachery.cox/Documents/Code/Github/stelligent-u/11-parameter-store/params.json"
STACKNAME="lab11-zach"
REGION="us-east-1"
PROFILE="labs-mfa"
LOCAL_STATE="./.test.state.txt"

#automate todo
# Launch template version. get latest and add it as a parameter
# determine if an EC2 instance is created and if it is, create ssh key
# If there is an asg, push a refresh



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

add_state (){
    #key, value
    print_style "$(cat $LOCAL_STATE)" "background" 
    echo $(cat $LOCAL_STATE | jq ". + {\"$1\": \"$2\"}") > $LOCAL_STATE
    print_style "$(cat $LOCAL_STATE)" "background" 
}

remove_state (){
    #key
    print_style "$(cat $LOCAL_STATE)" "background" 
    echo $(cat $LOCAL_STATE | jq -r "del(.$1)") > $LOCAL_STATE
    print_style "$(cat $LOCAL_STATE)" "background" 
}

get_state (){
    #key
    echo $(cat $LOCAL_STATE | jq -r ".$1")
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

#Performs tasks before tests can be performed
create_tls_cert () {
    print_style  "TLS Cert Creation" "background"
    openssl req -newkey rsa:2048 -nodes -keyout key.pem -x509 -days 365 -out certificate.pem -subj "/C=''/ST=''/L=''/O=''/OU=''/CN=*.amazonaws.com"
    openssl pkcs12 -inkey key.pem -in certificate.pem -export -out certificate.p12

    add_state cert "$(aws --profile $PROFILE --region $REGION acm import-certificate --certificate fileb://Certificate.pem --private-key fileb://Key.pem --tags Key=Name,Value=$STACKNAME | jq -r '.CertificateArn')"


}

#Performs tasks before tests can be performed
init () {
    
    print_style  "Creating local state file..." "background"
    if [ -f "$LOCAL_STATE" ];
        then
            print_style  "local state file exists." "background"
        else 
            echo "{}" > $LOCAL_STATE
    fi


    print_style  "Key Pair Creation..." "background"

    # Temp
    print_style  "Creating Key Pair..." "background"
    chmod 744 ./zacherycox.pem
    aws --profile $PROFILE --region $REGION ec2 create-key-pair --key-name zacherycox | jq -r '.KeyMaterial' > zacherycox.pem
    chmod 400 zacherycox.pem
    
    this_file="${YAMLLOCATION:7}"
    ec2=$(cat $this_file | grep -i "AWS::EC2::Instance")
    if [[ "$ec2" != '' ]]
        then
            aws --profile $PROFILE --region $REGION ec2 describe-key-pairs --key-name zacherycox
            if [[ "$?" != '0' ]]
                then
                    print_style  "Creating Key Pair..." "background"
                    chmod 744 ./zacherycox.pem
                    aws --profile $PROFILE --region $REGION ec2 create-key-pair --key-name zacherycox | jq -r '.KeyMaterial' > zacherycox.pem
            fi
            chmod 400 zacherycox.pem
        else
            print_style  "No EC2 Instances Specified! Key Pair Creation Skipped..." "background"
    fi
    

    # read -r -p "Enter 1 to create a TLS cert or Enter to continue: " answer
    # case $answer in
    #     [1]* ) create_tls_cert;;
    #     "" ) print_style  "TLS Cert Not Created..." "background";;
    #     * ) print_style  "Please answer 1 or Enter" "danger";;
    # esac

}

#Deletes resources created by the init
init_delete () {
    print_style  "Deleting Key Pair" "background"
    aws --profile $PROFILE --region $REGION ec2 delete-key-pair --key-name zacherycox
    rm -rf ./zacherycox.pem

    print_style  "Deleting Self-Signed TLS Cert" "background"    
    rm -rf ./certificate* ./key.pem
    aws --profile $PROFILE --region $REGION acm delete-certificate --certificate-arn "$(get_state cert)"


    print_style  "Deleting Local State File" "background" 
    rm $LOCAL_STATE


    print_style  "Emptying S3 Buckets..." "background" 
    these_buckets=$(aws --profile $PROFILE --region $REGION cloudformation describe-stack-resources --stack $STACKNAME | jq -r '.StackResources' | jq -r '.[] | select(.ResourceType=="AWS::S3::Bucket") | .PhysicalResourceId')

    for i in $these_buckets
        do
            aws --profile $PROFILE --region $REGION s3 rb --force s3://$i/
        done

}

#Delete CloudFormation Stack
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

    aws --profile $PROFILE --region $REGION cloudformation wait stack-delete-complete --stack-name $stack
}

get_stack_issue () {
    #Stack name
    print_style  "[$1]Stack Issue Info:" "danger"
    aws --profile $PROFILE --region $REGION cloudformation describe-stack-events --stack $1 | jq -r '.StackEvents | .[] | select((.ResourceStatus=="CREATE_FAILED") or .ResourceStatus=="UPDATE_FAILED") | {LogicalResourceId, ResourceStatus, ResourceStatusReason}'
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
            get_stack_issue $1
            status=$(aws --profile $profile --region $REGION cloudformation describe-stacks --stack $1 | jq -r '.Stacks | .[].StackStatus')

            while true; do
                read -r -p "[$status] Issues exist. Enter 1 to delete the stack, 2 to try updating, 3 to exit, Enter to continue: " answer
                case $answer in
                    [1]* ) delete_stack "$1"; exit 1; break;;
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

    aws --profile $profile --region $REGION cloudformation describe-stacks --stack-name "$1" --max-items 1 

    if [[ "$?" != '0' ]]
        then
            print_style  "Creating Stack $1..." "info"
            stackid=$(aws cloudformation create-stack --stack-name $1 --profile $profile --region $REGION --template-body $2 --capabilities CAPABILITY_NAMED_IAM --parameters "$3")

            aws --profile $profile --region $REGION cloudformation wait stack-create-complete --stack-name $(echo $stackid | jq -r '.StackId')


            if [[ "$?" != '0' ]]
                then
                    get_stack_issue $1
                    status=$(aws --profile $profile --region $REGION cloudformation describe-stacks --stack $1 | jq -r '.Stacks | .[].StackStatus')

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

#Troubleshoot Cloud-init
troubleshoot_init () {
    #instance-id, public ip

    if [[ "$1" == '' ]]
        then
            print_style  "IP is blank! Error! [$1]" "danger"
            exit 1
    fi

    print_style  "Troubleshooting Cloud-init [$1]" "info"

    while true; do
        ssh -i zacherycox.pem ec2-user@$1 'systemctl | grep -i "cloud-final.service"'
        read -r -p "Enter 1 exit loop or Enter to try call again: " answer
        case $answer in
            [1]* ) break;;
            "" ) : ;;
            * ) print_style  "Please answer 1 or Enter" "danger";;
        esac
    done
    while true; do
        ssh -i zacherycox.pem ec2-user@$1 'sudo cat /var/log/cloud-init.log'
        read -r -p "Enter 1 exit loop or Enter to try call again: " answer
        case $answer in
            [1]* ) break;;
            "" ) : ;;
            * ) print_style  "Please answer 1 or Enter" "danger";;
        esac
    done
    while true; do
        ssh -i zacherycox.pem ec2-user@$1 'sudo cat /var/lib/cloud/instance/scripts/part-001'
        read -r -p "Enter 1 exit loop or Enter to try call again: " answer
        case $answer in
            [1]* ) break;;
            "" ) : ;;
            * ) print_style  "Please answer 1 or Enter" "danger";;
        esac
    done
    while true; do
        ssh -i zacherycox.pem ec2-user@$1 ' sudo /opt/aws/bin/cfn-init -v --stack lab7-zach --resource WebServersLC --configsets ascending --region us-east-1'
        read -r -p "Enter 1 exit loop or Enter to try call again: " answer
        case $answer in
            [1]* ) break;;
            "" ) : ;;
            * ) print_style  "Please answer 1 or Enter" "danger";;
        esac
    done
    print_style  "Finished troubleshooting Cloud-init [$1]" "success"
}

#Perform Tests after stack creation
tests () {

    #Lab 11.1.2
    print_style "$(aws --profile $PROFILE --region $REGION ssm get-parameters-by-path --path /zachery.cox.labs/stelligent-u/lab11)\n" "info" 

    this_alias=$(aws --profile $PROFILE --region $REGION cloudformation describe-stack-resources --stack $STACKNAME | jq -r '.StackResources' | jq -r '.[] | select(.ResourceType=="AWS::KMS::Alias") | .PhysicalResourceId')

    aws --profile $PROFILE --region $REGION ssm put-parameter --name "/zachery.cox.labs/stelligent-u/lab11/middlename" --value "Papa" --type "SecureString" --tier Advanced --key-id $this_alias

    
    this_YAMLPARAMSLOCATION="file:///Users/zachery.cox/Documents/Code/Github/stelligent-u/11-parameter-store/params2.json"
    this_YAMLLOCATION="file:///Users/zachery.cox/Documents/Code/Github/stelligent-u/11-parameter-store/asg.yaml"

    create_stack "$STACKNAME-2" "$this_YAMLLOCATION" "$this_YAMLPARAMSLOCATION"

    #Lab 7 Tests

    this_asg_name=$(aws --profile $PROFILE --region $REGION autoscaling describe-auto-scaling-groups | jq -r '.AutoScalingGroups | .[] | select(.LaunchConfigurationName=="SimpleWebServerLC-zach") | .AutoScalingGroupName')
    # aws --profile $PROFILE --region $REGION autoscaling start-instance-refresh --auto-scaling-group-name $this_asg_name --preferences '{"InstanceWarmup": 0, "MinHealthyPercentage": 0}'
    sleep 15
    this_instance_id=$(aws --profile $PROFILE --region $REGION autoscaling describe-auto-scaling-groups | jq -r '[.AutoScalingGroups | .[] | select(.LaunchConfigurationName=="SimpleWebServerLC-zach") | .Instances | .[] | select((.LifecycleState=="Pending") or .LifecycleState=="InService") | .InstanceId][0]')

    this_instance_pub_ip=$(aws --profile $PROFILE --region $REGION ec2 describe-instances --instance-ids $this_instance_id | jq -r '.Reservations | .[] | .Instances | .[].PublicIpAddress')

    print_style  "Waiting 60 seconds for Nginx to launch. May take longer..." "warning"
    sleep 60

    while true; do
        this_response=$(curl $this_instance_pub_ip)
        this_status=$(ssh -i zacherycox.pem ec2-user@$this_instance_pub_ip 'systemctl status nginx | grep -i "Active: active (running)"')
        echo $this_response $this_status
        if [[ "$this_response" != '<p>Automation for the People</p>' ]]
            then
                print_style  "Waiting for NGINX to launch...\n $this_status" "background"
                sleep 3
            else
                print_style "NGINX is up!" "success"
                break
        fi
        read -r -p "Enter 1 to finish, 2 to troubleshoot init, 3 to exit, Enter to try call again: " answer
        case $answer in
            [1]* ) break;;
            [2]* ) troubleshoot_init $this_instance_pub_ip; break;;
            [3]* ) exit 1; break;;
            "" ) : ;;
            * ) print_style  "Please answer 1, 2, 3, or Enter" "danger";;
        esac
    done

    this_elb=$(aws --profile labs-mfa --region us-east-1 cloudformation describe-stack-resources --stack "$STACKNAME-2" | jq -r '.StackResources' | jq -r '.[] | select(.LogicalResourceId=="ALB") | .PhysicalResourceId')

    elb_dns=$(aws --profile labs-mfa --region us-east-1 elbv2 describe-load-balancers --load-balancer-arns "$this_elb" | jq -r '.LoadBalancers | .[] | .DNSName')

    print_style  "ELB Curl:" "info"
    curl $elb_dns


    while true; do
        read -r -p "Enter 1 to delete stack,  3 to exit, Enter to continue: " answer
        case $answer in
            [1]* ) delete_stack "$STACKNAME-2"; break;;
            [3]* ) exit 1; break;;
            "" ) break;;
            * ) print_style  "Please answer 1, 3, or Enter" "danger";;
        esac
    done

    aws --profile $PROFILE --region $REGION ssm delete-parameter --name "/zachery.cox.labs/stelligent-u/lab11/middlename"



    #Lab 10
    # this_alias=$(aws --profile $PROFILE --region $REGION cloudformation describe-stack-resources --stack $STACKNAME | jq -r '.StackResources' | jq -r '.[] | select(.ResourceType=="AWS::KMS::Alias") | .PhysicalResourceId')
    # this_key_id=$(aws --profile $PROFILE --region $REGION cloudformation describe-stack-resources --stack $STACKNAME | jq -r '.StackResources' | jq -r '.[] | select(.ResourceType=="AWS::KMS::Key") | .PhysicalResourceId')
    # # echo $this_alias
    # # echo $this_key_id

    # aws --profile $PROFILE --region $REGION kms encrypt --key-id $this_alias --plaintext fileb://./secret.txt --output text --query CiphertextBlob | base64 --decode > ExampleEncryptedFile

    # print_style "$(cat ./ExampleEncryptedFile)" "danger"

    # aws --profile $PROFILE --region $REGION kms decrypt --ciphertext-blob fileb://./ExampleEncryptedFile --key-id $this_alias --output text --query Plaintext | base64 --decode > ExamplePlaintextFile.txt
    # cat ./ExamplePlaintextFile.txt
    # echo "\n\n"

    # rm ./ExamplePlaintextFile.txt ./ExampleEncryptedFile

    # this_bucket=$(aws --profile $PROFILE --region $REGION cloudformation describe-stack-resources --stack $STACKNAME | jq -r '.StackResources' | jq -r '.[] | select(.ResourceType=="AWS::S3::Bucket") | .PhysicalResourceId')


    # print_style "Ruby:\n" "warning"
    # ruby ./kms.rb "$this_alias" "$this_bucket"

    # cat ./test-final.txt

    # read -r -p "Enter to continue... " answer

    # rm ./test-*.txt


    # 9.1.3
    # this_stack=zachstackname$RANDOM
    # this_bucket=zachs3buckettesting$RANDOM
    # aws --profile $PROFILE --region $REGION s3api create-bucket --bucket $this_bucket
    
    # aws --profile $PROFILE --region $REGION cloudformation package --template-file ./lambda.yaml --s3-bucket $this_bucket --output-template-file packaged-template.json

    # if [[ "$?" == '0' ]]
    #     then
    #         aws --profile $PROFILE --region $REGION cloudformation deploy --template-file ./packaged-template.json --stack-name $this_stack --capabilities CAPABILITY_NAMED_IAM --parameter-overrides "$YAMLPARAMSLOCATION"
    #     else
    #         print_style "$?" "danger"
    # fi


    # tmp=$RANDOM

    # api_resource_id=$(aws --profile $PROFILE --region $REGION cloudformation describe-stacks --stack $this_stack  | jq -r '.Stacks | .[] | .Outputs | .[] | select(.OutputKey=="APIGatewayResourceId") | .OutputValue')

    # api_id=$(aws --profile $PROFILE --region $REGION cloudformation describe-stacks --stack $this_stack  | jq -r '.Stacks | .[] | .Outputs | .[] | select(.OutputKey=="APIGatewayID") | .OutputValue')

    # this_response=$(aws --profile $PROFILE --region $REGION apigateway test-invoke-method --rest-api-id $api_id --resource-id $api_resource_id --http-method POST --path-with-query-string '/' --body $tmp)

    # print_style "Test 1 Results: $(echo $this_response | grep "WORKS!!!") \n\n\n" "info"
    # print_style "Test 2 Results: $(echo $this_response | grep "$tmp")" "info"


    

    # read -r -p "Enter to continue... " answer


    # rm ./packaged-template.json
    # aws --profile $PROFILE --region $REGION s3 rb --force s3://$this_bucket/
    # delete_stack $this_stack

    # #9.1.2
    # tmp=$RANDOM
    # this_bucket=zachs3buckettesting$RANDOM
    # aws --profile $PROFILE --region $REGION s3api create-bucket --bucket $this_bucket

    # api_resource_id=$(aws --profile $PROFILE --region $REGION cloudformation describe-stacks --stack $STACKNAME  | jq -r '.Stacks | .[] | .Outputs | .[] | select(.OutputKey=="APIGatewayResourceId") | .OutputValue')

    # api_id=$(aws --profile $PROFILE --region $REGION cloudformation describe-stacks --stack $STACKNAME  | jq -r '.Stacks | .[] | .Outputs | .[] | select(.OutputKey=="APIGatewayID") | .OutputValue')

    # this_table=$(aws --profile $PROFILE --region $REGION cloudformation describe-stack-resources --stack $STACKNAME | jq -r '.StackResources' | jq -r '.[] | select(.ResourceType=="AWS::DynamoDB::Table") | .PhysicalResourceId')

    # print_style "Items in Table: $(aws --profile $PROFILE --region $REGION dynamodb scan --table-name $this_table)" "warning"

    # this_response=$(aws --profile $PROFILE --region $REGION apigateway test-invoke-method --rest-api-id $api_id --resource-id $api_resource_id --http-method POST --path-with-query-string '/' --body '{"Artist":{"S":"Testauto2"},"NumberOfSongs":{"N":"267"}}')

    # print_style "Test 1 Results: $(echo $this_response | grep "WORKS!!!") \n\n" "info"
    # print_style "Test 2 Results: $(echo $this_response | grep "Testauto2") \n\n" "info"
    # print_style "Test 3 Results: $(echo $this_response | grep "ThisTest") \n\n" "info"


    # print_style "Items in Table: $(aws --profile $PROFILE --region $REGION dynamodb scan --table-name $this_table)" "warning"

    # while true; do
    #     read -r -p "Enter 1 to finish test, Enter to run tests: " answer
    #     case $answer in
    #         [1]* ) break ;;
    #         "" ) aws --profile $PROFILE --region $REGION s3api put-object --bucket $this_bucket --key $RANDOM.txt --body ./params.json; sleep 5; print_style "Items in Table: $(aws --profile $PROFILE --region $REGION dynamodb scan --table-name $this_table)" "warning"  ;;
    #         * ) print_style  "Please answer 1 or Enter" "danger";;
    #     esac
    # done
    
    # aws --profile $PROFILE --region $REGION s3 rb --force s3://$this_bucket/


    # print_style  "Waiting 30 seconds..." "warning"
    # sleep 30    

    # this_stack_name=$(echo $STACKNAME-2)
    # this_yaml_location="file:///Users/zachery.cox/Documents/Code/Github/stelligent-u/08-cloudwatch-logs/cw2.yaml"
    # create_stack $this_stack_name $this_yaml_location $YAMLPARAMSLOCATION

    # sleep 15  


    # this_log_group=$(aws --profile $PROFILE --region $REGION cloudformation describe-stack-resources --stack $STACKNAME | jq -r '.StackResources' | jq -r '.[] | select(.ResourceType=="AWS::Logs::LogGroup") | .PhysicalResourceId')

    # while true; do
    #     read -r -p "Enter 1 to finish test, 2 to delete stack, Enter to run tests: " answer
    #     case $answer in
    #         [1]* ) break ;;
    #         [2]* ) delete_stack $this_stack_name ;;
    #         "" ) awslogs get $this_log_group --profile $PROFILE --aws-region $REGION --start='10 minutes' | grep -i "zachery.cox.labs"; awslogs get $this_log_group --profile $PROFILE --aws-region $REGION --start='5 minutes' | grep -i "zachery.cox.labs" | jq -r '.'  ;;
    #         * ) print_style  "Please answer 1, 2, or Enter" "danger";;
    #     esac
    # done

    


    # aws --profile $PROFILE --region $REGION logs put-retention-policy --log-group-name "zach.cox.c9logs" --retention-in-days 3653


    # this_ip=$(aws --profile $PROFILE --region $REGION ec2 describe-instances --instance-ids $(aws --profile $PROFILE --region $REGION cloudformation describe-stack-resources --stack $STACKNAME | jq -r '.StackResources' | jq -r '.[] | select(.ResourceType=="AWS::EC2::Instance") | .PhysicalResourceId') | jq -r '.Reservations | .[].Instances | .[] | .PublicIpAddress')
    
    # ssh ubuntu@$this_ip -i ./zacherycox.pem "amazon-cloudwatch-agent-ctl -a status"
    # ssh ubuntu@$this_ip -i ./zacherycox.pem


    #wait for 2mins
    # print_style  "Waiting 120 seconds..." "warning"
    # sleep 120

    # this_asg_name=$(aws --profile $PROFILE --region $REGION autoscaling describe-auto-scaling-groups | jq -r '.AutoScalingGroups | .[] | select(.LaunchConfigurationName=="SimpleWebServerLC-zach") | .AutoScalingGroupName')
    # # aws --profile $PROFILE --region $REGION autoscaling start-instance-refresh --auto-scaling-group-name $this_asg_name --preferences '{"InstanceWarmup": 0, "MinHealthyPercentage": 0}'
    # sleep 15
    # this_instance_id=$(aws --profile $PROFILE --region $REGION autoscaling describe-auto-scaling-groups | jq -r '[.AutoScalingGroups | .[] | select(.LaunchConfigurationName=="SimpleWebServerLC-zach") | .Instances | .[] | select((.LifecycleState=="Pending") or .LifecycleState=="InService") | .InstanceId][0]')

    # this_instance_pub_ip=$(aws --profile $PROFILE --region $REGION ec2 describe-instances --instance-ids $this_instance_id | jq -r '.Reservations | .[] | .Instances | .[].PublicIpAddress')

    # # print_style  "Waiting 60 seconds for Nginx to launch. May take longer..." "warning"
    # # sleep 60

    # while true; do
    #     this_response=$(curl $this_instance_pub_ip)
    #     this_status=$(ssh -i zacherycox.pem ec2-user@$this_instance_pub_ip 'systemctl status nginx | grep -i "Active: active (running)"')
    #     echo $this_response $this_status
    #     if [[ "$this_response" != '<p>Automation for the People</p>' ]]
    #         then
    #             print_style  "Waiting for NGINX to launch...\n $this_status" "background"
    #             sleep 3
    #         else
    #             print_style "NGINX is up!" "success"
    #             break
    #     fi
    #     read -r -p "Enter 1 to finish, 2 to troubleshoot init, 3 to exit, Enter to try call again: " answer
    #     case $answer in
    #         [1]* ) break;;
    #         [2]* ) troubleshoot_init $this_instance_pub_ip; break;;
    #         [3]* ) exit 1; break;;
    #         "" ) : ;;
    #         * ) print_style  "Please answer 1, 2, 3, or Enter" "danger";;
    #     esac
    # done

    # this_elb=$(aws --profile labs-mfa --region us-east-1 cloudformation describe-stack-resources --stack lab7-zach | jq -r '.StackResources' | jq -r '.[] | select(.LogicalResourceId=="ALB") | .PhysicalResourceId')

    # elb_dns=$(aws --profile labs-mfa --region us-east-1 elbv2 describe-load-balancers --load-balancer-arns "$this_elb" | jq -r '.LoadBalancers | .[] | .DNSName')

    # print_style  "ELB Curl:" "info"
    # curl $elb_dns



    print_style  "Test Complete!" "success"

}

#Script Start
package_check

#Function to just run tests
if [[ "$1" == 't' ]]
    then
        while true; do
            tests
            read -r -p "Enter 1 to delete the stack, 2 to exit, Enter to test again: [To make changes, please exit and run tests again without 't' flag!]" answer
            case $answer in
                [1]* ) init_delete; delete_stack; exit 1;;
                [2]* ) exit 1 ;;
                "" ) : ;;
                * ) print_style  "Please answer 1, 2, or Enter" "danger";;
            esac
        done
fi

#Function to delete all stacks
if [[ "$1" == 'delete' ]]
    then
        init_delete; delete_stack; exit 1
fi

#Function to add the assume_role to logic
if [[ "$1" == 'sts' ]]
    then
        assume_role
fi


#Main Loop
while true; do
    init
    create_stack $STACKNAME $YAMLLOCATION $YAMLPARAMSLOCATION
    tests
    read -r -p "Enter 1 to delete the stack, 2 to update stack + test again, Enter to exit: " answer
    case $answer in
        [1]* ) init_delete; delete_stack; exit 1;;
        [2]* ) : ;;
        "" ) exit 1;;
        * ) print_style  "Please answer 1, 2, or Enter" "danger";;
    esac
done