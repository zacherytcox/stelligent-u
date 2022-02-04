import json
import boto3
client = boto3.client('dynamodb')
print('Loading function')
def lambda_handler(event, context):

    this_table = None
    tables = client.list_tables()
    # print(tables['TableNames'])
    for table in tables['TableNames']:
      if table.startswith("lab9-zach-DynaDB"):
        print(table)
        this_table = table

    response = client.put_item(
        TableName=this_table,
        Item={"Artist":{"S":"Testauto2"},"NumberOfSongs":{"N":"267"}}
    )
        


    return {
      'body': 'WORKS!!! ' + str(event),
      'headers': {
        'Content-Type': 'application/json'
      },
      'statusCode': 200
    } 