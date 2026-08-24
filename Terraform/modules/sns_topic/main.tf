# 1. יצירת ערוץ ההתראות (Topic)
resource "aws_sns_topic" "alerts" {
  name = var.topic_name

  tags = {
    Name = var.topic_name
  }
}

# 2. יצירת המנוי (Subscription) - זה מה שהיה חסר!
resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # האימייל שאליו יישלחו ההודעות
}