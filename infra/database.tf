# DB password is generated here and kept in Secrets Manager
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#%^*()-_=+" # RDS does not allow slash, at sign, quotes or spaces
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.prefix}-db-password"
  recovery_window_in_days = 0 # delete straight away on destroy so the name can be reused
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = random_password.db.result
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.prefix}-db-subnets"
  subnet_ids = aws_subnet.db[*].id
}

resource "aws_db_instance" "main" {
  identifier              = "${var.prefix}-db"
  engine                  = "postgres"
  engine_version          = "16"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  storage_type            = "gp3"
  storage_encrypted       = true
  multi_az                = true # standby copy in the second AZ
  db_name                 = "exams"
  username                = "examadmin"
  password                = random_password.db.result
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  publicly_accessible     = false
  backup_retention_period = 1
  skip_final_snapshot     = true # class project, so terraform destroy can clean up
}
