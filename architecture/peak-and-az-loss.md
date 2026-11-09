# How the Design Handles the Exam Peak and the Loss of One AZ

## Exam peak

At peak, 3,000 students start one exam within 5 minutes. The frontend is static files cached by CloudFront, so page loads never reach my servers. Before each exam a scheduled scaling action raises the ECS service from 4 to 20 tasks, so capacity is ready before students log in instead of waiting for auto scaling to react. Target tracking on CPU adds more tasks if needed. Autosave is a small write every 30 seconds, which is about 100 writes per second for 3,000 students, and RDS handles that easily. Assignment uploads go straight to S3 with presigned URLs, so large files never use API capacity. Marking and emails go into SQS, so the API only drops a message and replies.

## Loss of one AZ

Every tier runs in both AZs. If one AZ fails, the ALB health checks mark the tasks there as unhealthy and send all traffic to the other AZ. ECS starts replacement tasks in the healthy AZ to get back to the desired count. Each AZ has its own NAT Gateway, so the healthy AZ still has outbound access. RDS Multi-AZ fails over to the standby, usually within 1 to 2 minutes, and the endpoint name stays the same so the app reconnects without any change. The standby is written synchronously, so no saved answers are lost, and the frontend retries autosave during the short pause. This meets the 99.9% availability target, the 5 minute RPO and the 1 hour RTO. If the database itself is damaged, point in time restore (logs are backed up every 5 minutes) still keeps data loss under 5 minutes and recovery under an hour.
