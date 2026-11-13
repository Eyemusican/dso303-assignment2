import json
import urllib.parse


def handler(event, context):
    # each SQS message body is an S3 event with one or more records
    for message in event["Records"]:
        s3_event = json.loads(message["body"])
        # S3 sends a test event with no Records when the notification is set up
        for record in s3_event.get("Records", []):
            key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
            print(f"tutor notified: {key}")
