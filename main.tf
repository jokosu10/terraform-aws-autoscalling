variable "server_port" {
  description = "The port the web server will be listening"
  type        = number
  default     = 8080
}

variable "http_port" {
  description = "The port the sweb erver will be listening"
  type        = number
  default     = 8080
}

variable "elb_port" {
  description = "The port the elb will be listening"
  type        = number
  default     = 80
}

data "aws_availability_zones" "all" {}

resource "aws_launch_configuration" "asg-launch-config-aws-ug" {
  image_id        = "ami-053b0d53c279acc90"
  instance_type   = "t2.nano"
  security_groups = [aws_security_group.busybox.id]
  key_name        = "my-key-pair"

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, Terraform & AWS UG SUB DEV TALK 2023" > index.html
              nohup busybox httpd -f -p "${var.server_port}" &
              EOF
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "busybox" {
  name = "terraform-busybox-sg"
  ingress {
    from_port   = var.http_port
    to_port     = var.http_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "elb-sg" {
  name = "terraform-aws-ug-elb-sg"
  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Inbound HTTP from anywhere
  ingress {
    from_port   = var.elb_port
    to_port     = var.elb_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_autoscaling_group" "asg-aws-ug" {
  launch_configuration = aws_launch_configuration.asg-launch-config-aws-ug.id
  availability_zones   = data.aws_availability_zones.all.names

  min_size = 2
  max_size = 5

  load_balancers    = [aws_elb.aws-ug.name]
  health_check_type = "ELB"

  tag {
    key                 = "Name"
    value               = "terraform-asg-aws-ug"
    propagate_at_launch = true
  }
}

# Creating the autoscaling policy of the autoscaling group
resource "aws_autoscaling_policy" "aws-ug-policy" {
  name               = "autoscalegroup_policy"
  scaling_adjustment = 2
  adjustment_type    = "ChangeInCapacity"
  # The amount of time (seconds) after a scaling completes and the next scaling starts.
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.asg-aws-ug.name
}

# Creating the AWS CLoudwatch Alarm that will autoscale the AWS EC2 instance based on CPU utilization.
resource "aws_cloudwatch_metric_alarm" "web_cpu_alarm_up" {
  # defining the name of AWS cloudwatch alarm
  alarm_name          = "web_cpu_alarm_up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  # Defining the metric_name according to which scaling will happen (based on CPU) 
  metric_name = "CPUUtilization"
  # The namespace for the alarm's associated metric
  namespace = "AWS/EC2"
  # After AWS Cloudwatch Alarm is triggered, it will wait for 60 seconds and then autoscales
  period    = "60"
  statistic = "Average"
  # CPU Utilization threshold is set to 10 percent
  threshold = "10"
  alarm_actions = [
    "${aws_autoscaling_policy.aws-ug-policy.arn}"
  ]
  dimensions = {
    AutoScalingGroupName = "${aws_autoscaling_group.asg-aws-ug.name}"
  }
}

resource "aws_elb" "aws-ug" {
  name               = "terraform-asg-aws-ug"
  security_groups    = [aws_security_group.elb-sg.id]
  availability_zones = data.aws_availability_zones.all.names

  health_check {
    target              = "HTTP:${var.server_port}/"
    interval            = 30
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  # Adding a listener for incoming HTTP requests.
  listener {
    lb_port           = var.elb_port
    lb_protocol       = "http"
    instance_port     = var.server_port
    instance_protocol = "http"
  }
}

output "elb_dns_name" {
  value       = aws_elb.aws-ug.dns_name
  description = "The domain name of the load balancer"
}
