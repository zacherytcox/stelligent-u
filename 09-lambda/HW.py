import json
print('Loading function')
def lambda_handler(event, context):
    return {
    'body': 'WORKS!!! ' + str(event),
    'headers': {
        'Content-Type': 'application/json'
    },
    'statusCode': 200
    } 