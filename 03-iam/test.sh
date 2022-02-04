#!/bin/bash

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


#Set parameters
YAMLLOCATION="file:///Users/zachery.cox/Documents/Code/Github/stelligent-u/03-iam/lab3-3.yaml"
STACKNAME="lab3-zach"
REGION="us-east-1"
PROFILE="labs-mfa"


if [[ "$1" == 'delete' ]]
    then
        print_style  "Deleting Stack..." "danger"

        aws --profile $PROFILE --region $REGION cloudformation describe-stacks --stack-name "$STACKNAME"
        if [[ "$?" != '0' ]]
            then
                #Exit if the stack does not exist
                print_style  "Stack does not exist!" "danger"
                exit 1
        fi

        aws cloudformation delete-stack --stack-name "$STACKNAME" --profile $PROFILE --region $REGION 

        print_style  "Check status by running 'cfn $STACKNAME' " "info"
        print_style  "For S3 buckets that do not delete due to objects, please run 'aws --profile $PROFILE --region $REGION s3 rb --force s3://BUCKETNAME/'" "info"

        aws --profile $PROFILE --region $REGION cloudformation wait stack-delete-complete --stack-name $STACKNAME
        exit 1

fi


#Set credentials
print_style  "Setting credentials" "info"
creds=$(aws sts assume-role --role-arn arn:aws:iam::324320755747:role/zachroleplzdelete --role-session-name "test" --profile $PROFILE)

aws configure set aws_access_key_id $(echo $creds | jq -r '.Credentials.AccessKeyId') --profile test
aws configure set aws_secret_access_key $(echo $creds | jq -r '.Credentials.SecretAccessKey') --profile test
aws configure set aws_session_token $(echo $creds | jq -r '.Credentials.SessionToken') --profile test



#Set Environment
print_style  "Setting environment" "info"

aws --profile $PROFILE --region $REGION cloudformation describe-stacks --stack-name "$STACKNAME"

if [[ "$?" != '0' ]]
    then
        print_style  "Creating Stack..." "info"
        stackid=$(aws cloudformation create-stack --stack-name $STACKNAME --profile $PROFILE --region $REGION --template-body $YAMLLOCATION --capabilities CAPABILITY_NAMED_IAM)

        aws --profile $PROFILE --region $REGION cloudformation wait stack-create-complete --stack-name $(echo $stackid | jq -r '.StackId')
    else
        print_style  "Updating Stack..." "info"
        stackid=$(aws cloudformation update-stack --stack-name "$STACKNAME" --profile $PROFILE --region $REGION --template-body $YAMLLOCATION --capabilities CAPABILITY_NAMED_IAM )

        print_style  "$stackid" "warning" 

        aws --profile $PROFILE --region $REGION cloudformation wait stack-update-complete --stack-name $(echo $stackid | jq -r '.StackId')

        if [[ "$?" != '0' ]]
            then
                read -p "Issues exist. Enter 1 to continue, anything else to cancel: " policytype && [[ $policytype == [1] ]] || exit 1
        fi

fi



#Tests
print_style  "$PROFILE tests" "info"
aws --profile $PROFILE --region $REGION s3api list-objects --max-items 4 --bucket stelligent-u-zacherycox1
aws --profile $PROFILE --region $REGION s3api list-objects --max-items 4 --bucket stelligent-u-zacherycox2

aws --profile $PROFILE --region $REGION s3api list-objects --max-items 4 --bucket stelligent-u-zacherycox1 --prefix "lebowski/"
aws --profile $PROFILE --region $REGION s3api list-objects --max-items 4 --bucket stelligent-u-zacherycox2 --prefix "lebowski/"

aws --profile $PROFILE --region $REGION s3 cp ./iam.yaml s3://stelligent-u-zacherycox1/iam.yaml
aws --profile $PROFILE --region $REGION s3 cp ./iam.yaml s3://stelligent-u-zacherycox2/iam.yaml

print_style  "Assumed Role tests" "info"
aws --profile test --region $REGION s3api list-objects --max-items 4 --bucket stelligent-u-zacherycox1
aws --profile test --region $REGION s3api list-objects --max-items 4 --bucket stelligent-u-zacherycox2

aws --profile test --region $REGION s3api list-objects --max-items 4 --bucket stelligent-u-zacherycox1 --prefix "lebowski/"
aws --profile test --region $REGION s3api list-objects --max-items 4 --bucket stelligent-u-zacherycox2 --prefix "lebowski/"

aws --profile test --region $REGION s3 cp ./iam.yaml s3://stelligent-u-zacherycox1/iam.yaml
aws --profile test --region $REGION s3 cp ./iam.yaml s3://stelligent-u-zacherycox2/iam.yaml


#new tests for lab
print_style  "New Tests for Lab" "info"

aws --profile test --region $REGION s3 rm s3://stelligent-u-zacherycox1/iam.yaml
if [[ "$?" == '0' ]]
    then
        #Restore if successful
        print_style  "Restoring file" "info"
        aws --profile $PROFILE --region $REGION s3 cp ./iam.yaml s3://stelligent-u-zacherycox1/iam.yaml
fi

aws --profile test --region $REGION s3 rm s3://stelligent-u-zacherycox2/iam.yaml
if [[ "$?" == '0' ]]
    then
        #Restore if successful
        print_style  "Restoring file" "info"
        aws --profile $PROFILE --region $REGION s3 cp ./iam.yaml s3://stelligent-u-zacherycox2/iam.yaml
fi


print_style  "Restrict PutObject" "info"
aws --profile test --region $REGION s3 cp ./iam.yaml s3://stelligent-u-zacherycox1/lebowski/iam.yaml
aws --profile test --region $REGION s3 cp ./iam.yaml s3://stelligent-u-zacherycox2/lebowski/iam.yaml
