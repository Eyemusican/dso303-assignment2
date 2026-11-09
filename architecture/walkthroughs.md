# Request Walkthroughs

## Walkthrough 1: A student opens an exam and answers autosave

1. The student goes to the exam site. Route 53 resolves the domain to CloudFront.
2. AWS WAF checks the request. CloudFront returns the frontend files from its cache (origin is the private S3 frontend bucket).
3. The student signs in with Cognito and gets a JWT token that shows they are in the student group.
4. The frontend calls `POST /api/exams/{id}/start`. CloudFront forwards /api/* to the ALB, which sends it to a healthy ECS task in either AZ.
5. The ECS task checks the JWT and group, checks the exam is open, gets the DB password from Secrets Manager, reads the questions from RDS, saves the start time and returns the questions. The timer is checked on the server, not only in the browser.
6. Every 30 seconds the frontend sends `PUT /api/attempts/{id}/answers` with the current answers. The same path (CloudFront, ALB, ECS) saves them to the RDS primary, which copies each write to the standby in the other AZ straight away.
7. If an autosave fails, the frontend keeps the answers in the browser and retries on the next save.

## Walkthrough 2: A student uploads a 40 MB assignment and the tutor is notified

1. The signed in student picks a 40 MB PDF. The frontend calls `POST /api/assignments/{id}/upload-url`.
2. The ECS task checks the JWT, creates a presigned POST for the assignments bucket with a 50 MB size limit and a 5 minute expiry, and saves a pending submission in RDS.
3. The browser uploads the file directly to S3 over HTTPS. S3 encrypts it with the KMS key. The 40 MB file never passes through the ALB or ECS.
4. When the upload finishes, S3 sends an ObjectCreated event to the notification SQS queue.
5. A Lambda function reads the message, marks the submission as received in RDS, looks up the tutor's email and sends the notification through SES.
6. If sending fails, SQS retries. After 3 failed tries the message goes to the dead letter queue and a CloudWatch alarm fires.
7. Later, the S3 lifecycle rules move the file to Standard-IA after 30 days and Glacier after 1 year, and delete it after 5 years.
